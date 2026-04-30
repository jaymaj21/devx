use crate::mprewriter;

pub fn run_demo() {
    mprewriter::set_context("fractal_demo::run_demo");
    mprewriter::scope_START(2042);
    mprewriter::log_message("Fractal demo execution started.");
    let result = (1..=10).sum::<u32>();
    mprewriter::log_message(&format!("Fractal result: {}", result));
    mprewriter::log_message("Fractal demo execution ended.");
}
