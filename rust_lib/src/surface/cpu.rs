use surface::{Surface, SurfaceSession};

pub struct CpuSurface {}

impl CpuSurface {
    pub fn new() -> CpuSurface {
        CpuSurface {}
    }
}

impl Surface for CpuSurface {
    type SurfaceSessionType = CpuSurfaceSession;

    fn draw_session() -> CpuSurfaceSession {
        CpuSurfaceSession {}
    }
}

pub struct CpuSurfaceSession {}

impl SurfaceSession for CpuSurfaceSession {}
