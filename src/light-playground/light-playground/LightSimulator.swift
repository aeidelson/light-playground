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

    var simulationSnapshotObservable: Observable<SimulationSnapshot> { get }
}

/// A context object which instances used throughout the the simulator.
class CPULightSimulatorContext {
}

public class CPULightSimulator: LightSimulator {
    public required init(simulationSize: CGSize) {

        self.simulationSize = simulationSize
        self.context = CPULightSimulatorContext()

        self.simulatorQueue = serialOperationQueue()
        self.tracerQueue = concurrentOperationQueue(10)
        self.grid = LightGrid(context: context, size: simulationSize)

        // TODO: Unsubscribe from token on deinit
        _ = grid.imageObservable.subscribe(onQueue: simulatorQueue) { [weak self] image in
            guard let strongSelf = self else { return }
            strongSelf.simulationSnapshotObservable.notify(SimulationSnapshot(image: image))
        }
    }

    public func restartSimulation(layout: SimulationLayout) {
        stop()

        // There's no light to trace.
        guard layout.lights.count > 0 else { return }

        // Seed the operation queue with a number of operations maxing out the queue (plus a couple).
        for _ in 0..<(concurrentOperations+2) {
            enqueueTracer(layout: layout)
        }
    }

    public func stop() {
        measure("tracerQueue.cancelAllOperations()") {
            tracerQueue.cancelAllOperations()
        }

        measure("tracerQueue.waitUntilAllOperationsAreFinished()") {
            tracerQueue.waitUntilAllOperationsAreFinished()
        }
        measure("grid.reset()") {
            grid.reset()
        }

        segmentsAccountedFor = 0
    }

    public var simulationSnapshotObservable = Observable<SimulationSnapshot>()

    // MARK: Private

    private func enqueueTracer(layout: SimulationLayout) {
        print("QueueSize: \(tracerQueue.operationCount)")
        let segmentsToTrace = min(maxSegmentsToTrace - segmentsAccountedFor, maxSegmentsPerTracer)

        guard segmentsToTrace != 0 else { return }

        segmentsAccountedFor += segmentsToTrace

        let tracer = Tracer.makeTracer(
            context: context,
            grid: grid,
            layout: layout,
            simulationSize: simulationSize,
            maxSegmentsToTrace: segmentsToTrace)

        // When the tracer finishes, enqueue another one.
        tracer.completionBlock = { [weak self] in
            // TODO: Retain cycle?
            if !tracer.isCancelled {
                self?.enqueueTracer(layout: layout)
            }
        }

        tracerQueue.addOperation(tracer)
    }


    private var segmentsAccountedFor = 0
    private let maxSegmentsToTrace = 1_000_000
    private let maxSegmentsPerTracer = 10000

    private let simulationSize: CGSize

    private let context: CPULightSimulatorContext

    /// The queue to use for any top-level simulator logic.
    private let simulatorQueue: OperationQueue

    /// The queue to run traces on
    private let tracerQueue: OperationQueue

    private let concurrentOperations = 10

    /// The grid that everything is drawn to.
    private let grid: LightGrid
}
