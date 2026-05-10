package com.divideandconcur.examples;
import com.divideandconcur.core.*;
import java.util.*;
public final class BrokenBakeryNoTieBreakExample {
    private BrokenBakeryNoTieBreakExample() {} static final class BakeryState {
        final int[] number=new int[2];
        int inCritical=0;
    } static final class WorkerCode {
        private final BakeryState s;
        private final int id,other;
        private int observedMax;
        WorkerCode(BakeryState s,int id) {
            this.s=s;
            this.id=id;
            this.other=1-id;
        } void run(String tid,ScheduleGate gate) {
            gate.init(tid);
            observedMax=Math.max(s.number[0],s.number[1]);
            gate.barrier(tid);
            s.number[id]=observedMax+1;
            gate.barrier(tid);
            boolean mayEnter=s.number[other]==0 || s.number[id]<=s.number[other];
            if(mayEnter) {
                s.inCritical++;
            }
            gate.barrier(tid);
            if(mayEnter) {
                s.inCritical--;
                s.number[id]=0;
            }
            gate.end(tid);
        }
    }
    public static ExplorationResult run() {
        return DncExplorer.explore(Map.of("t0",4,"t1",4),ScheduleOptions.exhaustive(),
                gate-> {
            BakeryState s=new BakeryState();
            gate.addInvariant(
                    Invariant.that("mutual exclusion violated: both workers entered critical section", () -> s.inCritical <= 1));
            return new ScenarioRun(List.of(
                    new Worker("bakery-broken-t0", ()->new WorkerCode(s,0).run("t0",gate))
                    ,
                    new Worker("bakery-broken-t1",()->new WorkerCode(s,1).run("t1",gate)))
            );
        });
    }
}
