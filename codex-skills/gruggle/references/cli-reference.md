# Gruggle CLI Reference

Gruggle is a single-file Node.js tool:

```powershell
node ..\greggle\gruggle.js [-i file.dot ...] [--curved|--ortho|--rectilinear] [subcommands...]
```

If no `-i` file is supplied, Gruggle starts from an empty digraph. Repeated `-i` files are parsed and merged. Later graph/default attributes override earlier conflicting attributes; duplicate edges are merged by endpoints/ports/direction with attribute merge.

Use `node ..\greggle\gruggle.js help` for the script's own detailed command reference.

## Chain

Prefer `chain` for nontrivial edits:

```powershell
node ..\greggle\gruggle.js -i graph.dot chain "cmd arg arg" "cmd2 arg"
```

Inside `chain`, `-f file` splices commands line by line. Blank lines and lines beginning with `#` are ignored.

## Graph Construction

- `set-name <name>`: rename graph.
- `add-nodes <id>|<prefix:start:end>`: add one node or a numeric range, e.g. `nx:1:3` gives `nx1`, `nx2`, `nx3`.
- `add-nodes <count> <root> [start]`: add isolated nodes `root_start` onward.
- `add-edges <label> <fromRe> <toRe>`: add every matching pair, preserving graph direction.
- `add-edges <count> <fromRe> <toRe> [label]`: add up to `count` random distinct matching pairs.
- `add-chain <root> <n>`: create `root_1 -> ... -> root_n`.
- `add-ring <root> <n> [start]`: create a chain and close last to first.
- `add-grid <root> <rows> <cols> [start]`: create `root_i_j` nodes with down/right grid edges.
- `add-clique <root> <n> [start]`: create a complete graph on `root_<start>...`.

Examples:

```powershell
node ..\greggle\gruggle.js chain "add-chain c 4" > chain.dot
node ..\greggle\gruggle.js chain "add-ring r 3 0" > ring.dot
node ..\greggle\gruggle.js chain "add-grid g 2 2" "to-svg grid.svg" > grid.dot
```

## Deletion and Pruning

- `delete-isolated-nodes`: drop nodes with no incident edges.
- `remove-nodes <regex>`: delete matching nodes and incident edges.
- `remove-edges-between-nodes <fromRe> <toRe>`: delete matching directed edges.

Use pruning after synthetic generation or path filters to make outputs readable:

```powershell
node ..\greggle\gruggle.js -i tree.dot chain "remove-nodes tmp.*" "delete-isolated-nodes" > clean.dot
```

## Path-Based Operations

These operate over structural graph paths between source and target node regex matches:

- `keep-paths <fromRe> <toRe>`: mark nodes and edges on any such path as kept.
- `remove-paths <fromRe> <toRe>`: mark nodes and edges on any such path as removed.
- `keep-path-edges <fromRe> <toRe>` / `remove-path-edges <fromRe> <toRe>`: affect only edges.
- `filter-to-paths <fromRe> <toRe>`: remove everything not lying on matching paths.
- `select-nodes-on-paths <fromRe> <toRe>` / `select-edges-on-paths <fromRe> <toRe>`: select path elements for later bulk editing.
- `add-labels-to-edges-on-paths <fromRe> <toRe> <label>`: append a label to path edges.
- `remove-labels-from-edges-on-paths <fromRe> <toRe> <label>`: remove a label from path edges.

Keep/remove semantics: if any element is marked keep, serialization emits only kept elements. If nothing is kept, elements marked remove are suppressed. These flags are not written as DOT attributes.

## Selection and Bulk Editing

Selection is an in-memory flag used by subsequent commands:

- `select-nodes <regex>` / `deselect-nodes <regex>`.
- `select-nodes-label <labelRe>`: match comma-separated node labels.
- `select-edges <labelRe>`: match any comma-separated edge-label component.
- `select-edges <fromRe> <toRe>`: match endpoints.
- `deselect-edges ...`: same forms as `select-edges`.
- `select-random-nodes <n> <regex>` and `select-random-edges <n> <fromRe> <toRe>`.
- `select-neighbours [in|out|both] <hops>`: expand current selection by BFS.
- `select-nodes-degree|select-nodes-indegree|select-nodes-outdegree <lt|le|eq|ge|gt> <k>`.
- `select-component-of-nodes <regex>`: select components containing matching nodes.
- `select-components-with-selected`: select components containing already selected nodes.
- `clear-selection`, `invert-selection-nodes`, `invert-selection-edges`.

Bulk operations:

- `delete-selected`.
- `add-labels-to-selected <label>` / `remove-labels-from-selected <label>`.
- `set-node-attr-on-selected <attr> <value>` / `set-edge-attr-on-selected <attr> <value>`.
- `unset-node-attr-on-selected <attr>` / `unset-edge-attr-on-selected <attr>`.
- `clear-visual-attrs-on-selected`: remove `color`, `fillcolor`, `fontcolor`, `style`, `shape`, `penwidth`, `arrowsize`, `fontsize`.

Example:

```powershell
node ..\greggle\gruggle.js -i graph.dot chain `
  "select-nodes-degree ge 3" `
  "add-labels-to-selected hub" `
  "set-node-attr-on-selected fillcolor yellow" > hubs.dot
```

## Greggle-Compatible Witness Paths

`find-path <regex> <label>` annotates one path whose edge labels match a Greggle-compatible path regex. It appends `<label>` to the witness path's edge labels.

```powershell
node ..\greggle\gruggle.js -i sample.dot chain "find-path (concat x y) pathlab" > witness.dot
```

See `greggle-path-queries.md` for regex syntax and lifted node predicates.

## SVG Output

`to-svg <file.svg>` pipes serialized DOT through Graphviz:

```powershell
node ..\greggle\gruggle.js --ortho -i graph.dot chain "to-svg graph.svg" > graph.dot
```

Use `--ortho` or `--rectilinear` for `splines=ortho`; `--curved` is default.
