package com.divideandconcur.core;
import java.util.*;
public final class ExplorationResult {
    private final List<RunResult> runs=new ArrayList<>();

    void add(RunResult r) {
        runs.add(r);
    }

    public List<RunResult> runs() {
        return List.copyOf(runs);
    }

    public long totalRuns() {
        return runs.size();
    }

    public long failedRuns() {
        return runs.stream().filter(r->!r.passed()).count();
    }

    public long passedRuns() {
        return runs.stream().filter(RunResult::passed).count();
    }

    public Optional<RunResult> firstFailure() {
        return runs.stream().filter(r->!r.passed()).findFirst();
    }

    public boolean allPassed() {
        return failedRuns()==0;
    }

    public String summary() {
        return "runs="+totalRuns()+", passed="+passedRuns()+", failed="+failedRuns();
    }
}
