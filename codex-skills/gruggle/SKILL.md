---
name: gruggle
description: Use when Codex needs to manipulate, inspect, merge, generate, filter, annotate, query, or render Graphviz DOT graphs with the local Gruggle Node.js script at ../greggle/gruggle.js, including path-based pruning, selection workflows, visual styling, SVG output, command-chain files, programmatic JavaScript API use, and Greggle-compatible regular-path queries such as find-path.
---

# Gruggle

Use this skill to turn graph-editing, DOT-file, visualization, and regular-path-query requests into concrete `gruggle.js` commands or Node.js API calls.

## Repository Orientation

Assume the tool checkout is the sibling directory `../greggle` from `C:\Git\jmtools`, unless the user points to another checkout.

Primary files:

- `../greggle/gruggle.js`: dependency-free Node.js DOT loader, transformer, CLI, and importable API.
- `../greggle/gruggle_testsuite/`: executable examples and golden outputs for Gruggle behavior.
- `../greggle/docs/`: Greggle architecture and BDD integration notes.
- `../greggle/greggle_paper.tex`: Greggle query-language semantics.
- `../greggle/gruggle_paper.tex`: Gruggle CLI and workflow documentation.
- `../greggle/gruggle_api.tex`: Gruggle JavaScript API documentation.

Spell the tool command as `gruggle`; understand `greggle` as the regular-path-query engine and project context behind `find-path`.

## Default Workflow

1. Identify whether the task is graph transformation, graph generation, graph inspection/querying, visual rendering, API integration, or skill/tool maintenance.
2. Prefer the CLI for one-off graph edits, reproducible pipelines, and user-visible artifacts:

   ```powershell
   node ..\greggle\gruggle.js -i input.dot chain "select-nodes error.*" "add-labels-to-selected reviewed" > output.dot
   ```

3. Prefer the JS API when the user needs Gruggle inside a larger Node workflow, repeated graph construction, conditional logic, or direct access to the in-memory graph.
4. Use `chain` for multi-step work. Put complex, reused, or generated pipelines in a command file and invoke it with `chain -f commands.txt`.
5. When producing SVG, require Graphviz `dot` on `PATH` and use `to-svg file.svg`; otherwise emit DOT and tell the user SVG rendering was not attempted.
6. Validate risky transformations by running the command on a copy or writing to a new output path, then inspect the DOT/SVG or compare expected labels/counts.

## Command Patterns

Read `references/cli-reference.md` for the command catalog and exact syntax.

Use these common shapes:

```powershell
# Merge DOT files, set graph name, emit DOT.
node ..\greggle\gruggle.js -i a.dot -i b.dot chain "set-name merged" > merged.dot

# Generate a synthetic graph and render it.
node ..\greggle\gruggle.js --ortho chain "add-grid g 4 6" "to-svg grid.svg" > grid.dot

# Keep only paths between matching endpoints.
node ..\greggle\gruggle.js -i graph.dot chain "filter-to-paths start.* end.*" > focused.dot

# Highlight one Greggle-compatible regular-label path.
node ..\greggle\gruggle.js -i graph.dot chain "find-path (concat x y) pathlab" > highlighted.dot
```

## Decision Guide

- To build toy, benchmark, or explanatory graphs: use `add-nodes`, `add-edges`, `add-chain`, `add-ring`, `add-grid`, `add-clique`, and random edge forms.
- To simplify a busy graph: use `delete-isolated-nodes`, `remove-nodes`, `filter-to-paths`, `keep-paths`, `keep-path-edges`, degree selectors, or component selectors.
- To mark or style regions without deleting them: select nodes/edges first, then use `add-labels-to-selected`, `set-*-attr-on-selected`, or path-label commands.
- To answer "is there a path matching this pattern?": use `find-path` when a witness path annotation is enough; use Greggle query tooling only when the user needs satisfying bindings or full relational query semantics.
- To integrate in code: read `references/programmatic-api.md` and use `require('../greggle/gruggle.js')`.
- To design non-obvious applications or graph-analysis workflows: read `references/application-patterns.md`.
- To write or explain regular path expressions: read `references/greggle-path-queries.md`.

## Guardrails

- Preserve user input DOT files. Write transformed output to a new file unless the user explicitly asks to overwrite.
- Remember keep/remove flags are in-memory emission controls, not DOT attributes. If anything is marked `keep`, only kept elements are serialized; otherwise elements marked `remove` are omitted.
- Treat regex arguments as JavaScript regular expressions over node IDs or label components, depending on the command.
- Use quoted chain commands so PowerShell does not split regexes or S-expressions.
- `find-path` throws if no witness path is found. Handle this as "no path annotated", not as file corruption.
- Random commands are nondeterministic; avoid them in tests unless the expected output allows variation.
- For large graphs, prefer path/component/degree filters before SVG rendering. Graphviz layout can dominate runtime.

## References

- `references/cli-reference.md`: Gruggle command syntax, flags, semantics, and examples.
- `references/programmatic-api.md`: Node.js import API, classes, helper functions, and integration patterns.
- `references/greggle-path-queries.md`: edge predicates, path expressions, relational queries, and `find-path` regex guidance.
- `references/application-patterns.md`: creative uses such as trace slicing, architecture maps, dependency review, graph fixtures, and review workflows.
- `references/troubleshooting.md`: common failures and verification checks.
