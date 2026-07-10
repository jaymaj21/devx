# Source Annotation

Use source annotation when the user wants Java source files marked with branch probe coverage, including source-facing branch edge markers, context hit counts, and hit counts.

## Inputs

Required:

- Java sources JAR, usually `target\<artifact>-<version>-sources.jar`.
- Code Analytics coverage report from `:coverage-report <appId> <instanceId> <filename>`.
- One or more branch probe CSV sidecars from instrumentation, or directories containing CSVs.
- Output directory for extracted and annotated sources.

The source JAR should correspond to the classes that were instrumented. Line-number fidelity depends on the target classes being compiled with debug line information.

Regenerate CSV sidecars with the current branch-probe instrumenter. Current CSVs have this header:

```text
id,class,method,where,source,line,edge,opcode,sense
```

The annotation tool expects this current format. Do not spend effort preserving compatibility with older six-column CSVs unless the user explicitly asks.

## Generate Coverage Report

Inside `ClojureShell` after running the instrumented app:

```text
:coverage-report 410 1 .\artifacts\run-001\coverage-report.txt
:flush-trace
:trace-persist
```

## Annotate Sources

Basic command:

```powershell
tclsh .\annotate_source_coverage.tcl app-sources.jar coverage-report.txt annotated-src app-instrumented-branch-probes.csv
```

With context filtering:

```powershell
tclsh .\annotate_source_coverage.tcl --context {.*} app-sources.jar coverage-report.txt annotated-src probes-folder
tclsh .\annotate_source_coverage.tcl --context {counter.*} app-sources.jar coverage-report.txt annotated-src probes-folder
tclsh .\annotate_source_coverage.tcl --context 1 app-sources.jar coverage-report.txt annotated-src app-instrumented-branch-probes.csv
```

Output Java lines receive trailing comments:

```java
if (value > 0) { /*COV T+ 2 7 10001*/
```

The comment values are:

```text
/*COV <edge><sense> <context_hit_count|NOHIT> <hit_count> <probe-id>*/
/*COV <context_hit_count|NOHIT> <hit_count> <probe-id>*/
```

Use the marker form for conditional branch probes and the markerless form for method-entry or other non-branch probes.

Marker meaning:

- `T` means the then/fall-through edge for the source-level conditional.
- `E` means the else/jump-target edge for the source-level conditional.
- `+` means the source-level subexpression sense is positive.
- `-` means the source-level subexpression sense is negated relative to the bytecode branch.

Count meaning:

- `context_hit_count` is the number of distinct selected/matching contexts in which the probe was hit at least once.
- `hit_count` is the total number of executions of that probe within selected/matching contexts.
- `NOHIT` is written where the selected context set did not hit that probe; the hit count field is then normally `0`.

The Code Analytics coverage report contains enough information to compute both numbers because each `HITS` row is keyed by context id, probe id, and count:

```text
<ctxId> <locId> <count>
```

For example, if probe `20072` has counts under two matching contexts totaling seven executions, annotate it as:

```java
while (...) { /*COV T+ 2 7 20072*/
```

## End-To-End Demo

```powershell
tclsh .\demo_source_coverage_annotation.tcl 10001 410 1 .* counter.json
```

Defaults:

```text
startId=10001
appId=410
instanceId=1
contextRegex=.*
specGlob=counter.json
```

Typical output folder:

```text
artifacts\source-coverage-annotation\<timestamp>\annotated-sources
```

The demo writes a manifest with the annotated sources, coverage report, probe CSV, source JAR, Code Analytics output, context regex, and spec glob.

## Fixture For Annotation Semantics

The repository contains a focused Java fixture for building a mental model of annotation behavior:

```text
coverage-annotation-fixture/src/main/java/com/example/covfixture
```

`CoverageFixtureMain` sets a separate context before each test case, then calls `TargetCode`, which intentionally contains short-circuit `&&` and `||`, negation, ternary expressions, loops, break, and continue. Use it when validating `T/E`, `+/-`, `NOHIT`, context hit counts, and hit counts.

When rerunning this fixture, save output under a timestamped folder such as:

```text
artifacts/coverage-annotation-fixture/<timestamp>/
```

Useful outputs are:

- `coverage-fixture-instrumented-branch-probes.csv`
- `fixture-coverage-report.csv`
- `annotated-sources-all*/com/example/covfixture/TargetCode.java`
- `annotated-by-context*/<context>/com/example/covfixture/TargetCode.java`

## Class Map For Metadata Filtering

For source-aware filtering in `ClojureShell`, generate a class map:

```powershell
tclsh .\list_java_classes.tcl overwrite .\classes.tsv C:\path\to\src\main\java
tclsh .\list_java_classes.tcl append .\classes.tsv C:\path\to\other\src\main\java
```

Then load it:

```text
:probe-metadata-load-classes .\classes.tsv
```

Use this when probe metadata contains class names but the user wants path-oriented operations such as `*/service/*.java`.
