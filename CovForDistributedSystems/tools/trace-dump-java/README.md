Java HITTRC01 Trace Dumper

- Build:
  - `javac TraceDumper.java`
- Run:
  - `java TraceDumper /path/to/hits.trace > out.txt`
  - With time filter (nanoseconds or RFC3339 UTC):
    - `java TraceDumper /path/to/hits.trace -start 1710000000000000000 -end 1710000001000000000`
    - `java TraceDumper /path/to/hits.trace -start 2025-01-01T12:00:00Z -end 2025-01-01T12:00:01.250Z`

Output (legacy style with stack-depth digits)

- HIT: `:12345<42> appId, instanceId, threadId`
- LOG: `LOG message text`

