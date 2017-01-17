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
    init(simulationSize: CGSize)

    /// Will erase any existing rays.
    func restartSimulation(layout: SimulationLayout)

    /// Will stop any further processing. No-op if the simulator hasn't been started.
    func stop()

    var simulationSnapshotObservable: Observable<SimulationSnapshot> { get }
}

public class CPULightSimulator: LightSimulator {
    public required init(simulationSize: CGSize) {
        let totalMaxSegments = 100000
        let numberOfTracers = 1

        for _ in 0..<numberOfTracers {
            let tracer = CPUTracer(
                simulationSize: simulationSize,
                maxSegmentsToTrace: totalMaxSegments/numberOfTracers)

            tracers.append(tracer)
        }


        accumulator = CPUAccumulator(simulationSize: simulationSize, tracers: tracers)

        // TODO: Unsubscribe from token on deinit
        _ = accumulator.imageObservable.subscribe(onQueue: simulatorQueue) { [weak self] image in
            guard let strongSelf = self else { return }
            strongSelf.simulationSnapshotObservable.notify(SimulationSnapshot(image: image))
        }
    }

    public func restartSimulation(layout: SimulationLayout) {
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

    /// The queue to use for any top-level simulator logic.
    private let simulatorQueue = DispatchQueue(label: "simulator_queue")
}
