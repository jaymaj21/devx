package org.dstr.clj;

import clojure.lang.RT;
import clojure.lang.Symbol;
import clojure.lang.Var;

public final class CdstrShell {
    private CdstrShell() {
    }

    public static void main(String[] args) throws Exception {
        Var require = RT.var("clojure.core", "require");
        require.invoke(Symbol.intern("dstr.clj.compiler"));
        Var main = RT.var("dstr.clj.compiler", "-main");
        main.applyTo(RT.seq(args));
    }
}
