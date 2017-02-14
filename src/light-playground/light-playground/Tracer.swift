import Foundation
import CoreGraphics

final class Tracer {
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
                let tracerGrid = LightGrid(context: context, size: simulationSize, initialRenderProperties: nil)
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

    /// Volume attributes applying to empty space in a scene.
    private static let spaceAttributes = ShapeAttributes(indexOfRefraction: 1)

    /// Synchronously produces light segments given the simulation layout.
    /// This shouldn't rely on any mutable state outside of the function, as this may be running in parallel to other
    /// traces if a trace is in the process of being canceled.
    /// Note: Made internal for testing.
    internal static func trace(
        layout: SimulationLayout,
        simulationSize: CGSize,
        maxSegments: Int
    ) -> [LightSegment] {
        /// There's nothing to show if there are no lights.
        guard layout.lights.count > 0 else { preconditionFailure() }

        let rayQueue = CircularBufferQueue<LightRay>(
            capacity: maxSegments,
            empty: LightRay.zero)

        // Prime rayBuffer with the rays emitting from lights. Half of the remaining segments alloted are used for
        // bounces.
        // TODO: Figure out a smarter way to allow for more rays (maybe based on the number of objects in the scene?)
        let initialRaysToCast = maxSegments / 2

        for i in 0..<initialRaysToCast {
            let lightChosen = layout.lights[i % layout.lights.count]

            // Rays from light have both a random origin and a random direction.
            let rayOrigin = lightChosen.pos
            let rayDirectionPoint = randomPointOnCircle(center: CGPoint(x: 0, y: 0), radius: 300.0)
            let rayDirection = CGVector(dx: rayDirectionPoint.x, dy: rayDirectionPoint.y)
            rayQueue.enqueue(LightRay(
                origin: rayOrigin,
                direction: rayDirection,
                color: lightChosen.color,
                mediumAttributes: spaceAttributes))
        }

        // Hardcode walls to prevent out of index.
        let minX: CGFloat = 1.0
        let minY: CGFloat = 1.0
        let maxX: CGFloat = simulationSize.width - 2.0
        let maxY: CGFloat = simulationSize.height - 2.0
        let shapeAttributes = ShapeAttributes(absorption: FractionalLightColor.total, diffusion: 0)
        var allItems: [SimulationItem] = [
            Wall(pos1: CGPoint(x: minX, y: minY), pos2: CGPoint(x: maxX, y: minY),
                 shapeAttributes: shapeAttributes),
            Wall(pos1: CGPoint(x: minX, y: minY), pos2: CGPoint(x: minX, y: maxY),
                 shapeAttributes: shapeAttributes),
            Wall(pos1: CGPoint(x: maxX, y: minY), pos2: CGPoint(x: maxX, y: maxY),
                 shapeAttributes: shapeAttributes),
            Wall(pos1: CGPoint(x: minX, y: maxY), pos2: CGPoint(x: maxX, y: maxY),
                 shapeAttributes: shapeAttributes)
        ]
        allItems.append(contentsOf: layout.walls as [SimulationItem])
        allItems.append(contentsOf: layout.circleShapes as [SimulationItem])

        var producedSegments = [LightSegment]()
        producedSegments.reserveCapacity(maxSegments)

        while let ray = rayQueue.dequeue(), producedSegments.count < maxSegments {

            // For safety, we ignore any rays that originate outside the image
            guard isInsideSimulationBounds(
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY,
                point: ray.origin) else { continue }

            var closestDistance = CGFloat.greatestFiniteMagnitude
            var closestIntersectionPoint: CGPoint?

            /// This is the item whose wall the ray intersected with. It may be the item the ray is traveling through.
            var closestIntersectionSurfaceItem: SimulationItem?

            for item in allItems {
                guard let possibleIntersectionPoint = item.intersectionPoint(ray: ray) else { continue }

                // Check if the intersection points are closer than the current closest
                let distFromOrigin = sqrt(
                    sq(ray.origin.x - possibleIntersectionPoint.x) +
                        sq(ray.origin.y - possibleIntersectionPoint.y))

                if distFromOrigin < closestDistance {
                    closestDistance = distFromOrigin
                    closestIntersectionPoint = possibleIntersectionPoint
                    closestIntersectionSurfaceItem = item
                }
            }

            guard let intersectionPoint = closestIntersectionPoint else { preconditionFailure() }
            guard let intersectionSurfaceItem = closestIntersectionSurfaceItem else { preconditionFailure() }

            // Return the light segment for drawing of the ray.
            producedSegments.append(LightSegment(
                pos1: ray.origin,
                p1: intersectionPoint,
                color: ray.color))

            // TODO: Stop if the ray is too dark to begin with
            let absorption = intersectionSurfaceItem.shapeAttributes.absorption
            guard absorption.r < 0.99 || absorption.g < 0.99 || absorption.b < 0.99 else { continue }
            let colorAfterAbsorption =
                ray.color.multiplyBy(intersectionSurfaceItem.shapeAttributes.absorption.remainder())

            // Now we may spawn some more rays depending on the ray and attributes of the intersectionItem.

            // Some commonly used variables are calculated.
            let normals = intersectionSurfaceItem.calculateNormals(ray: ray, atPos: intersectionPoint)
            let reverseIncomingDirection = ray.direction.reverse()
            let incomingAngleFromNormal = angle(normals.reflectionNormal, reverseIncomingDirection)

            // Calculate the reflected ray.
            // TODO: Don't bother with the reflected ray if the ammount reflected is small.

            let reflectedProperties = calculateReflectedProperties(
                intersectionPoint: intersectionPoint,
                intersectedSurfaceAttributes: intersectionSurfaceItem.shapeAttributes,
                reverseIncomingDirection: reverseIncomingDirection,
                reflectionNormal: normals.reflectionNormal,
                incomingAngleFromNormal: incomingAngleFromNormal)

            // Calculate the refracted ray if the surface item is translucent.
            var percentReflected: CGFloat = 1.0

            if intersectionSurfaceItem.shapeAttributes.translucent {
                // Find the medium that the new rayis going to enter.
                let newItemTestPoint = advance(p: intersectionPoint, by: 0.1, towards: ray.direction)

                let newItem = pointItem(items: allItems, point: newItemTestPoint)
                let newMedium = newItem?.shapeAttributes ?? spaceAttributes

                percentReflected = calculateReflectance(
                    fromAttributes: ray.mediumAttributes,
                    toAttributes: newMedium,
                    incomingAngleFromNormal: incomingAngleFromNormal)

                let refractedProperties = calculateRefractedProperties(
                    intersectionPoint: intersectionPoint,
                    incomingAngleFromNormal: incomingAngleFromNormal,
                    refractionNormal: normals.refractionNormal,
                    oldMediumAttributes: ray.mediumAttributes,
                    newMediumAttributes: newMedium)

                rayQueue.enqueue(LightRay(
                    origin: refractedProperties.origin,
                    direction: refractedProperties.direction,
                    color: colorAfterAbsorption.multiplyBy(1 - percentReflected),
                    mediumAttributes: newMedium))
            }

            rayQueue.enqueue(LightRay(
                origin: reflectedProperties.origin,
                direction: reflectedProperties.direction,
                color: colorAfterAbsorption.multiplyBy(percentReflected),
                /// Because the ray is a reflection, it will share the same attributes as the original ray.
                mediumAttributes: ray.mediumAttributes))
        }

        return producedSegments
    }
}

