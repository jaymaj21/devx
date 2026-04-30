package org.dstr.check;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.dstr.ast.Expr;
import org.dstr.eval.EvaluationContext;
import org.dstr.eval.ExprEvaluator;
import org.dstr.model.CheckResult;
import org.dstr.model.Counterexample;
import org.dstr.model.NamedExpr;
import org.dstr.model.Spec;
import org.dstr.model.State;

public final class ExplicitStateChecker {
    private final ExprEvaluator evaluator = new ExprEvaluator();

    public CheckResult check(Spec spec) {
        List<State> universe = enumerateStates(spec);
        Set<State> reachable = new LinkedHashSet<>();
        Map<State, State> predecessor = new LinkedHashMap<>();
        Deque<State> queue = new ArrayDeque<>();
        List<Counterexample> invariantViolations = new ArrayList<>();
        List<Counterexample> deadlocks = new ArrayList<>();
        int transitions = 0;

        for (State s : universe) {
            EvaluationContext ctx = new EvaluationContext(s, null, Map.of(), Map.of());
            if (evaluator.evalBoolean(spec.init(), ctx)) {
                reachable.add(s);
                predecessor.put(s, null);
                queue.add(s);
            }
        }

        while (!queue.isEmpty()) {
            State current = queue.removeFirst();

            for (NamedExpr inv : spec.invariants()) {
                EvaluationContext ctx = new EvaluationContext(current, null, Map.of(), Map.of());
                if (!evaluator.evalBoolean(inv.body(), ctx)) {
                    invariantViolations.add(new Counterexample("invariant", inv.name(), buildPath(current, predecessor)));
                }
            }

            List<State> enabledSuccessors = new ArrayList<>();
            for (State candidateNext : universe) {
                Map<String, Boolean> actionResults = evaluator.evaluateActions(spec, current, candidateNext);
                EvaluationContext nextCtx = new EvaluationContext(current, candidateNext, Map.of(), actionResults);
                if (evaluator.evalBoolean(spec.next(), nextCtx)) {
                    enabledSuccessors.add(candidateNext);
                    transitions++;
                    if (reachable.add(candidateNext)) {
                        predecessor.put(candidateNext, current);
                        queue.add(candidateNext);
                    }
                }
            }
            if (enabledSuccessors.isEmpty()) {
                deadlocks.add(new Counterexample("deadlock", "deadlock", buildPath(current, predecessor)));
            }
        }

        Map<String, Boolean> properties = new LinkedHashMap<>();
        for (NamedExpr prop : spec.properties()) {
            boolean result;
            if (prop.body() instanceof org.dstr.ast.UnaryExpr unary && unary.op().equals("eventually")) {
                result = reachable.stream()
                        .anyMatch(s -> evaluator.evalBoolean(unary.arg(), new EvaluationContext(s, null, Map.of(), Map.of())));
            } else {
                result = reachable.stream()
                        .anyMatch(s -> evaluator.evalBoolean(prop.body(), new EvaluationContext(s, null, Map.of(), Map.of())));
            }
            properties.put(prop.name(), result);
        }

        return new CheckResult(reachable, transitions, invariantViolations, deadlocks, properties);
    }

    public List<State> enumerateStates(Spec spec) {
        List<String> vars = spec.variables();
        List<List<Object>> domains = vars.stream()
                .map(v -> materializeDomain(spec, v))
                .toList();
        List<State> results = new ArrayList<>();
        buildStates(vars, domains, 0, new LinkedHashMap<>(), results);
        return results;
    }

    private List<Object> materializeDomain(Spec spec, String variable) {
        Expr domainExpr = spec.domains().get(variable);
        if (domainExpr == null) {
            throw new IllegalArgumentException("Missing finite domain for variable: " + variable);
        }
        Object raw = evaluator.eval(domainExpr, new EvaluationContext(new State(Map.of()), null, Map.of(), Map.of()));
        if (!(raw instanceof Set<?> set)) {
            throw new IllegalArgumentException("Domain for " + variable + " did not evaluate to a set");
        }
        return set.stream().collect(Collectors.toList());
    }

    private void buildStates(List<String> vars, List<List<Object>> domains, int index,
                             Map<String, Object> partial, List<State> out) {
        if (index == vars.size()) {
            out.add(new State(partial));
            return;
        }
        String var = vars.get(index);
        for (Object value : domains.get(index)) {
            Map<String, Object> nextPartial = new LinkedHashMap<>(partial);
            nextPartial.put(var, value);
            buildStates(vars, domains, index + 1, nextPartial, out);
        }
    }

    private List<State> buildPath(State target, Map<State, State> predecessor) {
        List<State> path = new ArrayList<>();
        State cur = target;
        while (cur != null) {
            path.add(0, cur);
            cur = predecessor.get(cur);
        }
        return path;
    }
}

