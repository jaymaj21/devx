# CDSTR Clojure DSL Samples

These `.cdstr` files mirror the `.dstr` and `.tdstr` front-end samples using
the Clojure-based front end in `clj-dstr`.

Most files correspond directly to a `.dstr` file, with action references written
using the Clojure/Lisp-friendly `$action-name` form. The
`trade-cancellation-parent-children-small.cdstr` file mirrors the reduced
TDSTR-only sample.

## Compile

From the repository root:

```powershell
.\cdstr.bat cdstr-testsuite\light-switch.cdstr
```

```bash
./cdstr.sh cdstr-testsuite/light-switch.cdstr
```

## Visualize

```powershell
.\cdstr-to-svg.bat cdstr-testsuite\light-switch.cdstr
```

```bash
./cdstr-to-svg.sh cdstr-testsuite/light-switch.cdstr
```

Large explicit-domain samples such as `trade-cancellation-parent-children.cdstr`
should be visualized with `--max-states N`.

## Check the Suite

```powershell
mvn -q -f clj-dstr\pom.xml compile exec:java "-Dexec.args=cdstr-testsuite target\cdstr-generated"
```

The generated JSON can be checked with `scripts\spec-to-dot.js`. The full
`bakery-3proc.cdstr` graph is intentionally larger than the other samples.
