package com.divideandconcur.core;
import java.time.Instant;

public record TraceEvent(int scheduleIndex, Turn turn, String event, Instant at, String javaThreadName) {
    public String toString() {
        return scheduleIndex+" "+turn+" "+event+" ["+javaThreadName+"]";
    }
}
