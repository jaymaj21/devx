# Source-Level Instrumentation

Use `development_tools/CovForDistributedSystems/instr2.py` when the user wants to instrument Java source files before compilation rather than rewrite compiled JAR bytecode.

This tool is intentionally regex-based, not Java-parser-based. It usually works on typical Java files, but always inspect diffs and compile the project after instrumentation.

## What It Does

`instr2.py` reads a file list and injects calls like:

```java
mprewriter.scope_START(10001);
```

It looks for likely block openings such as method bodies, `try`, `else`, lambda arrows, `case`, and `default`, then skips obvious non-probe sites such as class/interface/enum declarations, switch blocks, object creation blocks, repeated `mprewriter` calls, and constructor `super(...)`/`this(...)` positions.

It can now emit two metadata formats:

- branch-probe-compatible CSV: `id,class,method,where,source,line`
- grep-style trace lookup lines: `path/to/File.java:line:mprewriter.scope_START(id);`

The grep-style format matches the Spectral/JMWrap pattern used by `load_trace_lookup` and `read_trace_lookup`, which extract `file`, `line`, and numeric probe id from lines containing `mprewriter.*START(...)`.

## Basic Usage

Preferred folder mode:

```powershell
python .\instr2.py C:\path\to\src\main\java 10001 --dry-run --metadata .\source-probes.csv --grep-metadata .\trace_lookup.txt
```

Instrument all Java files under a folder with backups:

```powershell
python .\instr2.py C:\path\to\src\main\java 10001 --backup --metadata .\source-probes.csv --grep-metadata .\trace_lookup.txt
```

The first positional argument can be:

- a directory, recursively scanned for `*.java`;
- a single `.java` file;
- a text file containing one Java source path per line.

File-list mode:

```powershell
Get-ChildItem C:\path\to\src\main\java -Recurse -Filter *.java |
  ForEach-Object { $_.FullName } |
  Set-Content .\java-files.txt
```

Then run:

```powershell
python .\instr2.py .\java-files.txt 10001 --dry-run --metadata .\source-probes.csv --grep-metadata .\trace_lookup.txt
```

The script prints:

```text
Total files instrumented: <n>
Total probes inserted: <m>
LAST_ID=<last-id>
```

Use `LAST_ID + 1` as the next start id when instrumenting another source tree or JAR.

## Runtime Import And Call Template

The default injected call is:

```java
mprewriter.scope_START(<id>);
```

The default inserted import is:

```java
import com.mprewriter.utils.*;
```

Override the import when the project exposes a different source-visible runtime class:

```powershell
python .\instr2.py C:\path\to\src\main\java 10001 --import-line "import com.trading.domain.mprewriter;" --backup --metadata .\source-probes.csv --grep-metadata .\trace_lookup.txt
```

Suppress import insertion if the files already import or define `mprewriter`:

```powershell
python .\instr2.py C:\path\to\src\main\java 10001 --no-import --backup --metadata .\source-probes.csv --grep-metadata .\trace_lookup.txt
```

Override the injected call shape if needed:

```powershell
python .\instr2.py C:\path\to\src\main\java 10001 --call-template "com.trading.domain.mprewriter.scope_START({id});" --no-import --backup
```

## Compile And Run

After source instrumentation:

1. Compile the application normally.
2. Ensure the source-visible `mprewriter` implementation sends UDP hits to `code-analytics`.
3. Start `code-analytics`.
4. Run the compiled app with appropriate runtime settings or source runtime defaults.
5. Use `:coverage-report <appId> <instanceId> <file>` to produce hit counts keyed by probe id.

If using the shared `branch-probe-suite/mprewriter-runtime`, the runtime class is `com.trading.domain.mprewriter`. If using older source-level demos, the app may provide its own `mprewriter.java`; inspect the target project before choosing `--import-line` or `--call-template`.

## Metadata Workflows

Load CSV metadata into `code-analytics`:

```text
:probe-metadata-load .\source-probes.csv
:probe-metadata-summary
:probe-metadata-find-class com.example.*
:probe-metadata-find-method render*
:probe-metadata-find-where SOURCE_SCOPE_START
```

Use grep-style metadata with Spectral/JMWrap:

```tcl
read_trace_lookup c:/temp/trace_lookup.txt mprewriter.*START
```

The relevant Tcl pattern extracts:

```text
loc_file from the path before :line:
loc_line from the line number
tag from mprewriter.*START(<id>)
file_lookup(tag) = "loc_file:loc_line:"
```

If the user asks for the older manual grep approach instead of `--grep-metadata`, produce equivalent lines with a recursive grep over the instrumented source tree:

```powershell
Select-String -Path C:\path\to\src\main\java\*.java -Recurse -Pattern "mprewriter\.scope_START\([0-9]+\)" |
  ForEach-Object { "$($_.Path):$($_.LineNumber):$($_.Line.Trim())" } |
  Set-Content .\trace_lookup.txt
```

On Unix-like shells:

```bash
grep -RIn 'mprewriter\.scope_START([0-9]\+)' src/main/java > trace_lookup.txt
```

## Source Annotation

The generated `source-probes.csv` uses the same columns as branch-probe CSV sidecars, with `where=SOURCE_SCOPE_START`. It can be used anywhere that expects `id,class,method,where,source,line`, including metadata search in `code-analytics` and source annotation workflows, provided the source files line up with the compiled instrumented source.

## Limitations

- It does not parse Java syntax fully.
- It may inject into unusual constructs incorrectly.
- It edits source files in place unless `--dry-run` is used.
- It should be run on a clean working tree or with `--backup`.
- Existing injected sources can be re-instrumented if the file list points at already instrumented files; inspect or revert first.
