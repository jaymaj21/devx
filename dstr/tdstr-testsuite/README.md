# TDSTR Samples

These `.tdstr` files use a Tcl-shaped front-end that compiles into the JSON
specs consumed by the Java checker.

## Syntax sketch

```tcl
system light-switch {
    vars light
    domain light off on
    init {= light off}
    action turn-on {= light off} {= light+ on}
    action turn-off {= light on} {= light+ off}
    next {or @turn-on @turn-off}
    invariant type-ok {in light {set off on}}
    property eventually-on {eventually {= light on}}
}
```

## Surface rules

- declared variable names refer to current-state variables
- names ending in `+` refer to next-state variables, for example `light+`
- names beginning with `@` refer to actions in `next`, for example `@turn-on`
- other bare words become string literals
- integers and floating-point numbers become numeric literals
- `true` / `false` are boolean literals
- `t` / `nil` are also accepted for parity with the Lisp DSL
- `{quote foo}` forces a literal string when needed
- `{if cond then body}` is shorthand for `{and cond body}`
- inside `if ... then ...`, a brace block containing multiple sibling
  expressions is treated as an implicit `and`
- `{assign expr to var}` is shorthand for `{= var+ expr}`
- `{set var as expr}` is the same next-state assignment sugar as
  `{assign expr to var}`
- `{equals left right}` is shorthand for `{= left right}`
- `{unchanged* glob1 glob2 ...}` expands matching declared variables into an
  `and` of frame conditions like `{= var+ var}`
- `alternate-scenarios` is accepted as a synonym for `or`
- multiple body expressions in a clause are combined with `and`

The TDSTR compiler also performs a safe post-expansion reduction step:
declared variables that occur only in conjunctive unchanged/frame clauses are
omitted from the emitted JSON entirely. This reduces explicit state-space size
without changing the remaining behavior.

## Top-level forms

- ordinary Tcl `proc` definitions for helper abstractions
- ordinary Tcl `source` for helper libraries
- `system name { ... }`

## Built-in helpers

- `same var`
  Returns the expression `{= var+ var}`.
- `unchanged x y z`
  Returns a list of sibling frame-condition expressions suitable for `{*}`
  expansion inside a clause body.
- `vars* separator {group1 ...} * {group2 ...}`
  Generates the Cartesian product of the two groups, joining each pair with the
  given separator.
- `domain* pattern value...`
  Applies one domain body to every declared variable whose name matches the Tcl
  glob pattern.

Example:

```tcl
action p1-a0 {= p1pc a0} {= p1pc+ a1} {*}[unchanged p2pc c1 c2 turn]
```

Example:

```tcl
vars* _ {p c1 c2} * {market_status mission_state}
domain* *_mission_state OPEN RELEASED CANCELLED
```

For large explicit-domain models, the Graphviz helper also accepts
`--max-states N` to truncate the enumerated universe instead of attempting a
full graph. The financial lifecycle samples `instrument-lifecycle.tdstr` and
`instrument-lifecycle-small.tdstr` show the same surface forms in a market-data
/ trading-status setting and provide a manageable graph-rendering target.

## Compile

```powershell
& "c:\Tcl\bin\tclsh.exe" `
  scripts\tdstr-dsl-compiler.tcl `
  tdstr-testsuite `
  target\tdstr-generated
```
