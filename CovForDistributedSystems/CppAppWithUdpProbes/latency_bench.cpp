#include <iostream>
#include <chrono>
#include "mprewriter.hpp"

int main() {
    mpr_start_sender();

    // Warmup
    for (int i = 0; i < 10000;  ++i) {
             mprewriter_scope_START(1001);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    // Measure latency for 1M hits
    auto start = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < 1000000; ++i) {
        
        mprewriter_scope_START(1001);
    }
    auto end = std::chrono::high_resolution_clock::now();

    // Flush remaining hits
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    close_probe();
    mpr_join_sender();

    double elapsed_ms = std::chrono::duration<double, std::milli>(end - start).count();
    double elapsed_us = elapsed_ms * 1000.0;
    double per_hit_us = elapsed_us / 1000000.0;

    std::cout << "C++ Latency Benchmark Results:" << std::endl;
    std::cout << "==============================" << std::endl;
    std::cout << "Total hits: 1000000" << std::endl;
    std::cout << "Total time: " << elapsed_ms << " ms" << std::endl;
    std::cout << "Average latency per hit: " << per_hit_us << " microseconds" << std::endl;

    return 0;
}
