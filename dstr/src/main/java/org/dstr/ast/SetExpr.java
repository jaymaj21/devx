package org.dstr.ast;

import java.util.List;

public record SetExpr(List<Expr> elements) implements Expr {
}

