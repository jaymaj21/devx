//! Procedural macro demo: XML schema -> Rust structs, SQLite DAOs, JSON helpers,
//! and a small deterministic length-prefixed binary serializer called TinyProto.

use heck::{ToSnakeCase, ToUpperCamelCase};
use proc_macro::TokenStream;
use quote::{format_ident, quote};
use syn::{parse_macro_input, LitStr};

#[derive(Debug, Clone)]
struct AppSchema {
    module: String,
    entities: Vec<Entity>,
}

#[derive(Debug, Clone)]
struct Entity {
    name: String,
    table: String,
    fields: Vec<Field>,
}

#[derive(Debug, Clone)]
struct Field {
    name: String,
    ty: String,
    primary_key: bool,
}

#[proc_macro]
pub fn generate_app_schema(input: TokenStream) -> TokenStream {
    let path_lit = parse_macro_input!(input as LitStr);
    let relative_path = path_lit.value();

    match generate(&relative_path) {
        Ok(tokens) => tokens.into(),
        Err(message) => syn::Error::new(path_lit.span(), message).to_compile_error().into(),
    }
}

fn generate(relative_path: &str) -> Result<proc_macro2::TokenStream, String> {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .map_err(|_| "CARGO_MANIFEST_DIR was not set".to_string())?;
    let schema_path = std::path::Path::new(&manifest_dir).join(relative_path);
    let xml = std::fs::read_to_string(&schema_path)
        .map_err(|e| format!("could not read XML schema '{}': {e}", schema_path.display()))?;
    let schema = parse_schema(&xml)?;
    emit_schema(schema, relative_path)
}

fn parse_schema(xml: &str) -> Result<AppSchema, String> {
    let doc = roxmltree::Document::parse(xml).map_err(|e| format!("invalid XML schema: {e}"))?;
    let root = doc.root_element();
    if root.tag_name().name() != "application" {
        return Err("expected root element <application>".to_string());
    }

    let module = root.attribute("module").unwrap_or("generated_domain").to_string();
    let mut entities = Vec::new();

    for entity_node in root.children().filter(|n| n.has_tag_name("entity")) {
        let name = entity_node
            .attribute("name")
            .ok_or_else(|| "entity is missing required name attribute".to_string())?
            .to_string();
        let table = entity_node
            .attribute("table")
            .map(|s| s.to_string())
            .unwrap_or_else(|| name.to_snake_case());

        let mut fields = Vec::new();
        for field_node in entity_node.children().filter(|n| n.has_tag_name("field")) {
            let field_name = field_node
                .attribute("name")
                .ok_or_else(|| format!("entity {name} has a field without a name"))?
                .to_string();
            let ty = field_node
                .attribute("type")
                .ok_or_else(|| format!("field {name}.{field_name} has no type"))?
                .to_string();
            validate_type(&ty)?;
            let primary_key = field_node.attribute("primaryKey") == Some("true");
            fields.push(Field { name: field_name, ty, primary_key });
        }

        if fields.is_empty() {
            return Err(format!("entity {name} has no fields"));
        }
        if fields.iter().filter(|f| f.primary_key).count() != 1 {
            return Err(format!("entity {name} must have exactly one primaryKey=\"true\" field"));
        }

        entities.push(Entity { name, table, fields });
    }

    if entities.is_empty() {
        return Err("schema must contain at least one <entity>".to_string());
    }

    Ok(AppSchema { module, entities })
}

fn validate_type(ty: &str) -> Result<(), String> {
    match ty {
        "String" | "i64" | "bool" | "f64" => Ok(()),
        other => Err(format!("unsupported field type '{other}'; supported: String, i64, bool, f64")),
    }
}

fn rust_type(ty: &str) -> proc_macro2::TokenStream {
    match ty {
        "String" => quote! { String },
        "i64" => quote! { i64 },
        "bool" => quote! { bool },
        "f64" => quote! { f64 },
        _ => unreachable!(),
    }
}

fn sql_type(ty: &str) -> &'static str {
    match ty {
        "String" => "TEXT NOT NULL",
        "i64" => "INTEGER NOT NULL",
        "bool" => "INTEGER NOT NULL",
        "f64" => "REAL NOT NULL",
        _ => unreachable!(),
    }
}

fn emit_schema(schema: AppSchema, relative_path: &str) -> Result<proc_macro2::TokenStream, String> {
    let module_ident = format_ident!("{}", schema.module.to_snake_case());
    let schema_path = relative_path.to_string();

    let struct_defs = schema.entities.iter().map(emit_struct);
    let json_helpers = schema.entities.iter().map(emit_json_helpers);
    let proto_helpers = schema.entities.iter().map(emit_proto_helpers);
    let dao_mod = emit_dao_module(&schema.entities)?;

    Ok(quote! {
        pub mod #module_ident {
            pub const XML_SCHEMA_PATH: &str = #schema_path;

            #(#struct_defs)*
            #(#json_helpers)*
            #(#proto_helpers)*
            #dao_mod
        }
    })
}

