# Greggle Path Queries and Gruggle `find-path`

Greggle is the regular-path-query language behind Gruggle's `find-path` command. Use this reference when writing path regexes, explaining query behavior, or deciding whether `find-path` is enough.

## Edge Labels

DOT edge labels represent edge-label sets. A comma-separated label such as `label="a,b"` means the edge carries both `a` and `b`.

Atomic predicate `a` is true on an edge whose label set contains `a`.

## Edge Predicates

- `a`: edge has label `a`.
- `dot`: wildcard predicate, true on every edge.
- `~a` or `(negate a)`: edge does not have label `a`.
- `(all-of a b)`: all predicates hold on the same edge.
- `(some-of b c)`: at least one predicate holds on the same edge.
- `P@`: source node label matches regex `P`.
- `@P`: sink node label matches regex `P`.

Node-lifted predicates compose with `all-of`, `some-of`, and `negate`.

## Path Expressions

- `P`: a single edge satisfying predicate `P`.
- `(concat r1 r2 ...)`: paths formed by following each expression in sequence.
- `(alt r1 r2 ...)`: paths accepted by any branch.
- `(star r)`: zero or more repetitions.
- `(plus r)`: one or more repetitions.

Examples:

```text
(concat a (plus (concat b a)))
(alt x y)
(all-of a @TARGET)
(concat a (all-of b MID@))
```

## Gruggle `find-path`

`find-path <regex> <label>` searches for one witness path whose edge labels match the path expression and appends `<label>` to edges on that witness path.

```powershell
node ..\greggle\gruggle.js -i graph.dot chain "find-path (concat x y) pathlab" > highlighted.dot
```

Use `find-path` when:

- a witness path is sufficient;
- the desired output is an annotated DOT/SVG graph;
- the query can be expressed as a path regex over edge labels and optional source/sink node-label predicates.

Do not use `find-path` when the user needs all satisfying bindings, relational negation, existential projection, or exact query result tables. In that case use the Greggle query tool (`greggle.exe`) if built.

## Full Greggle Query Language

The query language relates node variables:

- `(exists-path x y r)`: path from `x` to `y` matching `r`.
- `(match x p)`: node label for `x` matches regex `p`.
- `(no-edge x y)`: no directed edge from `x` to `y`.
- `(no-connection x y)`: no edge in either direction.
- `(same x y)` / `(different x y)`.
- `(and e1 e2 ...)`, `(or e1 e2 ...)`, `(not e)`.
- `(exists (x y ...) e)`: existential projection.

The result is a relation over free variables, printed as satisfying bindings by the Greggle query tool.

## Semantics to Remember

- Path expressions compile to NFAs and are evaluated over graph nodes plus automaton states.
- Logical composition is relational: conjunction is natural join/intersection, disjunction is union, existential quantification is projection, and negation is complement over the relevant finite domain.
- Edge-level negation exists. General regex-level negation such as `(negate-regexp r)` is future work, not a current local operation.
