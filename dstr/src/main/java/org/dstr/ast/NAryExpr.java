package org.dstr.ast;

import java.util.List;

public record NAryExpr(String op, List<Expr> args) implements Expr {
}

