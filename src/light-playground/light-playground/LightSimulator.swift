import Foundation
import CoreGraphics

/// Contains the result of the simulation (so far)
public class SimulationSnapshot {
    public init(image: CGImage) {
        self.image = image
    }

    public let image: CGImage
}

public protocol LightSimulator {
    
    /// Will erase any existing rays.
    func restartSimulation(layout: SimulationLayout)

    /// Will stop any further processing. No-op if the simulator hasn't been started.
    func stop()

    var simulationSnapshotObservable: Observable<SimulationSnapshot> { get }
}

public class CPULightSimulator: LightSimulator {
    public required init(simulationSize: CGSize) {
        var managedQueues = [OperationQueue]()

        simulatorQueue = serialOperationQueue()
        managedQueues.append(simulatorQueue)

        let tracerSegmentMax = [5_000, 10_000_000]
        for segmentMax in tracerSegmentMax {
            let traceQueue = serialOperationQueue()
            managedQueues.append(traceQueue)

            let tracer = CPUTracer(
                traceQueue: traceQueue,
                simulationSize: simulationSize,
                maxSegmentsToTrace: segmentMax)

            tracers.append(tracer)
        }

        let accumulatorQueue = serialOperationQueue()
        managedQueues.append(accumulatorQueue)

        accumulator = CPUAccumulator(
            accumulatorQueue: accumulatorQueue,
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
        // This must happen first, so the work is started below.
        for queue in managedSerialQueues {
            queue.cancelAllOperations()
        }

        for tracer in tracers {
            tracer.restartTrace(layout: layout)
        }

        accumulator.reset()
    }

    public func stop() {
        for tracer in tracers {
            tracer.stop()
        }
    }

    public var simulationSnapshotObservable = Observable<SimulationSnapshot>()

    // MARK: Private

    private let accumulator: Accumulator
    private var tracers = [Tracer]()

    // Contains queues which are automatically cleared when the simulation layout changes.
    private var managedSerialQueues: [OperationQueue]

    /// The queue to use for any top-level simulator logic.
    private let simulatorQueue: OperationQueue

    private func createManagedSerialQueue() -> OperationQueue {
        let queue = serialOperationQueue()
        managedSerialQueues.append(queue)
        return queue
    }
}
