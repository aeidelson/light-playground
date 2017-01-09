import Foundation
import UIKit
import CoreGraphics

/// A ray that has a location, direction, and
private struct LightRay {
    let originX: CGFloat
    let originY: CGFloat

    let dX: CGFloat
    let dY: CGFloat

    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    /// The recorded color will be color * (1/inverseIntensity)
    public let inverseIntensity: UInt64
}

public struct LightSegment {
    public let x0: Int
    public let y0: Int
    public let x1: Int
    public let y1: Int

    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    /// The recorded color will be color * (1/inverseIntensity)
    public let inverseIntensity: UInt64
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

/// A light simulator which operates on the CPU.
public class CPULightSimulator: LightSimulator {
    public required init(imageWidth: Int, imageHeight: Int) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight

        self.accumulator = Accumulator(
            width: imageWidth,
            height: imageHeight,
            componentsPerPixel: componentsPerPixel)

        pixelData = [UInt8](repeatElement(0, count: imageWidth * imageHeight * componentsPerPixel))
    }

    // MARK: LightSimulator

    public func start(layout: SimulationLayout) {
        precondition(Thread.isMainThread)

        let lights = layout.lights
        if lights.count == 0 {
            // No lights means this is a no-op.
            // TODO: Make the behavior here more consistent
            return
        }

        // Stop the current computation if there is one
        cleanup()

        // TODO: This should probably be segments rather than rays?
        let rays = 10000

        var segments = [LightSegment]()

        traceRays(layout: layout, producedSegments: &segments, maxSegments: rays)

        accumulator.drawSegments(segments: segments)

        cachedImage = generateImage(rays: rays)

        // TODO: Call on main thread when running in background
        onDataChange()
    }

    public func stop() {
        precondition(Thread.isMainThread)

        // TODO: Stop async tasks

        cleanup()
    }

    public var onDataChange: () -> Void = { _ in }

    public var latestSnapshot: SimulationSnapshot {
        precondition(Thread.isMainThread)

        return SimulationSnapshot(image: cachedImage)
    }

    // MARK: Private

    private func cleanup() {
        accumulator.clear()
    }

    /// Used as a temporary buffer when tracing.
    private var rayBuffer = [LightRay]()

