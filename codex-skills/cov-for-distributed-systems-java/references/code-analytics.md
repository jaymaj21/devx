# Code Analytics

`code-analytics` receives runtime UDP probe hits, writes `HITTRC01` binary trace files, provides an interactive `ClojureShell`, and can load probe metadata for source-aware filtering.

## Start Server

```powershell
java -cp .\code-analytics\target\clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar com.codeanalytics.ClojureShell
```

Use these inside the shell:

```text
:help
:help trace
:help metadata
:help runtime
:concepts
:status
```

## Runtime Hit And Coverage Commands

```text
:hits
:apply-context <label>
:withdraw-context <label>
:coverage-report <appId> <instanceId> <filename>
:flush-trace
:trace-persist
:trace-rotate <filename>
:exit
```

Coverage report format:

```text
CONTEXTS N
<ctxId> <label>
HITS M
<ctxId> <locId> <count>
```

Context id `1` is normally `default`. `locId` is the branch probe id from the instrumenter CSV.

Each `HITS` row records the hit count for one context/probe pair. Source annotation derives two different numbers from this:

- context hit count: the number of distinct selected contexts that contain a row for the probe;
- hit count: the sum of the row counts for the selected contexts.

Do not conflate these when explaining annotations.

The UDP receive thread should stay lightweight: receive datagrams and enqueue them in arrival order for subsequent parsing. Context changes are order-sensitive, especially common `withdraw_context(ALL)` followed by `add_context(...)` sequences, so Java `code-analytics` parsing should preserve packet order with a single parser consumer while keeping the UDP receive thread unblocked.

## Remote UDP Commands

`code-analytics` also accepts a small allowlist of UTF-8 UDP control packets on the normal UDP receiver port. Payloads must begin with `CMD ` and are not evaluated by Clojure or any interpreter.

Supported payloads:

```text
CMD help
CMD status
CMD coverage-report <appId> <instanceId> <filename>
CMD save-hits <filename>
CMD flush-trace
CMD trace-persist
CMD trace-rotate <filename>
CMD exit
```

Remote output paths must be relative and must not contain empty, `.`, or `..` path segments. The server replies to the sender with one UTF-8 status datagram. If a workflow needs artifacts in a specific directory, start `code-analytics` with that directory as its working directory and pass relative filenames to remote `CMD` commands.

Use remote commands when the server is running unattended and the user wants to trigger coverage/hit/trace export without opening the Clojure shell. Do not add arbitrary remote evaluation; keep this surface to explicit runtime/export operations.

## capinger UDP Tester

`capinger.java` is a single-file JDK-only client in the repository root. Compile it directly:

```powershell
javac capinger.java
```

Common commands:

```powershell
java capinger CMD status
java capinger CMD coverage-report 1 1 app.cov
java capinger CMD coverage-hits hits.csv
java capinger HIT 1 1 7 2 1234
java capinger HIT 1 1 7 2 1234 100
java capinger LOG 1 1 7 2 hello from capinger
java capinger CTX test-run-42
java capinger CTX_WITHDRAW test-run-42
java capinger CMD flush-trace
java capinger CMD trace-persist
java capinger CMD exit
```

Defaults are `127.0.0.1:8083`; override them when needed:

```powershell
java capinger --host 192.168.1.10 --port 8083 CMD status
```

Packet formats sent by `capinger`:

- `HIT <appId> <instanceId> <threadId> <stackDepth> <locationId> [repeatCount]` sends one or more 20-byte big-endian hit records.
- `LOG <appId> <instanceId> <threadId> <stackDepth> <message...>` sends message type `2` with UTF-8 log text.
- `CTX <label...>` sends context attach message type `3`.
- `CTX_WITHDRAW <label...>` sends context withdraw message type `4`.
- `CMD coverage-hits <file>` is an alias for remote `save-hits`.
- `CMD coverage <appId> <instanceId> <file>` is an alias for remote `coverage-report`.

`capinger_sequence.bat` compiles `capinger.java`, sends a longer mixed sequence of `CMD`, `CTX`, `HIT`, `LOG`, and export commands, and skips `CMD exit` by default. Run from the repository root:

