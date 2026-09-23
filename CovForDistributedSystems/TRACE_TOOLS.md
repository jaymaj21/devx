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

Use [TraceIndexer.java](/c:/Git/jmtools/development_tools/CovForDistributedSystems/code-analytics/src/main/java/com/codeanalytics/TraceIndexer.java:1) to build a sparse seek index for huge traces without loading the full file:

```powershell
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceIndexer .\code-analytics\plant-trace-....txt
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceIndexer .\code-analytics\plant-trace-....txt .\trace.idx.tsv --stride-mib 64
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceIndexer .\code-analytics\plant-trace-....txt .\trace.idx.tsv --stride-bytes 67108864
```

The default output is `<trace-file>.idx.tsv`. The index is tab-separated text with comment metadata and compact rows:

```text
frame_seq	offset	t_ns
```

Rows are written for the first frame, then for the first frame at or beyond each byte-stride boundary, and finally for the last frame. A later navigator can binary-search these rows, seek to `offset`, read the 15-byte outer frame header from the trace itself, and scan forward from the nearest checkpoint.

Use [TraceGrep.java](/c:/Git/jmtools/development_tools/CovForDistributedSystems/code-analytics/src/main/java/com/codeanalytics/TraceGrep.java:1) for grep-like LOG search over large traces. It uses the sparse index to seek near `--start-ts` when possible, then streams complete outer frames and materializes only one frame payload at a time:

```powershell
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceGrep `
  --trace-file .\code-analytics\plant-trace-....txt `
  --index-file .\code-analytics\plant-trace-....txt.idx.tsv `
  --start-ts 2025-11-09T21:37:10Z `
  --end-ts 2025-11-09T21:37:30Z `
  --substring timeout `
  --regex "failed|error" `
  --logs-before 2 `
  --logs-after 2
```

`--start-ts` and `--end-ts` accept raw trace monotonic nanoseconds or RFC3339 UTC timestamps. RFC3339 conversion uses the trace header plus the first index row's `t_ns`, so pass `--index-file` or keep the default `<trace-file>.idx.tsv` next to the trace.

Matcher options may be repeated. Multiple `--regex` and `--substring` values are ORed. If no matcher is supplied, all LOG messages in the selected time range are printed. `-B` and `-A` are aliases for `--logs-before` and `--logs-after`.

Defaults can be stored in a config file. `TraceGrep` first looks for `tracegrep.cfg` next to the trace file, then applies `--cfg <file>`, then command-line options. Config files use repeatable `key=value` lines:

```text
# tracegrep.cfg
index-file=plant-trace-2025-11-09-21-37-07-259.txt.idx.tsv
start-ts=2025-11-09T21:37:10Z
logs-before=2
logs-after=2
ignore-case=true
substring=timeout
regex=failed|error
```

Inside `ClojureShell`, the same search is available as `:trace-grep`. If `:trace-load` has set a trace, `:trace-grep` can omit `--trace-file`:

```text
:trace-load .\code-analytics\plant-trace-....txt
:trace-grep --substring timeout -B 2 -A 2
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
