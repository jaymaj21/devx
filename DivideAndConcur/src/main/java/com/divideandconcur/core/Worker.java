package com.divideandconcur.core;
import java.util.Objects;
public record Worker(String javaThreadName, Body body) {
    public Worker {Objects.requireNonNull(javaThreadName); Objects.requireNonNull(body);}
    @FunctionalInterface
    public interface Body {
        void run() throws Exception;
    }
}
