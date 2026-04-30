package org.dstr.ast;

public record UnaryExpr(String op, Expr arg) implements Expr {
}

