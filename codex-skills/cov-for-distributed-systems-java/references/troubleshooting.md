# Troubleshooting

## No Hits Arrive

Check:

- `code-analytics` was started before the app.
- The app uses `mprewriter-runtime` on the classpath.
- The runtime properties match the server: `-Dmprewriter.host=127.0.0.1 -Dmprewriter.port=8083`.
- The `appId` and `instanceId` used in `:coverage-report` match the runtime properties.
- Firewalls or container networking are not blocking UDP `8083`.

Use:

```text
:status
:hits
```

## `NoClassDefFoundError: com/trading/domain/mprewriter`

Run with `-cp` and include the runtime JAR:

```powershell
java -cp ".\branch-probe-suite\mprewriter-runtime\target\mprewriter-runtime-1.0.0.jar;app-instrumented.jar" com.example.Main
```

Do not rely on `java -jar` unless the runtime has been shaded into the app.

## Metadata Filters Match Nothing

Check:

```text
:probe-metadata-summary
:probe-metadata-show <known-probe-id>
:probe-metadata-find-class *
:probe-metadata-find-where *
```

Then verify:

- the loaded CSV is from the same instrumentation run as the trace or coverage report;
- class globs use fully qualified Java class names, for example `com.example.*`;
- path globs require loaded class maps from `:probe-metadata-load-classes`;
- method and where filters use glob syntax, not regular expressions.

## Source Annotation Produces Few Or No Comments

Check:

- the coverage report contains hits for the selected context;
- probe CSV ids overlap coverage report `locId` values;
- source JAR matches the instrumented classes;
- classes were compiled with line number information;
- `--context` is broad enough, for example `{.*}`.

## Multi-JAR Id Collisions

Use `LAST_ID` from each instrumentation run:

```text
first run prints LAST_ID=11870
next run uses --startid=11871
```

If using `instrument_jars.tcl`, it handles this chaining automatically for all target JARs.

## Already Instrumented JARs

The newer instrumenter may skip already instrumented JARs. Keep pristine originals and avoid recursively instrumenting output folders that contain prior `*-instrumented.jar` files unless that is intentional.

## Trace File Looks Like Text But Is Binary

`plant-trace-*.txt` is a binary `HITTRC01` trace despite the `.txt` extension. Use:

```powershell
tclsh .\plant_trace_tool.tcl summary .\code-analytics\plant-trace-....txt
java -cp .\code-analytics\build\classes\java\main com.codeanalytics.TraceAnalyzer summary .\code-analytics\plant-trace-....txt
```
