package com.divideandconcur.core;
import java.util.*;
public record ScenarioRun(List<Worker> workers, FinalCheck finalCheck) {
    public ScenarioRun {
        Objects.requireNonNull(workers);
        Objects.requireNonNull(finalCheck);}

    public ScenarioRun(List<Worker> workers) {
        this(workers,()-> {});
    }

    @FunctionalInterface
    public interface FinalCheck {
        void check() throws Exception;
    }
}
