import Foundation
import CoreGraphics

/// Incrementally traces rays in the scene and batches of LightSegments.
protocol Tracer {
    /// Stops any running traces starts incrementally tracing.
    func restartTrace(layout: SimulationLayout)

    /// Is no-op if there isn't a trace running.
    func stop()

    /// Will be used to broadcast batches of segments as they are calculated.
    var incrementalSegmentsObservable: Observable<[LightSegment]> { get }
}

class CPUTracer: Tracer {
    required init(traceQueue: OperationQueue, simulationSize: CGSize, maxSegmentsToTrace: Int) {
        self.traceQueue = traceQueue
        self.simulationSize = simulationSize
        self.maxSegmentsToTrace = maxSegmentsToTrace
        self.segmentBatchSize = 10_000
    }

    func restartTrace(layout: SimulationLayout) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        // Note: The current queue will be flushed automatically in LightSimulator, since `traceQueue` is managed
        // automatically.

        // There's nothing to show if there are no lights.
        guard layout.lights.count > 0 else { return }

        currentlyExecuting = BlockOperation { [weak self] in
            guard let strongSelf = self else { return }
            guard let workItem = strongSelf.currentlyExecuting else { return }

            var segmentsLeft = strongSelf.maxSegmentsToTrace

            while !workItem.isCancelled && segmentsLeft > 0 {
                let currentBatchSize = min(strongSelf.segmentBatchSize, segmentsLeft)
                let segmentsTraced = strongSelf.traceSingleBatch(layout: layout, maxSegments: currentBatchSize)

                /// Do a final check to see if the work has been cancelled, before notifying anything.
                guard !workItem.isCancelled else { continue }
                segmentsLeft -= segmentsTraced.count
                strongSelf.incrementalSegmentsObservable.notify(segmentsTraced)
            }
        }

