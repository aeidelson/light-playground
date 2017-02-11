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

    /// Volume attributes applying to empty space in a scene.
    private static let spaceVolumeAttributes = VolumeAttributes(indexOfRefraction: 1)

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

        // Prime rayBuffer with the rays emitting from lights. Half of the remaining segments alloted are used for
        // bounces.
        // TODO: Figure out a smarter way to allow for more rays (maybe based on the number of objects in the scene?)
        let initialRaysToCast = maxSegments / 2

        for i in 0..<initialRaysToCast {
            let lightChosen = layout.lights[i % layout.lights.count]

            // Rays from light have both a random origin and a random direction.
            let rayOrigin = lightChosen.pos
            let rayDirectionPoint = randomPointOnCircle(center: CGPoint(x: 0, y: 0), radius: 300.0)
            let rayDirection = NormalizedVector(dx: rayDirectionPoint.x, dy: rayDirectionPoint.y)
            rayQueue.append(LightRay(
                origin: rayOrigin,
                direction: rayDirection,
                color: lightChosen.color,
                sourceVolumeAttributes: spaceVolumeAttributes))
        }

        // Hardcode walls to prevent out of index.
        let minX: CGFloat = 1.0
        let minY: CGFloat = 1.0
        let maxX: CGFloat = simulationSize.width - 2.0
        let maxY: CGFloat = simulationSize.height - 2.0
        let surfaceAttributes = SurfaceAttributes(absorption: 1.0, diffusion: 0)
        var allItems: [LightIntersectionItem] = [
            Wall(pos1: CGPoint(x: minX, y: minY), pos2: CGPoint(x: maxX, y: minY),
                surfaceAttributes: surfaceAttributes),
            Wall(pos1: CGPoint(x: minX, y: minY), pos2: CGPoint(x: minX, y: maxY),
                 surfaceAttributes: surfaceAttributes),
            Wall(pos1: CGPoint(x: maxX, y: minY), pos2: CGPoint(x: maxX, y: maxY),
                 surfaceAttributes: surfaceAttributes),
            Wall(pos1: CGPoint(x: minX, y: maxY), pos2: CGPoint(x: maxX, y: maxY),
                 surfaceAttributes: surfaceAttributes)
        ]
        allItems.append(contentsOf: layout.walls as [LightIntersectionItem])
        allItems.append(contentsOf: layout.circleShapes as [LightIntersectionItem])

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
            var closestIntersectionItem: LightIntersectionItem?
            var closestDistance = CGFloat.greatestFiniteMagnitude

            for item in allItems {
                guard let intersectionPoint = item.intersectionPoint(ray: ray) else { continue }

                // Check if the intersection points are closer than the current closest
                let distFromOrigin =
                    sqrt(pow(ray.origin.x - intersectionPoint.x, 2) + pow(ray.origin.y - intersectionPoint.y, 2))


                if distFromOrigin < closestDistance {
                    closestDistance = distFromOrigin
                    closestIntersectionItem = item
                    closestIntersectionPoint = intersectionPoint
                }
            }
            
            // Create a light segment using whatever the closest intersection was
            
            guard let intersectionPoint = closestIntersectionPoint else { preconditionFailure() }
            /// This must be set, since the grid is surrounded by walls.
            guard let intersectionItem = closestIntersectionItem else { preconditionFailure() }

            // Return the light segment for drawing of the ray.
            producedSegments.append(LightSegment(
                p0: ray.origin,
                p1: intersectionPoint,
                color: ray.color))

            // Now we may spawn some more rays depending on the ray and attributes of the intersectionItem.

            // TODO: Stop if the ray is too dark to begin with
            guard intersectionItem.surfaceAttributes.absorption < 0.99 else { continue }

            let colorAfterAbsorbtion =  ray.color.multiplyBy(1 - intersectionItem.surfaceAttributes.absorption)

            let normals = intersectionItem.calculateNormals(ray: ray, atPos: intersectionPoint)

            let reverseIncomingDirection = rotate(ray.direction, CGFloat(M_PI))

            let incomingAngleFromNormal = angle(normals.reflectionNormal, reverseIncomingDirection)

            // Fresnel equations determines how much is reflected vs refracted.
            let percentReflected: CGFloat
            if let newAttributes = intersectionItem.optionalVolumeAttributes {
                percentReflected = calculateReflectance(
                    fromVolume: VolumeAttributes(indexOfRefraction: 1.0),
                    toVolume: newAttributes,
                    incomingAngleFromNormal: incomingAngleFromNormal)
            } else {
                percentReflected = 1.0
            }

            // Calculate a reflected ray.

            // TODO: Much of this can be done ahead of time and cleaned up.
            // TODO: Don't bother with the reflected ray if the ammount reflected is small.

            var reflectedRayDirection = normalize(
                rotate(reverseIncomingDirection, -2 * incomingAngleFromNormal))

            // Adjust the reflected ray for diffusion:
            if intersectionItem.surfaceAttributes.diffusion > 0.0 {
                let normalAngle = absoluteAngle(normals.reflectionNormal)

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
                    CGFloat(M_PI / 8) * intersectionItem.surfaceAttributes.diffusion, closestAngleDifference - 0.1)
                let diffuseAngle = CGFloat(drand48()) * 2 * maxDiffuseAngle - maxDiffuseAngle
                reflectedRayDirection = rotate(reflectedRayDirection, diffuseAngle)
            }

            /// Start the ray off with a small head-start so it doesn't collide with the item it intersected with.
            let reflectedRayOrigin = CGPoint(
                x: intersectionPoint.x + reflectedRayDirection.dx * 0.1,
                y: intersectionPoint.y + reflectedRayDirection.dy * 0.1)

            // Calculate the refracted ray

            if var newRayAttributes = intersectionItem.optionalVolumeAttributes {
                // If the attributes are the same as the ray's current attributes, then assume the original ray
                // intersected with the outer wall and is now in space.
                // HACK: This assumption doesn't hold when objects overlap, and is generally error-prone. We probably
                // need to be able to hit-test the ray's origin to determin the volume attributes (rather than storing
                // them on the ray).
                if newRayAttributes == ray.sourceVolumeAttributes {
                    newRayAttributes = spaceVolumeAttributes
                }

                let percentTransmitted: CGFloat = 1.0 - percentReflected
                let n1 = ray.sourceVolumeAttributes.indexOfRefraction
                let n2 = newRayAttributes.indexOfRefraction

                let refractedAngleFromNormal = asin(sin(incomingAngleFromNormal) * n1 / n2)

                let rayDirection = rotate(normals.refractionNormal, refractedAngleFromNormal)

                /// Start the ray off with a small head-start so it doesn't collide with the item it intersected with.
                let rayOrigin = CGPoint(
                    x: intersectionPoint.x + rayDirection.dx * 0.1,
                    y: intersectionPoint.y + rayDirection.dy * 0.1)

                let refractedRay = LightRay(
                    origin: rayOrigin,
                    direction: rayDirection,
                    color: ray.color.multiplyBy(percentTransmitted),
                    sourceVolumeAttributes: newRayAttributes)

                rayQueue.append(refractedRay)
            }

            let reflectedRay = LightRay(
                origin: reflectedRayOrigin,
                direction: reflectedRayDirection,
                color: colorAfterAbsorbtion.multiplyBy(percentReflected),
                /// Because the ray is a reflection, it will share the same attributes as the original ray.
                sourceVolumeAttributes: ray.sourceVolumeAttributes)

            rayQueue.append(reflectedRay)
        }

        return producedSegments
    }
}

