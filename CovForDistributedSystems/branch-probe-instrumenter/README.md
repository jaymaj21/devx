# Branch-Probe Instrumenter

This is the newer top-level instrumenter. It rewrites `.class` files inside an input JAR, injects branch and method-entry probes, and writes an instrumented output JAR.

The injected probe calls target `com.trading.domain.mprewriter`, so the instrumented application still needs the `mprewriter-runtime` JAR from `branch-probe-suite/mprewriter-runtime` at runtime unless you explicitly shade that runtime into the target application yourself.

## What This Version Adds

- Method-entry probes are delayed until a real source line is known.
- Constructor entry probes are emitted only after `super(...)` has completed.
- If line information is missing, `METHOD_ENTRY` still gets emitted with an unknown line.
- Catch and finally handlers get explicit probe points.
- Probe ids can now start from an explicit value via `--startid=N`.
- The tool prints `LAST_ID=<n>` so multiple instrumentation runs can use disjoint id ranges.
- If the input JAR already contains `mprewriter.class`, that runtime class is copied without instrumentation.

## Probe Types

By default, the tool can emit these logical probe kinds:

- `METHOD_ENTRY`
- `IF_TRUE`
- `IF_FALSE`
- `CATCH_ENTRY(...)`
- `FINALLY_ENTRY`

The emitted probe index is always written into the output JAR as:

```text
META-INF/branch-probes.csv
```

The CSV columns are:

```text
id,class,method,where,source,line
```

## Build

### Maven

```bash
mvn -q -DskipTests clean package
```

Output:

```text
target/branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar
```

### Gradle

```bash
./gradlew clean build -x test
```

Typical output:

```text
build/libs/branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar
```

## Command Line

```bash
java -jar branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar [--startid=N] [--sidecar] input.jar output-instrumented.jar
```

Arguments:

- `input.jar`
  The original application JAR to instrument.
- `output-instrumented.jar`
  The rewritten JAR containing injected probes.
- `--startid=N`
  Optional. Sets the first probe id to use for this run.
- `--sidecar`
  Optional. Writes a second CSV file next to the output JAR in addition to embedding `META-INF/branch-probes.csv` inside the output JAR.

Printed output:

- `Instrumented: <input> -> <output>`
- `Wrote sidecar: <path>` if `--sidecar` is used
- `LAST_ID=<n>` after the run completes

## Basic Example

```bash
java -jar target/branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar app.jar app-instrumented.jar
```

## Multi-JAR Example

If you need globally unique location ids across several instrumented JARs, use `--startid` and chain from the previous `LAST_ID`.

Example:

```bash
java -jar target/branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar --startid=1001 service-a.jar service-a-instrumented.jar
```

If that prints:

```text
LAST_ID=1874
```

then the next JAR should start at `1875`:

```bash
java -jar target/branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar --startid=1875 service-b.jar service-b-instrumented.jar
```

## Filtering What Gets Instrumented

The tool supports optional include and exclude files via system properties.

System properties:

- `-Dbp.includefile=<path>`
- `-Dbp.excludefile=<path>`
- `-Dbp.inject=<comma-separated-kinds>`

Example:

```bash
java -Dbp.excludefile=exclusions.txt -Dbp.includefile=inclusions.txt -jar target/branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar --sidecar app.jar app-instrumented.jar
```

Expected file format:

```text
com.example.Foo:17
com.example.Bar:20-35
com.example.Baz:*
```

Meaning:

- `Class:17` matches exactly one source line
- `Class:20-35` matches an inclusive line range
- `Class:*` matches all lines in that class

Behavior:

- Exclusions suppress probes for matching source lines.
- Inclusions act as a whitelist when present.
- If no inclusion file is provided, everything is eligible by default.

## Selecting Probe Kinds

`bp.inject` limits the emitted logical probe kinds.

Example:

```bash
java -Dbp.inject=METHOD_ENTRY,IF_TRUE,IF_FALSE -jar target/branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar app.jar app-instrumented.jar
```

Supported kind names for filtering:

- `METHOD_ENTRY`
- `CATCH_ENTRY`
- `FINALLY_ENTRY`
- `IF_TRUE`
- `IF_FALSE`

Note that the CSV may still contain `where` values such as `CATCH_ENTRY(java.io.IOException)`, but filtering uses the base kind name `CATCH_ENTRY`.

## Runtime Requirements

The instrumented application needs `mprewriter-runtime` on its classpath when it runs.

Build the runtime:

```bash
cd ../branch-probe-suite/mprewriter-runtime
mvn -q -DskipTests package
```

Runtime artifact:

```text
target/mprewriter-runtime-1.0.0.jar
```

## Running an Instrumented Application

### Linux or macOS

```bash
java -cp "mprewriter-runtime-1.0.0.jar:app-instrumented.jar" com.example.Main
```

### Windows

```powershell
java -cp "mprewriter-runtime-1.0.0.jar;app-instrumented.jar" com.example.Main
```

If the original JAR had a `Main-Class` manifest entry, do not use `java -jar` unless the runtime has been shaded into that application. Use `-cp` so both jars are available.

## Runtime Network Settings

The runtime sends UDP hit packets to the analytics server. Defaults can be overridden with system properties.

Supported properties:

- `-Dmprewriter.host=127.0.0.1`
- `-Dmprewriter.port=8083`
- `-Dmprewriter.appId=12345`
- `-Dmprewriter.instanceId=1`

Example:

```bash
java -cp "mprewriter-runtime-1.0.0.jar:app-instrumented.jar" -Dmprewriter.host=127.0.0.1 -Dmprewriter.port=8083 -Dmprewriter.appId=101 -Dmprewriter.instanceId=7 com.example.Main
```

## Running with `code-analytics`

Start the Java analytics server first:

```bash
cd ../code-analytics
mvn -q -DskipTests package
java -cp target/clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar com.codeanalytics.ClojureShell
```

Then run the instrumented application with `mprewriter-runtime` on the classpath. By default, the runtime sends to UDP port `8083`, which matches `code-analytics`.

## Output Artifacts

The instrumenter produces:

- An instrumented output JAR
- An embedded `META-INF/branch-probes.csv`
- An optional sidecar CSV named like `output-instrumented-branch-probes.csv`

## Example Probe CSV Rows

```text
10,com.example.demo.Service,fizzBuzz,METHOD_ENTRY,Service.java,7
11,com.example.demo.Service,fizzBuzz,IF_TRUE,Service.java,12
12,com.example.demo.Service,fizzBuzz,IF_FALSE,Service.java,13
```

## Notes and Limitations

- Classes should retain line-number information for best source mapping.
- Signature files under `META-INF` are copied through unchanged and are not instrumented.
- `module-info.class` is copied through unchanged.
- `mprewriter.class` is copied through unchanged if present in the input JAR.
- On instrumentation failure for a class, the original class bytes are copied back and a warning is printed.
- This tool instruments class files inside a JAR. It does not rewrite loose `.class` files in directories.
