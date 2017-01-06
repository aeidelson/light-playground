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

        accumulator.randomize()

        // TODO: Intersect rays and convert into segments.

        let accumulated = accumulator.accumulated
        for i in 0..<(totalComponents) {
            pixelData[i] = UInt8(accumulated[i])
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

    public func randomize() {
        for i in 0..<(totalPixels) {
            accumulated[i*componentsPerPixel] = UInt64(arc4random() % UInt32(255))
            accumulated[i*componentsPerPixel+1] = UInt64(arc4random() % UInt32(255))
            accumulated[i*componentsPerPixel+2] = UInt64(arc4random() % UInt32(255))
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
}
