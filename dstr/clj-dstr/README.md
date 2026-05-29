# clj-dstr

`clj-dstr` is a Clojure-shaped front end for `dstr`. It reads `.cdstr` files and
emits the same normalized JSON consumed by the existing graph/checking tools.

The project is intentionally standalone. It can be run with either Maven or
Gradle and pulls Clojure from Maven Central.

## Build And Run

```powershell
cd clj-dstr
gradle run --args="samples\light-switch.cdstr target\light-switch.json"
```

```powershell
cd clj-dstr
mvn compile exec:java -Dexec.args="samples\light-switch.cdstr target\light-switch.json"
```

Directories are accepted too:

```powershell
gradle run --args="samples target"
```

From the repository root, use the wrapper scripts for the usual workflow:

```powershell
.\cdstr.bat clj-dstr\samples\light-switch.cdstr
.\cdstr-to-svg.bat clj-dstr\samples\light-switch.cdstr
```

```bash
./cdstr.sh clj-dstr/samples/light-switch.cdstr
./cdstr-to-svg.sh clj-dstr/samples/light-switch.cdstr
```

## Syntax Notes

The Clojure reader is used, so ordinary Clojure `defn` and `defmacro` forms may
appear before the `system` form. The compiler quotes the system body and then
macroexpands DSL forms before normalization.

Action references use the same portable prefix as the Lisp front end:

```clojure
(next (or $turn-on $turn-off))
```

This is interpreted as an action reference. The more explicit form is also
accepted:

```clojure
(next (or (action-ref turn-on) (action-ref turn-off)))
```

Supported assignment shorthands include:

```clojure
(assign value to x)
(set x as value)
```

Both mean:

```clojure
(= x+ value)
```
