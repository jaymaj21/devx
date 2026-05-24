# DSTR Lisp DSL Samples

These `.dstr` files use a compact s-expression front-end that compiles into the
JSON specs consumed by the existing Java checker.

## Syntax sketch

```lisp
(system light-switch
  (vars light)
  (domain light off on)
  (init (= light off))
  (action turn-on (= light off) (= light+ on))
  (action turn-off (= light on) (= light+ off))
  (next (or @turn-on @turn-off))
  (invariant type-ok (in light (set off on)))
  (property eventually-on (eventually (= light on))))
```

### Surface syntax rules

- plain declared variable names refer to current-state variables
- symbols ending in `+` refer to next-state variables, for example `light+`
- symbols beginning with `@` refer to actions in `next`, for example `@turn-on`
- `(expand macro-name arg...)` expands a predefined or top-level `defmacro`
  before parsing continues
- `(%macro-name arg...)` is shorthand for `(expand macro-name arg...)`
- `(!macro-name arg...)` expands to a list and splices that list into the
  surrounding form
- other bare symbols become string literals, for example `off`, `idle`, `cs`
- numbers stay numeric literals
- `t` and `nil` become boolean literals
- `'(foo)` or `(quote foo)` forces a literal symbol if needed

### Top-level forms

- `(defmacro name (args...) ...)`
- `(defun name (args...) ...)`
- `(load "relative-or-absolute-path.lisp")`
- `(vars ...)`
- `(vars* separator (group1 ...) * (group2 ...))`
- `(domain var value...)`
- `(domain* glob-pattern value...)`
- `(init expr...)`
- `(action name expr...)`
- `(next expr...)`
- `(invariant name expr...)`
- `(property name expr...)`

When a clause body contains more than one expression, the compiler combines them
as `(and ...)`.

### Macro support

The DSL compiler now recognizes explicit macro expansion anywhere inside the
system form:

```lisp
(!unchanged p2pc mem)
```

and also the shorter shorthand:

```lisp
(expand unchanged p2pc mem)
```

For macros that expand to lists intended for splicing into the surrounding
context, the DSL also supports:

```lisp
(!p1-actions)
```

This is treated roughly like a recursive `macroexpand` before the spec is
parsed into the JSON IR. For macros that return sibling clauses, the `!`
splicing form is the intended shorthand.

Predefined helper macros include:

- `(%same x)` which expands to `(= x+ x)`
- `(!unchanged x y z)` which expands to sibling clauses ` (= x+ x)`, ` (= y+ y)`,
  ` (= z+ z)` in the surrounding body

The front end now also supports a few readability-oriented surface shorthands
without requiring user macros:

- `(vars* _ (p c1 c2) * (market_status mission_state))`
  expands to variables such as `p_market_status`, `p_mission_state`,
  `c1_market_status`, and so on
- `(domain* *_mission_version 1 2 3 4)` applies one domain declaration to
  every declared variable whose name matches the glob pattern
- `(equals x y)` is a synonym for `(= x y)`
- `(assign value to x)` means `(= x+ value)`
- `(if condition then consequence)` means `(and condition consequence)`
- `(if ((equals x open) (equals y open)) then ((assign closed to x) ...))`
  treats each branch body as an implicit conjunction when it is a list of
  sibling expressions
- `(unchanged* *_status *_version)` expands to conjunctions of the form
  `(= var+ var)` for every matching declared variable
- `(alternate-scenarios ...)` is a synonym for `(or ...)`

Files may also contain top-level `defmacro` forms before the `system` form. See
`cas-2proc-race.dstr` for an example of `!...` splicing shorthand and a helper
macro library, and `trade-cancellation-parent-children.dstr` for a larger
example that uses the new product, glob, and transition-oriented shorthands.
The financial lifecycle samples `instrument-lifecycle.dstr` and
`instrument-lifecycle-small.dstr` show the same shorthands in a market-data /
trading-status setting.

Top-level `defun` is also supported so that macros can call helper functions at
expansion time, and top-level `load` is supported for importing macro libraries.
Relative `load` paths are resolved against the directory of the current `.dstr`
file.

## Compile

```powershell
& "C:\Program Files\Steel Bank Common Lisp\sbcl.exe" `
  --script scripts\dstr-dsl-compiler.lisp `
  dsl-testsuite\light-switch.dstr `
  target\light-switch-from-dsl.json
```