// MARK: Private

/// Calculates the percentage of light that is reflected, using Fresnel equations.
/// Equations taken from: https://en.wikipedia.org/wiki/Fresnel_equations
private func calculateReflectance(
    fromAttributes: ShapeAttributes,
    toAttributes: ShapeAttributes,
    incomingAngleFromNormal: CGFloat
) -> CGFloat {
    let n1 = fromAttributes.indexOfRefraction
    let n2 = toAttributes.indexOfRefraction

    // Is used commonly
    let ratioSinAngleSquared = sq((n1 / n2) * sin(incomingAngleFromNormal))

    // Calculate Rs
    let rsPart1 = n1 * cos(incomingAngleFromNormal)
    // HACK: To avoid imaginary numbers, we snap to 0.
    let rsPart2 = n2 * sqrt(max(1 - ratioSinAngleSquared, 0))
    let rs = sq((rsPart1 - rsPart2) / (rsPart1 + rsPart2))

    // Calculate Rp
    // HACK: To avoid imaginary numbers, we snap to 0.
    let rpPart1 = n1 * sqrt(max(1 - ratioSinAngleSquared, 0))
    let rpPart2 = n2 * cos(incomingAngleFromNormal)
    let rp = sq((rpPart1 - rpPart2) / (rpPart1 + rpPart2))

    /// Protect against values > 1
    return min((rs + rp) / 2, 1.0)
}

