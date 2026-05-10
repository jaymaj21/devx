package com.divideandconcur.examples;
import com.divideandconcur.core.*;
import java.util.*;
/** Bounded Lamport-bakery-style mutual exclusion sketch with choosing flag and lexicographic tie-breaker. This checks safety, not liveness. */
public final class BakerySketchCorrectExample {
    private BakerySketchCorrectExample() {} static final class BakeryState {
        final boolean[] choosing=new boolean[2];
        final int[] number=new int[2];
        int inCritical=0;
        int entries=0;
    }
    static final class WorkerCode {
        private final BakeryState s;
        private final int id,other;
        private int observedMax;
        WorkerCode(BakeryState s,int id) {
            this.s=s;
            this.id=id;
            this.other=1-id;
        } void run(String tid,ScheduleGate gate) {
            gate.init(tid);
            s.choosing[id]=true;
            gate.barrier(tid);
            observedMax=Math.max(s.number[0],s.number[1]);
            gate.barrier(tid);
            s.number[id]=observedMax+1;
            gate.barrier(tid);
            s.choosing[id]=false;
            gate.barrier(tid);
            boolean mayEnter=!s.choosing[other] && (s.number[other]==0 || less(id,s.number[id],other,s.number[other]));
            if(mayEnter) {
                s.inCritical++;
                s.entries++;
            }
            gate.barrier(tid);
            if(mayEnter) {
                s.inCritical--;
                s.number[id]=0;
            }
            gate.end(tid);
        } private boolean less(int idA,int ticketA,int idB,int ticketB) {
            return ticketA<ticketB || (ticketA==ticketB && idA<idB);
        }
    }
    public static ExplorationResult run() {
        return DncExplorer.explore(Map.of("t0",6,"t1",6),ScheduleOptions.exhaustive(),
                gate-> {
            BakeryState s=new BakeryState();
            gate.addInvariant(Invariant.that("mutual exclusion violated in correct bakery sketch",
                    () -> s.inCritical <= 1));
            return new ScenarioRun(List.of(
                    new Worker("bakery-correct-t0",()->new WorkerCode(s,0).run("t0",gate)),
                    new Worker("bakery-correct-t1",()->new WorkerCode(s,1).run("t1",gate))));
        });
    }
}
