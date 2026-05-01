# Rust XML Procedural Macro Codegen Demo

This is a deliberately impressive Rust procedural macro demo.

The consuming application has one XML schema:

```text
app/schema/customer_support.xml
```

From that XML, the `generate_app_schema!` procedural macro generates:

1. Rust domain structs: `Customer`, `Agent`, `Ticket`, `TicketMessage`
2. SQLite DDL and DAO functions using `rusqlite`
3. JSON helpers using `serde` / `serde_json`
4. A small generated binary wire format called `TinyProto`

The point is not that XML is the best schema language. The point is that a procedural macro is normal Rust code running at compile time: it can read a file, parse it, build an internal model, and emit a large amount of strongly typed Rust code.

## Run

From the project root:

```bash
cargo run -p supportdesk_app
```

Expected output includes:

- data loaded from an in-memory SQLite database
- pretty JSON for a generated `Ticket`
- a TinyProto byte count for a generated `TicketMessage`
- confirmation that all generated round-trips worked

## Inspect the generated code

Install `cargo-expand`:

```bash
cargo install cargo-expand
```

Then run:

```bash
cargo expand -p supportdesk_app
```

This is the best way to show the full force of the macro: the source app is tiny, but the expanded Rust contains the generated structs, DAO layer, JSON methods, and binary codecs.

## Files

```text
rust_xml_macro_codegen_demo/
├── Cargo.toml
├── xml_schema_macro/
│   ├── Cargo.toml
│   └── src/lib.rs
└── app/
    ├── Cargo.toml
    ├── schema/customer_support.xml
    └── src/main.rs
```

## Notes

For production-grade external-file codegen, compare procedural macros with a `build.rs` approach. Procedural macros give a beautiful call-site API. `build.rs` gives more explicit Cargo rebuild tracking via `cargo:rerun-if-changed=...`.
