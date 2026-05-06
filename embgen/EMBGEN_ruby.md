# embgen.rb — Embedded Generators for Self‑Maintaining Codebases (Ruby)

## Why embgen exists
Large systems evolve around shared schemas: database tables, JSON/XML contracts, DTOs, models, view models. Every schema tweak fans out into repetitive, error‑prone changes—fields in models/DTOs, converters, SQL DDL, UI forms, tests. embgen’s purpose is to make those mechanically repeated fragments **self‑maintaining** by embedding tiny generator scripts directly next to the code they produce. When the schema changes, you rerun embgen and the generated regions refresh in place, keeping the codebase aligned with the source of truth.

## The embedded generator pattern
An embedded generator macro lives entirely in single‑line comments, so it works in C/C++, Java, SQL, Ruby, etc. It has a header, a body (the embedded generator macro), and marked generated bounds:

```txt
//embgen_embedded_generator GENERATOR_TYPE 46db82e1-adf1-4371-aafc-9123b4f08c34
// ...embedded generator macro content...
//embgen_generated_start 46db82e1-adf1-4371-aafc-9123b4f08c34
// ...generated code (owned by embgen)...
//embgen_generated_end 46db82e1-adf1-4371-aafc-9123b4f08c34
```

Key properties:
- The UUID ties header/start/end together and lets embgen rewrite the correct region even if the file moves or other generators are added.
- The embedded generator macro body uses helpers like `emit` to produce text that replaces everything between the start/end markers.
- embgen preserves surrounding code and indentation; only the generated region is replaced.

## CLI usage (Ruby)
Single files:
```bash
ruby embgen.rb path/to/file.ext
```

Recursive (include/exclude globs matched against full normalized paths):
```bash
ruby embgen.rb -r ROOT1 -r ROOT2 --include=*.txt --include=*.sql --exclude=*Test.sql
```

List of files (one path per line, forward slashes allowed, absolute or relative):
```bash
ruby embgen.rb -l filelist.txt
```

Options summary:
- `-r ROOT` (repeatable): recurse under ROOT
- `-i PAT` / `--include=PAT`: include glob (default `*` if none supplied)
- `-x PAT` / `--exclude=PAT`: exclude glob
- `-l LISTFILE`: process listed files
- Or pass explicit files as positional arguments

Paths to auxiliary data (e.g., `types.xml`) resolve relative to the processed file, walking up parent directories; absolute paths are honored.

## Built‑in generator types
- `xml_driven_macro`: XPath + Ruby body, runs once per selected node (`xpathnode` is the current node; attributes become variables via local binding).
- `json_driven_macro`: JSON path spec + Ruby body, runs once per matched element.
- `ruby_macro`: Evaluate Ruby directly; use `emit` to build output.
- `dot`, `plantuml`, `plantuml_ascii`: Graphviz/PlantUML -> PNG/ASCII.
- `latex`, `latex_inline`: Render LaTeX to PNG (requires `latex` + `dvipng`).
- `using_command_line`: Run an external command and embed its stdout.
- `echo`: Return the embedded generator macro verbatim.

Helper APIs (selected):
- `emit STRING` / `emitted`: write/read the current output buffer.
- `emit_file PATH { ... }`: emit into another file (overwrites on flush).
- `emit_to_file PATH CONTENT`: queue content for another file.
- `snake_case`, `camel_case`, `pascal_case`, `kebab_case`, `upper_case`, `lower_case`.
- `comma_separate`, `permutations`, `combinations`, `seq`.

## Examples (Ruby bodies)

### Java fields from XML (per type)
```java
//embgen_embedded_generator xml_driven_macro 11111111-1111-1111-1111-111111111111
// @types.xml {/types/type[@name='Person']/fields/field} {
//     emit "    private #{javatype} #{name}; // #{dbtype}\n"
// }
//embgen_generated_start 11111111-1111-1111-1111-111111111111
//embgen_generated_end 11111111-1111-1111-1111-111111111111
```

### SQL DDL for all tables (single file)
```sql
--embgen_embedded_generator xml_driven_macro 22222222-2222-2222-2222-222222222222
-- @types.xml {/types/type} {
--     table_name = xpathnode.attributes['name']
--     emit "CREATE TABLE #{table_name} (\n"
--     xpathnode.elements.each_with_index('fields/field') do |field, idx|
--         emit ",\n" unless idx.zero?
--         emit "    #{field.attributes['name']} #{field.attributes['dbtype']}"
--     end
--     emit "\n);\n\n"
-- }
--embgen_generated_start 22222222-2222-2222-2222-222222222222
--embgen_generated_end 22222222-2222-2222-2222-222222222222
```

