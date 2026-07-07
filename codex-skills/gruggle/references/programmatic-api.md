# Gruggle Programmatic API

Use the API when commands need conditional logic, repeated graph construction, integration with another Node.js tool, or inspection of the in-memory graph.

```javascript
const {
  Gruggle,
  parse,
  serialize,
  applySubcommands,
  applyOne,
  parseChainString,
  emptyGraph,
  mergeGraphs,
} = require('../greggle/gruggle.js');
```

Importing `gruggle.js` does not run the CLI because the script checks `require.main === module`.

## Gruggle Wrapper

- `new Gruggle(graph = emptyGraph())`: start from an existing graph or empty graph.
- `Gruggle.fromDot(text, edgeMode = 'curved')`: parse DOT; `edgeMode` may be `curved`, `ortho`, or `rectilinear`.
- `Gruggle.fromFiles(files, edgeMode = 'curved')`: parse and merge DOT files.
- `.chain(commands)`: run one or more chain commands. Accepts a chain string, an array of strings, or token arrays.
- `.apply(tokens)`: apply one direct token list, e.g. `['add-nodes', 'n:1:3']`.
- `.toDot()`: serialize the current graph, honoring keep/remove flags.
- `.toSvg(outFile)`: render via Graphviz `dot`; returns `this`.
- `.value()`: return the underlying graph object.

## Helpers

- `parse(text)`: DOT text to graph object.
- `serialize(graph)`: graph object to DOT text.
- `applyOne(graph, tokens)`: apply a single subcommand token array.
- `applySubcommands(graph, tokens)`: apply a full token sequence, often beginning with `chain`.
- `parseChainString(str)`: split a CLI-style quoted chain string into tokens.
- `emptyGraph()`: create a fresh digraph.
- `mergeGraphs(graphs)`: merge parsed graphs the same way the CLI does.

## Examples

Build and serialize:

```javascript
const { Gruggle } = require('../greggle/gruggle.js');

const gm = new Gruggle();
gm.apply(['add-nodes', 'n:1:3'])
  .apply(['add-edges', 'lbl', 'n.*', 'n.*']);

console.log(gm.toDot());
```

Parse, edit, and inspect:

```javascript
const { Gruggle, parseChainString } = require('../greggle/gruggle.js');

const gm = Gruggle.fromDot('digraph G { a -> b; }');
gm.chain(parseChainString('add-nodes c'))
  .chain(['add-edges', 'lbl', 'a.*', 'c']);

const graph = gm.value();
console.log([...graph.nodes.keys()]);
console.log(gm.toDot());
```

Use direct helpers:

```javascript
const { parse, applySubcommands, serialize } = require('../greggle/gruggle.js');

let g = parse('digraph G { a -> b; }');
g = applySubcommands(g, ['add-nodes', 'c']);
g = applySubcommands(g, ['add-edges', 'lbl', 'a.*', 'c']);
console.log(serialize(g));
```

## Integration Guidance

- Use token arrays for generated commands; use `parseChainString` only when reading CLI-like strings.
- Keep graph mutation explicit. Most helpers return the graph, while `Gruggle` methods return `this`.
- For tests, assert stable DOT fragments or graph-object properties. Avoid random commands unless testing only invariants.
- For user-facing rendering, call `.toSvg()` only after checking Graphviz is installed or accepting that it may throw.
