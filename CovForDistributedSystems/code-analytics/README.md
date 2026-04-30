Java Coverage/Trace Server (ClojureShell)

- Listens on UDP 8083 and TCP 8084 for probe messages (HIT/LOG/CTX).
- Streams a binary trace file per session (HITTRC01 header + framed records).
- Provides an interactive Clojure-backed admin shell.

Run

- java -cp build/libs/clojure-shell-<version>-jar-with-dependencies.jar com.codeanalytics.ClojureShell

Common Admin Commands (colon-prefixed)

- :help — list available commands
- :hits — print hit records aggregated by (appId, instanceId, threadId, stackDepth, locationId)
- :apply-context <label> — attach a context to the current set
- :withdraw-context <label> — withdraw a context from the current set
- :coverage-report <appId> <instanceId> <filename> — write coverage file:
  - CONTEXTS N then "<ctxId> <label>" lines (ctxId 1 is default)
  - HITS M then "<ctxId> <locId> <count>" lines
- :exit — stop the shell and close the trace
- :flush-trace — flush trace buffers so external tools can read latest
- :trace-persist — force durable fsync of trace file

Trace Dumper

- Standalone dumpers are under `tools/` (Java/C++/Rust). See each folder for build/run instructions.
- Output lines (legacy style with stack-depth digits):
  - HIT: `:12345<42> appId, instanceId, threadId` (digits count shows stack depth)
  - LOG: `LOG message text`
