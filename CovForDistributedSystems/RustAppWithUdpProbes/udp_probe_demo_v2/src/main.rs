mod mprewriter;
mod fractal_demo;
fn factorial(n: u64) -> u64 {mprewriter_scope_START!(g_1001,1001);
    mprewriter::log_message(&format!("Factorial called with n={}", n));
    if n == 0 || n == 1 {mprewriter_scope_START!(g_1002,1002);
        1
    } else {mprewriter_scope_START!(g_1003,1003);
        n * factorial(n - 1)
    }
}

fn main() {
    mprewriter::start();
    mprewriter::set_context("main");
    mprewriter_scope_START!(g_1000,1000);
    mprewriter::log_message("Main module started.");
    fractal_demo::run_demo();
    let f = factorial(6);
    mprewriter::log_message(&format!("Factorial of 6 is {}", f));
    mprewriter::log_message("Main module finished.");
    mprewriter::shutdown();
}


