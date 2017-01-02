import Foundation
import UIKit
import CoreGraphics

/// A light simulator which operates on the CPU.
/// TODO(aeidelson): Explore using a simulator operating on the GPU.
class CPULightSimulator: LightSimulator {
    public init() { }

    func startWithLayout(layout: SimulationLayout) {
        precondition(Thread.isMainThread)

        // TODO: Need to make sure that a scale of 1 works with the retina (since already multiplying height and width
        // ahead of time).
        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: layout.pixelDimensions.w,
                   height: layout.pixelDimensions.h),
            true,
            1.0)

        let context = UIGraphicsGetCurrentContext();
        context?.setFillColor(UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0).cgColor)
        context?.fill(CGRect(x: 0, y: 0, width: layout.pixelDimensions.w/2, height: layout.pixelDimensions.h/2))

        cachedImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage

        UIGraphicsEndImageContext()
    }

    func stop() {
        precondition(Thread.isMainThread)
    }

    var latestSnapshot: SimulationSnapshot {
        precondition(Thread.isMainThread)

        return SimulationSnapshot(image: cachedImage)
    }

    // Contains a cached image. Should only be modified on the main thread.
    var cachedImage: CGImage?
}
