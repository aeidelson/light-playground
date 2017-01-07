import Foundation
import UIKit
import CoreGraphics

/// A ray that has a location, direction, and
private struct LightRay {
    let pos: CGPoint
    let dir: CGVector
    let intensity: Float
    // TODO: Add color information
}

/// A light simulator which operates on the CPU.
/// TODO(aeidelson): Explore using a simulator operating on the GPU.
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
            return
        }

        // Stop the current computation if there is one
        cleanup()

        let rays = 100000

        let exposure = 0.65
        let br = Float(exp(1 + 10 * exposure)) / Float(rays)

        accumulator.randomizeSegments(n: rays)

        // TODO: Intersect rays and convert into segments.

        let accumulated = accumulator.accumulated
        for i in 0..<(totalPixels) {
            let j = i * componentsPerPixel

            pixelData[j] = UInt8(min(Float(UInt8.max), Float(accumulated[j]) * br))
            //print("\((pixelData[j], accumulated[j]))")
            pixelData[j+1] = UInt8(min(Float(UInt8.max), Float(accumulated[j]) * br))
            pixelData[j+2] = UInt8(min(Float(UInt8.max), Float(accumulated[j]) * br))

        }

        let providerRef = CGDataProvider(data: NSData(bytes: &pixelData, length: pixelData.count))
        let bitsPerPixel = componentsPerPixel * bitsPerComponent

        cachedImage = CGImage(
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

        // TODO: Call on main thread
        onDataChange()
    }

    // Draws lines (in CG space) onto the pixelData.
    public func drawLines(segments: [(p1: CGPoint, p2: CGPoint)]) {

    }

    public func stop() {
        precondition(Thread.isMainThread)

        // TODO: Stop async tasks

        cleanup()
    }

    public var onDataChange: () -> Void = {_ in }

    public var latestSnapshot: SimulationSnapshot {
        precondition(Thread.isMainThread)

        return SimulationSnapshot(image: cachedImage)
    }

    // MARK: Private

    let imageWidth: Int
    let imageHeight: Int
    let componentsPerPixel = 4
    let bitsPerComponent = 8
    var totalPixels: Int {
        return imageWidth * imageHeight
    }
    var totalComponents: Int {
        return totalPixels * componentsPerPixel
    }

    private func cleanup() {
        accumulator.clear()
    }

    // MARK: Simulation state

    // Used to accumulate rays before rendering pixel data.
    var accumulator: Accumulator

    // Used as pixels for cached image.
    var pixelData: [UInt8]

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
        var segments = [LineSegment]()
        for _ in 0..<n {
            segments.append(LineSegment(
                x0: Int(arc4random() % UInt32(width)),
                y0: Int(arc4random() % UInt32(height)),
                x1: Int(arc4random() % UInt32(width)),
                y1: Int(arc4random() % UInt32(height)),
                r: UInt8(arc4random() % UInt32(255)),
                g: UInt8(arc4random() % UInt32(255)),
                b: UInt8(arc4random() % UInt32(255)),
                inverseIntensity: 1))
        }
        drawSegments(segments: segments)
    }

    public struct LineSegment {
        public let x0: Int
        public let y0: Int
        public let x1: Int
        public let y1: Int

        public let r: UInt8
        public let g: UInt8
        public let b: UInt8

        // The recorded color will be color * (1/inverseIntensity)
        public let inverseIntensity: UInt64
    }

    public func drawSegments(segments: [LineSegment]) {
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

    // Returns the index of the first component.
    func indexFromLocation(_ x: Int, _ y: Int) -> Int {
        #if DEBUG
        precondition(x < width)
        precondition(y < height)
        #endif

        return y * width * componentsPerPixel + x * componentsPerPixel
    }
}
