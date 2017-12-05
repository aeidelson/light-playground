use drawing_surface::DrawingSurface;

pub struct CpuDrawingSurface {
}

impl CpuDrawingSurface {
    pub fn new() -> CpuDrawingSurface {
        CpuDrawingSurface{}
    }
}

impl DrawingSurface for CpuDrawingSurface {
}