/// Calculates the position and direction of the reflected ray.
private func calculateReflectedProperties(
    intersectionPoint: CGPoint,
    intersectedSurfaceAttributes: ShapeAttributes,
    reverseIncomingDirection: CGVector,
    reflectionNormal: CGVector,
    incomingAngleFromNormal: CGFloat
) -> (origin: CGPoint, direction: CGVector) {
    var reflectedRayDirection = rotate(reverseIncomingDirection, -2 * incomingAngleFromNormal)

    // Adjust the reflected ray for diffusion:
    if intersectedSurfaceAttributes.diffusion > 0.0 {
        let normalAngle = absoluteAngle(reflectionNormal)

        let reflectedRayAngle = absoluteAngle(reflectedRayDirection)

        // Find how far the ray is from the closest perpendicular part of the item.
        // TODO: Need to investigate if this works for non-wall items.
        let perpendicularAngles = (normalAngle + CGFloat(M_PI_4), normalAngle - CGFloat(M_PI_4))
        let closestAngleDifference =
            min(abs(reflectedRayAngle - perpendicularAngles.0), abs(reflectedRayAngle - perpendicularAngles.0))

        // The maximum ammount the angle can change from diffusion.
        // This should be pi/8 normally, but if the of reflection is steep this will be the angle between
        // the reflection and the item (With a very small ammount of buffer room for safety).
        let maxDiffuseAngle = min(
            CGFloat(M_PI / 8) * intersectedSurfaceAttributes.diffusion, closestAngleDifference - 0.1)
        let diffuseAngle = CGFloat(drand48()) * 2 * maxDiffuseAngle - maxDiffuseAngle
        reflectedRayDirection = rotate(reflectedRayDirection, diffuseAngle)
    }

    /// Start the ray off with a small head-start so it doesn't collide with the item it intersected with.
    let reflectedRayOrigin = advance(p: intersectionPoint, by: 0.1, towards: reflectedRayDirection)

    return (reflectedRayOrigin, reflectedRayDirection)
}

private func calculateRefractedProperties(
    intersectionPoint: CGPoint,
    incomingAngleFromNormal: CGFloat,
    refractionNormal: CGVector,
    oldMediumAttributes: ShapeAttributes,
    newMediumAttributes: ShapeAttributes
) -> (origin: CGPoint, direction: CGVector) {
    let n1 = oldMediumAttributes.indexOfRefraction
    let n2 = newMediumAttributes.indexOfRefraction

    let refractedAngleFromNormal = asin(sin(incomingAngleFromNormal) * n1 / n2)

    let rayDirection = rotate(refractionNormal, refractedAngleFromNormal)

    /// Start the ray off with a small head-start so it doesn't collide with the item it intersected with.
    let origin = advance(p: intersectionPoint, by: 0.1, towards: rayDirection)

    return (origin: origin, direction: rayDirection)
}

private func randomPointOnCircle(center: CGPoint, radius: CGFloat) -> CGPoint {
    let radians = CGFloat(drand48() * 2.0 * M_PI)
    return CGPoint(
        x: center.x + radius * cos(radians),
        y: center.y + radius * sin(radians)
    )
}

