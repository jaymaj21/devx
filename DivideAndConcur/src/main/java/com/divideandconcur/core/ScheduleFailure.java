package com.divideandconcur.core;

import java.util.List;

public class ScheduleFailure extends DncException {
    private final List<Turn> schedule;
    private final List<TraceEvent> trace;

    public ScheduleFailure(String message, List<Turn> schedule, List<TraceEvent> trace) {
        super(message);
        this.schedule = List.copyOf(schedule);
        this.trace = List.copyOf(trace);
    }

    public ScheduleFailure(String message, Throwable cause, List<Turn> schedule, List<TraceEvent> trace) {
        super(message, cause);
        this.schedule = List.copyOf(schedule);
        this.trace = List.copyOf(trace);
    }

    public List<Turn> schedule() {
        return schedule;
    }

    public List<TraceEvent> trace() {
        return trace;
    }

    public String prettyTrace() {
        StringBuilder sb = new StringBuilder();
        sb.append("Schedule:\n");
        for (int i = 0; i < schedule.size(); i++) {
            sb.append("  ").append(i).append(". ").append(schedule.get(i)).append("\n");
        }
        sb.append("Trace:\n");
        for (TraceEvent e : trace) {
            sb.append("  ").append(e).append("\n");
        }
        return sb.toString();
    }
}
