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
    public init() {
        rayQueue = Array(
            // See declaration of rayQueue for what each index means.
            repeating: Array(repeating: Float(), count: 5),
            count: rayBatchSize)
    }

    // MARK: LightSimulator

    /// TODO: Look at https://github.com/scanlime/zenphoton/blob/bea23c1b2a7b7e68f8a8c3bb5ce4afd710005a22/html/src/worker-asm-shell.coffee#L200
    public func startWithLayout(layout: SimulationLayout) {
        precondition(Thread.isMainThread)

        let lights = layout.lights
        if lights.count == 0 {
            // No lights means this is a no-op.
            return
        }

        // Stop the current computation if there is one
        stop()

        // Populate with rabdom ray directions.
        for i in 0..<rayBatchSize {
            // Figure out which light the ray is coming from.
            let light = lights[i % lights.count]

            rayQueue[i][0] = light.pos.x;
            rayQueue[i][1] = light.pos.y;
            rayQueue[i][2] = (Float(arc4random()) - Float(UInt32.max)/2)
            rayQueue[i][3] = (Float(arc4random()) - Float(UInt32.max)/2)
            rayQueue[i][4] = 1.0
        }

        // TODO: Intersect rays and convert into segments.

        let imageSize = CGSize(width: layout.pixelDimensions.w,
                               height: layout.pixelDimensions.h)
        let imageRect = CGRect(origin: CGPoint(x: 0, y: 0), size: imageSize)

        UIGraphicsBeginImageContextWithOptions(imageSize, true, 1.0)

        guard let context = UIGraphicsGetCurrentContext() else { return };

        if let cachedImage = cachedImage, let copiedImage = cachedImage.copy() {
            // We flip the context, since otherwise the image is drawn upside-down.
            context.translateBy(x: 0, y: imageRect.height)
            context.scaleBy(x: 1.0, y: -1.0)
            context.draw(copiedImage, in: imageRect)
            context.scaleBy(x: 1.0, y: -1.0)
            context.translateBy(x: 0, y: -imageRect.height)
        }

        let exposure = 0.5
        let brightness = exp(1 + 10.0*exposure) / Double(rayBatchSize)
        let alpha = CGFloat(brightness)

        Swift.print("alpha: \(alpha)")

        // Draw each segment.
        // TODO: For now just drawing rays.
        for i in 0..<rayBatchSize {
            context.setLineWidth(3.0)
            context.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: alpha)

            let rayX = rayQueue[i][0]
            let rayY = rayQueue[i][1]
            let rayDX = rayQueue[i][2]
            let rayDY = rayQueue[i][3]

            context.move(to: CGPoint(x: CGFloat(rayX), y: CGFloat(rayY)))
            context.addLine(to: CGPoint(x: CGFloat(rayX + rayDX * 1000), y: CGFloat(rayY + rayDY * 10000)))
            context.strokePath()
        }

        cachedImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage

        // TODO: Call on main thread
        onDataChange()

        UIGraphicsEndImageContext()
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

    // MARK: Constants

    /// The number of rays to process at a time.
    let rayBatchSize: Int = 20000

    // MARK: Simulation state

    private var cachedImage: CGImage?
    /// A 2D array of the format [[x, y, dx, dy, intensity]]
    private var rayQueue: [[Float]]
}
