use drawing_surface::DrawingSurface;

pub struct Simulator<T: DrawingSurface> {
    draw_surface: T,
}

impl<T: DrawingSurface> Simulator<T> {
    pub fn new(draw_surface: T) -> Simulator<T> {
        Simulator{
            draw_surface: draw_surface,
        }
    }
}
