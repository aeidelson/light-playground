import Foundation
import CoreGraphics

class Tracer {
    /// Constructs an operation to perform a trace of some number of rays.
    static func makeTracer(
        context: CPULightSimulatorContext,
        rootGrid: LightGrid,
        layout: SimulationLayout,
        simulationSize: CGSize,
        segmentsToTrace: Int,
        interactiveTrace: Bool
    ) -> Operation {
        var operation: BlockOperation?
        operation = BlockOperation { [weak rootGrid] in
            // TODO: retain cycle?
            guard let strongOperation = operation else { return }

            precondition(layout.lights.count > 0)

            guard !strongOperation.isCancelled else { return }
            let segments = trace(layout: layout, simulationSize: simulationSize, maxSegments: segmentsToTrace)

            guard !strongOperation.isCancelled else { return }

            guard let strongRootGrid = rootGrid else { return }

            // In the case of an interactive trace, we know there is only one grid and tracer so we can write to it
            // directly. Otherwise we create a grid just for this tracer and lock / agregate at the end.
            if interactiveTrace {
                strongRootGrid.drawSegments(layout: layout, segments: segments, lowQuality: true)
            } else {
                let tracerGrid = LightGrid(context: context, generateImage: false, size: simulationSize)
                tracerGrid.drawSegments(layout: layout, segments: segments, lowQuality: false)

                guard !strongOperation.isCancelled else { return }

                objc_sync_enter(strongRootGrid)
                defer { objc_sync_exit(strongRootGrid) }
                // One more check to make sure it is still not cancelled when the grid is locked.
                guard !strongOperation.isCancelled else { return }
                strongRootGrid.aggregrate(layout: layout, grids: [tracerGrid])
            }
        }

        return operation!
    }

    // MARK: Private

    private static let lightRadius: CGFloat = 10.0

    /// Synchronously produces light segments given the simulation layout.
    /// This shouldn't rely on any mutable state outside of the function, as this may be running in parallel to other
    /// traces if a trace is in the process of being canceled.
    private static func trace(
        layout: SimulationLayout,
        simulationSize: CGSize,
        maxSegments: Int
    ) -> [LightSegment] {
        /// There's nothing to show if there are no lights.
        guard layout.lights.count > 0 else { preconditionFailure() }

        var rayQueue = [LightRay]()
        rayQueue.reserveCapacity(maxSegments)

        // Prime rayBuffer with the rays emitting from lights.
        // TODO: Figure out how to make this work with reflections.
        let initialRaysToCast = maxSegments / 2

        for i in 0..<initialRaysToCast {
            let lightChosen = layout.lights[i % layout.lights.count]

            // Rays from light have both a random origin and a random direction.
            //let rayOrigin = randomPointOnCircle(center: lightChosen.pos, radius: lightRadius)
            let rayOrigin = lightChosen.pos
            let rayDirectionPoint = randomPointOnCircle(center: CGPoint(x: 0, y: 0), radius: 300.0)
            let rayDirection = CGVector(dx: rayDirectionPoint.x, dy: rayDirectionPoint.y)
            rayQueue.append(LightRay(
                origin: rayOrigin,
                direction: rayDirection,
                // For now just assuming white light
                color: lightChosen.color))
        }

        // Hardcode walls to prevent out of index.
        let minX: CGFloat = 1.0
        let minY: CGFloat = 1.0
        let maxX: CGFloat = simulationSize.width - 2.0
        let maxY: CGFloat = simulationSize.height - 2.0
        var allWalls = [
            Wall(pos1: CGPoint(x: minX, y: minY), pos2: CGPoint(x: maxX, y: minY), reflection: 0.0),
            Wall(pos1: CGPoint(x: minX, y: minY), pos2: CGPoint(x: minX, y: maxY), reflection: 0.0),
            Wall(pos1: CGPoint(x: maxX, y: minY), pos2: CGPoint(x: maxX, y: maxY), reflection: 0.0),
            Wall(pos1: CGPoint(x: minX, y: maxY), pos2: CGPoint(x: maxX, y: maxY), reflection: 0.0)
        ]
        allWalls.append(contentsOf: layout.walls)

        var producedSegments = [LightSegment]()
        producedSegments.reserveCapacity(maxSegments)

        while rayQueue.count > 0 && producedSegments.count < maxSegments {
            let ray = rayQueue.removeFirst()

            // For safety, we ignore any rays that originate outside the image
            guard isInsideSimulationBounds(
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY,
                point: ray.origin) else { continue }

            var closestIntersectionPoint: CGPoint?
            var closestIntersectionWall: Wall?
            var closestDistance = CGFloat.greatestFiniteMagnitude

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
                    sqrt(pow(ray.origin.x - collisionX, 2) + pow(ray.origin.y - collisionY, 2))


                if distFromOrigin < closestDistance {
                    closestDistance = distFromOrigin
                    closestIntersectionWall = wall
                    closestIntersectionPoint = CGPoint(x: collisionX, y: collisionY)
                }
            }
            
            // Create a light segment using whatever the closest collision was
            
            guard let intersectionPoint = closestIntersectionPoint else { preconditionFailure() }
            guard let intersectionWall = closestIntersectionWall else { preconditionFailure() }

            // TODO: Prune rays that are too dark.
            if intersectionWall.reflection > 0.01 {
                let newColor = LightColor(
                    r: UInt8(intersectionWall.reflection * CGFloat(ray.color.r)),
                    g: UInt8(intersectionWall.reflection * CGFloat(ray.color.g)),
                    b: UInt8(intersectionWall.reflection * CGFloat(ray.color.b)))

                // TODO: Much of this can be done ahead of time.

                // Calculate the normal of the wall
                let dx = intersectionWall.pos2.x - intersectionWall.pos1.x
                let dy = intersectionWall.pos2.y - intersectionWall.pos1.y

                // To get the direction of the ray
                let reverseIncomingDirection = rotate(ray.direction, CGFloat(M_PI))

                let normal1 = CGVector(dx: -dy, dy: dx)
                let normal2 = CGVector(dx: dy, dy: -dx)

                // The normal on the side of the wall opposite of the ray origin.
                let normal: CGVector

                // Which ever normal is closest to the direction of the incoming ray is assumed to be on the opposite
                // side of the wall.
                if angle(normal1, reverseIncomingDirection) < CGFloat(M_PI) {
                    normal = normal1
                } else {
                    normal = normal2
                }

                let normalAngle = absoluteAngle(normal)
                let reverseIncomingDirectionAngle = absoluteAngle(reverseIncomingDirection)

                let newRaydirection = normalize(
                    rotate(reverseIncomingDirection, 2 * (reverseIncomingDirectionAngle - normalAngle)))

                /// Start the ray off with a small head-start so it doesn't collide with the wall it intersected with.
                let bounceRayOrigin = CGPoint(
                    x: intersectionPoint.x + newRaydirection.dx * 0.1,
                    y: intersectionPoint.y + newRaydirection.dy * 0.1)

                let bounceRay = LightRay(
                    origin: bounceRayOrigin,
                    direction: newRaydirection,
                    color: newColor)

                rayQueue.append(bounceRay)
            }

            producedSegments.append(LightSegment(
                p0: ray.origin,
                p1: intersectionPoint,
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

private func isInsideSimulationBounds(
    minX: CGFloat,
    minY: CGFloat,
    maxX: CGFloat,
    maxY: CGFloat,
    point: CGPoint) -> Bool {
    return (point.x >= minX) && (point.x <= maxX) &&
        (point.y >= minY) && (point.y <= maxY)
}
