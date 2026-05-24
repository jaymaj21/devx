# dstr

**dstr** is an explicit-state tool for describing and checking finite dynamic systems.

This project is a Java prototype for a JSON-first formal specification language inspired by TLA+, but with an explicit, indentation-free syntax.

## What is implemented

- A concise JSON spec format
- A typed AST for expressions
- A parser from JSON into AST and spec objects
- An evaluator for state predicates and transition predicates
- A finite explicit-state checker
- Invariant checking
- Deadlock detection
- Simple existential temporal property checking via `eventually`
- Maven and Gradle build files
- JUnit test suite

## Current scope

This is a finite-state prototype. It is intentionally smaller than full TLA+.

Implemented expression forms include:

- literals: `{ "lit": 0 }`, `{ "lit": "idle" }`
- current variable: `{ "var": "pc" }`
- next-state variable: `{ "next": "pc" }`
- action reference inside `next`: `{ "actionRef": "enter" }`
- conjunction/disjunction: `{ "and": [ ... ] }`, `{ "or": [ ... ] }`
- equality and comparisons: `{ "=": [a, b] }`, `{ "<=": [a, b] }`, etc.
- arithmetic: `{ "+": [a, b] }`, `{ "-": [a, b] }`
- set literals: `{ "set": [ ... ] }`
- membership: `{ "in": [x, setExpr] }`
- quantifiers: `{ "exists": { "var": "x", "in": setExpr, "body": expr } }`
- simple temporal property: `{ "eventually": expr }`

## Running tests

### Maven

```bash
mvn test
```

### Gradle

```bash
gradle test
```

## Running the CLI

### Maven

```bash
mvn exec:java -Dexec.args="test-suite/specs/light-switch.json"
```

### Gradle

```bash
gradle run --args="test-suite/specs/light-switch.json"
```

## Visualizing specs with Graphviz

There is also a Node.js helper that converts a JSON spec into a Graphviz DOT state graph:

```bash
node scripts/spec-to-dot.js test-suite/specs/light-switch.json > light-switch.dot
dot -Tpng light-switch.dot -o light-switch.png
```

Useful options:

- `--all-states` includes unreachable states in dashed gray
- `--rankdir TB` lays the graph out top-to-bottom instead of left-to-right
- `--max-states N` truncates very large universes instead of exhausting memory

There are also front-end-aware wrapper scripts:

- `dstr-to-svg.sh` / `dstr-to-svg.bat`
- `tdstr-to-svg.sh` / `tdstr-to-svg.bat`

These compile a `.dstr` or `.tdstr` source when needed, then emit adjacent
`.json`, `.dot`, and `.svg` files. They also accept an existing `.json` spec
directly, which is useful when the normalized form has already been checked in
or produced elsewhere.

The generated graph is a state-transition visualization:

- nodes are concrete states with one line per variable
- the start marker points to initial states
- edges are labeled by the enabled action names that justify the transition
- red nodes violate invariants
- amber nodes are reachable deadlocks
- green nodes are initial states

## JSON structure

A spec has the shape:

```json
{
  "name": "light-switch",
  "variables": ["light"],
  "domains": {
    "light": { "set": [ { "lit": "off" }, { "lit": "on" } ] }
  },
  "init": { "=": [ { "var": "light" }, { "lit": "off" } ] },
  "actions": [
    {
      "name": "turn-on",
      "body": {
        "and": [
          { "=": [ { "var": "light" }, { "lit": "off" } ] },
          { "=": [ { "next": "light" }, { "lit": "on" } ] }
        ]
      }
    }
  ],
  "next": { "actionRef": "turn-on" },
  "invariants": [],
  "properties": []
}
```

## Example specs

See `test-suite/specs/` for:

- `light-switch.json`
- `mutex-2proc.json`
- `broken-mutex.json`
- `counter.json`

## Notes

`eventually` in this prototype is interpreted as a reachability-style property over reachable states, not as full liveness with fairness.

## Commands for the visualization tool

node scripts/spec-to-dot.js test-suite/specs/mutex-2proc.json > mutex.dot
dot -Tsvg mutex.dot -o mutex.svg
start mutex.svg


