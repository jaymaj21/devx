package com.divideandconcur.examples;
import com.divideandconcur.core.*;
import java.util.*;
public final class LazyInitBugExample {
    private LazyInitBugExample() {} static final class Registry {
        final Map<String,Object> states=new HashMap<>();
        int constructed=0;
    } static final class ExistingLazyInitProcedure {
        private final Registry registry;
        private boolean missing;
        ExistingLazyInitProcedure(Registry r) {
            registry=r;
        } void getOrCreate(String tid,ScheduleGate gate) {
            gate.init(tid);
            missing=!registry.states.containsKey("IBM");
            gate.barrier(tid);
            if(missing) {
                registry.constructed++;
                registry.states.put("IBM",new Object());
            }
            gate.end(tid);
        }
    }
    public static ExplorationResult run() {
        return DncExplorer.explore(Map.of("t1",2,"t2",2),ScheduleOptions.exhaustive(),
                gate-> {
            Registry r=new Registry();
            return new ScenarioRun(List.of(
                    new Worker("lazy-t1",()->new ExistingLazyInitProcedure(r).getOrCreate("t1",gate)),
                    new Worker("lazy-t2",()->new ExistingLazyInitProcedure(r).getOrCreate("t2",gate))
                     ),
                    ()->Assertions.check(r.constructed==1,"expected exactly one construction, observed "+ r.constructed));
        });
    }
}
