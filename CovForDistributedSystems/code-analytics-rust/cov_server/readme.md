To build
cargo build --release

To run
target/release/cov_server

Admin REPL (molt)

- Native commands
  - apply_context <label>
  - withdraw_context <label>
  - coverage_report <appId> <instanceId> — print coverage to console

- Java-style aliases (matching Java server)
- :apply-context <label>
- :withdraw-context <label>
- :hits — prints hit lines: "appId instanceId ctxId locId count"
- :coverage-report <appId> <instanceId> <filename> — writes file with sections:
  - CONTEXTS N then "<ctxId> <label>" lines (1 default)
  - HITS M then "<ctxId> <locId> <count>" lines
 - :help
 - :exit
 - :flush-trace — flush trace buffers so external tools can read latest
 - :trace-persist — force durable fsync of trace file

Trace dumper

- Standalone Rust dumper is under `tools/trace-dump-rust`. See its README for build/run steps.
