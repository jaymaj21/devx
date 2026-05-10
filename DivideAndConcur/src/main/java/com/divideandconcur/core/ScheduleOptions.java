package com.divideandconcur.core;
import java.util.*;
public final class ScheduleOptions {
    private final List<BeforeConstraint> beforeConstraints=new ArrayList<>();
    private Integer maxPreemptions=null;
    private long maxSchedules=Long.MAX_VALUE;

    public static ScheduleOptions exhaustive() {
        return new ScheduleOptions();
    }

    public ScheduleOptions requireBefore(Turn before,Turn after) {
        beforeConstraints.add(BeforeConstraint.of(before,after));
        return this;
    }

    public ScheduleOptions maxPreemptions(int n) {
        if(n<0) throw new IllegalArgumentException("maxPreemptions must be non-negative");
        maxPreemptions=n;
        return this;
    }

    public ScheduleOptions maxSchedules(long n) {
        if(n<=0) throw new IllegalArgumentException("maxSchedules must be positive");
        maxSchedules=n;
        return this;
    }

    public List<BeforeConstraint> beforeConstraints() {
        return List.copyOf(beforeConstraints);
    }

    public Integer maxPreemptions() {
        return maxPreemptions;
    }

    public long maxSchedules() {
        return maxSchedules;
    }
}
