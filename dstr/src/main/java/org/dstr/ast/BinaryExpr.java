package org.dstr.ast;

public record BinaryExpr(String op, Expr left, Expr right) implements Expr {
}

