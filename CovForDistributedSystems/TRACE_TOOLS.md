# Plant Trace Tools

This repo has several Tcl scripts for reading Code Analytics trace files. The trace files are the binary `HITTRC01` files that `code-analytics` writes with names like `plant-trace-2025-11-09-21-53-52-130.txt`.

## Recommended Entry Point

Use [plant_trace_tool.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/plant_trace_tool.tcl:1) first.

It consolidates the overlapping root-level scripts into one CLI:

```powershell
tclsh .\plant_trace_tool.tcl summary .\code-analytics\plant-trace-....txt
tclsh .\plant_trace_tool.tcl parsedump .\code-analytics\plant-trace-....txt
tclsh .\plant_trace_tool.tcl legacydump .\code-analytics\plant-trace-....txt
tclsh .\plant_trace_tool.tcl rawdump .\code-analytics\plant-trace-....txt
```

For very large traces, use the Java analyzer in [TraceAnalyzer.java](/c:/Git/jmtools/development_tools/CovForDistributedSystems/code-analytics/src/main/java/com/codeanalytics/TraceAnalyzer.java:1). It streams the binary file and avoids retaining all records in memory:

```powershell
.\gradlew.bat :code-analytics:compileJava
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceAnalyzer summary .\code-analytics\plant-trace-....txt
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceAnalyzer dump .\code-analytics\plant-trace-....txt --limit 100
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceAnalyzer histogram .\code-analytics\plant-trace-....txt --buckets 50
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceAnalyzer subset .\code-analytics\plant-trace-....txt .\subset.trace 3 1 1001-1070 2081-3120
```

The interactive `ClojureShell` exposes the same analyzer through `:trace-load`, `:trace-current`, `:trace-summary`, `:trace-dump`, `:trace-histogram`, and `:trace-save-subset`. Use `:help`, `:help trace`, `:help metadata`, `:help <command>`, or `:concepts` inside the shell for command-specific usage and trace terminology.

It can also load branch instrumenter probe metadata and `list_java_classes.tcl` class maps, then save trace subsets by class or source path:

```text
:probe-metadata-load .\branch-probe-demoapp\build\libs\branch-probe-demoapp-1.0.0-instrumented-branch-probes.csv
:probe-metadata-load-classes .\classes.tsv
:trace-load .\code-analytics\plant-trace-....txt
:trace-save-subset-class .\main-only.trace 3 1 com.example.demo.Main
:trace-save-subset-path .\services.trace 3 1 */service/*.java
:probe-metadata-find-method render*
:probe-metadata-find-where IF_*
:probe-metadata-show 1001-1070
:probe-metadata-find-filter class:com.example.* where:IF_* id:1001-1070
:trace-save-subset-method .\render.trace 3 1 render*
:trace-save-subset-where .\branches.trace 3 1 IF_*
:trace-save-subset-filter .\mixed.trace 3 1 class:com.example.* path:*/Service.java method:render* where:IF_* id:1001-1070
```

What each subcommand does:

- `summary`: counts outer trace records and inner HIT/LOG messages, prints timing, rate, and top hit locations.
- `parsedump`: delegates to [code-analytics/parsetrace.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/code-analytics/parsetrace.tcl:1) for the richer decoded dump.
- `legacydump`: delegates to [code-analytics/dumptrace.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/code-analytics/dumptrace.tcl:1) for the older line-oriented format.
- `rawdump`: delegates to [code-analytics/trace_dump.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/code-analytics/trace_dump.tcl:1) for low-level framed output.

## Existing Scripts

These are still useful, but they overlap:

- [count_hits.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/count_hits.tcl:1): counts individual HIT messages in batched payloads.
- [trace_counter.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/trace_counter.tcl:1): counts records by outer flag and prints a rough time span.
- [hit_stats.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/hit_stats.tcl:1): derives total hits, approximate UTC window, and average hit rate.
- [debug_trace.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/debug_trace.tcl:1): inspects the first records when the binary format looks wrong.
- [debug_epoch.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/debug_epoch.tcl:1): checks the timestamp math.
- [trace_histogram.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/trace_histogram.tcl:1): Tk-based histogram viewer.
- [edit-context.tcl](/c:/Git/jmtools/development_tools/CovForDistributedSystems/edit-context.tcl:1): sends context attach/withdraw packets to a running Code Analytics server.

## Running an Instrumented Java App and Saving a Trace

Use [run_dstr_code_analytics.ps1](/c:/Git/jmtools/development_tools/CovForDistributedSystems/run_dstr_code_analytics.ps1:1) for the end-to-end workflow against the external Maven `dstr` project.

Default run:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_dstr_code_analytics.ps1
```

Example with a different spec:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_dstr_code_analytics.ps1 -SpecPath test-suite\specs\bakery-3proc.json
```

The script:

1. builds or reuses `code-analytics`, `branch-probe-instrumenter`, and `mprewriter-runtime`,
2. builds the Maven `dstr` jar and copies its runtime dependencies,
3. instruments the `dstr` jar,
4. starts `code-analytics`,
5. runs the instrumented `dstr` CLI against a JSON spec,
6. sends `:flush-trace`, `:trace-persist`, and `:exit`,
7. copies the newly written `plant-trace-*.txt` into an `artifacts\dstr-trace\<timestamp>\` run folder,
8. runs `plant_trace_tool.tcl summary` against that saved trace.

## Notes

- The `plant-trace-*.txt` files are binary trace files despite the `.txt` extension.
- The outer record timestamp is based on `System.nanoTime()`, so absolute UTC times are approximate and derived from the trace header plus relative offsets.
- The newer parsed dumpers under `code-analytics/` are the most reliable readers for batched HIT payloads.
