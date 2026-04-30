# Gradle files (v4): jar names + fat JARs aligned with Maven


This version ensures:
- **Jar base name == Maven `artifactId`** (e.g., `clojure-shell-1.0-SNAPSHOT.jar`).
- If Maven used **maven-assembly-plugin** or **maven-shade-plugin**, Gradle applies **Shadow** and produces:
  - standard thin JAR: `<artifactId>-<version>.jar`
  - fat JAR with deps: `<artifactId>-<version>-jar-with-dependencies.jar`

Repositories remain defined in `settings.gradle.kts` only.

Usage:
1) Unzip into the parent folder containing your Maven projects.
2) From that parent folder:
   ```bash
   gradle wrapper --gradle-version 8.10.2
   ./gradlew build
   ```

You should now see, for modules like `code-analytics` with `artifactId` `clojure-shell`:
- `build/libs/clojure-shell-1.0-SNAPSHOT.jar`
- `build/libs/clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar`
matching the Maven outputs under `target/`.

```

Launching ClojureShell cov server
```
java -cp ./code-analytics/build/libs/clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar  com.codeanalytics.ClojureShell ```

## How To Launch

- Java server
  - `java -cp ./code-analytics/build/libs/clojure-shell-<version>-jar-with-dependencies.jar com.codeanalytics.ClojureShell`

- C++ server
  - `./code-analytics-cpp/build/cov_server --udp 8083 --tcp 8084 --trace trace.bin`

- Rust server
  - `cargo build --release --manifest-path code-analytics-rust/cov_server/Cargo.toml`
  - `code-analytics-rust/cov_server/target/release/cov_server`

## Common Admin Commands

Across Java (Clojure), C++ (Tcl), and Rust (molt) servers, the following Java-style colon-prefixed commands are available:

- `:help` — list available commands
- `:hits` — show received hits (format may vary slightly per server)
- `:apply-context <label>` — add a context to the current active set
- `:withdraw-context <label>` — remove a context from the active set
- `:coverage-report <appId> <instanceId> <filename>` — write coverage file with:
  - `CONTEXTS N` then `<ctxId> <label>` lines (ctxId `1` is `default`)
  - `HITS M` then `<ctxId> <locId> <count>` lines
- `:exit` — exit the server shell
- `:flush-trace` — flush trace buffers so external tools can read latest
- `:trace-persist` — force durable fsync of trace file

Native (non-colon) commands also exist in C++ and Rust shells (e.g., `ctx`, `coverage`, `report`), but the colon-prefixed set above is consistent across all three.
