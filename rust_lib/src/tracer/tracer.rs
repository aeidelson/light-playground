/// Asynchronously calls

use std::sync::{Arc, Mutex};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender, TryRecvError};
use std::thread;

use common::scene::Scene;
use common::simulation::LightSegment;
use tracer::job::{Job, JobProducer};

/// Each `Tracer` runs on its own thread. The `Simulator` interacts with the Tracer
/// object, which in turn interacts with the underlying thread.
pub struct Tracer {
    stop_sender: SyncSender<bool>,
}

impl Tracer {
    /// Creates the tracer and starts running.
    pub fn new(job_producer_mutex: &Arc<Mutex<JobProducer>>) -> Tracer {
        let (stop_sender, stop_receiver) = sync_channel(1); // When stopping, block until the thread has quit.
        let tracer = Tracer {
            stop_sender: stop_sender,
        };

        let job_producer_mutex_clone = job_producer_mutex.clone();
        thread::spawn(move || {
            run_tracer(stop_receiver, job_producer_mutex_clone);
        });
        return tracer;
    }

    /// Stops the tracer thread and destroys the object. Will block the calling thread until the
    /// thread has quit.
    pub fn stop(self) {
        self.stop_sender.send(true).unwrap();
    }
}

/// Main tracer function, running on the tracer thread.
fn run_tracer(stop_receiver: Receiver<bool>, job_producer_mutex: Arc<Mutex<JobProducer>>) {
    loop {
        // Check if the thread should exit.
        match stop_receiver.try_recv() {
            Result::Ok(_) => return,
            Result::Err(TryRecvError::Disconnected) => {
                panic!("Disconnected stop receiver. Maybe thread wasn't stopped?")
            }
            Result::Err(TryRecvError::Empty) => (),
        }

        let trace_job: Option<Job>;
        {
            trace_job = job_producer_mutex.lock().unwrap().take_job();
        }

        match trace_job {
            // TODO: This would be more efficient if it used a condition variable to wait until
            // there was more to process.
            Option::None => continue,
            Option::Some(job) => {
                // TODO: Do the tracing and drawing
            }
        }
    }
}
