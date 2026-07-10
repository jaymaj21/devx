Java Coverage/Trace Server (ClojureShell)

- Listens on UDP 8083 and TCP 8084 for probe messages (HIT/LOG/CTX).
- Streams a binary trace file per session (HITTRC01 header + framed records).
- Provides an interactive Clojure-backed admin shell.

Run

- `java -cp build/libs/clojure-shell-<version>-jar-with-dependencies.jar com.codeanalytics.ClojureShell`

Help

- `:help` is authoritative inside the shell and lists all commands with usage and descriptions.
- `:help trace`, `:help metadata`, and `:help runtime` show focused command groups.
- `:help <command>` shows one command, for example `:help trace-save-subset-filter`.
- `:concepts` explains the trace-file terms used by the tooling.

Runtime Commands

- `:status` prints the current trace, metadata counts, live hit-count keys, and trace-writer state.
- `:concepts` explains outer records, inner HIT messages, probe ids, metadata, class maps, and subset context windows.
- `:hits` prints live hit records aggregated by `(appId, instanceId, threadId, stackDepth, locationId)`.
- `:apply-context <label>` attaches a context to the current live hit set.
- `:withdraw-context <label>` withdraws a context from the current live hit set.
- `:coverage-report <appId> <instanceId> <filename>` writes a compact context-aware coverage report.
- `:flush-trace` flushes trace buffers so external tools can read the latest data.
- `:trace-persist` forces a durable fsync of the live trace file.
- `:trace-rotate <filename>` closes the current trace and starts writing live trace data to another file.
- `:exit` closes the trace writer and stops the shell.

UDP Remote Commands

- Send a UTF-8 UDP datagram to the normal analytics UDP port, prefixed with `CMD `.
- These commands are an allowlist only; UDP input is never evaluated by Clojure or any other interpreter.
- Remote output file paths must be relative and must not contain empty, `.`, or `..` path segments.
- Supported payloads:
  - `CMD help`
  - `CMD status`
  - `CMD coverage-report <appId> <instanceId> <filename>`
  - `CMD save-hits <filename>`
  - `CMD flush-trace`
  - `CMD trace-persist`
  - `CMD trace-rotate <filename>`
  - `CMD exit`
- The server replies to the sender with a single UTF-8 status datagram.

Trace Analyzer CLI

- Fast Java analyzer for large `HITTRC01` trace files:
  - Gradle: `java -cp build/classes/java/main com.codeanalytics.TraceAnalyzer summary <trace-file> [--top N]`
  - Maven: `java -cp target/classes com.codeanalytics.TraceAnalyzer summary <trace-file> [--top N]`
  - `java -cp build/classes/java/main com.codeanalytics.TraceAnalyzer dump <trace-file> [--limit N]`
  - `java -cp build/classes/java/main com.codeanalytics.TraceAnalyzer histogram <trace-file> [--buckets N]`
- `summary` streams the trace and reports outer frame counts, inner HIT/LOG/CTX counts, timing, top app/instance pairs, top locations, and cardinality.
- `histogram` uses two streaming passes, so it does not store all hit timestamps in memory.

Interactive Trace Commands

- `:trace-load <trace-file>` sets the current trace for later commands.
- `:trace-current` prints the current trace.
- `:trace-summary [trace-file] [top]` prints the same streaming summary as the Java CLI.
- `:trace-dump [trace-file] [limit]` prints decoded records from the trace.
- `:trace-histogram [trace-file] [buckets]` prints a hit histogram.
- `:trace-save-subset <target-trace-file> <pre-context-hits> <post-context-hits> <probe-id-range>...` writes a valid `HITTRC01` subset from the currently loaded trace.
- Example: `:trace-save-subset target-trace-file.trace 3 1 1001-1070 2081-3120`

Probe Metadata Commands

- `:probe-metadata-load <branch-probes.csv>...` loads one or more branch instrumenter sidecar CSV files with columns `id,class,method,where,source,line`.
- `:probe-metadata-load-classes <classes.tsv>...` loads one or more `list_java_classes.tcl` outputs with rows `<class-name>\t<relative-source-path>`.
- `:probe-metadata-clear` clears all loaded probe metadata and class mappings.
- `:probe-metadata-summary` prints loaded metadata counts and source files.
- `:probe-metadata-find-class <class-pattern>...` shows probe ids whose class names match glob patterns such as `com.example.*`.
- `:probe-metadata-find-path <path-pattern>...` shows probe ids whose resolved source paths match glob patterns such as `*/service/*.java`.
- `:probe-metadata-find-method <method-pattern>...` shows probe ids whose method names match glob patterns such as `render*`.
- `:probe-metadata-find-where <where-pattern>...` shows probe ids whose instrumentation kind matches glob patterns such as `IF_*` or `METHOD_ENTRY`.
- `:probe-metadata-find-filter <class:pattern|path:pattern|method:pattern|where:pattern|id:range>...` previews mixed filters before saving a subset.
- `:probe-metadata-show <probe-id|probe-id-range>...` describes specific probe ids using loaded metadata.
- `:trace-save-subset-class <target-trace-file> <pre-context-hits> <post-context-hits> <class-pattern>...` saves a subset for probes in matching classes.
- `:trace-save-subset-path <target-trace-file> <pre-context-hits> <post-context-hits> <path-pattern>...` saves a subset for probes in matching source paths.
- `:trace-save-subset-method <target-trace-file> <pre-context-hits> <post-context-hits> <method-pattern>...` saves a subset for probes in matching methods.
- `:trace-save-subset-where <target-trace-file> <pre-context-hits> <post-context-hits> <where-pattern>...` saves a subset for probes with matching instrumentation kinds.
- `:trace-save-subset-filter <target-trace-file> <pre-context-hits> <post-context-hits> <class:pattern|path:pattern|method:pattern|where:pattern|id:range>...` combines metadata and explicit id filters.

Typical Metadata Workflow

```text
:probe-metadata-load branch-probe-demoapp/build/libs/branch-probe-demoapp-1.0.0-instrumented-branch-probes.csv
:probe-metadata-load-classes classes.tsv
:probe-metadata-find-class com.example.demo.*
:probe-metadata-find-where IF_*
:probe-metadata-find-filter class:com.example.demo.* where:IF_* id:1001-1070
:trace-load code-analytics/plant-trace-....txt
:trace-save-subset-filter focused.trace 3 1 class:com.example.demo.* where:IF_* id:1001-1070
```
