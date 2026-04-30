
use proc_macro::TokenStream;
use quote::{format_ident, quote};
use syn::{parse_macro_input, Expr};
use std::sync::atomic::{AtomicUsize, Ordering};

// Global counter to generate unique guard identifiers per expansion
static COUNTER: AtomicUsize = AtomicUsize::new(0);

/// Usage:
///     mprewriter_scope_START!(42);
///
/// Expands to roughly:
///     let __mprewriter_guard_0 = mprewriter::mprewriter_stack_fathomer::enter();
///     mprewriter::scope_START(42);
#[proc_macro]
pub fn mprewriter_scope_START(input: TokenStream) -> TokenStream {
    let id_expr: Expr = parse_macro_input!(input as Expr);

    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    let guard_ident = format_ident!("__mprewriter_guard_{}", n);

    let expanded = quote! {
        #[allow(non_snake_case, unused_variables)]
        let #guard_ident = mprewriter::mprewriter_stack_fathomer::enter();
        mprewriter::scope_START(#id_expr);
    };

    TokenStream::from(expanded)
}
