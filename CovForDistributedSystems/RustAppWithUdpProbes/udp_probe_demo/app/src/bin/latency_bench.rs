use std::time::Instant;

fn main() {
    println!("Initializing probe...");
    mprewriter::start();
    println!("Probe initialized");

    // Warmup
    println!("Warmup...");
    for _ in 0..10_000 {
        mprewriter::scope_START(1001);
    }
    std::thread::sleep(std::time::Duration::from_millis(100));
    println!("Warmup complete");

    // Measure latency for 1M hits
    println!("Starting measurement...");
    let start = Instant::now();
    for _ in 0..1_000_000 {
        mprewriter::scope_START(1001);
    }
    let end = Instant::now();
    println!("Measurement complete");

    // Flush remaining hits
    println!("Flushing...");
    std::thread::sleep(std::time::Duration::from_millis(100));
    mprewriter::shutdown();
    println!("Shutdown complete");

    let elapsed = end.duration_since(start);
    let elapsed_us = elapsed.as_secs_f64() * 1_000_000.0;
    let per_hit_us = elapsed_us / 1_000_000.0;

    println!("Rust Latency Benchmark Results:");
    println!("==============================");
    println!("Total hits: 1000000");
    println!("Total time: {:.3} ms", elapsed_us / 1000.0);
    println!("Average latency per hit: {:.3} microseconds", per_hit_us);
}

