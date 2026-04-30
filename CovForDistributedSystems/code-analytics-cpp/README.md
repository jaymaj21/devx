# cov_server_cpp

A C++17 implementation of your coverage hit/log collector with both UDP and TCP listeners, a binary trace writer, and an embedded **Tcl** REPL for interrogation (replacing the Clojure shell you used in Java).

> **Message types (big‑endian):**
>
> - `1` **HIT**: `type:u16, appId:u16, instanceId:u32, threadId:u32, stackDepth:u32, locationId:u32`  (20 bytes total)
> - `2` **LOG**: `type:u16, appId:u16, instanceId:u32, threadId:u32, msgLen:u16, msg:bytes[msgLen]`
> - `3` **CTX_ATTACH**: `type:u16, utf8(context-name...)`
> - `4` **CTX_WITHDRAW**: `type:u16, utf8(context-name...)`
>
> The server keeps a *global* active context-set. When a CTX message arrives, it updates the current set; subsequent HITs are counted under the current set's **contextSetId**. Context set id `1` is reserved for the empty set; new sets are assigned ids starting from `2`.

## Build

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . -j
```

You need Tcl headers & libs installed. On Ubuntu/Debian:

```bash
sudo apt-get install tcl tcl-dev   # provides tcl.h and libtcl
```

On macOS (Homebrew):
```bash
brew install tcl-tk
# You may need to set CMAKE_PREFIX_PATH to the prefix of Tcl/Tk
```

On Windows (MinGW/MSYS2):
```bash
pacman -S mingw-w64-x86_64-tcl
```

## Run

```bash
./cov_server --udp 8083 --tcp 8084 --trace trace.bin
```

The process starts:
- a UDP listener on the specified port
- a TCP listener (multi-client) on the specified port
- a foreground **Tcl** REPL for admin/interrogation

## Tcl REPL commands

- Native commands
  - `hits ?limit?` — Print raw hit counts keyed by `(appId,instanceId,threadId,locationId)`.
  - `coverage ?appId? ?instanceId?` — Aggregate by `(appId,instanceId,locationId,ctxId)` and show counts.
  - `ctx current` — Show current active context-set id and names.
  - `ctx list` — Show all known context-set ids and their members.
  - `ctx attach NAME` — Add a context name to the current set.
  - `ctx withdraw NAME` — Remove a context name from the current set.
  - `report APP_ID INSTANCE_ID FILENAME` — Write a text coverage report (context sets + hits) to file.
  - `trace rotate FILENAME` — Close current trace (if any) and open a new one.
  - `help` — Show the list of commands.
  - `exit` — Quit the REPL and terminate the server.

- Java-style aliases (matching Java server)
  - `:hits`
  - `:apply-context NAME`
  - `:withdraw-context NAME`
  - `:coverage-report APP_ID INSTANCE_ID FILENAME` — Writes report in the same format as Java server:
    - `CONTEXTS N` then `<ctxId> <label>` lines (`1 default`)
    - `HITS M` then `<ctxId> <locId> <count>` lines
  - `:help`
  - `:exit`
  - `:flush-trace` — flush trace buffers so external tools can read latest
  - `:trace-persist` — force durable fsync of trace file

## Trace format (HITTRC01)

```
Header:
  magic:  8 bytes  "HITTRC01"
  endian: u8       0 = big-endian
  start:  u64      epochMillis when file opened
Frames (repeated):
  flag:   u16      1=HIT, 2=LOG, 3=CTX_ATTACH, 4=CTX_WITHDRAW, 9=TS
  src:    u8       0=UDP, 1=TCP, 2=INTERNAL
  t_ns:   u64      monotonic nanoseconds at write
  len:    u32      payload length N
  data:   N bytes  raw payload (HIT/LOG/CTX start at message type)
```

## Trace dumper

- Standalone C++ dumper is under `tools/trace-dump-cpp`. See its README for build/run steps.

## Example Tcl script

See `scripts/example.tcl` for a tiny demo you can source into the REPL, or run via `cov_server --run scripts/example.tcl` to execute and quit.

