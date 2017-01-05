import Foundation
import CoreGraphics

public struct Light {
    let pos: (x: Float, y: Float)
}

public struct Wall {
    let pos1, pos2: (x: Float, y: Float)
}

public struct SimulationLayout {
    public let approxRayCount: UInt64
    public let pixelDimensions: (w: Int, h: Int)
    // TODO: public let dims
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

/// All functions/variables must be called or accessed from main thread.
public protocol LightSimulator {
    /// Will erase any existing rays.
    func startWithLayout(layout: SimulationLayout)

    /// Will stop any further processing. No-op if the simulator hasn't been started, and not required before
    /// calling start again.
    func stop()

    /// Will be called when a new snapshot is available, on the main thread.
    var onDataChange:  () -> Void { get set }

    var latestSnapshot: SimulationSnapshot { get }
}
