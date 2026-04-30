use std::time::Instant;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::thread;

// Minimal inline hit counter without network I/O
fn main() {
    let hit_counter = Arc::new(AtomicU32::new(0));
    let running = Arc::new(AtomicBool::new(true));
    
    // Warmup
    println!("Warmup...");
    for _ in 0..10000 {
        hit_counter.fetch_add(1, Ordering::Relaxed);
    }
    std::thread::sleep(std::time::Duration::from_millis(100));
    hit_counter.store(0, Ordering::Relaxed);
    println!("Warmup complete");

    // Measure latency for 1M hits
    println!("Starting measurement...");
    let start = Instant::now();
    for _ in 0..1000000 {
        hit_counter.fetch_add(1, Ordering::Relaxed);
    }
    let end = Instant::now();
    println!("Measurement complete");

    let elapsed = end.duration_since(start);
    let elapsed_us = elapsed.as_secs_f64() * 1_000_000.0;
    let per_hit_us = elapsed_us / 1_000_000.0;

    println!("Rust Latency Benchmark Results:");
    println!("==============================");
    println!("Total hits: 1000000");
    println!("Total time: {:.3} ms", elapsed_us / 1000.0);
    println!("Average latency per hit: {:.6} microseconds", per_hit_us);
}
