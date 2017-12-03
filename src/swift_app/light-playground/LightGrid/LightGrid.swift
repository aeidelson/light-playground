import Foundation
import CoreGraphics

protocol LightGrid: class {

    /// Setting this updates some properties affecting the render. Should trigger an update to the image if
    /// an important value actually changes.
    var renderProperties: RenderImageProperties { get set }

    /// Is called any time the light grid is updated. Is called on the thread which triggered the
    /// update.
    var snapshotHandler: (SimulationSnapshot) -> Void { get set }

    /// Reset the light grid to the  to a state as if it was just created. Called as an optimization
    /// rather than re-creating array buffers.
    /// The provided bool indicates if the image should be updated and `snapshotHandler` called. This is
    /// important because in cases where we reset and there are still lights in the scene, it's a better
    /// user experience to not have the screen go black until the next frame is drawn.
    func reset(updateImage: Bool)

    /// Draw the specfied light segments to the light grid. lowQuality indicates if the faster
    /// drawing method should be used.
    /// If `layout.version` is < than the max the LightGrid has seen, then it can be assumed that
    /// the caller is out of date and this call should be ignored.
    func drawSegments(layout: SimulationLayout, segments: [LightSegment], lowQuality: Bool)
}

public struct SimulationSnapshot {
    public let image: CGImage
    public let totalLightSegmentsTraced: UInt64
}
