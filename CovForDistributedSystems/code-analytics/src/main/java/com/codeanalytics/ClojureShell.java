package com.codeanalytics;

import clojure.java.api.Clojure;
import clojure.lang.IFn;

import java.io.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class ClojureShell {
    private final Map<String, Command> commands = new HashMap<>();
    private final IFn clojureReadString = Clojure.var("clojure.core", "read-string");
    private final IFn clojureEval = Clojure.var("clojure.core", "eval");
    private final Map<String, Integer> hitRecords;
    private static HitTraceWriter writer = null;

    static {
        // Add this block for trace streaming
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd-HH-mm-ss-SSS");
        Calendar cal = Calendar.getInstance();
        String traceFileName="plant-trace-" + sdf.format(cal.getTime()) + ".txt";
        
        try {
            writer = new HitTraceWriter(new File(traceFileName), /*append*/ true);

        } catch (IOException e) {
            System.err.println("Error initializing trace writer: " + e.getMessage());
        }
        
    }
    public interface Command { void execute(String args); }

    public ClojureShell(Map<String, Integer> hitRecords) {
        this.hitRecords = hitRecords;
        addCommand(":help", args -> {
            System.out.println("Commands:");
            commands.keySet().forEach(cmd -> System.out.println("  " + cmd));
            System.out.println("Clojure expressions also work.");
        });
        addCommand(":exit", args -> { 
            if (writer != null) {
                try {
                    writer.close();
                } catch (IOException e) {
                    System.err.println("Error closing trace writer: " + e.getMessage());
                }
            }
            System.out.println("Bye!"); 
            System.exit(0);
         });

        // New context management commands
        addCommand(":apply-context", args -> {
            String ctx = args.trim();
            if (ctx.isEmpty()) {
                System.out.println("Usage: :apply-context <context-label>");
            } else {
                ContextManager.applyContext(ctx);
                System.out.println("Applied context: " + ctx);
            }
        });
        addCommand(":withdraw-context", args -> {
            String ctx = args.trim();
            if (ctx.isEmpty()) {
                System.out.println("Usage: :withdraw-context <context-label>");
            } else {
                ContextManager.withdrawContext(ctx);
                System.out.println("Withdrew context: " + ctx);
            }
        });

        // Coverage report command
        addCommand(":coverage-report", args -> {
            String[] toks = args.trim().split("\\s+");
            if (toks.length != 3) {
                System.out.println("Usage: :coverage-report <appId> <instanceId> <filename>");
                return;
            }
            try {
                int appId = Integer.parseInt(toks[0]);
                int instanceId = Integer.parseInt(toks[1]);
                String filename = toks[2];
                String result = writeCoverageReport(appId, instanceId, filename);
                System.out.println(result);
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
            }
        });

        // Flush trace file to disk
        addCommand(":flush-trace", args -> {
            try {
                if (writer != null) { writer.flush(); System.out.println("Trace flushed"); }
                else System.out.println("No trace writer active");
            } catch (IOException e) {
                System.out.println("ERROR: " + e.getMessage());
            }
        });

        // Force durable fsync of trace file
        addCommand(":trace-persist", args -> {
            try {
                if (writer != null) { writer.persist(); System.out.println("Trace persisted"); }
                else System.out.println("No trace writer active");
            } catch (IOException e) {
                System.out.println("ERROR: " + e.getMessage());
            }
        });
    }

    public void addCommand(String name, Command command) { commands.put(name, command); }

    public void repl() throws Exception {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        System.out.println("Welcome to Analytics Engine Shell. :help for commands.");
        String line;
        while (true) {
            System.out.print("admin> ");
            line = in.readLine();
            if (line == null) break;
            line = line.trim();
            if (line.isEmpty()) continue;
            if (line.startsWith(":")) {
                String cmdName = line.split("\\s+", 2)[0];
                String arg = line.contains(" ") ? line.substring(line.indexOf(' ') + 1) : "";
                Command cmd = commands.get(cmdName);
                if (cmd != null) {
                    try { cmd.execute(arg); }
                    catch (Exception ex) { System.err.println("Error: " + ex); }
                } else {
                    System.out.println("Unknown command. Type :help.");
                }
            } else {
                try {
                    Object form = clojureReadString.invoke(line);
                    Object result = clojureEval.invoke(form);
                    System.out.println(result);
                } catch (Exception ex) {
                    System.err.println("Clojure error: " + ex.getMessage());
                }
            }
        }
    }

    // Static so the listeners can call for pretty-printing
    public static void printHitsMap(Map<String, Integer> hitRecords) {
        // The stored legacy record string is: appId,instanceId,threadId,stackDepth,locationId
        // Print both stackDepth and locationId explicitly so users see the true key.
        System.out.println("Hit Records Map:");
        System.out.printf("%-10s %-12s %-12s %-12s %-12s %-10s%n", "AppID", "InstanceID", "ThreadID", "StackDepth", "LocationID", "Count");
        System.out.println("--------------------------------------------------------------------------------");
        for (Map.Entry<String, Integer> entry : hitRecords.entrySet()) {
            String[] fields = entry.getKey().split(",");
            // Defensive: ensure we have all expected fields
            String app = fields.length > 0 ? fields[0] : "?";
            String inst = fields.length > 1 ? fields[1] : "?";
            String thread = fields.length > 2 ? fields[2] : "?";
            String stackDepth = fields.length > 3 ? fields[3] : "?";
            String loc = fields.length > 4 ? fields[4] : "?";
            System.out.printf("%-10s %-12s %-12s %-12s %-12s %-10s%n", app, inst, thread, stackDepth, loc, entry.getValue());
        }
    }

    // Static parse for use by listeners
    public static String parseHitRecord(ByteBuffer buffer) {
        short appId = buffer.getShort();
        int instanceId = buffer.getInt();
        int threadId = buffer.getInt();
        int stackDepth = buffer.getInt();
        int locationId = buffer.getInt();
        return String.format("%d,%d,%d,%d,%d", appId, instanceId, threadId, stackDepth, locationId);
    }

    // Coverage report utility, inline for self-containment
    public static String writeCoverageReport(int appId, int instanceId, String filename) {
        // 1. Get all context sets and their ids
        Map<Integer, Set<String>> idToContextSet = ContextManager.getIdToContextSetMap();

        // 2. Gather all hit records for this app and instance
        List<String> hitLines = new ArrayList<>();
        int hitCount = 0;
        for (Map.Entry<List<Integer>, Integer> entry : ContextManager.getHitCountsSnapshot().entrySet()) {
            List<Integer> key = entry.getKey();
            if (key.get(0) == appId && key.get(1) == instanceId) {
                int ctxId = key.get(2);
                int locId = key.get(3);
                int count = entry.getValue();
                hitLines.add(String.format("%d %d %d", ctxId, locId, count));
                hitCount++;
            }
        }
        // Sort hits for deterministic order: context id, then location id
        hitLines.sort((a, b) -> {
            String[] pa = a.split(" ");
            String[] pb = b.split(" ");
            int cmp = Integer.compare(Integer.parseInt(pa[0]), Integer.parseInt(pb[0]));
            if (cmp != 0) return cmp;
            return Integer.compare(Integer.parseInt(pa[1]), Integer.parseInt(pb[1]));
        });

        // 3. Write report
        try (PrintWriter out = new PrintWriter(new FileWriter(filename))) {
            // Contexts section
            out.printf("CONTEXTS %d%n", idToContextSet.size());
            for (Map.Entry<Integer, Set<String>> entry : idToContextSet.entrySet()) {
                int ctxId = entry.getKey();
                Set<String> ctxSet = entry.getValue();
                String label = (ctxId == 1) ? "default" : String.join(",", new TreeSet<>(ctxSet));
                out.printf("%d %s%n", ctxId, label);
            }
            // Hits section
            out.printf("HITS %d%n", hitCount);
            for (String line : hitLines) {
                out.println(line);
            }
            return "Coverage report written to " + filename;
        } catch (IOException e) {
            return "ERROR writing report: " + e.getMessage();
        }
    }

    public static void main(String[] args) throws Exception {
        final Map<String, Integer> hitRecords = new ConcurrentHashMap<>();

        

        // Start UDP listener
        Thread udpThread = new Thread(new UdpListener(8083, hitRecords, writer), "UDPListener");
        udpThread.setDaemon(true);
        udpThread.start();

        // Start TCP listener
        Thread tcpThread = new Thread(new TcpListener(8084, hitRecords, writer), "TCPListener");
        tcpThread.setDaemon(true);
        tcpThread.start();

        // Periodic timestamp writer (every 10s) to the trace
        Thread tsThread = new Thread(() -> {
            while (true) {
                try { Thread.sleep(10_000); } catch (InterruptedException ie) { return; }
                try {
                    if (writer != null) {
                        byte[] payload = ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(System.currentTimeMillis()).array();
                        writer.writeRaw(HitTraceWriter.FLAG_TS, HitTraceWriter.SRC_INTERNAL, payload);
                    }
                } catch (Exception ignore) {}
            }
        }, "TSWriter");
        tsThread.setDaemon(true);
        tsThread.start();

        // Start the interpreter shell, with access to hitRecords
        ClojureShell shell = new ClojureShell(hitRecords);

        // Example: add a shell command to print hit map
        shell.addCommand(":hits", args1 -> ClojureShell.printHitsMap(hitRecords));

        shell.repl(); // blocking, until user exits
    }
}
