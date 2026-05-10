package com.divideandconcur.core;
public final class Assertions {
    private Assertions() {} public static void check(boolean condition,String message) {
        if(!condition) throw new AssertionError(message);
    }
}
