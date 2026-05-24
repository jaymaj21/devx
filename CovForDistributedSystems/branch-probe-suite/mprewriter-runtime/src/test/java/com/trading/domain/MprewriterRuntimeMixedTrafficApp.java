package com.trading.domain;

import java.util.ArrayList;
import java.util.List;

public final class MprewriterRuntimeMixedTrafficApp {
    private MprewriterRuntimeMixedTrafficApp() {
    }

    public static void main(String[] args) throws Exception {
        int threadCount = args.length > 0 ? Integer.parseInt(args[0]) : 4;
        int iterations = args.length > 1 ? Integer.parseInt(args[1]) : 24;

        List<Thread> threads = new ArrayList<>();
        for (int t = 0; t < threadCount; t++) {
            final int threadIndex = t;
            Thread worker = new Thread(() -> runWorker(threadIndex, iterations), "mixed-traffic-" + threadIndex);
            threads.add(worker);
            worker.start();
        }

        for (Thread thread : threads) {
            thread.join();
        }

        mprewriter.log("final-log");
        mprewriter.shutdown();
    }

    private static void runWorker(int threadIndex, int iterations) {
        for (int i = 0; i < iterations; i++) {
            String context = "ctx-" + threadIndex + "-" + i;
            mprewriter.scope_ENTER();
            try {
                mprewriter.apply_context(context);
                mprewriter.hit(100000 + (threadIndex * 1000) + i);
                mprewriter.log("log-" + threadIndex + "-" + i);
                mprewriter.withdraw_context(context);
                if ((i % 4) == 0) {
                    try {
                        Thread.sleep(1L);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        return;
                    }
                }
            } finally {
                mprewriter.scope_EXIT();
            }
        }
    }
}
