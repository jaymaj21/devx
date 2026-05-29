# `list_java_classes.tcl`

`list_java_classes.tcl` creates a simple index of Java source files. For each
`.java` file under a folder, it writes the fully qualified class name and the
file's path relative to the scanned folder.

The output is a tab-separated two-column table:

```text
fully.qualified.ClassName    relative/path/ClassName.java
```

This is useful when another tool needs a compact map from Java class names to
source locations without invoking Maven, Gradle, `javac`, or an IDE indexer.

## Usage

```powershell
tclsh .\list_java_classes.tcl append|overwrite <output-file> <folder>
```

Arguments:

- `append|overwrite`: controls whether the output file is appended to or
  replaced.
- `<output-file>`: the file that receives the generated class index.
- `<folder>`: the root folder to scan recursively for Java source files.

Examples:

```powershell
tclsh .\list_java_classes.tcl overwrite .\classes.tsv .\code-analytics\src\main\java
tclsh .\list_java_classes.tcl append .\classes.tsv .\branch-probe-instrumenter\src\main\java
```

## Behavior

The script:

1. validates that exactly three arguments were provided,
2. validates that the mode is either `append` or `overwrite`,
3. validates that the scan folder exists and is a directory,
4. recursively finds files whose extension is `.java`, case-insensitively,
5. sorts the discovered file paths,
6. reads each file until it finds a Java `package ...;` declaration,
7. combines the package name with the file basename to form the class name,
8. writes one tab-separated row per Java source file.

For a file named:

```text
src/main/java/org/example/tools/Widget.java
```

with:

```java
package org.example.tools;
```

the output row is:

```text
org.example.tools.Widget    org/example/tools/Widget.java
```

If a Java file has no package declaration, the script uses only the file
basename:

```text
Widget    Widget.java
```

Relative paths in the output always use `/`, even on Windows.

## Output Modes

Use `overwrite` when creating a fresh index:

```powershell
tclsh .\list_java_classes.tcl overwrite .\all-java-classes.tsv .\code-analytics\src\main\java
```

Use `append` when combining multiple source trees into one file:

```powershell
tclsh .\list_java_classes.tcl overwrite .\all-java-classes.tsv .\code-analytics\src\main\java
tclsh .\list_java_classes.tcl append .\all-java-classes.tsv .\branch-probe-instrumenter\src\main\java
tclsh .\list_java_classes.tcl append .\all-java-classes.tsv .\branch-probe-suite\mprewriter-runtime\src\main\java
```

## Output Format

Each row has exactly two fields separated by one tab character:

```text
<class-name>\t<relative-source-path>
```

There is no header row. This keeps the file easy to consume from scripts that
expect plain tab-separated data.

Example:

```text
com.codeanalytics.ClojureShell    com/codeanalytics/ClojureShell.java
com.codeanalytics.ContextManager  com/codeanalytics/ContextManager.java
demo.JarInstrumenter              demo/JarInstrumenter.java
```

## Error Handling

The script exits with:

- `2` when the command line is invalid,
- `1` when the scan folder does not exist, is not a directory, or an unexpected
  file-processing error occurs.

Usage errors are printed to stderr:

```text
Usage: tclsh list_java_classes.tcl append|overwrite <output-file> <folder>
```

## Limitations

This script intentionally uses lightweight source scanning rather than Java
parsing. That keeps it fast and dependency-free, but it means:

- the class name is derived from the Java filename, not from parsed type
  declarations;
- nested, anonymous, or additional top-level classes in the same source file
  are not listed separately;
- package declarations must use the normal single-line `package name;` form;
- generated sources are included only if they already exist under the scanned
  folder.

For build-accurate class discovery, use the Java build tool or compiler output.
For a quick source index, this script is usually enough.
