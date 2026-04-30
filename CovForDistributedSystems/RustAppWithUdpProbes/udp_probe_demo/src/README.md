This directory contains legacy/demo sources that are not part of the current Cargo workspace build.

Notes

- The active demo is a Cargo workspace with members `mprewriter`, `mprewriter_macros`, and `app` (see `Cargo.toml`).
- The workspace uses the standardized 20-byte HIT record with stackDepth and the LOG record format expected by the servers.
- The files in this `src/` folder predate that change and are retained only for reference. They are not compiled.
- Prefer using `udp_probe_demo/app` as the entry point and `udp_probe_demo/mprewriter` for the runtime.

