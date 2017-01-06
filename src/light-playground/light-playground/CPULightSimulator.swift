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

        let totalPixels = imageWidth * imageHeight

        let totalComponents = totalPixels * componentsPerPixel

        pixelData = [UInt8](repeatElement(0, count: totalComponents))
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
        stop()

        // TODO: Intersect rays and convert into segments.

        for i in 0..<(imageWidth * imageHeight) {
            pixelData[i*4] = UInt8(arc4random() % UInt32(255))
            pixelData[i*4+1] = UInt8(arc4random() % UInt32(255))
            pixelData[i*4+2] = UInt8(arc4random() % UInt32(255))
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

    public func stop() {
        precondition(Thread.isMainThread)
    }

    public var onDataChange: () -> Void = {_ in }

    public var latestSnapshot: SimulationSnapshot {
        precondition(Thread.isMainThread)

        return SimulationSnapshot(image: cachedImage)
    }

    // MARK: Private

    let imageWidth: Int
    let imageHeight: Int

    // MARK: Constants

    let componentsPerPixel = 4
    let bitsPerComponent = 8


    // MARK: Simulation state

    var pixelData: [UInt8]

    private var cachedImage: CGImage?
}
