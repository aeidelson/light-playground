use std::thread;

/// Represents a unit of work for a single tracer to process.
pub struct TracerJob {}

pub struct TracerJobGenerator {}

impl TracerJobGenerator {}

/// Each `Tracer` runs on its own thread. The `Simulator` interacts with the Tracer object, which
/// in turn interacts with the underlying thread.
pub struct Tracer {}

impl Tracer {
    /// Creates the tracer and starts running.
    pub fn new() -> Tracer {
        let tracer = Tracer {};
        thread::spawn(|| {
            run_tracer();
        });
        return tracer;
    }

    /// Stops the tracer thread and destroys the object.
    pub fn stop(self) {}
}

/// Main tracer function, running on the tracer thread.
fn run_tracer() {}
