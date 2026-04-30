package com.codeanalytics;

import java.io.File;

public final class HitTraceDump {
    public static void do_dump(String[] args) throws Exception {
        if (args.length == 0) {
            System.err.println("Usage: java com.codeanalytics.HitTraceDump <trace-file>");
            System.exit(2);
        }
        File f = new File(args[0]);
        HitTraceReader.dump(f, System.out);
    }
}
