use std::collections::HashMap;

pub struct Scene {
    /// Objects keyed by `object.id`.
    objects: HashMap<u64, Object>,
}

pub struct Object {
    id: u64,
    shape: Shape,
    light_interaction: LightInteraction,
}

/// Shapes

pub enum Shape {
    Circle,
    ClosedPolygon,
}

/// Materials

pub enum LightInteraction {
    Emitter(Color),
    Collider(Material),
}

pub struct Material {
    /// Acts as a percentage of each color to reflect.
    reflects: Color,

    /// A value from 0 to 1 indicating how much to deviate from the angle of reflection.
    diffusion: f32,

    /// An opacity of 0 is a fully transparent object, and an opacity of 1 has no transparency.
    opacity: f32,

    indexOfRefraction: f32,
}

pub struct Color {
    red: u8,
    green: u8,
    blue: u8,
}
