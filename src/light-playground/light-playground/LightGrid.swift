import Foundation
import CoreGraphics


protocol LightGrid: class {

    /// Setting this updates some properties affecting the render. May trigger an update to the
    /// image.
    var renderProperties: RenderImageProperties { get set }

    /// Is called any time the light grid is updated. Is called on the thread which triggered the
    /// update.
    var imageHandler: (CGImage) -> Void { get set }

    /// Reset the light grid to the  to a state as if it was just created. Called as an optimization
    /// rather than re-creating array buffers.
    func reset()

    /// Draw the specfied light segments to the light grid. lowQuality indicates if the faster
    /// drawing method should be used.
    func drawSegments(layout: SimulationLayout, segments: [LightSegment], lowQuality: Bool)
}
