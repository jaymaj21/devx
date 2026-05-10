package com.divideandconcur.core;
@FunctionalInterface public interface Invariant {

    void check() throws Exception;

    static Invariant that(String message, java.util.function.BooleanSupplier condition) {
        return ()-> { if(!condition.getAsBoolean()) throw new AssertionError(message); };
    }
}
