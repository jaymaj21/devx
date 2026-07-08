package com.codeanalytics;

import clojure.java.api.Clojure;
import clojure.lang.IFn;

import java.io.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class ClojureShell {
    private final Map<String, CommandSpec> commands = new LinkedHashMap<>();
    private final IFn clojureReadString = Clojure.var("clojure.core", "read-string");
    private final IFn clojureEval = Clojure.var("clojure.core", "eval");
    private final Map<String, Integer> hitRecords;
    private final TraceMetadataRegistry traceMetadata = new TraceMetadataRegistry();
    private File loadedTraceFile;
    public interface Command { void execute(String args); }

    public ClojureShell(Map<String, Integer> hitRecords) {
        this.hitRecords = hitRecords;
        addCommand(":help", ":help [command|trace|metadata|runtime]",
                "Show command help. With no argument, prints every command grouped by area.", this::printHelp);
        addCommand(":status", ":status",
                "Print current trace, loaded probe metadata, live hit-count map size, and trace-writer state.", args -> printStatus());
        addCommand(":concepts", ":concepts",
                "Explain outer trace records, inner HIT messages, probe metadata, and subset context windows.", args -> printConcepts());
        addCommand(":exit", ":exit",
                "Close the current trace writer and stop the shell.", args -> {
            try {
                RuntimeCommands.closeTraceWriter();
            } catch (IOException e) {
                System.err.println("Error closing trace writer: " + e.getMessage());
            }
            System.out.println("Bye!"); 
            System.exit(0);
         });

        // New context management commands
        addCommand(":apply-context", ":apply-context <context-label>",
                "Attach a logical context label to subsequent live coverage hits.", args -> {
            String ctx = args.trim();
            if (ctx.isEmpty()) {
                System.out.println("Usage: :apply-context <context-label>");
            } else {
                ContextManager.applyContext(ctx);
                System.out.println("Applied context: " + ctx);
            }
        });
        addCommand(":withdraw-context", ":withdraw-context <context-label>",
                "Withdraw a previously applied logical context label.", args -> {
            String ctx = args.trim();
            if (ctx.isEmpty()) {
                System.out.println("Usage: :withdraw-context <context-label>");
            } else {
                ContextManager.withdrawContext(ctx);
                System.out.println("Withdrew context: " + ctx);
            }
        });

        // Coverage report command
        addCommand(":coverage-report", ":coverage-report <appId> <instanceId> <filename>",
                "Write a compact coverage report for live hits grouped by context id and location id.", args -> {
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
        addCommand(":flush-trace", ":flush-trace",
                "Flush trace buffers so external tools can read the latest live trace data.", args -> {
            try {
                System.out.println(RuntimeCommands.flushTrace());
            } catch (IOException e) {
                System.out.println("ERROR: " + e.getMessage());
            }
        });

        // Force durable fsync of trace file
        addCommand(":trace-persist", ":trace-persist",
                "Force a durable fsync of the live trace file.", args -> {
            try {
                System.out.println(RuntimeCommands.persistTrace());
            } catch (IOException e) {
                System.out.println("ERROR: " + e.getMessage());
            }
        });

        addCommand(":trace-rotate", ":trace-rotate <filename>",
                "Close the current trace and start writing live trace data to another file.", args -> {
            String[] toks = splitArgs(args);
            if (toks.length != 1) {
                System.out.println("Usage: :trace-rotate <filename>");
                return;
            }
            try {
                System.out.println(RuntimeCommands.rotateTrace(new File(toks[0])));
            } catch (IOException e) {
                System.out.println("ERROR: " + e.getMessage());
            }
        });

        addTraceCommands();
        addTraceMetadataCommands();
    }

    private void addTraceCommands() {
        addCommand(":trace-load", ":trace-load <trace-file>",
                "Set the current HITTRC01 trace file for later trace commands.", args -> {
            String[] toks = splitArgs(args);
            if (toks.length != 1) {
                System.out.println("Usage: :trace-load <trace-file>");
                return;
            }
            File traceFile = new File(toks[0]);
            if (!traceFile.exists()) {
                System.out.println("ERROR: Trace file not found: " + traceFile.getPath());
                return;
            }
            loadedTraceFile = traceFile;
            System.out.println("Loaded trace: " + loadedTraceFile.getPath());
        });

        addCommand(":trace-current", ":trace-current",
                "Print the currently loaded trace file.", args -> {
            if (loadedTraceFile == null) {
                System.out.println("No trace loaded.");
            } else {
                System.out.println("Current trace: " + loadedTraceFile.getPath());
            }
        });

        addCommand(":trace-summary", ":trace-summary [trace-file] [top]",
                "Stream a trace summary: outer records, inner HIT/LOG counts, timing, top apps, and top probe locations.", args -> {
            try {
                String[] toks = splitArgs(args);
                TraceCommandArgs parsed = parseOptionalTraceAndNumber(toks, 10);
                File traceFile = parsed.traceFile;
                int top = (int) parsed.number;
                TraceAnalyzer.printSummary(traceFile, System.out, top);
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
                System.out.println("Usage: :trace-summary [trace-file] [top]");
            }
        });

        addCommand(":trace-dump", ":trace-dump [trace-file] [limit]",
                "Decode and print the first records from a trace. Useful for sanity-checking payload shape.", args -> {
            try {
                String[] toks = splitArgs(args);
                TraceCommandArgs parsed = parseOptionalTraceAndNumber(toks, 100);
                TraceAnalyzer.printDump(parsed.traceFile, System.out, parsed.number);
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
                System.out.println("Usage: :trace-dump [trace-file] [limit]");
            }
        });

        addCommand(":trace-histogram", ":trace-histogram [trace-file] [buckets]",
                "Print a two-pass hit histogram without retaining all hit timestamps in memory.", args -> {
            try {
                String[] toks = splitArgs(args);
                TraceCommandArgs parsed = parseOptionalTraceAndNumber(toks, 50);
                TraceAnalyzer.printHistogram(parsed.traceFile, System.out, (int) parsed.number);
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
                System.out.println("Usage: :trace-histogram [trace-file] [buckets]");
            }
        });

        addCommand(":trace-save-subset", ":trace-save-subset <target-trace-file> <pre-context-hits> <post-context-hits> <probe-id-range>...",
                "Save a valid HITTRC01 subset from the current trace by explicit probe/location id ranges.", args -> {
            try {
                String[] toks = splitArgs(args);
                if (toks.length < 4) {
                    System.out.println("Usage: :trace-save-subset <target-trace-file> <pre-context-hits> <post-context-hits> <probe-id-range>...");
                    return;
                }
                File sourceFile = requireLoadedTraceFile();
                File targetFile = new File(toks[0]);
                int preContext = Integer.parseInt(toks[1]);
                int postContext = Integer.parseInt(toks[2]);
                List<TraceAnalyzer.Range> ranges = TraceAnalyzer.parseRanges(toks, 3);
                TraceAnalyzer.SubsetResult result = TraceAnalyzer.saveSubset(sourceFile, targetFile, preContext, postContext, ranges);
                TraceAnalyzer.printSubsetResult(result, System.out);
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
                System.out.println("Usage: :trace-load <source-trace-file>");
                System.out.println("       :trace-save-subset <target-trace-file> <pre-context-hits> <post-context-hits> <probe-id-range>...");
            }
        });

        addCommand(":trace-save-subset-class", ":trace-save-subset-class <target-trace-file> <pre-context-hits> <post-context-hits> <class-pattern>...",
                "Save a trace subset for probes whose loaded metadata class name matches one or more glob patterns.", args -> {
            try {
                String[] toks = splitArgs(args);
                if (toks.length < 4) {
                    System.out.println("Usage: :trace-save-subset-class <target-trace-file> <pre-context-hits> <post-context-hits> <class-pattern>...");
                    return;
                }
                saveMetadataFilteredSubset(toks, Arrays.asList(Arrays.copyOfRange(toks, 3, toks.length)), "class");
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
                System.out.println("Usage: :trace-save-subset-class <target-trace-file> <pre-context-hits> <post-context-hits> <class-pattern>...");
            }
        });

        addCommand(":trace-save-subset-path", ":trace-save-subset-path <target-trace-file> <pre-context-hits> <post-context-hits> <path-pattern>...",
                "Save a trace subset for probes whose resolved source path matches one or more glob patterns.", args -> {
            try {
                String[] toks = splitArgs(args);
                if (toks.length < 4) {
                    System.out.println("Usage: :trace-save-subset-path <target-trace-file> <pre-context-hits> <post-context-hits> <path-pattern>...");
                    return;
                }
                saveMetadataFilteredSubset(toks, Arrays.asList(Arrays.copyOfRange(toks, 3, toks.length)), "path");
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
                System.out.println("Usage: :trace-save-subset-path <target-trace-file> <pre-context-hits> <post-context-hits> <path-pattern>...");
            }
        });

        addCommand(":trace-save-subset-method", ":trace-save-subset-method <target-trace-file> <pre-context-hits> <post-context-hits> <method-pattern>...",
                "Save a trace subset for probes whose method names match one or more glob patterns.", args -> {
            try {
                String[] toks = splitArgs(args);
                if (toks.length < 4) {
                    System.out.println("Usage: :trace-save-subset-method <target-trace-file> <pre-context-hits> <post-context-hits> <method-pattern>...");
                    return;
                }
                saveMetadataFilteredSubset(toks, Arrays.asList(Arrays.copyOfRange(toks, 3, toks.length)), "method");
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
                System.out.println("Usage: :trace-save-subset-method <target-trace-file> <pre-context-hits> <post-context-hits> <method-pattern>...");
            }
        });

        addCommand(":trace-save-subset-where", ":trace-save-subset-where <target-trace-file> <pre-context-hits> <post-context-hits> <where-pattern>...",
                "Save a trace subset for probes whose branch/source kind matches patterns such as IF_TRUE or METHOD_ENTRY.", args -> {
            try {
                String[] toks = splitArgs(args);
                if (toks.length < 4) {
                    System.out.println("Usage: :trace-save-subset-where <target-trace-file> <pre-context-hits> <post-context-hits> <where-pattern>...");
                    return;
                }
                saveMetadataFilteredSubset(toks, Arrays.asList(Arrays.copyOfRange(toks, 3, toks.length)), "where");
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
                System.out.println("Usage: :trace-save-subset-where <target-trace-file> <pre-context-hits> <post-context-hits> <where-pattern>...");
            }
        });

        addCommand(":trace-save-subset-filter", ":trace-save-subset-filter <target-trace-file> <pre-context-hits> <post-context-hits> <class:pattern|path:pattern|method:pattern|where:pattern|id:range>...",
                "Save a trace subset using a union of metadata filters and explicit id ranges.", args -> {
            try {
                String[] toks = splitArgs(args);
                if (toks.length < 4) {
                    System.out.println("Usage: :trace-save-subset-filter <target-trace-file> <pre-context-hits> <post-context-hits> <class:pattern|path:pattern|method:pattern|where:pattern|id:range>...");
                    return;
                }
                File sourceFile = requireLoadedTraceFile();
                File targetFile = new File(toks[0]);
                int preContext = Integer.parseInt(toks[1]);
                int postContext = Integer.parseInt(toks[2]);
                Set<Long> ids = traceMetadata.probeIdsForMixedFilters(Arrays.asList(Arrays.copyOfRange(toks, 3, toks.length)));
                saveSubsetForProbeIds(sourceFile, targetFile, preContext, postContext, ids);
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
                System.out.println("Usage: :trace-save-subset-filter <target-trace-file> <pre-context-hits> <post-context-hits> <class:pattern|path:pattern|method:pattern|where:pattern|id:range>...");
            }
        });
    }

    private void addTraceMetadataCommands() {
        addCommand(":probe-metadata-load", ":probe-metadata-load <branch-probes.csv>...",
                "Load one or more branch instrumenter sidecar CSV files: id,class,method,where,source,line.", args -> {
            String[] toks = splitArgs(args);
            if (toks.length == 0) {
                System.out.println("Usage: :probe-metadata-load <branch-probes.csv>...");
                return;
            }
            for (String tok : toks) {
                try {
                    File file = new File(tok);
                    int count = traceMetadata.loadProbeCsv(file);
                    System.out.println("Loaded " + count + " probes from " + file.getPath());
                } catch (Exception e) {
                    System.out.println("ERROR loading " + tok + ": " + e.getMessage());
                }
            }
        });

        addCommand(":probe-metadata-load-classes", ":probe-metadata-load-classes <classes.tsv>...",
                "Load one or more list_java_classes.tcl TSV files mapping class name to relative source path.", args -> {
            String[] toks = splitArgs(args);
            if (toks.length == 0) {
                System.out.println("Usage: :probe-metadata-load-classes <classes.tsv>...");
                return;
            }
            for (String tok : toks) {
                try {
                    File file = new File(tok);
                    int count = traceMetadata.loadClassMap(file);
                    System.out.println("Loaded " + count + " class mappings from " + file.getPath());
                } catch (Exception e) {
                    System.out.println("ERROR loading " + tok + ": " + e.getMessage());
                }
            }
        });

        addCommand(":probe-metadata-clear", ":probe-metadata-clear",
                "Clear all loaded probe CSVs and class-to-source mappings.", args -> {
            traceMetadata.clear();
            System.out.println("Cleared probe metadata and class mappings");
        });

        addCommand(":probe-metadata-summary", ":probe-metadata-summary",
                "Print loaded metadata counts and the files they came from.", args -> {
            TraceMetadataRegistry.MetadataSummary summary = traceMetadata.summary();
            System.out.println("Probe metadata:");
            System.out.println("  Probes: " + summary.probeCount);
            System.out.println("  Class mappings: " + summary.classMapCount);
            System.out.println("  Probe CSV files:");
            for (File file : summary.probeCsvFiles) {
                System.out.println("    " + file.getPath());
            }
            System.out.println("  Class map files:");
            for (File file : summary.classMapFiles) {
                System.out.println("    " + file.getPath());
            }
        });

        addCommand(":probe-metadata-find-class", ":probe-metadata-find-class <class-pattern>...",
                "Show loaded probe ids whose class names match glob patterns, for example com.example.*.", args -> {
            List<String> patterns = Arrays.asList(splitArgs(args));
            Set<Long> ids = traceMetadata.probeIdsForClassPatterns(patterns);
            printProbeMatches(ids);
        });

        addCommand(":probe-metadata-find-path", ":probe-metadata-find-path <path-pattern>...",
                "Show loaded probe ids whose resolved source paths match glob patterns, for example */service/*.java.", args -> {
            List<String> patterns = Arrays.asList(splitArgs(args));
            Set<Long> ids = traceMetadata.probeIdsForPathPatterns(patterns);
            printProbeMatches(ids);
        });

        addCommand(":probe-metadata-find-method", ":probe-metadata-find-method <method-pattern>...",
                "Show loaded probe ids whose method names match glob patterns.", args -> {
            List<String> patterns = Arrays.asList(splitArgs(args));
            Set<Long> ids = traceMetadata.probeIdsForMethodPatterns(patterns);
            printProbeMatches(ids);
        });

        addCommand(":probe-metadata-find-where", ":probe-metadata-find-where <where-pattern>...",
                "Show loaded probe ids whose instrumentation kind matches glob patterns such as IF_* or METHOD_ENTRY.", args -> {
            List<String> patterns = Arrays.asList(splitArgs(args));
            Set<Long> ids = traceMetadata.probeIdsForWherePatterns(patterns);
            printProbeMatches(ids);
        });

        addCommand(":probe-metadata-show", ":probe-metadata-show <probe-id|probe-id-range>...",
                "Describe specific probe ids or id ranges using loaded metadata.", args -> {
            String[] toks = splitArgs(args);
            if (toks.length == 0) {
                System.out.println("Usage: :probe-metadata-show <probe-id|probe-id-range>...");
                return;
            }
            Set<Long> ids = traceMetadata.probeIdsForRanges(Arrays.asList(toks));
            printProbeMatches(ids);
        });

        addCommand(":probe-metadata-find-filter", ":probe-metadata-find-filter <class:pattern|path:pattern|method:pattern|where:pattern|id:range>...",
                "Preview the probe ids matched by the same mixed filter syntax used by :trace-save-subset-filter.", args -> {
            String[] toks = splitArgs(args);
            if (toks.length == 0) {
                System.out.println("Usage: :probe-metadata-find-filter <class:pattern|path:pattern|method:pattern|where:pattern|id:range>...");
                return;
            }
            Set<Long> ids = traceMetadata.probeIdsForMixedFilters(Arrays.asList(toks));
            printProbeMatches(ids);
        });
    }

    private void saveMetadataFilteredSubset(String[] toks, List<String> patterns, String filterKind) throws IOException {
        File sourceFile = requireLoadedTraceFile();
        File targetFile = new File(toks[0]);
        int preContext = Integer.parseInt(toks[1]);
        int postContext = Integer.parseInt(toks[2]);
        Set<Long> ids;
        if ("class".equals(filterKind)) {
            ids = traceMetadata.probeIdsForClassPatterns(patterns);
        } else if ("path".equals(filterKind)) {
            ids = traceMetadata.probeIdsForPathPatterns(patterns);
        } else if ("method".equals(filterKind)) {
            ids = traceMetadata.probeIdsForMethodPatterns(patterns);
        } else if ("where".equals(filterKind)) {
            ids = traceMetadata.probeIdsForWherePatterns(patterns);
        } else {
            throw new IllegalArgumentException("Unsupported metadata filter kind: " + filterKind);
        }
        saveSubsetForProbeIds(sourceFile, targetFile, preContext, postContext, ids);
    }

    private void saveSubsetForProbeIds(File sourceFile, File targetFile, int preContext, int postContext, Set<Long> ids) throws IOException {
        if (ids.isEmpty()) {
            System.out.println("No probes matched the supplied metadata filters");
            return;
        }
        System.out.println("Matched " + ids.size() + " probes:");
        System.out.print(traceMetadata.describeProbeIds(ids, 20));
        TraceAnalyzer.SubsetResult result = TraceAnalyzer.saveSubsetMatching(sourceFile, targetFile, preContext, postContext, ids::contains);
        TraceAnalyzer.printSubsetResult(result, System.out);
    }

    private void printProbeMatches(Set<Long> ids) {
        System.out.println("Matched probes: " + ids.size());
        System.out.print(traceMetadata.describeProbeIds(ids, 50));
    }

    private TraceCommandArgs parseOptionalTraceAndNumber(String[] toks, long defaultNumber) {
        TraceCommandArgs parsed = new TraceCommandArgs();
        parsed.number = defaultNumber;
        if (toks.length == 0) {
            parsed.traceFile = requireLoadedTraceFile();
            return parsed;
        }
        if (toks.length == 1 && loadedTraceFile != null && isInteger(toks[0])) {
            parsed.traceFile = loadedTraceFile;
            parsed.number = Long.parseLong(toks[0]);
            return parsed;
        }

        parsed.traceFile = new File(toks[0]);
        loadedTraceFile = parsed.traceFile;
        if (toks.length >= 2) {
            parsed.number = Long.parseLong(toks[1]);
        }
        return parsed;
    }

    private File requireLoadedTraceFile() {
        if (loadedTraceFile == null) {
            throw new IllegalStateException("No trace loaded. Use :trace-load <trace-file> first.");
        }
        return loadedTraceFile;
    }

    private static String[] splitArgs(String args) {
        String trimmed = args.trim();
        if (trimmed.isEmpty()) {
            return new String[0];
        }
        return trimmed.split("\\s+");
    }

    private static boolean isInteger(String text) {
        try {
            Long.parseLong(text);
            return true;
        } catch (NumberFormatException ex) {
            return false;
        }
    }

    private static final class TraceCommandArgs {
        File traceFile;
        long number;
    }

    private static final class CommandSpec {
        final String name;
        final String usage;
        final String description;
        final Command command;

        CommandSpec(String name, String usage, String description, Command command) {
            this.name = name;
            this.usage = usage;
            this.description = description;
            this.command = command;
        }
    }

    public void addCommand(String name, Command command) {
        addCommand(name, name, "No help text is available for this command.", command);
    }

    public void addCommand(String name, String usage, String description, Command command) {
        commands.put(name, new CommandSpec(name, usage, description, command));
    }

    private void printHelp(String args) {
        String topic = args.trim();
        if (topic.isEmpty()) {
            printHelpGroup("Runtime and Live Coverage", "runtime", ":help", ":status", ":concepts", ":hits", ":apply-context", ":withdraw-context", ":coverage-report", ":flush-trace", ":trace-persist", ":trace-rotate", ":exit");
            printHelpGroup("Trace Files", "trace", ":trace-load", ":trace-current", ":trace-summary", ":trace-dump", ":trace-histogram", ":trace-save-subset");
            printHelpGroup("Metadata Filtering", "metadata", ":probe-metadata-load", ":probe-metadata-load-classes", ":probe-metadata-clear", ":probe-metadata-summary",
                    ":probe-metadata-find-class", ":probe-metadata-find-path", ":probe-metadata-find-method", ":probe-metadata-find-where", ":probe-metadata-find-filter", ":probe-metadata-show",
                    ":trace-save-subset-class", ":trace-save-subset-path", ":trace-save-subset-method", ":trace-save-subset-where", ":trace-save-subset-filter");
            System.out.println();
            System.out.println("Use :help <command> for details, or :help trace / :help metadata / :help runtime for focused lists.");
            System.out.println("Non-command input is evaluated as a Clojure expression.");
            return;
        }

        if ("trace".equalsIgnoreCase(topic)) {
            printHelpGroup("Trace Files", "trace", ":trace-load", ":trace-current", ":trace-summary", ":trace-dump", ":trace-histogram", ":trace-save-subset");
            printTraceHelpNotes();
            return;
        }
        if ("metadata".equalsIgnoreCase(topic) || "probes".equalsIgnoreCase(topic)) {
            printHelpGroup("Metadata Filtering", "metadata", ":probe-metadata-load", ":probe-metadata-load-classes", ":probe-metadata-clear", ":probe-metadata-summary",
                    ":probe-metadata-find-class", ":probe-metadata-find-path", ":probe-metadata-find-method", ":probe-metadata-find-where", ":probe-metadata-find-filter", ":probe-metadata-show",
                    ":trace-save-subset-class", ":trace-save-subset-path", ":trace-save-subset-method", ":trace-save-subset-where", ":trace-save-subset-filter");
            printMetadataHelpNotes();
            return;
        }
        if ("runtime".equalsIgnoreCase(topic) || "live".equalsIgnoreCase(topic)) {
            printHelpGroup("Runtime and Live Coverage", "runtime", ":help", ":status", ":concepts", ":hits", ":apply-context", ":withdraw-context", ":coverage-report", ":flush-trace", ":trace-persist", ":trace-rotate", ":exit");
            return;
        }

        String commandName = topic.startsWith(":") ? topic : ":" + topic;
        CommandSpec spec = commands.get(commandName);
        if (spec == null) {
            System.out.println("Unknown help topic: " + topic);
            System.out.println("Use :help to list commands.");
            return;
        }
        System.out.println(spec.usage);
        System.out.println("  " + spec.description);
        printCommandExamples(commandName);
    }

    private void printHelpGroup(String title, String topic, String... names) {
        System.out.println();
        System.out.println(title + " (:help " + topic + ")");
        for (String name : names) {
            CommandSpec spec = commands.get(name);
            if (spec != null) {
                System.out.printf("  %-38s %s%n", spec.usage, spec.description);
            }
        }
    }

    private void printStatus() {
        TraceMetadataRegistry.MetadataSummary metadataSummary = traceMetadata.summary();
        System.out.println("Status:");
        System.out.println("  Current trace: " + (loadedTraceFile == null ? "<none>" : loadedTraceFile.getPath()));
        System.out.println("  Live hit keys: " + hitRecords.size());
        System.out.println("  Loaded probe metadata entries: " + metadataSummary.probeCount);
        System.out.println("  Loaded class path mappings: " + metadataSummary.classMapCount);
        System.out.println("  Trace writer: " + (RuntimeCommands.getTraceWriter() == null ? "<not active>" : "active"));
        System.out.println("  Live trace file: " + RuntimeCommands.getTraceFilePath());
    }

    private void printConcepts() {
        System.out.println("Code Analytics concepts:");
        System.out.println("  Outer record: one framed HITTRC01 file record with flag, source, nano timestamp, length, and payload.");
        System.out.println("  Inner HIT message: one probe hit inside a HIT payload; contains appId, instanceId, threadId, stackDepth, and locationId.");
        System.out.println("  Probe id / locationId: the instrumented branch/runtime id emitted by the app. Branch CSV id values map to these ids.");
        System.out.println("  Probe metadata: branch-probes.csv rows mapping id -> class, method, instrumentation kind, source file, and line.");
        System.out.println("  Class map: list_java_classes.tcl TSV rows mapping fully qualified class names to source paths.");
        System.out.println("  Subset context: pre/post counts include neighboring inner HIT messages around each matched probe hit, useful for stack/call-flow context.");
        System.out.println("  Metadata filters: class:, path:, method:, where:, and id: filters are unioned by :trace-save-subset-filter.");
    }

    private void printTraceHelpNotes() {
        System.out.println();
        System.out.println("Trace subset context counts are inner HIT message counts before/after each matching probe hit.");
        System.out.println("Example:");
        System.out.println("  :trace-load code-analytics/plant-trace-....txt");
        System.out.println("  :trace-save-subset focused.trace 3 1 1001-1070 2081-3120");
    }

    private void printMetadataHelpNotes() {
        System.out.println();
        System.out.println("Metadata filters use glob patterns: * matches any text, ? matches one character.");
        System.out.println("Path filters use loaded class maps when available, otherwise class/source fields from the probe CSV.");
        System.out.println("Examples:");
        System.out.println("  :probe-metadata-load app-instrumented-branch-probes.csv");
        System.out.println("  :probe-metadata-load-classes classes.tsv");
        System.out.println("  :probe-metadata-find-class com.example.*");
        System.out.println("  :probe-metadata-find-where IF_*");
        System.out.println("  :trace-save-subset-filter focused.trace 3 1 class:com.example.* method:render* where:IF_* id:1001-1070");
    }

    private void printCommandExamples(String commandName) {
        if (":trace-save-subset-filter".equals(commandName)) {
            System.out.println("  Filter kinds: class:, path:, file:, method:, where:, kind:, id:, probe:.");
            System.out.println("  Filters are unioned; a hit is included if its probe id matches any supplied filter.");
            System.out.println("  Example: :trace-save-subset-filter focused.trace 3 1 class:com.example.* path:*/Service.java method:render* where:IF_* id:1001-1070");
        } else if (":trace-save-subset".equals(commandName)) {
            System.out.println("  Example: :trace-save-subset target.trace 3 1 1001-1070 2081-3120");
        } else if (":probe-metadata-load".equals(commandName)) {
            System.out.println("  Expected CSV columns: id,class,method,where,source,line");
        } else if (":probe-metadata-load-classes".equals(commandName)) {
            System.out.println("  Expected TSV rows: <class-name>\\t<relative-source-path>");
        } else if (":probe-metadata-find-class".equals(commandName)) {
            System.out.println("  Example: :probe-metadata-find-class com.example.*");
        } else if (":probe-metadata-find-path".equals(commandName)) {
            System.out.println("  Example: :probe-metadata-find-path */service/*.java");
        } else if (":probe-metadata-find-method".equals(commandName)) {
            System.out.println("  Example: :probe-metadata-find-method render* main");
        } else if (":probe-metadata-find-where".equals(commandName)) {
            System.out.println("  Example: :probe-metadata-find-where IF_* METHOD_ENTRY");
        } else if (":probe-metadata-find-filter".equals(commandName)) {
            System.out.println("  Filter kinds: class:, path:, file:, method:, where:, kind:, id:, probe:.");
            System.out.println("  Example: :probe-metadata-find-filter class:com.example.* method:render* where:IF_* id:1001-1070");
        }
    }

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
                CommandSpec spec = commands.get(cmdName);
                if (spec != null) {
                    try { spec.command.execute(arg); }
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

        RuntimeCommands.initializeDefaultTraceWriter();

        // Start UDP listener
        Thread udpThread = new Thread(new UdpListener(8083, hitRecords), "UDPListener");
        udpThread.setDaemon(true);
        udpThread.start();

        // Start TCP listener
        Thread tcpThread = new Thread(new TcpListener(8084, hitRecords), "TCPListener");
        tcpThread.setDaemon(true);
        tcpThread.start();

        // Periodic timestamp writer (every 10s) to the trace
        Thread tsThread = new Thread(() -> {
            while (true) {
                try { Thread.sleep(10_000); } catch (InterruptedException ie) { return; }
                try {
                    HitTraceWriter writer = RuntimeCommands.getTraceWriter();
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
        shell.addCommand(":hits", ":hits",
                "Print live hit counts aggregated by appId, instanceId, threadId, stackDepth, and locationId.",
                args1 -> ClojureShell.printHitsMap(hitRecords));

        shell.repl(); // blocking, until user exits
    }
}