### One file per table (multi‑file emit)
```sql
--embgen_embedded_generator xml_driven_macro 99999999-9999-9999-9999-999999999999
-- @types.xml {/types/type} {
--     table_name = xpathnode.attributes['name']
--     target_tables ||= []
--     unless target_tables.any? && !target_tables.include?(table_name)
--         out_path = defined?(base_dir) ? File.join(base_dir, "#{table_name}.sql") : "#{table_name}.sql"
--         emit_file out_path do
--             emit "CREATE TABLE #{table_name} (\n"
--             xpathnode.elements.each_with_index('fields/field') do |field, idx|
--                 emit ",\n" unless idx.zero?
--                 emit "    #{field.attributes['name']} #{field.attributes['dbtype']}"
--             end
--             emit "\n);\n"
--         end
--         emit "#{@context.comment_line("generated file: #{out_path}")}\n"
--         emit "\n"
--     end
-- }
--embgen_generated_start 99999999-9999-9999-9999-999999999999
--embgen_generated_end 99999999-9999-9999-9999-999999999999
```

### Rails views (read‑only + edit)
```erb
--embgen_embedded_generator xml_driven_macro 12121212-1212-1212-1212-121212121212
-- @types.xml {/types/type} {
--     target_types ||= []
--     type_name = name
--     next if target_types.any? && !target_types.include?(type_name)
--     model_var = snake_case(type_name)
--     view_dir  = File.join(rails_views, snake_case(type_name))
--     emit_file File.join(view_dir, "show.html.erb") do
--         emit "<h1>#{type_name}</h1>\n"
--         xpathnode.elements.each('fields/field') do |field|
--             fname_sn = snake_case(field.attributes['name'])
--             label    = fname_sn.tr('_', ' ').split.map(&:capitalize).join(' ')
--             emit "<p><strong>#{label}:</strong> <%= @#{model_var}.#{fname_sn} %></p>\n"
--         end
--         emit "<%= link_to 'Edit', edit_#{model_var}_path(@#{model_var}) %> |\n"
--         emit "<%= link_to 'Back', #{model_var}s_path %>\n"
--     end
--     emit_file File.join(view_dir, "edit.html.erb") do
--         emit "<h1>Edit #{type_name}</h1>\n"
--         emit "<%= form_with model: @#{model_var}, local: true do |f| %>\n"
--         xpathnode.elements.each('fields/field') do |field|
--             fname_sn = snake_case(field.attributes['name'])
--             label    = fname_sn.tr('_', ' ').split.map(&:capitalize).join(' ')
--             emit "  <div class=\"field\">\n"
--             emit "    <%= f.label :#{fname_sn}, \"#{label}\" %>\n"
--             emit "    <%= f.text_field :#{fname_sn} %>\n"
--             emit "  </div>\n"
--         end
--         emit "  <div class=\"actions\">\n    <%= f.submit %>\n  </div>\n<% end %>\n"
--         emit "<%= link_to 'Show', @#{model_var} %> |\n"
--         emit "<%= link_to 'Back', #{model_var}s_path %>\n"
--     end
--     emit "#{@context.comment_line("generated rails views for #{type_name} at #{view_dir}")}\n\n"
-- }
--embgen_generated_start 12121212-1212-1212-1212-121212121212
--embgen_generated_end 12121212-1212-1212-1212-121212121212
```

## How it works internally (brief)
1) Scan the file for embedded generator macros (normalizing legacy `g4_` markers).
2) For each macro: collect comment‑stripped body, detect indentation and comment prefix, capture UUID and generator type.
3) Dispatch to the registered generator; generators may queue writes to other files via `emit_file`/`emit_to_file`.
4) Replace the region between `embgen_generated_start`/`end` with the new output, preserving indentation.

## Path resolution for data files
- Relative paths in generator bodies (e.g., `types.xml`) resolve relative to the file being processed, walking up parent directories until found. This makes embedded generator macros relocatable with their source files.
- Absolute paths are used as given.

## External tools and dependencies
- `dot` (Graphviz) for `dot`.
- `java` + `plantuml.jar` (bundled under `plantuml/`) for `plantuml` / `plantuml_ascii`.
- `latex` and `dvipng` for `latex` / `latex_inline` (outputs are written next to the source file).
- `REXML` is used for XML parsing (bundled with Ruby); `json` from stdlib for JSON.

## Best practices
- Commit both the embedded generator macro and its generated region; rerun embgen after schema changes and review diffs.
- Keep generator UUIDs stable; change them only if intentionally resetting the generated region.
- Use `emit_file` when the natural artifact is a separate file (e.g., per‑table DDL, per‑type view).
- Scope generators narrowly—one concern per UUID—so diffs stay small and reviewable.
- Prefer schema‑driven generators (`xml_driven_macro`/`json_driven_macro`) for anything tied to types/fields.

## Quick start checklist
1. Add an embedded generator macro with `embgen_embedded_generator ...` and a UUID.
2. Write the generator body using `emit` (or `emit_file`).
3. Run `ruby embgen.rb yourfile.ext` (or `-r ...` / `-l ...`).
4. Inspect diffs; commit.
5. Re‑run after schema changes to keep code in sync.

## Why this solves boilerplate drift
Because the embedded generator macro sits next to the code it owns, the pattern for regeneration is always discoverable. Tying it to a shared schema (XML/JSON) means every future schema change has a single, mechanical regeneration path. No more retyping converters, DTOs, forms, or DDL by hand—the codebase refreshes itself from the schema with one command, keeping repetitive layers aligned as the domain evolves.
