import Foundation
import CoreGraphics

/* Architecture

 The simulator has the following rough architecture:

                   LightSimulator
                /    /       \     \
          Tracer  Tracer  Tracer Tracer
            |       |        |      |
      LightGrid LightGrid LightGrid LightGrid


 - LightGrid: Holds the light accumulation data (and helpers to mutate or read that data)

 - Tracer: Each is responsible for (asynchronously) tracing some number of rays and producing an accumulated grid data

 - LightSimulator: A clean interface for the UI layer to interact with

 Note: Outside of the LightGrid, everything operates in CG variables (CGFloat, CGImage, CGVector, etc.)

 */

// TODO: Consider changing all coords here to ints.

public struct Light {
    let pos: CGPoint
}

public struct Wall {
    let pos1, pos2: CGPoint
}

public struct SimulationLayout {
    public let lights: [Light]
    public let walls: [Wall]
}

/// Contains the result of the simulation (so far)
public class SimulationSnapshot {
    public init(image: CGImage?) {
        self.image = image
    }

    public let image: CGImage?
}

public struct LightColor {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8
    /// TODO: Does it make sense to also include intensity?
}

public struct LightSegment {
    public let p0: CGPoint
    public let p1: CGPoint
    public let color: LightColor
}

/// All functions/variables must be called or accessed from main thread.
public class LightSimulator {
    init(size: CGSize) {
        previewTracer = CPUTracer(completionQueue: .main, simulationSize: size)
    }

    /// Will erase any existing rays.
    func start(layout: SimulationLayout) {
        let raysToTrace = 10000

        let brightness = CGFloat(exp(1 + 10 * exposure)) / CGFloat(raysToTrace)

        previewTracer.startAsync(
            layout: layout,
            raysToTrace: raysToTrace
        ) { grid in
            cachedImage = grid.renderImage(brightness: brightness)
            onDataChange()
        }
    }

    /// Will stop any further processing. No-op if the simulator hasn't been started, and not required before
    /// calling start again.
    func stop() {
        previewTracer.stop()
    }

    /// Will be called when a new snapshot is available, on the main thread.
    var onDataChange:  () -> Void = { }

    public var latestSnapshot: SimulationSnapshot {
        precondition(Thread.isMainThread)

        return SimulationSnapshot(image: cachedImage)
    }

    // MARK: Private

    private let exposure = 0.5

    private let previewTracer: Tracer
    private var cachedImage: CGImage?
}
