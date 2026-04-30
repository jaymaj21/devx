package org.dstr.model;

import java.util.List;
import java.util.Map;
import org.dstr.ast.Expr;

public record Spec(
        String name,
        List<String> variables,
        Map<String, Expr> domains,
        Expr init,
        List<NamedExpr> actions,
        Expr next,
        List<NamedExpr> invariants,
        List<NamedExpr> properties) {
}

