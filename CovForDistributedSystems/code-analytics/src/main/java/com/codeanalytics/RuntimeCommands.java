package com.codeanalytics;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Map;

final class RuntimeCommands {
    private static final Object TRACE_LOCK = new Object();
    private static HitTraceWriter traceWriter;
    private static File traceFile;

    private RuntimeCommands() {
    }

    static void initializeDefaultTraceWriter() {
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd-HH-mm-ss-SSS");
        String traceFileName = "plant-trace-" + sdf.format(Calendar.getInstance().getTime()) + ".txt";
        try {
            rotateTrace(new File(traceFileName));
        } catch (IOException e) {
            System.err.println("Error initializing trace writer: " + e.getMessage());
        }
    }

    static HitTraceWriter getTraceWriter() {
        synchronized (TRACE_LOCK) {
            return traceWriter;
        }
    }

    static String getTraceFilePath() {
        synchronized (TRACE_LOCK) {
            return traceFile == null ? "<none>" : traceFile.getPath();
        }
    }

    static String flushTrace() throws IOException {
        HitTraceWriter writer = getTraceWriter();
        if (writer == null) {
            return "No trace writer active";
        }
        writer.flush();
        return "Trace flushed";
    }

    static String persistTrace() throws IOException {
        HitTraceWriter writer = getTraceWriter();
        if (writer == null) {
            return "No trace writer active";
        }
        writer.persist();
        return "Trace persisted";
    }

    static String rotateTrace(File targetFile) throws IOException {
        synchronized (TRACE_LOCK) {
            HitTraceWriter oldWriter = traceWriter;
            HitTraceWriter newWriter = new HitTraceWriter(targetFile, true);
            traceWriter = newWriter;
            traceFile = targetFile;
            if (oldWriter != null) {
                oldWriter.close();
            }
            return "Trace rotated to " + targetFile.getPath();
        }
    }

    static void closeTraceWriter() throws IOException {
        synchronized (TRACE_LOCK) {
            if (traceWriter != null) {
                traceWriter.close();
                traceWriter = null;
            }
        }
    }

    static String saveHits(Map<String, Integer> hitRecords, File targetFile) throws IOException {
        try (PrintWriter out = new PrintWriter(new FileWriter(targetFile))) {
            out.printf("%s,%s,%s,%s,%s,%s%n", "appId", "instanceId", "threadId", "stackDepth", "locationId", "count");
            for (Map.Entry<String, Integer> entry : hitRecords.entrySet()) {
                out.printf("%s,%d%n", entry.getKey(), entry.getValue());
            }
        }
        return "Hit records written to " + targetFile.getPath();
    }

    static String executeRemoteCommand(String line, Map<String, Integer> hitRecords) {
        String[] toks = splitArgs(line);
        if (toks.length == 0) {
            return "ERROR empty command";
        }

        String command = toks[0].startsWith(":") ? toks[0].substring(1) : toks[0];
        try {
            switch (command) {
                case "help":
                    return remoteHelp();
                case "coverage-report":
                    if (toks.length != 4) {
                        return "ERROR usage: coverage-report <appId> <instanceId> <filename>";
                    }
                    return ClojureShell.writeCoverageReport(
                            Integer.parseInt(toks[1]),
                            Integer.parseInt(toks[2]),
                            safeRemoteFile(toks[3]).getPath());
                case "save-hits":
                    if (toks.length != 2) {
                        return "ERROR usage: save-hits <filename>";
                    }
                    return saveHits(hitRecords, safeRemoteFile(toks[1]));
                case "flush-trace":
                    if (toks.length != 1) {
                        return "ERROR usage: flush-trace";
                    }
                    return flushTrace();
                case "trace-persist":
                    if (toks.length != 1) {
                        return "ERROR usage: trace-persist";
                    }
                    return persistTrace();
                case "trace-rotate":
                    if (toks.length != 2) {
                        return "ERROR usage: trace-rotate <filename>";
                    }
                    return rotateTrace(safeRemoteFile(toks[1]));
                case "status":
                    if (toks.length != 1) {
                        return "ERROR usage: status";
                    }
                    return "Trace writer: " + (getTraceWriter() == null ? "<not active>" : "active")
                            + "; current trace: " + getTraceFilePath()
                            + "; live hit keys: " + hitRecords.size();
                case "exit":
                    if (toks.length != 1) {
                        return "ERROR usage: exit";
                    }
                    closeTraceWriter();
                    new Thread(() -> System.exit(0), "RemoteExit").start();
                    return "Exiting";
                default:
                    return "ERROR unknown remote command: " + command;
            }
        } catch (Exception e) {
            return "ERROR " + e.getMessage();
        }
    }

    private static String remoteHelp() {
        return "Remote commands: help, status, coverage-report <appId> <instanceId> <filename>, "
                + "save-hits <filename>, flush-trace, trace-persist, trace-rotate <filename>, exit. "
                + "UDP payload must be UTF-8 text prefixed with CMD ";
    }

    private static File safeRemoteFile(String text) {
        File file = new File(text);
        if (file.isAbsolute()) {
            throw new IllegalArgumentException("Remote file paths must be relative");
        }
        for (String part : text.replace('\\', '/').split("/")) {
            if (part.isEmpty() || ".".equals(part) || "..".equals(part)) {
                throw new IllegalArgumentException("Remote file path contains an unsafe segment: " + text);
            }
        }
        return file;
    }

    private static String[] splitArgs(String line) {
        String trimmed = line.trim();
        if (trimmed.isEmpty()) {
            return new String[0];
        }
        return trimmed.split("\\s+");
    }
}
