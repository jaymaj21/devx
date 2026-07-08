---
name: cov-for-distributed-systems-java
description: Use when Codex needs to work with the Java side of CovForDistributedSystems, including source-level Java instrumentation with instr2.py, bytecode/JAR instrumentation with the branch-probe instrumenter, allocating probe id ranges across multiple source files or JARs, recording probe hits with mprewriter and code-analytics, remotely triggering code-analytics exports over UDP, testing collectors with capinger, loading branch-probe CSV metadata or grep-style scope_START metadata, loading Java class maps, filtering traces by class/path/method/probe kind/id, producing coverage reports, and annotating Java source JARs or source trees with probe hit counts.
---

# CovForDistributedSystems Java

Use this skill to turn natural-language requests about Java coverage instrumentation into concrete CovForDistributedSystems commands and artifacts.

## Repository Orientation

Assume the project root is `development_tools/CovForDistributedSystems` unless the user points to another checkout.

Prefer the newer top-level instrumenter at `branch-probe-instrumenter` for Java JAR instrumentation. Use `branch-probe-suite/branch-probe-instrumenter` only when the user asks for the older integrated suite or compatibility with the older shaded artifact.

Use `instr2.py` when the user specifically wants source-code-level instrumentation before compilation, wants editable injected Java source, or wants grep-style `mprewriter.scope_START(id)` metadata for Spectral/JMWrap trace lookup workflows. It is regex-based rather than parser-based, so treat it as pragmatic and inspect diffs before compiling.

Key components:

- `branch-probe-instrumenter`: newer Java bytecode instrumenter for application JARs.
- `instr2.py`: regex-based Java source rewriter that injects `mprewriter.scope_START(id)` calls and can emit CSV and grep-style metadata.
- `branch-probe-suite/mprewriter-runtime`: runtime JAR required by instrumented applications.
- `code-analytics`: Java/Clojure analytics server, UDP hit receiver, interactive shell, trace writer, trace analyzer, and metadata filter host.
- `capinger.java` and `capinger_sequence.bat`: standalone UDP smoke-test client and scripted command sequence for sending `CMD`, `HIT`, `LOG`, and context packets to `code-analytics`.
- `list_java_classes.tcl`: source indexer that maps Java class names to relative source paths.
- `annotate_source_coverage.tcl`: annotates extracted Java sources from a sources JAR using coverage reports and branch probe CSVs.
- `plant_trace_tool.tcl`: Tcl trace summary and dump wrapper.
- `run_dstr_code_analytics.ps1`, `run_dstr_instrumented_testsuite.tcl`, `demo_source_coverage_annotation.tcl`: end-to-end examples.

## Default Workflow

For a Java coverage request, first choose the instrumentation mode:

- Use JAR instrumentation when the target is already built, source should remain untouched, or branch/method-entry probe metadata should come from bytecode.
- Use source-level instrumentation when the target source tree is editable, the user wants to inspect or compile injected Java, or the associated tooling expects grep-style `scope_START` location metadata.

For the default JAR workflow, execute or explain this sequence:

1. Build `code-analytics`, `branch-probe-instrumenter`, and `branch-probe-suite/mprewriter-runtime`.
2. Build the target application JAR and, when source annotation is needed, its `*-sources.jar`.
3. Instrument the application JAR with `--sidecar`; use `--startid` for stable or multi-JAR probe id ranges.
4. Start `code-analytics` before running the application.
5. Run the instrumented app with `mprewriter-runtime` plus the instrumented JAR on the classpath. Do not use `java -jar` unless the runtime has been shaded into the app.
6. In `ClojureShell`, inspect live hits or write `:coverage-report <appId> <instanceId> <file>`.
7. Load branch probe metadata and class maps when the user wants class/path/method/source-level exploration.
8. Save focused trace subsets or annotate sources as requested.

For source-level instrumentation, read `references/source-level-instrumentation.md` before editing source files.

Read `references/java-workflows.md` for exact JAR commands before running or producing an end-to-end command plan.

## Conversational Behavior

When the user asks for "instrument this", first identify:

- input application JAR path;
- main class or launch command;
- desired `appId`, `instanceId`, UDP host/port, and starting probe id;
- whether to instrument one JAR or a set of JARs with globally unique ids;
- whether they need trace analysis, coverage report, source annotation, or all artifacts.

If any value is missing and a safe default exists, choose it and state it:

- `startId=10001`
- `appId=410`
- `instanceId=1`
- host `127.0.0.1`
- UDP port `8083`
- TCP admin port `8084`

Preserve generated artifacts in a timestamped folder under `development_tools/CovForDistributedSystems/artifacts/` unless the user specifies another output directory.

## Important Guardrails

- Keep original JARs. If using `instrument_jars.tcl`, note that it backs up originals as `*_uninstrumented.jar` and instruments in place.
- Use `--sidecar` whenever metadata, filtering, source annotation, or later debugging may be needed.
- Chain `LAST_ID=<n>` into the next run as `--startid=<n+1>` for multi-JAR instrumentation.
- Keep source line debug information in compiled classes; source annotation quality depends on line numbers.
- Use Windows classpath separator `;` on this machine and `:` on Linux/macOS.
- Prefer Maven commands shown in the references when both Maven and Gradle artifacts exist, unless the user is already working in Gradle.
- Use `:help`, `:help trace`, `:help metadata`, `:help runtime`, and `:concepts` inside `ClojureShell` as the local source of truth for shell command details.
- Use remote UDP `CMD ...` commands or `capinger` only for the fixed code-analytics allowlist; never expose or depend on remote Clojure evaluation.

## References

- Use `references/java-workflows.md` for build, instrumentation, runtime, and end-to-end command recipes.
- Use `references/source-level-instrumentation.md` for `instr2.py`, source-tree instrumentation, grep-style metadata, and Spectral/JMWrap trace lookup compatibility.
- Use `references/code-analytics.md` for ClojureShell commands, remote UDP commands, `capinger`, trace analysis, metadata loading, filtering, and subset creation.
- Use `references/source-annotation.md` for Java source JAR annotation with coverage reports and probe CSV metadata.
- Use `references/troubleshooting.md` for common failure modes and checks.