// MARK: Private

/// Calculates the percentage of light that is reflected, using Fresnel equations.
/// Equations taken from: https://en.wikipedia.org/wiki/Fresnel_equations
private func calculateReflectance(
    fromVolume: VolumeAttributes,
    toVolume: VolumeAttributes,
    incomingAngleFromNormal: CGFloat
) -> CGFloat {
    let n1 = fromVolume.indexOfRefraction
    let n2 = toVolume.indexOfRefraction

    // Is used commonly
    let ratioSinAngleSquared = pow((n1 / n2) * sin(incomingAngleFromNormal), 2)

    // Calculate Rs
    let rsPart1 = n1 * cos(incomingAngleFromNormal)
    let rsPart2 = n2 * sqrt(1 - ratioSinAngleSquared)
    let rs = pow((rsPart1 - rsPart2) / (rsPart1 + rsPart2), 2)

    // Calculate Rp
    let rpPart1 = n1 * sqrt(1 - ratioSinAngleSquared)
    let rpPart2 = n2 * cos(incomingAngleFromNormal)
    let rp = pow((rpPart1 - rpPart2) / (rpPart1 + rpPart2), 2)


    /// Protect against values > 1
    return min((rs + rp) / 2, 1.0)
}

private func randomPointOnCircle(center: CGPoint, radius: CGFloat) -> CGPoint {
    let radians = CGFloat(drand48() * 2.0 * M_PI)
    return CGPoint(
        x: center.x + radius * cos(radians),
        y: center.y + radius * sin(radians)
    )
}

fileprivate func calculateDistance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))

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

// MARK: Ray intersections

