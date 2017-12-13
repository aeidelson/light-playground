use std::sync::{Arc, Mutex};


use surface::Surface;
use tracer::{Tracer, TracerJobProducer};

pub struct Simulator<TSurface: Surface> {
    surface: TSurface,
}

impl<TSurface: Surface> Simulator<TSurface> {
    pub fn new(surface: TSurface) -> Simulator<TSurface> {
        let tracer_job_producer_mutex = Arc::new(Mutex::new(TracerJobProducer::new()));
        let tracer1 = Tracer::new(&tracer_job_producer_mutex);
        let tracer2 = Tracer::new(&tracer_job_producer_mutex);

        tracer1.stop();
        tracer2.stop();
        Simulator { surface: surface }
    }
}
