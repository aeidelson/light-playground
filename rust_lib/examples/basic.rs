extern crate light_playground_lib as lp;
use lp::drawing_surface::cpu::CpuDrawingSurface;
use lp::simulator::Simulator;

fn main() {
    Simulator::new(CpuDrawingSurface::new());
}