fileprivate struct LightRay {
    public let origin: CGPoint
    public let direction: NormalizedVector
    public let color: LightColor

    /// The volume attributes of where the ray was produced.
    /// For rays in space (i.e. coming from lights or in-between items), this will be `spaceVolumeAttributes`. For rays
    /// inside of an object with volume, this will be that object's attributes.
    public let sourceVolumeAttributes: VolumeAttributes
}

fileprivate protocol LightIntersectionItem {

    /// All intersection items must have a surface and so they must have surface attributes.
    var surfaceAttributes: SurfaceAttributes { get }

    /// Not all intersection items have volume (i.e. walls), so this property is optional.
    /// For now, this property being set indicates that light can go through the item (the ammount of light reflected
    /// will be calculated based on the normal).
    /// TODO: Should consider using a translucency property on the surface to indicate if light can go through the
    /// object.
    var optionalVolumeAttributes: VolumeAttributes? { get }

    /// For a given ray, returns the point where the item and ray collide
    func intersectionPoint(ray: LightRay) -> CGPoint?

    /// Given the light ray and the intersection point, returns the reflection and the refraction normals.
    func calculateNormals(ray: LightRay, atPos: CGPoint) ->
        (reflectionNormal: NormalizedVector, refractionNormal: NormalizedVector)
}

extension Wall: LightIntersectionItem {
    /// Walls don't have any volume.
    fileprivate var optionalVolumeAttributes: VolumeAttributes? { return nil }

    /// For a given ray, returns the point where the item and ray collide
    fileprivate func intersectionPoint(ray: LightRay) -> CGPoint? {
        // TODO: Should move all the (constant) ray calculations out of this loop.
        // Given the equation `y = mx + b`

        // Calculate `m`:
        let raySlope = safeDivide(ray.direction.dy, ray.direction.dx)
        let wallSlope = safeDivide((pos2.y - pos1.y), (pos2.x - pos1.x))
        if abs(raySlope - wallSlope) < 0.01 {
            // They are rounghly parallel, stop processing.
            return nil
        }

        // Calculate `b` using: `b = y - mx`
        let rayYIntercept = ray.origin.y - raySlope * ray.origin.x
        let wallYIntercept = pos1.y - wallSlope * pos1.x

        // Calculate x-intersection (derived from equations above)
        let intersectionX = safeDivide((wallYIntercept - rayYIntercept), (raySlope - wallSlope))

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
        let segmentXRange = (min(pos1.x, pos2.x)-0.5)...(max(pos1.x, pos2.x)+0.5)
        let segmentYRange = (min(pos1.y, pos2.y)-0.5)...(max(pos1.y, pos2.y)+0.5)

        let intersectionInWallX = segmentXRange.contains(intersectionX)

        let intersectionInWallY = segmentYRange.contains(intersectionY)

        guard intersectionInWallX && intersectionInWallY else { return nil }

        return CGPoint(x: intersectionX, y: intersectionY)
    }

    /// Given the light ray and the intersection point, returns the reflection and the refraction normals.
    fileprivate func calculateNormals(
        ray: LightRay,
        atPos: CGPoint
    ) -> (reflectionNormal: NormalizedVector, refractionNormal: NormalizedVector) {

        // Calculate the normal of the wall
        let dx = pos2.x - pos1.x
        let dy = pos2.y - pos1.y

        // To get the direction of the ray
        let reverseIncomingDirection = rotate(ray.direction, CGFloat(M_PI))

        let normal1 = NormalizedVector(dx: -dy, dy: dx)
        let normal2 = NormalizedVector(dx: dy, dy: -dx)

        let reflectionNormal: NormalizedVector
        let refractionNormal: NormalizedVector

        if abs(angle(normal1, reverseIncomingDirection)) < CGFloat(M_PI_2) {
            reflectionNormal = normal1
            refractionNormal = normal2
        } else {
            reflectionNormal = normal2
            refractionNormal = normal1
        }

        return (reflectionNormal: reflectionNormal, refractionNormal: refractionNormal)
    }
}

extension CircleShape: LightIntersectionItem {
    fileprivate var optionalVolumeAttributes: VolumeAttributes? { return volumeAttributes }

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

        let a = pow(x1 - x0, 2) + pow(y1 - y0, 2)
        let b = 2 * (x1 - x0) * (x0 - h) + 2 * (y1 - y0) * (y0 - k)
        let c = pow(x0 - h, 2) + pow(y0 - k, 2) - pow(r, 2)

        let det = pow(b, 2) - 4 * a * c

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
    ) -> (reflectionNormal: NormalizedVector, refractionNormal: NormalizedVector) {
        let normalTowardsCenter = NormalizedVector(
            dx: pos.x - atPos.x,
            dy: pos.y - atPos.y)

        let normalAwayFromCenter = rotate(normalTowardsCenter, CGFloat(M_PI))

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
}