    /// Produces light segments given the simulation layout.
    private func traceRays(
        layout: SimulationLayout,
        producedSegments: inout [LightSegment],
        maxSegments: Int
    ) {
        rayBuffer.removeAll()
        rayBuffer.reserveCapacity(maxSegments)

        // Prime rayBuffer with the rays emitting from lights. We use 1/3 to allow rays for bouncing and refraction.
        let initialRaysToCast = maxSegments// / 3

        for i in 0..<initialRaysToCast {
            let lightChosen = layout.lights[i % layout.lights.count]

            // Rays from light have both a random origin and a random direction.
            let rayOrigin = randomPointOnCircle(center: lightChosen.pos, radius: lightRadius)
            //let rayOrigin = lightChosen.pos
            //let rayDirection = CGPoint(x: 1.0, y: 100.0)
            let rayDirection = randomPointOnCircle(center: CGPoint(x: 0, y: 0), radius: 10000.0)
            rayBuffer.append(LightRay(
                originX: rayOrigin.x,
                originY: rayOrigin.y,
                dX: rayDirection.x,
                dY: rayDirection.y,
                // For now just assuming white light
                r: 255,
                g: 255,
                b: 255,
                inverseIntensity: 1))
        }

        var segmentCount = 0

        // Hardcode walls to prevent out of index.
        var allWalls = [
            Wall(pos1: CGPoint(x: 1, y: 1), pos2: CGPoint(x: imageWidth, y: 1)),
            Wall(pos1: CGPoint(x: 1, y: 1), pos2: CGPoint(x: 1, y: imageHeight)),
            Wall(pos1: CGPoint(x: imageWidth, y: 1), pos2: CGPoint(x: imageWidth, y: imageHeight)),
            Wall(pos1: CGPoint(x: 1, y: imageHeight), pos2: CGPoint(x: imageWidth, y: imageHeight))
        ]
        allWalls.append(contentsOf: layout.walls)

        while rayBuffer.count > 0 && segmentCount < maxSegments {
            let ray = rayBuffer.removeFirst()

            // For simplicty, we ignore any rays that originate outside the image
            guard insideImageBounds(x: Int(ray.originX.rounded()), y: Int(ray.originY.rounded())) else { continue }

            var closestIntersectionPoint: CGPoint?
            var closestDistance = FLT_MAX

            for wall in allWalls {
                // TODO: Should move all the (constant) ray calculations out of this loop.
                // Given the equation `y = mx + b`

                // Calculate `m`:
                let raySlope = safeDivide(ray.dY, ray.dX)
                let wallSlope = safeDivide((wall.pos2.y - wall.pos1.y), (wall.pos2.x - wall.pos1.x))
                if abs(raySlope - wallSlope) < 0.01 {
                    // They are rounghly parallel, stop processing.
                    continue
                }

                // Calculate `b` using: `b = y - mx`
                let rayYIntercept = ray.originY - raySlope * ray.originX
                let wallYIntercept = wall.pos1.y - wallSlope * wall.pos1.x


                // Calculate x-collision (derived from equations above)
                let collisionX = safeDivide((wallYIntercept - rayYIntercept), (raySlope - wallSlope))

                // Calculate y intercept using `y = mx + b`
                let collisionY = raySlope * collisionX + rayYIntercept

                // Check if the collision points are on the correct side of the light ray
                let positiveXRayDirection = ray.dX >= 0
                let positiveYRayDirection = ray.dY >= 0
                let positiveCollisionXDirection = (collisionX - ray.originX) >= 0
                let positiveCollisionYDirection = (collisionY - ray.originY) >= 0

                guard positiveXRayDirection == positiveCollisionXDirection &&
                    positiveYRayDirection == positiveCollisionYDirection else { continue }

                // Check if the collision points are inside the wall segment. Some buffer is added to handle horizontal
                // or vertical lines.
                let segmentXRange = (min(wall.pos1.x, wall.pos2.x)-0.5)...(max(wall.pos1.x, wall.pos2.x)+0.5)
                let segmentYRange = (min(wall.pos1.y, wall.pos2.y)-0.5)...(max(wall.pos1.y, wall.pos2.y)+0.5)

                let collisionInWallX = segmentXRange.contains(CGFloat(collisionX))

                let collisionInWallY = segmentYRange.contains(CGFloat(collisionY))

                guard collisionInWallX && collisionInWallY else { continue }

                // Check if the collision points are closer than the current closest
                let distFromOrigin =
                    sqrt(pow(Float(ray.originX - collisionX), 2) + pow(Float(ray.originY - collisionY), 2))


                if distFromOrigin < closestDistance {
                    closestDistance = distFromOrigin
                    closestIntersectionPoint = CGPoint(x: CGFloat(collisionX), y: CGFloat(collisionY))
                }
            }

            // Create a light segment using whatever the closest collision was

            guard  let segmentEndPoint = closestIntersectionPoint else { preconditionFailure() }

            // TODO: Should spawn rays if bouncing off wall
            producedSegments.append(LightSegment(
                x0: Int(ray.originX.rounded()),
                y0: Int(ray.originY.rounded()),
                x1: Int(segmentEndPoint.x.rounded()),
                y1: Int(segmentEndPoint.y.rounded()),
                r: ray.r,
                g: ray.g,
                b: ray.b,
                inverseIntensity: 1))

            segmentCount += 1
        }
    }

    private func insideImageBounds(x: Int, y: Int) -> Bool {
        return (x >= 0) && (x < imageWidth) && (y >= 0) && (y < imageHeight)
    }

    /// Creates an image based on the current state of the acucmulator.
    private func generateImage(rays: Int) -> CGImage? {
        let br = Float(exp(1 + 10 * exposure)) / Float(rays)

        let accumulated = accumulator.accumulated
        for i in 0..<(totalPixels) {
            let j = i * componentsPerPixel

            pixelData[j] = UInt8(min(Float(UInt8.max), Float(accumulated[j]) * br))
            pixelData[j+1] = UInt8(min(Float(UInt8.max), Float(accumulated[j]) * br))
            pixelData[j+2] = UInt8(min(Float(UInt8.max), Float(accumulated[j]) * br))

        }

        let providerRef = CGDataProvider(data: NSData(bytes: &pixelData, length: pixelData.count))
        let bitsPerPixel = componentsPerPixel * bitsPerComponent

        return CGImage(
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: imageWidth * bitsPerPixel / 8,
            space: CGColorSpaceCreateDeviceRGB(),
            // Alpha is ignored.
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: providerRef!,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent)
    }

