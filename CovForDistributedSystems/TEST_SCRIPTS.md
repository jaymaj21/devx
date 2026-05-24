# Test Scripts

This file documents the runnable scripts used for testing/showcasing.

## `instrument_jars.tcl`

Purpose:
- instrument one jar, many jars, or whole folders of jars in place
- skip jars already instrumented
- back up each newly instrumented jar as `*_uninstrumented.jar`
- archive probe CSV files into `~/tmp/probes`

Usage:

```powershell
tclsh .\instrument_jars.tcl <startId> <path> [<path> ...]
```

Examples:

```powershell
tclsh .\instrument_jars.tcl 10001 C:\Git\jmtools\dstr\target\dstr-0.1.0.jar
tclsh .\instrument_jars.tcl 20001 C:\apps\my-jars C:\apps\other\service.jar
```

Interactive folder chooser:
- if you run it with no arguments, it opens a Tk folder chooser
- the selected folder is processed with `startId` `1`

```powershell
tclsh .\instrument_jars.tcl
```

## `run_dstr_instrumented_testsuite.tcl`

Purpose:
- ensure the built `dstr` jar is instrumented
- run the `dstr` JSON specs against an already running `code-analytics`
- send context resets plus spec-filename contexts through `mprewriter-runtime`

Defaults:
- `startId = 10001`
- `appId = 410`
- `instanceId = 1`
- expects `code-analytics` to already be listening on UDP `8083`

Usage:

```powershell
tclsh .\run_dstr_instrumented_testsuite.tcl [startId] [appId] [instanceId]
```

Examples:

```powershell
tclsh .\run_dstr_instrumented_testsuite.tcl
tclsh .\run_dstr_instrumented_testsuite.tcl 10001 410 1
```

Notes:
- this walks the checked-in specs under `C:\Git\jmtools\dstr\test-suite\specs`
- large specs can take a long time
- for a quick demo, run only a few small specs manually with `java` instead of the whole testsuite

## `test_mprewriter_runtime_udp_race.ps1`

Purpose:
- start `code-analytics`
- run a concurrent test app using `mprewriter-runtime`
- mix hits, log messages, and context attach/withdraw messages
- persist the trace and validate the received counts from the binary trace summary

Usage:

```powershell
powershell -ExecutionPolicy Bypass -File .\test_mprewriter_runtime_udp_race.ps1
```

Optional parameters:

```powershell
powershell -ExecutionPolicy Bypass -File .\test_mprewriter_runtime_udp_race.ps1 -ThreadCount 4 -Iterations 24
```

Artifacts:
- saved under `artifacts\mprewriter-runtime-race-test\<timestamp>\`

## Supporting Code Added Today

These are not standalone scripts, but they were changed to support the workflows above:

- `branch-probe-instrumenter/src/main/java/demo/JarInstrumenter.java`
  - improved idempotency detection so direct references to `mprewriter` do not cause false positives
- `branch-probe-suite/mprewriter-runtime/src/main/java/com/trading/domain/mprewriter.java`
  - unified outbound queue for hits, logs, and context messages
  - added queued log support and explicit shutdown
- `branch-probe-suite/mprewriter-runtime/src/test/java/com/trading/domain/MprewriterRuntimeMixedTrafficApp.java`
  - concurrent mixed-traffic integration client
- `code-analytics/src/main/java/com/codeanalytics/ContextManager.java`
  - `withdrawContext("ALL")` and `withdrawContext("all")` now clear the whole active context set
- `C:\Git\jmtools\dstr\src\main\java\org\dstr\cli\DstrCli.java`
  - resets collector context to `ALL`, then applies the spec filename for each run
