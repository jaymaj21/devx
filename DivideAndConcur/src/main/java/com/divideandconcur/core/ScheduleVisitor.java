package com.divideandconcur.core;
import java.util.List;

@FunctionalInterface
public interface ScheduleVisitor {
    boolean visit(List<Turn> schedule);
}
