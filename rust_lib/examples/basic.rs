extern crate light_playground_lib as lp;
use lp::surface::cpu::CpuSurface;
use lp::simulator::Simulator;

fn main() {
    Simulator::new(CpuSurface::new());
}
