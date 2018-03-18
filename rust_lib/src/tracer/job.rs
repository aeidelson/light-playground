use common::scene::Scene;
use common::simulation::LightSegment;

/// Represents a unit of work for a single tracer to process.
pub struct Job {
    /// The scene description at the time the Input was created.
    /// TODO: Current plan here is to use a copy. Arc would also work, but would probably be
    /// slower?
    scene: Scene,

    /// The number of segments to be produced in executing this Input.
    segments_to_produce: usize,
}

/// Creates jobs for the pool of tracers to process.
pub struct JobProducer {}

impl JobProducer {
    pub fn new() -> JobProducer {
        JobProducer {}
    }

    pub fn reset(&mut self, latest_scene: Scene) {}

    /// If this returns a None, the tracer is expected to wait until it is woken up by the
    /// condition variable.
    pub fn take_job(&mut self) -> Option<Job> {
        None
    }
}

