package org.dstr.model;

import java.util.List;
import java.util.Map;
import java.util.Set;

public record CheckResult(
        Set<State> reachableStates,
        int exploredTransitions,
        List<Counterexample> invariantViolations,
        List<Counterexample> deadlocks,
        Map<String, Boolean> existentialProperties) {
}

