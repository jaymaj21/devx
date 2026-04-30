# Hit Trace Dumpers — Usage and Examples

This repo contains multiple standalone trace dumpers for files produced by HitTraceWriter (magic `HITTRC01`). Each dumper can print hits/logs to stdout and now supports time-range filtering via `-start` and `-end`.

Use this doc as quick user-facing documentation with ready-to-run examples.

## Tools Overview

- Raw Tcl dumper: `code-analytics/trace_dump.tcl`
  - Shows outer frames with source, nanoseconds, and a text/hex preview of payload.
  - Always prints timestamp frames (TS) for context.

- Parsed Tcl dumper: `code-analytics/parsetrace.tcl`
  - Parses inner message payloads into structured output (`HIT`, `LOG`, `CTX+/CTX-`).
  - Always prints timestamp frames (TS) for context.

- Old-style Tcl dumper: `code-analytics/dumptrace.tcl`
  - Prints hits in the legacy “depth digits” line format and one-line logs.
  - Always prints timestamp frames (TS) for context.

- C++ dumper: `tools/trace-dump-cpp/trace_dump.cpp`
  - Legacy-style line output (fast). Supports `-start/-end` filters.

- Java dumper: `tools/trace-dump-java/TraceDumper.java`
  - Legacy-style line output. Supports `-start/-end` filters.

- Rust dumper: `tools/trace-dump-rust` (binary name: `dump_old`)
  - Legacy-style line output. Supports `-start/-end` filters.

## Time Filters: `-start` and `-end`

All dumpers accept optional `-start` and `-end` values. Filters are inclusive.

- Pass either:
  - Nanoseconds (file-clock) as an integer, or
  - RFC3339 UTC strings like `2025-01-01T12:34:56Z` or with fractional seconds `2025-01-01T12:34:56.250Z`.

When RFC3339 is used, the dumper converts each frame’s monotonic nanosecond timestamp to an epoch-based nanosecond time using the file header’s `startMillis` and the first frame’s `nanos` as a baseline.

Timestamp frames (flag 9; printed as `TS <time>`) are always included even if out of range.

## Finding a Valid Time Window

Before filtering, it’s easy to pick non-overlapping timestamps. Use the stats helper to locate the span:

```
tclsh hit_stats.tcl <trace-file>
```

This prints total hits and the approximate earliest/latest UTC times corresponding to the trace span. Use that as your `-start/-end` window or choose a narrower interval within that span.

## Build Instructions (compiled dumpers)

You can use any dumper; Tcl scripts require no build. For compiled dumpers:

- C++
  - `g++ -std=c++17 -O2 tools/trace-dump-cpp/trace_dump.cpp -o tools/trace-dump-cpp/trace_dump`

- Java
  - `javac tools/trace-dump-java/TraceDumper.java`
  - Run with: `java -cp tools/trace-dump-java TraceDumper ...`

- Rust
  - `cargo run --manifest-path tools/trace-dump-rust/Cargo.toml -- <args>`
  - Or `cargo build --release` then use the built binary.

## Examples

The examples below use the sample file `plant-trace-2025-11-13-20-33-15-196.txt`. Adjust paths and times as needed.

### 1) Discover the usable time range

```
tclsh hit_stats.tcl plant-trace-2025-11-13-20-33-15-196.txt
```

Example output (abridged):

- File start UTC: 2025-11-13 20:33:15
- Earliest Hit (UTC): 2025-11-13 20:33:15
- Latest Hit (UTC):   2025-11-13 20:33:33

### 2) Dump everything (no filters)

- Raw Tcl
  - `tclsh code-analytics/trace_dump.tcl plant-trace-2025-11-13-20-33-15-196.txt`

- Parsed Tcl
  - `tclsh code-analytics/parsetrace.tcl plant-trace-2025-11-13-20-33-15-196.txt`

- Old-style Tcl
  - `tclsh code-analytics/dumptrace.tcl plant-trace-2025-11-13-20-33-15-196.txt`

- C++
  - `tools/trace-dump-cpp/trace_dump plant-trace-2025-11-13-20-33-15-196.txt`

- Java
  - `java -cp tools/trace-dump-java TraceDumper plant-trace-2025-11-13-20-33-15-196.txt`

- Rust
  - `cargo run --manifest-path tools/trace-dump-rust/Cargo.toml -- plant-trace-2025-11-13-20-33-15-196.txt`

### 3) Filter by RFC3339 (UTC) window

Use a short 200 ms window within the file span:

- Raw Tcl (RFC3339)
  - `tclsh code-analytics/trace_dump.tcl plant-trace-2025-11-13-20-33-15-196.txt -start 2025-11-13T20:33:20Z -end 2025-11-13T20:33:20.200Z`

- Parsed Tcl (RFC3339)
  - `tclsh code-analytics/parsetrace.tcl plant-trace-2025-11-13-20-33-15-196.txt -start 2025-11-13T20:33:20Z -end 2025-11-13T20:33:20.200Z`

- Old-style Tcl (RFC3339)
  - `tclsh code-analytics/dumptrace.tcl plant-trace-2025-11-13-20-33-15-196.txt -start 2025-11-13T20:33:20Z -end 2025-11-13T20:33:20.200Z`

- C++ (RFC3339)
  - `tools/trace-dump-cpp/trace_dump plant-trace-2025-11-13-20-33-15-196.txt -start 2025-11-13T20:33:20Z -end 2025-11-13T20:33:20.200Z`

- Java (RFC3339)
  - `java -cp tools/trace-dump-java TraceDumper plant-trace-2025-11-13-20-33-15-196.txt -start 2025-11-13T20:33:20Z -end 2025-11-13T20:33:20.200Z`

- Rust (RFC3339)
  - `cargo run --manifest-path tools/trace-dump-rust/Cargo.toml -- plant-trace-2025-11-13-20-33-15-196.txt -start 2025-11-13T20:33:20Z -end 2025-11-13T20:33:20.200Z`

### 4) Filter by file-clock nanoseconds

If you know the raw `nanos` range from frames, pass integers directly. Example only (replace with real values from your file):

- Raw Tcl (nanos):
  - `tclsh code-analytics/trace_dump.tcl sample.trace -start 1535053850700000 -end 1535053850900000`

- C++ (nanos):
  - `tools/trace-dump-cpp/trace_dump sample.trace -start 1535053850700000 -end 1535053850900000`

### 5) Full-span dump using RFC3339 bounds

Using the bounds reported by `hit_stats.tcl`:

- Old-style Tcl (full span)
  - `tclsh code-analytics/dumptrace.tcl plant-trace-2025-11-13-20-33-15-196.txt -start 2025-11-13T20:33:15Z -end 2025-11-13T20:33:33Z`

### 6) Notes and Tips

- Timestamp frames (TS) are always printed, even if out of range, to help provide temporal context.
- RFC3339 parsing expects a trailing `Z` (UTC). Fractional seconds up to 9 digits are supported and internally normalized to nanoseconds.
- If a filter appears to return no data, verify you didn’t mix epoch-based RFC3339 values with file-clock nanos by mistake. Use `hit_stats.tcl` to find a matching range.

