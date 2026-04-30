

import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

public class Main {
    public static void main(String[] args) throws Exception {
        // Warmup
        for (int i = 0; i < 10000; ++i) {
            mprewriter.scope_START(1001);
        }
        Thread.sleep(100);

        // Measure latency for 1M hits
        long start = System.nanoTime();
        for(int i = 0; i < 1000000; ++i) {
            mprewriter.scope_START(1001);
        }
        long end = System.nanoTime();

        // Flush remaining hits
        Thread.sleep(100);
        mprewriter.shutdown();

        double elapsed_us = (end - start) / 1000.0;
        double per_hit_us = elapsed_us / 1000000.0;

        System.out.println("Java Latency Benchmark Results:");
        System.out.println("==============================");
        System.out.println("Total hits: 1000000");
        System.out.printf("Total time: %.3f ms%n", elapsed_us / 1000.0);
        System.out.printf("Average latency per hit: %.3f microseconds%n", per_hit_us);
    }
}

