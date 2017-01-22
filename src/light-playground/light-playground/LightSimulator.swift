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
    init() {
    }

    public let lightSegmentArrayManager = UnsafeArrayManager<LightSegment>()
}

public class CPULightSimulator: LightSimulator {
    public required init(simulationSize: CGSize) {

        context = CPULightSimulatorContext()

        var managedQueues = [(DispatchQueue, OperationQueue)]()

        let simulatorManagedQueue = serialOperationQueue()
        managedQueues.append(simulatorManagedQueue)
        simulatorQueue = simulatorManagedQueue.1

        let tracerConfigs = [
            (100_000, 1_000),
            (1_000_000, 10_000),
        ]

        //let tracerSegmentMax = [5_000, 10_000_000]
        //let tracerSegmentMax = [1_000_000_000, 1_000_000_000, 1_000_000_000, 1_000_000_000]
        for config in tracerConfigs {
            let traceManagedQueue = serialOperationQueue()
            managedQueues.append(traceManagedQueue)

            let tracer = CPUTracer(
                context: context,
                traceQueue: traceManagedQueue.1,
                simulationSize: simulationSize,
                maxSegmentsToTrace: config.0,
                segmentBatchSize: config.1)

            tracers.append(tracer)
        }

        let accumulatorManagedQueue = serialOperationQueue()
        managedQueues.append(accumulatorManagedQueue)

        accumulator = CPUAccumulator(
            context: context,
            accumulatorQueue: accumulatorManagedQueue.1,
            simulationSize: simulationSize,
            tracers: tracers)

        managedSerialQueues = managedQueues

        // TODO: Unsubscribe from token on deinit
        _ = accumulator.imageObservable.subscribe(onQueue: simulatorQueue) { [weak self] image in
            guard let strongSelf = self else { return }
            strongSelf.simulationSnapshotObservable.notify(SimulationSnapshot(image: image))
        }
    }

    public func restartSimulation(layout: SimulationLayout) {
        // Flush all of the operation queues.
        for managedQueue in managedSerialQueues {
            managedQueue.1.cancelAllOperations()
        }
        for managedQueue in managedSerialQueues {
            managedQueue.1.waitUntilAllOperationsAreFinished()
        }

        accumulator.reset()

        // Clean up any light segment arrays that shouldn't be in use anymore (since we've killed all operations)
        context.lightSegmentArrayManager.releaseAll()

        for tracer in tracers {
            tracer.restartTrace(layout: layout)
        }
    }

    public func stop() {
        for tracer in tracers {
            tracer.stop()
        }
    }

    public var simulationSnapshotObservable = Observable<SimulationSnapshot>()

    // MARK: Internal

    let lightSegmentArrayManager = UnsafeArrayManager<LightSegment>()

    // MARK: Private

    private let context: CPULightSimulatorContext
    private let accumulator: Accumulator
    private var tracers = [Tracer]()

    // Contains queues which are automatically cleared when the simulation layout changes.
    private var managedSerialQueues: [(DispatchQueue, OperationQueue)]

    /// The queue to use for any top-level simulator logic.
    private let simulatorQueue: OperationQueue
}
