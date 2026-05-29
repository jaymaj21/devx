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
import org.dstr.ast.BinaryExpr;
import org.dstr.ast.Expr;
import org.dstr.ast.LiteralExpr;
import org.dstr.ast.NAryExpr;
import org.dstr.ast.QuantifiedExpr;
import org.dstr.ast.SetExpr;
import org.dstr.ast.UnaryExpr;
import org.dstr.ast.VarExpr;
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
        Map<String, List<Object>> domainValues = new LinkedHashMap<>();
        for (String variable : vars) {
            List<Object> values = materializeDomain(spec, variable);
            if (values.isEmpty()) {
                return List.of();
            }
            domainValues.put(variable, values);
        }

        Set<String> relevantVariables = collectRelevantVariables(spec);
        List<String> enumeratedVars = vars.stream()
                .filter(relevantVariables::contains)
                .toList();
        Map<String, Object> fixedValues = new LinkedHashMap<>();
        for (String variable : vars) {
            if (!relevantVariables.contains(variable)) {
                fixedValues.put(variable, domainValues.get(variable).get(0));
            }
        }

        List<List<Object>> domains = enumeratedVars.stream()
                .map(domainValues::get)
                .toList();
        List<State> results = new ArrayList<>();
        buildStates(spec, enumeratedVars, domains, 0, new LinkedHashMap<>(), fixedValues, results);
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

    private void buildStates(Spec spec, List<String> vars, List<List<Object>> domains, int index,
                             Map<String, Object> partial, Map<String, Object> fixedValues, List<State> out) {
        if (index == vars.size()) {
            Map<String, Object> fullState = new LinkedHashMap<>();
            for (String variable : spec.variables()) {
                if (partial.containsKey(variable)) {
                    fullState.put(variable, partial.get(variable));
                } else {
                    fullState.put(variable, fixedValues.get(variable));
                }
            }
            out.add(new State(fullState));
            return;
        }
        String var = vars.get(index);
        for (Object value : domains.get(index)) {
            Map<String, Object> nextPartial = new LinkedHashMap<>(partial);
            nextPartial.put(var, value);
            buildStates(spec, vars, domains, index + 1, nextPartial, fixedValues, out);
        }
    }

    private Set<String> collectRelevantVariables(Spec spec) {
        Set<String> declaredVariables = new LinkedHashSet<>(spec.variables());
        Set<String> relevantVariables = new LinkedHashSet<>();

        collectRelevantVariables(spec.init(), declaredVariables, relevantVariables);
        collectRelevantVariables(spec.next(), declaredVariables, relevantVariables);
        for (NamedExpr action : spec.actions()) {
            collectRelevantVariables(action.body(), declaredVariables, relevantVariables);
        }
        for (NamedExpr invariant : spec.invariants()) {
            collectRelevantVariables(invariant.body(), declaredVariables, relevantVariables);
        }
        for (NamedExpr property : spec.properties()) {
            collectRelevantVariables(property.body(), declaredVariables, relevantVariables);
        }

        return relevantVariables;
    }

    private void collectRelevantVariables(Expr expr, Set<String> declaredVariables, Set<String> relevantVariables) {
        if (expr instanceof LiteralExpr) {
            return;
        }
        if (expr instanceof VarExpr varExpr) {
            if (declaredVariables.contains(varExpr.name())) {
                relevantVariables.add(varExpr.name());
            }
            return;
        }
        if (expr instanceof UnaryExpr unaryExpr) {
            collectRelevantVariables(unaryExpr.arg(), declaredVariables, relevantVariables);
            return;
        }
        if (expr instanceof BinaryExpr binaryExpr) {
            if (isUnchangedClause(binaryExpr)) {
                return;
            }
            collectRelevantVariables(binaryExpr.left(), declaredVariables, relevantVariables);
            collectRelevantVariables(binaryExpr.right(), declaredVariables, relevantVariables);
            return;
        }
        if (expr instanceof NAryExpr nAryExpr) {
            for (Expr arg : nAryExpr.args()) {
                collectRelevantVariables(arg, declaredVariables, relevantVariables);
            }
            return;
        }
        if (expr instanceof SetExpr setExpr) {
            for (Expr element : setExpr.elements()) {
                collectRelevantVariables(element, declaredVariables, relevantVariables);
            }
            return;
        }
        if (expr instanceof QuantifiedExpr quantifiedExpr) {
            collectRelevantVariables(quantifiedExpr.domain(), declaredVariables, relevantVariables);
            collectRelevantVariables(quantifiedExpr.body(), declaredVariables, relevantVariables);
        }
    }

    private boolean isUnchangedClause(BinaryExpr binaryExpr) {
        if (!"=".equals(binaryExpr.op())) {
            return false;
        }
        return isMatchingNowNextPair(binaryExpr.left(), binaryExpr.right())
                || isMatchingNowNextPair(binaryExpr.right(), binaryExpr.left());
    }

    private boolean isMatchingNowNextPair(Expr left, Expr right) {
        if (!(left instanceof VarExpr leftVar) || !(right instanceof VarExpr rightVar)) {
            return false;
        }
        return leftVar.phase() == VarExpr.Phase.NEXT
                && rightVar.phase() == VarExpr.Phase.NOW
                && leftVar.name().equals(rightVar.name());
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

