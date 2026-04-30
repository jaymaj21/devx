CTR1 Trace Dumper (C++)

- Build (example with g++):
  - `g++ -std=c++17 -O2 trace_dump.cpp -o trace_dump`
- Run:
  - `./trace_dump /path/to/trace.bin > out.txt`
  - Optional time filter (nanoseconds or RFC3339 UTC):
    - `./trace_dump /path/to/trace.bin -start 1710000000000000000 -end 1710000001000000000`
    - `./trace_dump /path/to/trace.bin -start 2025-01-01T12:00:00Z -end 2025-01-01T12:00:01.250Z`

Output (legacy style with stack-depth digits)

- HIT: `:12345<42> appId, instanceId, threadId`
- LOG: `LOG message text`

