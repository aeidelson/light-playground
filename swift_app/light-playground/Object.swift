import Foundation
import CoreGraphics

/// Objects represent everything a user can add to a scene.
/// Note: This isn't used yet, but will be the primary way of representing objects in the scene soon.
struct Object {
    let id: Id
    var shape: Shape
    let lightInteraction: LightInteraction

    enum LightInteraction {
        // Doesn't interact with rays, only generates them.
        case emitter(color: LightColor)
        // A standard object that interacts with light.
        case collider(Material)
    }

    struct Material {
        // Percentage of the light to reflect per color.
        let reflects: FractionalLightColor

        /// A value from 0 to 1 indicating how much to deviate from the angle of reflection.
        let diffusion: CGFloat

        /// An opacity of 0 is a fully transparent object, and an opacity of 1 has no transparency.
        let opacity: CGFloat

        let indexOfRefraction: CGFloat
    }

    enum Shape {
        case circle(CircleShapeParams)
        case closedPolygon(ClosedPolygonShapeParams)
    }
}

struct CircleShapeParams {
    let pos: CGPoint
    let radius: CGFloat
}

struct ClosedPolygonShapeParams {
    let pos: [CGPoint]
}
