import Foundation
import CoreGraphics

/// Contains the result of the simulation (so far)
public class SimulationSnapshot {
    public init(image: CGImage) {
        self.image = image
    }

    public let image: CGImage
}

public protocol LightSimulator: class {
    
    /// Will erase any existing rays.
    func restartSimulation(layout: SimulationLayout)

    /// Will stop any further processing. No-op if the simulator hasn't been started.
    func stop()

    var snapshotHandler: (SimulationSnapshot) -> Void { get set }
}

/// A context object which instances used throughout the the simulator.
class CPULightSimulatorContext {
}

public class CPULightSimulator: LightSimulator {
    public required init(simulationSize: CGSize) {

        self.simulationSize = simulationSize
        self.context = CPULightSimulatorContext()

        self.simulatorQueue = serialOperationQueue()
        self.tracerQueue = concurrentOperationQueue(tracerQueueConcurrency)

        _ = setupNewRootLightGrid()
    }

    public func restartSimulation(layout: SimulationLayout) {
        precondition(Thread.isMainThread)

        print("\(Date().timeIntervalSince1970): Simulation restart called")

        // The simulation is restarted on a background thread so we don't hold up the UI.
        simulatorQueue.addOperation {
            self.stop()

            // There's no light to trace.
            guard layout.lights.count > 0 else { return }

            self.enqueueTracersIfNeeded(layout: layout)
        }
    }

    public func stop() {
        tracerQueue.cancelAllOperations()
        _ = setupNewRootLightGrid()
        self.tracerQueue = concurrentOperationQueue(tracerQueueConcurrency)
        traceSegmentsAccountedFor = 0
    }

    public var snapshotHandler: (SimulationSnapshot) -> Void = { _ in }

    // MARK: Private

    private func setupNewRootLightGrid() -> LightGrid {
        objc_sync_enter(self.rootGrid)
        self.rootGrid?.imageHandler = { _ in }
        objc_sync_exit(self.rootGrid)

        self.rootGrid = LightGrid(context: context, generateImage: true, size: simulationSize)
        self.rootGrid?.imageHandler = { [weak self] image in
            guard let strongSelf = self else { return }
            print("\(Date().timeIntervalSince1970): Calling snapshotHandler with new image")
            strongSelf.snapshotHandler(SimulationSnapshot(image: image))
        }
        return self.rootGrid!
    }

    private func enqueueTracersIfNeeded(layout: SimulationLayout) {
        guard let rootGrid = self.rootGrid else { return }
        for _ in 0..<max((tracerQueueConcurrency - tracerQueue.operationCount), 0) {
            // The first operation is special-cased as being interactive.
            var tracerSize = standardTracerSize
            if tracerQueue.operationCount == 0 {
                tracerSize = interactiveTracerSize
            }

            tracerSize = min(tracerSize, maxSegmentsToTrace - traceSegmentsAccountedFor)

            guard tracerSize > 0 else { return }

            traceSegmentsAccountedFor += tracerSize

            // A grid for this tracer to accumulate on.
            var tracer: Operation?
            tracer = Tracer.makeTracer(
                context: context,
                rootGrid: rootGrid,
                layout: layout,
                simulationSize: simulationSize,
                segmentsToTrace: tracerSize)

            tracer?.completionBlock = { [weak self] in
                guard let strongTracer = tracer else { return }
                guard !strongTracer.isCancelled else { return }

                self?.simulatorQueue.addOperation { [weak self] in
                    self?.enqueueTracersIfNeeded(layout: layout)
                }
            }
            
            tracerQueue.addOperation(tracer!)
        }
    }

    private let interactiveTracerSize = 5_000
    private let standardTracerSize = 10_000
    private let maxSegmentsToTrace = 10_000_000
    private var traceSegmentsAccountedFor = 0

    private let simulationSize: CGSize

    private let context: CPULightSimulatorContext

    /// The queue to use for any top-level simulator logic.
    private let simulatorQueue: OperationQueue

    /// The queue to run traces on
    private var tracerQueue: OperationQueue

    private let tracerQueueConcurrency = ProcessInfo.processInfo.activeProcessorCount

    /// The grid that everything aggregrated to.
    private var rootGrid: LightGrid?
}
