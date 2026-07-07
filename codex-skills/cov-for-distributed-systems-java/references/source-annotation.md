# Source Annotation

Use source annotation when the user wants Java source files marked with probe hit counts.

## Inputs

Required:

- Java sources JAR, usually `target\<artifact>-<version>-sources.jar`.
- Code Analytics coverage report from `:coverage-report <appId> <instanceId> <filename>`.
- One or more branch probe CSV sidecars from instrumentation, or directories containing CSVs.
- Output directory for extracted and annotated sources.

The source JAR should correspond to the classes that were instrumented. Line-number fidelity depends on the target classes being compiled with debug line information.

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
if (value > 0) { /*COV 42 10001*/
```

The comment values are:

```text
/*COV <aggregated-hit-count> <probe-id>*/
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
