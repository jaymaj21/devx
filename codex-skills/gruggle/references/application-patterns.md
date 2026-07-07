# Gruggle Application Patterns

Use these patterns to turn vague graph requests into useful Gruggle workflows.

## Architecture and Dependency Maps

Merge generated DOT from multiple subsystems, then label, filter, and render focused views:

```powershell
node ..\greggle\gruggle.js -i services.dot -i calls.dot chain `
  "select-nodes auth.*" `
  "select-neighbours both 2" `
  "add-labels-to-selected auth-neighbourhood" `
  "filter-to-paths ingress.* database.*" `
  "to-svg auth-paths.svg" > auth-paths.dot
```

Use component selectors to isolate connected regions and degree selectors to identify hubs.

## Debugging and Trace Slicing

Represent states/events as nodes and transitions as labelled edges. Then:

- `filter-to-paths start failure` to reduce the graph to failure paths.
- `find-path (concat request timeout)` to annotate one concrete witness.
- `add-labels-to-edges-on-paths` to mark all structural paths between two endpoint classes.
- `select-neighbours both 1` around selected error nodes to show local context.

## Review Workflows

Use labels and visual attributes for review without deleting graph structure:

```powershell
node ..\greggle\gruggle.js -i design.dot chain `
  "select-nodes deprecated.*" `
  "set-node-attr-on-selected fillcolor pink" `
  "add-labels-to-selected remove-candidate" `
  "select-edges legacy" `
  "set-edge-attr-on-selected color red" > review.dot
```

Later, use `delete-selected` only after the review criteria are agreed.

## Test Fixture Generation

Use synthetic builders for deterministic fixtures:

- Chains for linear workflows.
- Rings for cycle handling.
- Grids for path multiplicity and layout stress.
- Cliques for dense graph behavior.
- Random edges for informal stress tests only.

Example:

```powershell
node ..\greggle\gruggle.js chain `
  "add-grid g 10 10" `
  "add-edges 25 g.* g.* noisy" `
  "delete-isolated-nodes" > stress.dot
```

## Graph-Based Explanations

For papers, diagrams, and docs, build a minimal graph with `add-chain`, `add-ring`, `add-grid`, or `add-clique`, then style selected parts. Prefer `--ortho` for process and architecture diagrams, and `--curved` for abstract networks.

## Query-Aided Visualization

Use Greggle-compatible `find-path` when a label sequence matters more than raw connectivity:

```powershell
node ..\greggle\gruggle.js -i protocol.dot chain `
  "find-path (concat SYN (plus ACK)) handshake" `
  "select-edges handshake" `
  "set-edge-attr-on-selected color green" > handshake.dot
```

Use lifted node predicates when endpoint identity belongs inside the path condition, e.g. `(all-of a @TARGET)`.

## Progressive Exploration

For unknown graphs:

1. Render a quick SVG only if the graph is small.
2. Select by node regex, label regex, degree, or component.
3. Expand with `select-neighbours`.
4. Add labels or visual attributes.
5. Filter or delete only after inspecting the selected region.

This keeps exploratory commands reversible in the sense that the original DOT remains untouched.
