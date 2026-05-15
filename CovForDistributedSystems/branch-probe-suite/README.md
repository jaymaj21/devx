# Branch Probe Suite

This folder contains the older integrated branch-probe toolchain. It has two Maven modules:

- `mprewriter-runtime`
- `branch-probe-instrumenter`

The instrumenter rewrites application JARs and injects probe calls. The runtime is the library those injected calls target at application runtime.

This suite is still usable and supports explicit probe-id ranges via `--startid`, but the newer top-level `../branch-probe-instrumenter` has more refined method-entry placement and better source-line fidelity.

## Modules

### `mprewriter-runtime`

This is the runtime used by the instrumented application.

Responsibilities:

- Tracks per-thread stack depth
- Sends UDP hit messages
- Exposes the static methods the injected bytecode calls

The runtime class is:

```text
com.trading.domain.mprewriter
```

### `branch-probe-instrumenter`

This is the older CLI instrumenter.

Responsibilities:

- Reads an input JAR
- Rewrites `.class` files
- Injects probe calls
- Writes an output JAR
- Embeds `META-INF/branch-probes.csv`
- Optionally writes a sidecar CSV next to the output JAR

## Build

From this directory:

```bash
mvn -q -e -DskipTests package
```

Artifacts:

- `mprewriter-runtime/target/mprewriter-runtime-1.0.0.jar`
- `branch-probe-instrumenter/target/branch-probe-instrumenter-1.0.0-shaded.jar`

The instrumenter artifact is a fat JAR for the instrumenter itself. It does not package `mprewriter-runtime` into the target application.

## Instrumenter Command Line

```bash
java -jar branch-probe-instrumenter/target/branch-probe-instrumenter-1.0.0-shaded.jar [--startid=N] [--sidecar] input.jar output-instrumented.jar
```

Arguments:

- `input.jar`
  The original application JAR to instrument.
- `output-instrumented.jar`
  The rewritten JAR that contains injected probes.
- `--startid=N`
  Optional. Sets the first probe id for this run.
- `--sidecar`
  Optional. Writes a CSV file next to the output JAR in addition to embedding the CSV into the JAR.

Printed output:

- `Wrote sidecar: <path>` if `--sidecar` is used
- `Instrumented: <input> -> <output>`
- `LAST_ID=<n>`

## Basic Example

```bash
java -jar branch-probe-instrumenter/target/branch-probe-instrumenter-1.0.0-shaded.jar --sidecar app.jar app-instrumented.jar
```

## Multi-JAR Example

This older tool already supports allocating disjoint probe-id ranges across multiple JARs.

Example:

```bash
java -jar branch-probe-instrumenter/target/branch-probe-instrumenter-1.0.0-shaded.jar --startid=5001 --sidecar service-a.jar service-a-instrumented.jar
```

If the output ends with:

```text
LAST_ID=6180
```

then the next run should start at `6181`:

```bash
java -jar branch-probe-instrumenter/target/branch-probe-instrumenter-1.0.0-shaded.jar --startid=6181 --sidecar service-b.jar service-b-instrumented.jar
```

## Probe Mapping Output

The instrumenter embeds this file into the output JAR:

```text
META-INF/branch-probes.csv
```

CSV columns:

```text
id,class,method,where,source,line
```

If `--sidecar` is given, it also writes a neighboring file named like:

```text
output-instrumented-branch-probes.csv
```

## Filtering What Gets Instrumented

The older instrumenter supports the same include, exclude, and probe-kind filters through system properties.

Supported properties:

- `-Dbp.includefile=<path>`
- `-Dbp.excludefile=<path>`
- `-Dbp.inject=<comma-separated-kinds>`

Example:

```bash
java -Dbp.excludefile=exclusions.txt -Dbp.includefile=inclusions.txt -jar branch-probe-instrumenter/target/branch-probe-instrumenter-1.0.0-shaded.jar --sidecar app.jar app-instrumented.jar
```