```bat
capinger_sequence.bat
capinger_sequence.bat 127.0.0.1 8083
```

## Trace Analyzer CLI

Compile classes first if needed:

```powershell
.\gradlew.bat :code-analytics:compileJava
```

Analyze large traces without loading all records into memory:

```powershell
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceAnalyzer summary .\code-analytics\plant-trace-....txt --top 20
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceAnalyzer dump .\code-analytics\plant-trace-....txt --limit 100
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceAnalyzer histogram .\code-analytics\plant-trace-....txt --buckets 50
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceAnalyzer subset .\code-analytics\plant-trace-....txt .\subset.trace 3 1 1001-1070 2081-3120
```

Tcl wrapper:

```powershell
tclsh .\plant_trace_tool.tcl summary .\code-analytics\plant-trace-....txt
tclsh .\plant_trace_tool.tcl parsedump .\code-analytics\plant-trace-....txt
tclsh .\plant_trace_tool.tcl legacydump .\code-analytics\plant-trace-....txt
tclsh .\plant_trace_tool.tcl rawdump .\code-analytics\plant-trace-....txt
```

## Interactive Trace Commands

```text
:trace-load <trace-file>
:trace-current
:trace-summary [trace-file] [top]
:trace-dump [trace-file] [limit]
:trace-histogram [trace-file] [buckets]
:trace-save-subset <target-trace-file> <pre-context-hits> <post-context-hits> <probe-id-range>...
```

Example:

```text
:trace-load .\code-analytics\plant-trace-20251109-215352.txt
:trace-summary
:trace-save-subset .\focused.trace 3 1 1001-1070 2081-3120
```

## Load Probe Metadata

Load branch-probe CSV sidecars:

```text
:probe-metadata-load .\app-instrumented-branch-probes.csv
```

Build and load Java class maps:

```powershell
tclsh .\list_java_classes.tcl overwrite .\classes.tsv C:\path\to\source-root
```

Inside `ClojureShell`:

```text
:probe-metadata-load-classes .\classes.tsv
:probe-metadata-summary
```

Class map rows are:

```text
fully.qualified.ClassName<TAB>relative/source/path.java
```

## Metadata Search

```text
:probe-metadata-find-class <class-pattern>...
:probe-metadata-find-path <path-pattern>...
:probe-metadata-find-method <method-pattern>...
:probe-metadata-find-where <where-pattern>...
:probe-metadata-find-filter <class:pattern|path:pattern|method:pattern|where:pattern|id:range>...
:probe-metadata-show <probe-id|probe-id-range>...
```

Examples:

```text
:probe-metadata-find-class com.example.demo.*
:probe-metadata-find-path */service/*.java
:probe-metadata-find-method render* main
:probe-metadata-find-where IF_* METHOD_ENTRY
:probe-metadata-find-filter class:com.example.* method:render* where:IF_* id:1001-1070
:probe-metadata-show 1001-1070
```

## Source-Aware Trace Subsets

```text
:trace-save-subset-class <target-trace-file> <pre-context-hits> <post-context-hits> <class-pattern>...
:trace-save-subset-path <target-trace-file> <pre-context-hits> <post-context-hits> <path-pattern>...
:trace-save-subset-method <target-trace-file> <pre-context-hits> <post-context-hits> <method-pattern>...
:trace-save-subset-where <target-trace-file> <pre-context-hits> <post-context-hits> <where-pattern>...
:trace-save-subset-filter <target-trace-file> <pre-context-hits> <post-context-hits> <class:pattern|path:pattern|method:pattern|where:pattern|id:range>...
```

Examples:

```text
:trace-save-subset-class .\main-only.trace 3 1 com.example.demo.Main
:trace-save-subset-path .\services.trace 3 1 */service/*.java
:trace-save-subset-method .\render.trace 3 1 render*
:trace-save-subset-where .\branches.trace 3 1 IF_*
:trace-save-subset-filter .\mixed.trace 3 1 class:com.example.* path:*/Service.java method:render* where:IF_* id:1001-1070
```
