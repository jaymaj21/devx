# Branch Probe Suite

Two Maven modules:

- **mprewriter-runtime** — tiny runtime that sends UDP hits (`APPLICATION_ID, INSTANCE_ID, threadId, locationId`). 
  Exposes `com.trading.domain.mprewriter.scope_START(int)`.

- **branch-probe-instrumenter** — ASM-based CLI that injects probes into `.class` files inside a JAR. 
  Each probe calls `mprewriter.scope_START(id)` and appends a mapping file to the output JAR at `META-INF/branch-probes.csv`.

## Build

```bash
mvn -q -e -DskipTests package
```
Artifacts:
- `mprewriter-runtime/target/mprewriter-runtime-1.0.0.jar`
- `branch-probe-instrumenter/target/branch-probe-instrumenter-1.0.0-shaded.jar` (fat JAR)

## Usage

```bash
java -jar branch-probe-instrumenter/target/branch-probe-instrumenter-1.0.0-shaded.jar   --startid=1001 --sidecar input.jar output-instrumented.jar
```

Output:
- Prints `LAST_ID=<n>` so you can chain instrumentation runs with disjoint id ranges.
- Embeds `META-INF/branch-probes.csv` inside the output JAR and writes a neighbor CSV if `--sidecar` is used.

## Runtime

Ensure the instrumented program has `mprewriter-runtime` on its classpath (or shade it in).
Optionally tune via system properties:

```
-Dmprewriter.host=127.0.0.1
-Dmprewriter.port=8083
-Dmprewriter.appId=12345
-Dmprewriter.instanceId=1
```