    private let imageWidth: Int
    private let imageHeight: Int
    private let componentsPerPixel = 4
    private let bitsPerComponent = 8
    private var totalPixels: Int {
        return imageWidth * imageHeight
    }
    private var totalComponents: Int {
        return totalPixels * componentsPerPixel
    }

    private let exposure = 0.6
    private let lightRadius: CGFloat = 10.0

    /// Used to accumulate rays before rendering pixel data.
    private var accumulator: Accumulator

    /// Used as pixels for cached image.
    private var pixelData: [UInt8]

    private var cachedImage: CGImage?
}

class Accumulator {
    public init(width: Int, height: Int, componentsPerPixel: Int) {
        self.width = width
        self.height = height
        self.componentsPerPixel = componentsPerPixel

        self.accumulated = [UInt64](repeatElement(0, count: width * height * componentsPerPixel))
    }

    public var accumulated: [UInt64]

    public func clear() {
        for i in 0..<totalComponents {
            accumulated[i] = 0
        }
    }

    // Randomize all the pixels, for debugging.
    public func randomizePixels() {
        for i in 0..<(totalPixels) {
            accumulated[i*componentsPerPixel] = UInt64(arc4random() % UInt32(255))
            accumulated[i*componentsPerPixel+1] = UInt64(arc4random() % UInt32(255))
            accumulated[i*componentsPerPixel+2] = UInt64(arc4random() % UInt32(255))
        }
    }

    public func randomizeSegments(n: Int) {
        var segments = [LightSegment]()
        for _ in 0..<n {
            let p1 = randomPointOnCircle(center: CGPoint(x: CGFloat(width) / 2.0, y: CGFloat(height) / 2.0), radius: 50)
            let p2 = randomPointOnCircle(center: CGPoint(x: CGFloat(width) / 2.0, y: CGFloat(height) / 2.0), radius: 600)
            segments.append(LightSegment(
                x0: Int(p1.x.rounded()),
                y0: Int(p1.y.rounded()),
                x1: Int(p2.x.rounded()),
                y1: Int(p2.y.rounded()),
                r: UInt8(arc4random() % UInt32(255)),
                g: UInt8(arc4random() % UInt32(255)),
                b: UInt8(arc4random() % UInt32(255)),
                inverseIntensity: 1))
        }
        drawSegments(segments: segments)
    }

    public func drawSegments(segments: [LightSegment]) {
        for segment in segments {
            // Taken almost directly from:
            // https://github.com/ssloy/tinyrenderer/wiki/Lesson-1:-Bresenham%E2%80%99s-Line-Drawing-Algorithm
            var steep = false
            var x0 = segment.x0
            var y0 = segment.y0
            var x1 = segment.x1
            var y1 = segment.y1

            if abs(x0 - x1) < abs(y0 - y1) {
                swap(&x0, &y0)
                swap(&x1, &y1)
                steep = true
            }
            if x0 > x1 {
                swap(&x0, &x1)
                swap(&y0, &y1)
            }
            let dx = x1 - x0
            let dy = y1 - y0
            let derror2 = abs(dy) * 2
            var error2 = 0
            var y = y0
            for x in x0...x1 {
                let index = steep ? indexFromLocation(y, x) : indexFromLocation(x, y)
                accumulated[index] += UInt64(segment.r)/segment.inverseIntensity
                accumulated[index+1] += UInt64(segment.g)/segment.inverseIntensity
                accumulated[index+2] += UInt64(segment.b)/segment.inverseIntensity

                error2 += derror2
                if error2 > dx {
                    y += (y1 > y0 ? 1 : -1)
                    error2 -= dx * 2
                }
            }
        }
    }

    // MARK: Private

    private let width: Int
    private let height: Int
    private let componentsPerPixel: Int
    private var totalPixels: Int {
        return width * height
    }
    private var totalComponents: Int {
        return totalPixels * componentsPerPixel
    }

    /// Returns the index of the first component, and is a 1-based index.
    /// Pixels are accessible at (1, 1) through (width, height).
    func indexFromLocation(_ x: Int, _ y: Int) -> Int {
        #if DEBUG
            precondition(x >= 1)
            precondition(x <= width)
            precondition(y >= 1)
            precondition(y <= height)
        #endif

        return (y - 1) * width * componentsPerPixel + (x - 1) * componentsPerPixel
    }
}
