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
    func restartSimulation(layout: SimulationLayout, isInteractive: Bool)

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
        self.simulatorQueue.qualityOfService = .userInteractive
        self.tracerQueue = concurrentOperationQueue(tracerQueueConcurrency)
        self.tracerQueue.qualityOfService = .userInitiated

        self.rootGrid = LightGrid(context: context, generateImage: true, size: simulationSize)
        self.currentLayout = SimulationLayout(lights: [], walls: [])
    }

    public func restartSimulation(layout: SimulationLayout, isInteractive: Bool) {
        precondition(Thread.isMainThread)

        // The simulation is restarted on a background thread so we don't hold up the UI.
        simulatorQueue.addOperation { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.currentLayout = layout

            strongSelf.stop()

            // There's no light to trace.
            guard layout.lights.count > 0 else { return }

            strongSelf.traceSegmentsLeft = isInteractive ?
                strongSelf.interactiveMaxSegmentsToTrace : strongSelf.finalMaxSegmentsToTrace

            strongSelf.enqueueTracersIfNeeded()
        }
    }

    public func stop() {
        tracerQueue.cancelAllOperations()
        _ = setupNewRootLightGrid()
        self.tracerQueue = concurrentOperationQueue(tracerQueueConcurrency)
        self.tracerQueue.qualityOfService = .userInitiated
        traceSegmentsLeft = 0
    }

    public var snapshotHandler: (SimulationSnapshot) -> Void = { _ in }

    // MARK: Private

    private func setupNewRootLightGrid() -> LightGrid {
        objc_sync_enter(self.rootGrid)
        self.rootGrid.imageHandler = { _ in }
        objc_sync_exit(self.rootGrid)

        self.rootGrid = LightGrid(context: context, generateImage: true, size: simulationSize)
        self.rootGrid.imageHandler = { [weak self] image in
            guard let strongSelf = self else { return }
            strongSelf.snapshotHandler(SimulationSnapshot(image: image))
        }
        return self.rootGrid
    }

    private func enqueueTracersIfNeeded() {
        for _ in 0..<max((tracerQueueConcurrency - tracerQueue.operationCount), 0) {
            // The first operation is special-cased as being interactive.
            var tracerSize = standardTracerSize
            /*
            if tracerQueue.operationCount == 0 {
                tracerSize = interactiveTracerSize
            }*/

            tracerSize = min(tracerSize, traceSegmentsLeft)

            guard tracerSize > 0 else { return }

            traceSegmentsLeft -= tracerSize

            // A grid for this tracer to accumulate on.
            var tracer: Operation?
            tracer = Tracer.makeTracer(
                context: context,
                rootGrid: rootGrid,
                layout: currentLayout,
                simulationSize: simulationSize,
                segmentsToTrace: tracerSize)

            tracer?.completionBlock = { [weak self] in
                guard let strongTracer = tracer else { return }
                guard !strongTracer.isCancelled else { return }

                self?.simulatorQueue.addOperation { [weak self] in
                    self?.enqueueTracersIfNeeded()
                }
            }

            tracerQueue.addOperation(tracer!)
        }
    }

    private let standardTracerSize = 10_000
    private let interactiveMaxSegmentsToTrace = 200
    private let finalMaxSegmentsToTrace = 10_000_000
    private var traceSegmentsLeft = 0


    private let simulationSize: CGSize

    private let context: CPULightSimulatorContext

    /// The queue to use for any top-level simulator logic.
    private let simulatorQueue: OperationQueue

    /// The queue to run traces on
    private var tracerQueue: OperationQueue

    private let tracerQueueConcurrency = ProcessInfo.processInfo.activeProcessorCount

    /// The grid that everything aggregrated to.
    private var rootGrid: LightGrid

    private var currentLayout: SimulationLayout
}
