# Gruggle Troubleshooting

## Command Fails Immediately

- Run `node ..\greggle\gruggle.js help` to confirm Node can execute the script.
- Check quoting. In PowerShell, wrap each chain subcommand in double quotes, especially S-expressions such as `"find-path (concat x y) pathlab"`.
- Confirm relative paths from the current working directory. From `C:\Git\jmtools`, the script is `..\greggle\gruggle.js`.

## SVG Is Not Written

`to-svg` requires Graphviz `dot` on `PATH`.

Check:

```powershell
dot -V
```

If Graphviz is unavailable, emit DOT and defer rendering.

## `find-path: no path annotated`

This means no witness path matched the regex. Check:

- Edge labels exist and are comma-separated as expected.
- The regex uses Greggle path syntax, not JavaScript regex syntax.
- Node-lifted predicates `P@` and `@P` match node labels/IDs as intended.
- The graph direction permits the path.

Start with simpler regexes such as `dot`, `x`, or `(concat x y)`.

## Output Drops Too Much

Keep/remove flags affect serialization:

- If any element is marked keep, only kept elements are emitted.
- If nothing is kept, removed elements are suppressed.

Use selection plus styling when you want to mark items without changing emitted graph membership.

## Regex Matches Too Broadly or Narrowly

Node and edge selectors use JavaScript regular expressions. Anchor when needed:

- `^api$` for exactly `api`.
- `^api` for prefix.
- `.*api.*` for contains.

Edge label selectors match label components, not necessarily the full comma-separated label string.

## Random Results Change

`add-edges <count> ...`, `select-random-nodes`, and `select-random-edges` are nondeterministic. Avoid them for golden outputs unless the test asserts only coarse invariants.

## Large Graph Rendering Is Slow

Filter before rendering:

```powershell
node ..\greggle\gruggle.js -i large.dot chain "filter-to-paths src.* dst.*" "to-svg focused.svg" > focused.dot
```

Prefer DOT inspection or counts from a small Node API script if Graphviz layout is the bottleneck.
