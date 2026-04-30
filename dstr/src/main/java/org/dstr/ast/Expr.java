package org.dstr.ast;

public sealed interface Expr permits LiteralExpr, VarExpr, UnaryExpr, BinaryExpr, NAryExpr, SetExpr, QuantifiedExpr {
}

