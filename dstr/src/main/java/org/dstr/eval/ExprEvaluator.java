package org.dstr.eval;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import org.dstr.ast.*;
import org.dstr.model.NamedExpr;
import org.dstr.model.Spec;

public final class ExprEvaluator {

    public boolean evalBoolean(Expr expr, EvaluationContext ctx) {
        Object value = eval(expr, ctx);
        if (!(value instanceof Boolean b)) {
            throw new IllegalArgumentException("Expected boolean value but got: " + value);
        }
        return b;
    }

    public Object eval(Expr expr, EvaluationContext ctx) {
        if (expr instanceof LiteralExpr literal) {
            return literal.value();
        }
        if (expr instanceof VarExpr var) {
            return var.phase() == VarExpr.Phase.NOW ? ctx.resolveNow(var.name()) : ctx.resolveNext(var.name());
        }
        if (expr instanceof UnaryExpr unary) {
            return evalUnary(unary, ctx);
        }
        if (expr instanceof BinaryExpr binary) {
            return evalBinary(binary, ctx);
        }
        if (expr instanceof NAryExpr nAry) {
            return evalNAry(nAry, ctx);
        }
        if (expr instanceof SetExpr setExpr) {
            return evalSet(setExpr, ctx);
        }
        if (expr instanceof QuantifiedExpr quantifiedExpr) {
            return evalQuantified(quantifiedExpr, ctx);
        }
        throw new IllegalArgumentException("Unknown expression type: " + expr);
    }

    private Object evalUnary(UnaryExpr unary, EvaluationContext ctx) {
        return switch (unary.op()) {
            case "not" -> !asBoolean(eval(unary.arg(), ctx));
            case "eventually" -> asBoolean(eval(unary.arg(), ctx));
            default -> throw new IllegalArgumentException("Unknown unary operator: " + unary.op());
        };
    }

    private Object evalBinary(BinaryExpr binary, EvaluationContext ctx) {
        Object left = eval(binary.left(), ctx);
        Object right = eval(binary.right(), ctx);
        return switch (binary.op()) {
            case "=" -> Objects.equals(left, right);
            case "!=" -> !Objects.equals(left, right);
            case "<" -> compare(left, right) < 0;
            case "<=" -> compare(left, right) <= 0;
            case ">" -> compare(left, right) > 0;
            case ">=" -> compare(left, right) >= 0;
            case "in" -> asCollection(right).contains(left);
            case "implies" -> !asBoolean(left) || asBoolean(right);
            default -> throw new IllegalArgumentException("Unknown binary operator: " + binary.op());
        };
    }

    private Object evalNAry(NAryExpr expr, EvaluationContext ctx) {
        List<Object> values = new ArrayList<>();
        for (Expr arg : expr.args()) {
            values.add(eval(arg, ctx));
        }
        return switch (expr.op()) {
            case "and" -> values.stream().allMatch(ExprEvaluator::asBoolean);
            case "or" -> values.stream().anyMatch(ExprEvaluator::asBoolean);
            case "+" -> values.stream().mapToLong(ExprEvaluator::asLong).sum();
            case "*" -> values.stream().mapToLong(ExprEvaluator::asLong).reduce(1L, (a, b) -> a * b);
            case "-" -> {
                if (values.isEmpty()) throw new IllegalArgumentException("- needs at least one arg");
                long acc = asLong(values.get(0));
                for (int i = 1; i < values.size(); i++) acc -= asLong(values.get(i));
                yield acc;
            }
            case "/" -> {
                if (values.size() != 2) throw new IllegalArgumentException("/ expects exactly 2 args");
                yield asLong(values.get(0)) / asLong(values.get(1));
            }
            default -> throw new IllegalArgumentException("Unknown n-ary operator: " + expr.op());
        };
    }

    private Object evalSet(SetExpr expr, EvaluationContext ctx) {
        Set<Object> result = new HashSet<>();
        for (Expr element : expr.elements()) {
            result.add(eval(element, ctx));
        }
        return result;
    }

    private Object evalQuantified(QuantifiedExpr expr, EvaluationContext ctx) {
        Set<?> domain = asCollection(eval(expr.domain(), ctx));
        return switch (expr.quantifier()) {
            case "forall" -> domain.stream().allMatch(v -> evalBoolean(expr.body(), withLocal(ctx, expr.variable(), v)));
            case "exists" -> domain.stream().anyMatch(v -> evalBoolean(expr.body(), withLocal(ctx, expr.variable(), v)));
            default -> throw new IllegalArgumentException("Unknown quantifier: " + expr.quantifier());
        };
    }

    public Map<String, Boolean> evaluateActions(Spec spec, org.dstr.model.State now, org.dstr.model.State next) {
        Map<String, Boolean> results = new HashMap<>();
        EvaluationContext seed = new EvaluationContext(now, next, Map.of(), Map.of());
        for (NamedExpr action : spec.actions()) {
            results.put(action.name(), evalBoolean(action.body(), seed));
        }
        return results;
    }

    private EvaluationContext withLocal(EvaluationContext ctx, String name, Object value) {
        Map<String, Object> locals = new HashMap<>(ctx.locals());
        locals.put(name, value);
        return new EvaluationContext(ctx.now(), ctx.next(), locals, ctx.actionResults());
    }

    private static boolean asBoolean(Object value) {
        if (!(value instanceof Boolean b)) {
            throw new IllegalArgumentException("Expected boolean but got: " + value);
        }
        return b;
    }

    private static long asLong(Object value) {
        if (value instanceof Integer i) return i.longValue();
        if (value instanceof Long l) return l;
        if (value instanceof Short s) return s.longValue();
        if (value instanceof Byte b) return b.longValue();
        throw new IllegalArgumentException("Expected integer-like number but got: " + value);
    }

    @SuppressWarnings("unchecked")
    private static Set<?> asCollection(Object value) {
        if (value instanceof Set<?> s) return s;
        throw new IllegalArgumentException("Expected set but got: " + value);
    }

    @SuppressWarnings({"rawtypes", "unchecked"})
    private static int compare(Object left, Object right) {
        if (left instanceof Comparable l && right instanceof Comparable r) {
            return l.compareTo(r);
        }
        throw new IllegalArgumentException("Values are not comparable: " + left + " and " + right);
    }
}

