# C++ UDP Probe + RAII Scope Macro

This folder contains a small C++ probe runtime that batches coverage hits and logs over UDP to `127.0.0.1:8083`, plus a convenient RAII macro to track thread‑local stack depth like the Rust proc‑macro version.

Key pieces:
- `mprewriter.hpp` — header exposing the RAII guard and `mprewriter_scope_START(locationId)` macro, plus init/shutdown helpers.
- `mprewriter.cpp` — runtime implementation (UDP sender thread, queues, serialization). Contains an optional standalone demo `main()` behind `MPREWRITER_STANDALONE`.
- `fractal_demo.cpp` — example program that renders a Mandelbrot fractal to `fractal.ppm` while emitting probes and logs.

Build (MinGW on Windows):
```
c++ -DMPREWRITER_STANDALONE=1 mprewriter.cpp -lws2_32 -o mprewriter.exe
c++ -DMPREWRITER_STANDALONE=0 mprewriter.cpp fractal_demo.cpp -lws2_32 -o fractal_demo.exe
```

Usage in your code:
```
#include "mprewriter.hpp"

int main() {
  mpr_start_sender();
  mprewriter_scope_START(2001); // records a hit; depth increments for this scope
  // ... work (nested scopes will have higher depths) ...
  close_probe();
  mpr_join_sender();
}
```

Packet format (big‑endian):
- HIT (type=1): `[u16 type][u16 appId][u32 instanceId][u32 threadId][u32 stackDepth][u32 locationId]`
- LOG (type=2): `[u16 type][u16 appId][u32 instanceId][u32 threadId][u32 stackDepth][u16 len][bytes]`

The Java server (`code-analytics`) already accepts this format and uses `stackDepth`.