Line-spec format:

```text
com.example.Foo:17
com.example.Bar:20-35
com.example.Baz:*
```

Behavior:

- Exclusion entries suppress matching source-line probes.
- Inclusion entries act as a whitelist if an inclusion file is present.
- If no inclusion file is given, all lines are eligible by default.

## Selecting Probe Kinds

Example:

```bash
java -Dbp.inject=METHOD_ENTRY,IF_TRUE,IF_FALSE -jar branch-probe-instrumenter/target/branch-probe-instrumenter-1.0.0-shaded.jar app.jar app-instrumented.jar
```

Supported kind names:

- `METHOD_ENTRY`
- `CATCH_ENTRY`
- `FINALLY_ENTRY`
- `IF_TRUE`
- `IF_FALSE`

## Runtime Requirements

After instrumentation, the application must run with `mprewriter-runtime` on its classpath unless you separately shade that runtime into the application.

Build the runtime:

```bash
cd mprewriter-runtime
mvn -q -DskipTests package
```

Runtime artifact:

```text
mprewriter-runtime/target/mprewriter-runtime-1.0.0.jar
```

## Running an Instrumented Application

### Linux or macOS

```bash
java -cp "mprewriter-runtime/target/mprewriter-runtime-1.0.0.jar:app-instrumented.jar" com.example.Main
```

### Windows

```powershell
java -cp "mprewriter-runtime\target\mprewriter-runtime-1.0.0.jar;app-instrumented.jar" com.example.Main
```

If the application JAR originally ran with `java -jar`, switch to `java -cp` unless you have explicitly repackaged the runtime into that application.

## Runtime Configuration

The runtime sends UDP hits to the analytics server. Defaults can be overridden via system properties:

- `-Dmprewriter.host=127.0.0.1`
- `-Dmprewriter.port=8083`
- `-Dmprewriter.appId=12345`
- `-Dmprewriter.instanceId=1`

Example:

```bash
java -cp "mprewriter-runtime/target/mprewriter-runtime-1.0.0.jar:app-instrumented.jar" -Dmprewriter.host=127.0.0.1 -Dmprewriter.port=8083 -Dmprewriter.appId=101 -Dmprewriter.instanceId=7 com.example.Main
```

## Running with `code-analytics`

Start `code-analytics` first:

```bash
cd ../code-analytics
mvn -q -DskipTests package
java -cp target/clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar com.codeanalytics.ClojureShell
```

By default:

- `code-analytics` listens on UDP `8083`
- `mprewriter-runtime` sends to UDP `8083`

So the default network settings line up without extra configuration.

## Windows Demo Flow

The repo includes an older batch example in `../branch-probe-demoapp/test-probe-suite.bat`.

Equivalent commands:

```powershell
java -jar ..\branch-probe-suite\branch-probe-instrumenter\target\branch-probe-instrumenter-1.0.0-shaded.jar --startid=5001 --sidecar demo.jar demo-instrumented.jar
java -cp "..\branch-probe-suite\mprewriter-runtime\target\mprewriter-runtime-1.0.0.jar;demo-instrumented.jar" com.example.demo.Main
```

## Compatibility Notes

- This instrumenter uses the same `com.trading.domain.mprewriter` runtime API as the newer top-level instrumenter.
- The current code injects `scope_ENTER()`, `hit(id)`, and `scope_EXIT()` calls. Some older comments and text may still mention `scope_START(int)`, but that is stale documentation.
- If the input JAR already contains `mprewriter.class`, this older instrumenter copies it through without instrumenting it.

## Notes and Limitations

- Source-line mapping is only as good as the line information present in the compiled classes.
- Signature files under `META-INF` are copied through unchanged.
- `module-info.class` is copied through unchanged.
- `mprewriter.class` is copied through unchanged if present in the input JAR.
- This suite instruments JAR contents, not loose class directories.
