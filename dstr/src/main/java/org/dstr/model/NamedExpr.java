package org.dstr.model;

import org.dstr.ast.Expr;

public record NamedExpr(String name, Expr body) {
}

