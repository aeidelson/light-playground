use surface::Surface;

pub struct Simulator<TSurface: Surface> {
    surface: TSurface,
}

impl<TSurface: Surface> Simulator<TSurface> {
    pub fn new(surface: TSurface) -> Simulator<TSurface> {
        Simulator{
            surface: surface,
        }
    }
}