fn emit_struct(entity: &Entity) -> proc_macro2::TokenStream {
    let name = format_ident!("{}", entity.name.to_upper_camel_case());
    let fields = entity.fields.iter().map(|f| {
        let ident = format_ident!("{}", f.name.to_snake_case());
        let ty = rust_type(&f.ty);
        quote! { pub #ident: #ty, }
    });

    quote! {
        #[derive(Debug, Clone, PartialEq, ::serde::Serialize, ::serde::Deserialize)]
        pub struct #name {
            #(#fields)*
        }
    }
}

fn emit_json_helpers(entity: &Entity) -> proc_macro2::TokenStream {
    let name = format_ident!("{}", entity.name.to_upper_camel_case());
    quote! {
        impl #name {
            pub fn to_json_pretty(&self) -> ::serde_json::Result<String> {
                ::serde_json::to_string_pretty(self)
            }

            pub fn from_json(input: &str) -> ::serde_json::Result<Self> {
                ::serde_json::from_str(input)
            }
        }
    }
}

fn emit_proto_helpers(entity: &Entity) -> proc_macro2::TokenStream {
    let name = format_ident!("{}", entity.name.to_upper_camel_case());

    let encoders = entity.fields.iter().enumerate().map(|(idx, f)| {
        let field_ident = format_ident!("{}", f.name.to_snake_case());
        let tag = (idx + 1) as u8;
        match f.ty.as_str() {
            "String" => quote! { __tinyproto_write_field(&mut out, #tag, self.#field_ident.as_bytes()); },
            "i64" => quote! { __tinyproto_write_field(&mut out, #tag, &self.#field_ident.to_le_bytes()); },
            "bool" => quote! { __tinyproto_write_field(&mut out, #tag, &[self.#field_ident as u8]); },
            "f64" => quote! { __tinyproto_write_field(&mut out, #tag, &self.#field_ident.to_le_bytes()); },
            _ => unreachable!(),
        }
    });

    let defaults = entity.fields.iter().map(|f| {
        let field_ident = format_ident!("{}", f.name.to_snake_case());
        match f.ty.as_str() {
            "String" => quote! { let mut #field_ident: Option<String> = None; },
            "i64" => quote! { let mut #field_ident: Option<i64> = None; },
            "bool" => quote! { let mut #field_ident: Option<bool> = None; },
            "f64" => quote! { let mut #field_ident: Option<f64> = None; },
            _ => unreachable!(),
        }
    });

    let decoders = entity.fields.iter().enumerate().map(|(idx, f)| {
        let field_ident = format_ident!("{}", f.name.to_snake_case());
        let field_name = f.name.clone();
        let tag = (idx + 1) as u8;
        match f.ty.as_str() {
            "String" => quote! { #tag => { #field_ident = Some(String::from_utf8(value.to_vec()).map_err(|e| format!("field {} is not UTF-8: {e}", #field_name))?); } },
            "i64" => quote! { #tag => { if value.len() != 8 { return Err(format!("field {} expected 8 bytes", #field_name)); } let mut a = [0u8; 8]; a.copy_from_slice(value); #field_ident = Some(i64::from_le_bytes(a)); } },
            "bool" => quote! { #tag => { if value.len() != 1 { return Err(format!("field {} expected 1 byte", #field_name)); } #field_ident = Some(value[0] != 0); } },
            "f64" => quote! { #tag => { if value.len() != 8 { return Err(format!("field {} expected 8 bytes", #field_name)); } let mut a = [0u8; 8]; a.copy_from_slice(value); #field_ident = Some(f64::from_le_bytes(a)); } },
            _ => unreachable!(),
        }
    });

    let builders = entity.fields.iter().map(|f| {
        let field_ident = format_ident!("{}", f.name.to_snake_case());
        let field_name = f.name.clone();
        quote! { #field_ident: #field_ident.ok_or_else(|| format!("missing field {}", #field_name))?, }
    });

    quote! {
        impl #name {
            pub fn to_tinyproto_bytes(&self) -> Vec<u8> {
                let mut out = Vec::new();
                #(#encoders)*
                out
            }

            pub fn from_tinyproto_bytes(input: &[u8]) -> Result<Self, String> {
                #(#defaults)*
                let mut pos = 0usize;
                while pos < input.len() {
                    let (tag, value, next) = __tinyproto_read_field(input, pos)?;
                    pos = next;
                    match tag {
                        #(#decoders)*
                        _ => {}
                    }
                }
                Ok(Self { #(#builders)* })
            }
        }
    }
}

fn emit_dao_module(entities: &[Entity]) -> Result<proc_macro2::TokenStream, String> {
    let create_sql_statements = entities.iter().map(|e| {
        let table = &e.table;
        let columns: Vec<String> = e.fields.iter().map(|f| {
            let mut s = format!("{} {}", f.name.to_snake_case(), sql_type(&f.ty));
            if f.primary_key { s.push_str(" PRIMARY KEY"); }
            s
        }).collect();
        format!("CREATE TABLE IF NOT EXISTS {table} ({});", columns.join(", "))
    });

    let dao_functions = entities.iter().map(emit_entity_dao);

    Ok(quote! {
        fn __tinyproto_write_field(out: &mut Vec<u8>, tag: u8, value: &[u8]) {
            out.push(tag);
            out.extend_from_slice(&(value.len() as u32).to_le_bytes());
            out.extend_from_slice(value);
        }

        fn __tinyproto_read_field(input: &[u8], pos: usize) -> Result<(u8, &[u8], usize), String> {
            if pos + 5 > input.len() {
                return Err("truncated TinyProto field header".to_string());
            }
            let tag = input[pos];
            let mut len_bytes = [0u8; 4];
            len_bytes.copy_from_slice(&input[pos + 1..pos + 5]);
            let len = u32::from_le_bytes(len_bytes) as usize;
            let start = pos + 5;
            let end = start + len;
            if end > input.len() {
                return Err("truncated TinyProto field body".to_string());
            }
            Ok((tag, &input[start..end], end))
        }

        pub mod dao {
            use super::*;

            pub fn create_tables(conn: &::rusqlite::Connection) -> ::rusqlite::Result<()> {
                #(
                    conn.execute(#create_sql_statements, [])?;
                )*
                Ok(())
            }

            #(#dao_functions)*
        }
    })
}

fn emit_entity_dao(entity: &Entity) -> proc_macro2::TokenStream {
    let type_ident = format_ident!("{}", entity.name.to_upper_camel_case());
    let snake = entity.name.to_snake_case();
    let insert_fn = format_ident!("insert_{}", snake);
    let get_fn = format_ident!("get_{}_by_id", snake);
    let list_fn = format_ident!("list_{}s", snake);
    let table = entity.table.clone();

    let field_names: Vec<String> = entity.fields.iter().map(|f| f.name.to_snake_case()).collect();
    let columns_csv = field_names.join(", ");
    let placeholders = (1..=field_names.len()).map(|i| format!("?{i}")).collect::<Vec<_>>().join(", ");
    let insert_sql = format!("INSERT OR REPLACE INTO {table} ({columns_csv}) VALUES ({placeholders})");
    let select_sql = format!("SELECT {columns_csv} FROM {table} WHERE {} = ?1", entity.fields.iter().find(|f| f.primary_key).unwrap().name.to_snake_case());
    let list_sql = format!("SELECT {columns_csv} FROM {table} ORDER BY {}", entity.fields.iter().find(|f| f.primary_key).unwrap().name.to_snake_case());

    let value_refs = entity.fields.iter().map(|f| {
        let ident = format_ident!("{}", f.name.to_snake_case());
        quote! { &value.#ident }
    });

    let pk_field = entity.fields.iter().find(|f| f.primary_key).unwrap();
    let pk_ident = format_ident!("{}", pk_field.name.to_snake_case());
    let pk_ty = rust_type(&pk_field.ty);

    let row_fields = entity.fields.iter().enumerate().map(|(idx, f)| {
        let ident = format_ident!("{}", f.name.to_snake_case());
        quote! { #ident: row.get(#idx)?, }
    });

    let row_mapper_name = format_ident!("map_{}_row", snake);

    quote! {
        fn #row_mapper_name(row: &::rusqlite::Row<'_>) -> ::rusqlite::Result<#type_ident> {
            Ok(#type_ident { #(#row_fields)* })
        }

        pub fn #insert_fn(conn: &::rusqlite::Connection, value: &#type_ident) -> ::rusqlite::Result<usize> {
            conn.execute(#insert_sql, ::rusqlite::params![#(#value_refs),*])
        }

        pub fn #get_fn(conn: &::rusqlite::Connection, id: #pk_ty) -> ::rusqlite::Result<Option<#type_ident>> {
            let mut stmt = conn.prepare(#select_sql)?;
            let mut rows = stmt.query(::rusqlite::params![id])?;
            if let Some(row) = rows.next()? {
                Ok(Some(#row_mapper_name(row)?))
            } else {
                Ok(None)
            }
        }

        pub fn #list_fn(conn: &::rusqlite::Connection) -> ::rusqlite::Result<Vec<#type_ident>> {
            let mut stmt = conn.prepare(#list_sql)?;
            let rows = stmt.query_map([], |row| #row_mapper_name(row))?;
            rows.collect()
        }
    }
}
