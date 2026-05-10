package com.divideandconcur.examples;
import com.divideandconcur.core.*;
import java.util.*;
public final class LostUpdateExample {
    private LostUpdateExample() {}
    static final class Counter {
        int value=0;
    }

    static final class ExistingIncrementProcedure {
        private final Counter counter;
        private int local;
        ExistingIncrementProcedure(Counter c) {
            counter=c;
        } void increment(String tid,ScheduleGate gate) {
            gate.init(tid);
            local=counter.value;
            gate.barrier(tid);
            counter.value=local+1;
            gate.end(tid);
        }
    }

    public static ExplorationResult run() {
        return DncExplorer.explore(Map.of("t1",2,"t2",2),ScheduleOptions.exhaustive(),
                gate-> {
            Counter counter=new Counter(); Worker t1=new Worker("java-t1",
                            ()->new ExistingIncrementProcedure(counter).increment("t1",gate));
            Worker t2=new Worker("java-t2",()->new ExistingIncrementProcedure(counter).increment("t2",gate));
            return new ScenarioRun(List.of(t1,t2),
                    ()->Assertions.check(counter.value==2,"lost update: expected counter=2, observed counter="+counter.value));
        });
    }
}
