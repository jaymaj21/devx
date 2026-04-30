package org.dstr.eval;

import java.util.Map;
import org.dstr.model.State;

public record EvaluationContext(State now, State next, Map<String, Object> locals, Map<String, Boolean> actionResults) {
    public Object resolveNow(String name) {
        if (name.startsWith("@action:")) {
            return actionResults.getOrDefault(name.substring("@action:".length()), false);
        }
        if (locals.containsKey(name)) {
            return locals.get(name);
        }
        return now.get(name);
    }

    public Object resolveNext(String name) {
        if (next == null) {
            throw new IllegalStateException("next-state unavailable while resolving " + name);
        }
        return next.get(name);
    }
}

