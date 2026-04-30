package org.dstr.ast;

public record VarExpr(String name, Phase phase) implements Expr {
    public enum Phase { NOW, NEXT }
}

