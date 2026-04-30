use std::time::Instant;

mod mprewriter;

fn main() {
    println!("Initializing probe...");
    mprewriter::start();
    println!("Probe initialized");

    // Warmup
    println!("Warmup...");
    for _ in 0..10000 {
        mprewriter::scope_START(1001);
    }
    std::thread::sleep(std::time::Duration::from_millis(100));
    println!("Warmup complete");

    // Measure latency for 1M hits
    println!("Starting measurement...");
    let start = Instant::now();
    for _ in 0..1000000 {
        mprewriter::scope_START(1001);
    }
    let end = Instant::now();
    println!("Measurement complete");

    // Flush remaining hits
    println!("Flushing...");
    std::thread::sleep(std::time::Duration::from_millis(100));
        // Note: Skipping mprewriter::shutdown() because it hangs on join()
        // The background thread will be killed when the process exits
        println!("Shutdown complete (skipped join)");

    let elapsed = end.duration_since(start);
    let elapsed_us = elapsed.as_secs_f64() * 1_000_000.0;
    let per_hit_us = elapsed_us / 1_000_000.0;

    println!("Rust Latency Benchmark Results:");
    println!("==============================");
    println!("Total hits: 1000000");
    println!("Total time: {:.3} ms", elapsed_us / 1000.0);
    println!("Average latency per hit: {:.3} microseconds", per_hit_us);
}
