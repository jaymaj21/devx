package org.dstr.ast;

public record QuantifiedExpr(String quantifier, String variable, Expr domain, Expr body) implements Expr {
}

