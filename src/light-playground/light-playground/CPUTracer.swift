import Foundation
import CoreGraphics

private struct LightRay {
    public let origin: CGPoint
    public let direction: CGVector
    public let color: LightColor
}

class CPUTracer: Tracer {
    required public init(completionQueue: DispatchQueue) {
        self.completionQueue = completionQueue
    }

    func startAsync(layout: SimulationLayout, raysToTrace: Int, completion: (LightGrid) -> Void) {

    }

    func stop() {

    }

    // MARK: Private

    private let completionQueue: DispatchQueue
}
