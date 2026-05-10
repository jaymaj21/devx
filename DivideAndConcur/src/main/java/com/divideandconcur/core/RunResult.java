package com.divideandconcur.core;

import java.util.List;

public record RunResult(List<Turn> schedule, List<TraceEvent> trace, List<Throwable> failures) {
    public boolean passed() {
        return failures.isEmpty();
    }

    public String shortStatus() {
        return passed() ? "PASS" : "FAIL";
    }

    public String pretty() {
        StringBuilder sb = new StringBuilder();
        sb.append(shortStatus()).append(" schedule ").append(schedule).append("\n");

        if (!failures.isEmpty()) {
            sb.append("Failures:\n");
            for (Throwable t : failures) {
                sb.append("  - ").append(t.getClass().getSimpleName()).append(": ")
                .append(t.getMessage()).append("\n");
                if (t instanceof ScheduleFailure sf) {
                    sb.append(sf.prettyTrace());
                }
            }
        }

        sb.append("Trace:\n");
        for (TraceEvent e : trace) {
            sb.append("  ").append(e).append("\n");
        }
        return sb.toString();
    }
}
