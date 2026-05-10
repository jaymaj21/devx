package com.divideandconcur.core;
import java.time.*;
import java.util.*;
import java.util.function.Function;
public final class DncExplorer {
    private DncExplorer() {}
    public static ExplorationResult explore(Map<String,Integer> counts,ScheduleOptions options,Function<ScheduleGate,ScenarioRun> factory) {
        return explore(counts,options,Duration.ofSeconds(5),factory);
    }
    public static ExplorationResult explore(Map<String,Integer> counts,ScheduleOptions options,Duration timeout,Function<ScheduleGate,ScenarioRun> factory) {
        ExplorationResult result=new ExplorationResult();
        ScheduleGenerator.visitAll(counts,options,s-> { result.add(runOneSchedule(s,timeout,factory)); return true; });
        return result;
    }
    public static RunResult runOneSchedule(List<Turn> schedule,Function<ScheduleGate,ScenarioRun> factory) {
        return runOneSchedule(schedule,Duration.ofSeconds(5),factory);
    }
    public static RunResult runOneSchedule(List<Turn> schedule,Duration timeout,Function<ScheduleGate,ScenarioRun> factory) {
        ScheduleGate gate=ScheduleGate.forSchedule(schedule,timeout);
        ScenarioRun run=factory.apply(gate);
        List<Throwable> failures=Collections.synchronizedList(new ArrayList<>());
        List<Thread> threads=new ArrayList<>();
        for(Worker w:run.workers()) {
            Thread t=new Thread(()-> {try {
                w.body().run();
            } catch(Throwable ex) {
                failures.add(ex);
            }
                                     },w.javaThreadName());
            threads.add(t);
        }
        for(Thread t:threads)t.start();
        for(Thread t:threads) {
            try {
                t.join(timeout.toMillis()*3);
            } catch(InterruptedException e) {
                Thread.currentThread().interrupt();
                failures.add(e);
            }
        }
        for(Thread t:threads) {
            if(t.isAlive()) {
                t.interrupt();
                failures.add(new ScheduleFailure("Java thread did not terminate: "+t.getName(),schedule,gate.trace()));
            }
        }
        try {
            gate.assertScheduleCompleted();
        } catch(Throwable t) {
            failures.add(t);
        }
        try {
            run.finalCheck().check();
        } catch(Throwable t) {
            failures.add(t);
        }
        return new RunResult(List.copyOf(schedule),gate.trace(),List.copyOf(failures));
    }
}