        traceQueue.addOperation(currentlyExecuting!)
    }

    func stop() {
        traceQueue.cancelAllOperations()
    }

    var incrementalSegmentsObservable = Observable<[LightSegment]>()

    // MARK: Private

    /// The queue to run traces on.
    private let traceQueue: OperationQueue

    /// A worker to performing the current trace. Should lock on self when changing or accessing this value.
    private var currentlyExecuting: Operation?

    private let simulationSize: CGSize
    private let maxSegmentsToTrace: Int
    private let segmentBatchSize: Int
    private let lightRadius: CGFloat = 10.0

    // Should lock on `self` when calling this.
    //private func stopCurrentTrace() {
        //currentlyExecuting?.cancel()
        //currentlyExecuting = nil
    //}

    /// Synchronously produces light segments given the simulation layout.
    /// This shouldn't rely on any mutable state outside of the function, as this may be running in parallel to other
    /// traces if a trace is in the process of being canceled.
    private func traceSingleBatch(
        layout: SimulationLayout,
        maxSegments: Int
    ) -> [LightSegment] {
        /// There's nothing to show if there are no lights.
        guard layout.lights.count > 0 else { preconditionFailure() }

        var rayQueue = [LightRay]()
        rayQueue.reserveCapacity(maxSegments)

        // Prime rayBuffer with the rays emitting from lights.
        // TODO: Figure out how to make this work with reflections.
        let initialRaysToCast = maxSegments

        for i in 0..<initialRaysToCast {
            let lightChosen = layout.lights[i % layout.lights.count]

            // Rays from light have both a random origin and a random direction.
            let rayOrigin = randomPointOnCircle(center: lightChosen.pos, radius: lightRadius)
            let rayDirectionPoint = randomPointOnCircle(center: CGPoint(x: 0, y: 0), radius: 10000.0)
            let rayDirection = CGVector(dx: rayDirectionPoint.x, dy: rayDirectionPoint.y)
            rayQueue.append(LightRay(
                origin: rayOrigin,
                direction: rayDirection,
                // For now just assuming white light
                color: LightColor(r: 255, g: 255, b: 255)))
        }

        // Hardcode walls to prevent out of index.
        let maxX = simulationSize.width - 1.0
        let maxY = simulationSize.height - 1.0
        var allWalls = [
            Wall(pos1: CGPoint(x: 0.0, y: 0.0), pos2: CGPoint(x: maxX, y: 0)),
            Wall(pos1: CGPoint(x: 0.0, y: 0.0), pos2: CGPoint(x: 0.0, y: maxY)),
            Wall(pos1: CGPoint(x: maxX, y: 0.0), pos2: CGPoint(x: maxX, y: maxY)),
            Wall(pos1: CGPoint(x: 0.0, y: maxY), pos2: CGPoint(x: maxX, y: maxY))
        ]
        allWalls.append(contentsOf: layout.walls)

        var producedSegments = [LightSegment]()
        producedSegments.reserveCapacity(maxSegments)

        while rayQueue.count > 0 && producedSegments.count < maxSegments {
            let ray = rayQueue.removeFirst()

            // For simplicty, we ignore any rays that originate outside the image
            guard isInsideSimulationBounds(simulationSize: simulationSize, point: ray.origin) else { continue }

            var closestIntersectionPoint: CGPoint?
            var closestIntersectionWall: Wall?
            var closestDistance = FLT_MAX

            for wall in allWalls {
                // TODO: Should move all the (constant) ray calculations out of this loop.
                // Given the equation `y = mx + b`

                // Calculate `m`:
                let raySlope = safeDivide(ray.direction.dy, ray.direction.dx)
                let wallSlope = safeDivide((wall.pos2.y - wall.pos1.y), (wall.pos2.x - wall.pos1.x))
                if abs(raySlope - wallSlope) < 0.01 {
                    // They are rounghly parallel, stop processing.
                    continue
                }

                // Calculate `b` using: `b = y - mx`
                let rayYIntercept = ray.origin.y - raySlope * ray.origin.x
                let wallYIntercept = wall.pos1.y - wallSlope * wall.pos1.x


                // Calculate x-collision (derived from equations above)
                let collisionX = safeDivide((wallYIntercept - rayYIntercept), (raySlope - wallSlope))

                // Calculate y intercept using `y = mx + b`
                let collisionY = raySlope * collisionX + rayYIntercept

                // Check if the collision points are on the correct side of the light ray
                let positiveXRayDirection = ray.direction.dx >= 0
                let positiveYRayDirection = ray.direction.dy >= 0
                let positiveCollisionXDirection = (collisionX - ray.origin.x) >= 0
                let positiveCollisionYDirection = (collisionY - ray.origin.y) >= 0

                guard positiveXRayDirection == positiveCollisionXDirection &&
                    positiveYRayDirection == positiveCollisionYDirection else { continue }

                // Check if the collision points are inside the wall segment. Some buffer is added to handle horizontal
                // or vertical lines.
                let segmentXRange = (min(wall.pos1.x, wall.pos2.x)-0.5)...(max(wall.pos1.x, wall.pos2.x)+0.5)
                let segmentYRange = (min(wall.pos1.y, wall.pos2.y)-0.5)...(max(wall.pos1.y, wall.pos2.y)+0.5)

                let collisionInWallX = segmentXRange.contains(collisionX)

                let collisionInWallY = segmentYRange.contains(collisionY)

                guard collisionInWallX && collisionInWallY else { continue }

                // Check if the collision points are closer than the current closest
                let distFromOrigin =
                    sqrt(pow(Float(ray.origin.x - collisionX), 2) + pow(Float(ray.origin.y - collisionY), 2))


                if distFromOrigin < closestDistance {
                    closestDistance = distFromOrigin
                    closestIntersectionWall = wall
                    closestIntersectionPoint = CGPoint(x: collisionX, y: collisionY)
                }
            }
            
            // Create a light segment using whatever the closest collision was
            
            guard let segmentEndPoint = closestIntersectionPoint else { preconditionFailure() }
            guard let _ = closestIntersectionWall else { preconditionFailure() }
            
            // TODO: Should spawn rays if bouncing off wall
            
            producedSegments.append(LightSegment(
                p0: ray.origin,
                p1: segmentEndPoint,
                color: ray.color))
        }

        return producedSegments
    }
}


// MARK: Private

private struct LightRay {
    public let origin: CGPoint
    public let direction: CGVector
    public let color: LightColor
}

private func randomPointOnCircle(center: CGPoint, radius: CGFloat) -> CGPoint {
    let radians = CGFloat(drand48() * 2.0 * M_PI)
    return CGPoint(
        x: center.x + radius * cos(radians),
        y: center.y + radius * sin(radians)
    )
}

private func safeDivide(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let c = a / b
    if c.isInfinite {
        return 9999999
    }
    return c
}

private func isInsideSimulationBounds(simulationSize: CGSize, point: CGPoint) -> Bool {
    return (point.x >= 0) && (point.x < simulationSize.width) &&
        (point.y >= 0) && (point.y < simulationSize.height)
}
