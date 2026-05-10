package com.divideandconcur.core;
public class DncException extends RuntimeException {
    public DncException(String m) {
        super(m);
    }
    public DncException(String m,Throwable c) {
        super(m,c);
    }
}
