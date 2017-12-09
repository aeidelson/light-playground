use surface::Surface;
use tracer::Tracer;

pub struct Simulator<TSurface: Surface> {
    surface: TSurface,
}

impl<TSurface: Surface> Simulator<TSurface> {
    pub fn new(surface: TSurface) -> Simulator<TSurface> {
        let tracer = Tracer::new();
        tracer.stop();
        Simulator { surface: surface }
    }
}
