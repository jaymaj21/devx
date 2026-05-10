package com.divideandconcur.examples;
import com.divideandconcur.core.*;
import java.util.*;
public final class ConstrainedScheduleExample {
    private ConstrainedScheduleExample() {}
    public static ExplorationResult run() {
        ScheduleOptions options=
                ScheduleOptions.exhaustive().requireBefore(Turn.of("t1",0),Turn.of("t2",1)).maxPreemptions(1);
        return DncExplorer.explore(
                Map.of("t1",2,"t2",2),options,
                gate->
                { StringBuilder sb=new StringBuilder();
                    Worker t1=new Worker("constraint-t1",()->{
                        gate.init("t1");
                        sb.append("A");
                        gate.barrier("t1");
                        sb.append("B");
                        gate.end("t1");
                    });
                    Worker t2=new Worker("constraint-t2",()->{
                        gate.init("t2");
                        sb.append("X");
                        gate.barrier("t2");
                        sb.append("Y");
                        gate.end("t2");
                    });
                    return new ScenarioRun(List.of(t1,t2));
                });
    }
}
