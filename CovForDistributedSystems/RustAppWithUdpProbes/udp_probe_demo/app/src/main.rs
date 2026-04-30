mod fractal_demo;
use mprewriter;
use mprewriter_macros::mprewriter_scope_START;
fn factorial(n: u64) -> u64 {mprewriter_scope_START!(1001);
    mprewriter::log_message(&format!("Factorial called with n={}", n));
    if n == 0 || n == 1 {
        mprewriter_scope_START!(1002);
        mprewriter_scope_START!(1004);
        1
    } else {mprewriter_scope_START!(1003);
        n * factorial(n - 1)
    }
}

fn main() {
    mprewriter::start();
    mprewriter::set_context("main");
    mprewriter_scope_START!(1000);
    mprewriter::log_message("Main module started.");
    fractal_demo::run_demo();
    let f = factorial(6);
    mprewriter::log_message(&format!("Factorial of 6 is {}", f));
    mprewriter::log_message("Main module finished.");
    mprewriter::shutdown();
}

