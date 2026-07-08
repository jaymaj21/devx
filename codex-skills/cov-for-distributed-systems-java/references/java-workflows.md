# Java Workflows

Run commands from `development_tools/CovForDistributedSystems` unless noted.

## Build Core Artifacts

Maven:

```powershell
Push-Location .\code-analytics
mvn -DskipTests package
Pop-Location

Push-Location .\branch-probe-instrumenter
mvn -DskipTests clean package
Pop-Location

Push-Location .\branch-probe-suite\mprewriter-runtime
mvn -DskipTests package
Pop-Location
```

Expected artifacts:

```text
code-analytics\target\clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar
branch-probe-instrumenter\target\branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar
branch-probe-suite\mprewriter-runtime\target\mprewriter-runtime-1.0.0.jar
```

Gradle is also available:

```powershell
.\gradlew.bat build -x test
```

## Instrument One Application JAR

Prefer the newer top-level instrumenter:

```powershell
java -jar .\branch-probe-instrumenter\target\branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar --startid=10001 --sidecar app.jar app-instrumented.jar
```

Outputs:

```text
app-instrumented.jar
app-instrumented-branch-probes.csv
META-INF/branch-probes.csv embedded in app-instrumented.jar
LAST_ID=<n>
```

Probe CSV columns:

```text
id,class,method,where,source,line
```

## Instrument Multiple JARs

Use disjoint id ranges:

```powershell
java -jar .\branch-probe-instrumenter\target\branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar --startid=10001 --sidecar service-a.jar service-a-instrumented.jar
```

If the output prints `LAST_ID=11870`, run the next JAR with `--startid=11871`.

For recursive in-place instrumentation with backups and archived probe CSVs:

```powershell
tclsh .\instrument_jars.tcl 10001 C:\path\to\jars
```

This creates `*_uninstrumented.jar` backups and archives sidecar probe CSV files under `~/tmp/probes`.

## Include, Exclude, And Probe Kind Filters

Line filter file format:

```text
com.example.Foo:17
com.example.Bar:20-35
com.example.Baz:*
```

Use the filters as Java system properties before `-jar`:

```powershell
java -Dbp.includefile=inclusions.txt -Dbp.excludefile=exclusions.txt -Dbp.inject=METHOD_ENTRY,IF_TRUE,IF_FALSE -jar .\branch-probe-instrumenter\target\branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar --sidecar app.jar app-instrumented.jar
```

Supported `bp.inject` base kinds:

```text
METHOD_ENTRY
CATCH_ENTRY
FINALLY_ENTRY
IF_TRUE
IF_FALSE
```

## Start Code Analytics

```powershell
java -cp .\code-analytics\target\clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar com.codeanalytics.ClojureShell
```

Defaults:

```text
UDP hit receiver: 8083
TCP admin: 8084
trace files: code-analytics\plant-trace-*.txt
```

## Smoke-Test Code Analytics With capinger

Use `capinger.java` when the user wants to verify that a running `code-analytics` UDP server accepts hits, logs, context changes, and remote export commands without launching an instrumented application.

```powershell
javac capinger.java
java capinger CMD status
java capinger CTX smoke-test
java capinger HIT 1 1 7 2 1234 10
java capinger LOG 1 1 7 2 smoke test log
java capinger CTX_WITHDRAW smoke-test
java capinger CMD coverage-report 1 1 capinger-smoke.cov
java capinger CMD coverage-hits capinger-smoke-hits.csv
java capinger CMD flush-trace
```

For a longer scripted run:

```bat
capinger_sequence.bat
capinger_sequence.bat 127.0.0.1 8083
```

`capinger_sequence.bat` does not stop the server unless `SEND_EXIT=1` is set in the batch file.

## Run An Instrumented Java App

Windows classpath:

```powershell
java -cp ".\branch-probe-suite\mprewriter-runtime\target\mprewriter-runtime-1.0.0.jar;app-instrumented.jar" -Dmprewriter.host=127.0.0.1 -Dmprewriter.port=8083 -Dmprewriter.appId=410 -Dmprewriter.instanceId=1 com.example.Main
```

Linux/macOS classpath:

```bash
java -cp "./branch-probe-suite/mprewriter-runtime/target/mprewriter-runtime-1.0.0.jar:app-instrumented.jar" -Dmprewriter.host=127.0.0.1 -Dmprewriter.port=8083 -Dmprewriter.appId=410 -Dmprewriter.instanceId=1 com.example.Main
```

Do not use `java -jar app-instrumented.jar` unless `mprewriter-runtime` has been shaded into that application JAR.

## End-To-End DSTR Examples

Run the PowerShell DSTR workflow:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_dstr_code_analytics.ps1
```

With a specific spec:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_dstr_code_analytics.ps1 -SpecPath test-suite\specs\bakery-3proc.json -StartId 10001 -AppId 410 -InstanceId 1
```

Source annotation demo:

```powershell
tclsh .\demo_source_coverage_annotation.tcl 10001 410 1 .* counter.json
```