private func calculateDistance(_ p1: CGPoint, _ pos2: CGPoint) -> CGFloat {
    return sqrt(sq(p1.x - pos2.x) + sq(p1.y - pos2.y))

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

/// Gets the item at the given point (if there is one). Currently has undefined behavior if items are overlapping each
/// other.
private func pointItem(items: [SimulationItem], point: CGPoint) -> SimulationItem? {
    for item in items {
        if item.hitPoint(point: point) {
            return item
        }
    }
    return nil
}

// MARK: Ray intersections

fileprivate struct LightRay {
    let origin: CGPoint
    let direction: CGVector
    let color: LightColor

    /// Attributes for the medium the ray is traveling in.
    /// For rays in space (i.e. coming from lights or in-between items), this will be `spaceVolumeAttributes`. For rays
    /// inside of an object , this will be that object's attributes.
    let mediumAttributes: ShapeAttributes

    static let zero = LightRay(
        origin: CGPoint.zero,
        direction: CGVector.zero,
        color: LightColor.zero,
        mediumAttributes: ShapeAttributes.zero)
}

fileprivate protocol SimulationItem {

    /// All intersection items must have a surface and so they must have surface attributes.
    var shapeAttributes: ShapeAttributes { get }

    /// For a given ray, returns the point where the item and ray collide
    func intersectionPoint(ray: LightRay) -> CGPoint?

    /// Given the light ray and the intersection point, returns the reflection and the refraction normals.
    func calculateNormals(ray: LightRay, atPos: CGPoint) ->
        (reflectionNormal: CGVector, refractionNormal: CGVector)

    /// Returns if the provided point is contained within the item.
    func hitPoint(point: CGPoint) -> Bool
}

/// Made availible so SimulationItems can use it.

// TODO: Batch this and make faster.
private func segmentIntersection(ray: LightRay, shapeSegment: ShapeSegment) -> CGPoint? {
    // Given the equation `y = mx + b`

    // Calculate `m`:
    let raySlope = safeDivide(ray.direction.dy, ray.direction.dx)
    if abs(raySlope - shapeSegment.slope) < 0.01 {
        // They are rounghly parallel, stop processing.
        return nil
    }

    // Calculate `b` using: `b = y - mx`
    let rayYIntercept = ray.origin.y - raySlope * ray.origin.x

    // Calculate x-intersection (derived from equations above)
    let intersectionX = safeDivide(
        (shapeSegment.yIntercept - rayYIntercept),
        (raySlope - shapeSegment.slope))

    // Calculate y intercept using `y = mx + b`
    let intersectionY = raySlope * intersectionX + rayYIntercept

    // Check if the intersection points are on the correct side of the light ray
    let positiveXRayDirection = ray.direction.dx >= 0
    let positiveYRayDirection = ray.direction.dy >= 0
    let positiveIntersectionXDirection = (intersectionX - ray.origin.x) >= 0
    let positiveIntersectionYDirection = (intersectionY - ray.origin.y) >= 0

    guard positiveXRayDirection == positiveIntersectionXDirection &&
        positiveYRayDirection == positiveIntersectionYDirection else { return nil }

    // Check if the intersection points are inside the wall segment. Some buffer is added to handle horizontal
    // or vertical lines.

    let intersectionInWallX = shapeSegment.xRange.contains(intersectionX)
    let intersectionInWallY = shapeSegment.yRange.contains(intersectionY)
    guard intersectionInWallX && intersectionInWallY else { return nil }

    return CGPoint(x: intersectionX, y: intersectionY)
}

private func segmentNormals(
    ray: LightRay,
    shapeSegment: ShapeSegment
) -> (reflectionNormal: CGVector, refractionNormal: CGVector) {
    // To get the direction of the ray
    let reverseIncomingDirection = ray.direction.reverse()

    let reflectionNormal: CGVector
    let refractionNormal: CGVector

    if abs(angle(shapeSegment.normals.0, reverseIncomingDirection)) < CGFloat(M_PI_2) {
        reflectionNormal = shapeSegment.normals.0
        refractionNormal = shapeSegment.normals.1
    } else {
        reflectionNormal = shapeSegment.normals.1
        refractionNormal = shapeSegment.normals.0
    }

    return (reflectionNormal: reflectionNormal, refractionNormal: refractionNormal)
}

extension Wall: SimulationItem {

    /// For a given ray, returns the point where the item and ray collide
    fileprivate func intersectionPoint(ray: LightRay) -> CGPoint? {
        return segmentIntersection(ray: ray, shapeSegment: self.shapeSegment)
    }

    /// Given the light ray and the intersection point, returns the reflection and the refraction normals.
    fileprivate func calculateNormals(
        ray: LightRay,
        atPos: CGPoint
    ) -> (reflectionNormal: CGVector, refractionNormal: CGVector) {
        return segmentNormals(ray: ray, shapeSegment: self.shapeSegment)
    }

    func hitPoint(point: CGPoint) -> Bool {
        return false
    }
}

extension CircleShape: SimulationItem {

    fileprivate func intersectionPoint(ray: LightRay) -> CGPoint? {
        // Inspired heavily by the derivation here: http://math.stackexchange.com/a/311956

        let x0 = ray.origin.x
        let y0 = ray.origin.y

        // The ending points are just the ray extrapolated to some very far location.
        let x1 = ray.origin.x + ray.direction.dx * 100000
        let y1 = ray.origin.y + ray.direction.dy * 100000

        let h = pos.x
        let k = pos.y
        let r = radius

        let a = sq(x1 - x0) + sq(y1 - y0)
        let b = 2 * (x1 - x0) * (x0 - h) + 2 * (y1 - y0) * (y0 - k)
        let c = sq(x0 - h) + sq(y0 - k) - sq(r)

        let det = sq(b) - 4 * a * c

        guard det >= 0 else { return nil }

        let t1 = (-b + sqrt(det)) / (2 * a)
        let t2 = (-b - sqrt(det)) / (2 * a)

        let t: CGFloat
        if t1 > 0 && t2 > 0 {
            t = min(t1, t2)
        } else if t1 > 0 {
            t = t1
        } else if t2 > 0 {
            t = t2
        } else {
            return nil
        }

        return CGPoint(
            x: (x1 - x0) * t + x0,
            y: (y1 - y0) * t + y0)
    }

    fileprivate func calculateNormals(
        ray: LightRay,
        atPos: CGPoint
    ) -> (reflectionNormal: CGVector, refractionNormal: CGVector) {
        let normalTowardsCenter = CGVector(
            dx: pos.x - atPos.x,
            dy: pos.y - atPos.y)

        let normalAwayFromCenter = normalTowardsCenter.reverse()

        if calculateDistance(pos, ray.origin) >= radius {
            // The ray originates from outside the circle.
            return (
                reflectionNormal: normalAwayFromCenter,
                refractionNormal: normalTowardsCenter)
        } else {
            // The ray originates from inside the circle.
            return (
                reflectionNormal: normalTowardsCenter,
                refractionNormal: normalAwayFromCenter)
        }
    }

    func hitPoint(point: CGPoint) -> Bool {
        return sqrt(sq(point.x-pos.x) + sq(point.y-pos.y)) <= radius
    }
}

extension PolygonShape: SimulationItem {
    /// For a given ray, returns the point where the item and ray collide
    fileprivate func intersectionPoint(ray: LightRay) -> CGPoint? {
        return nil
    }

    /// Given the light ray and the intersection point, returns the reflection and the refraction normals.
    fileprivate func calculateNormals(
        ray: LightRay,
        atPos: CGPoint
    ) -> (reflectionNormal: CGVector, refractionNormal: CGVector) {
        return (CGVector.zero, CGVector.zero)
    }

    /// Returns if the provided point is contained within the item.
    internal func hitPoint(point: CGPoint) -> Bool {
        return true
    }
}
