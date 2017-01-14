import Foundation
import CoreGraphics

/// Is responsible for asynchronously tracing rays in the scene.
protocol Tracer {
    init(completionQueue: DispatchQueue, simulationSize: CGSize)
    
    /// Will stop the currently running trace if there is one. `completion` method will be called on some provided
    /// completion queue.
    func startAsync(layout: SimulationLayout, raysToTrace: Int, completion: (LightGrid) -> Void)

    /// Is no-op if there isn't a trace running.
    func stop()
}
