package com.divideandconcur.core;
import org.junit.jupiter.api.Test;
import java.time.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.jupiter.api.Assertions.*;
class ScheduleGateTest {
    @Test void supportsInitBarrierEndWithoutExplicitBarrierIds() throws Exception {
        ScheduleGate gate=ScheduleGate.forSchedule(List.of(Turn.of("t1",0),
                Turn.of("t2",0),Turn.of("t1",1),Turn.of("t2",1)),Duration.ofSeconds(3));
        StringBuilder observed=new StringBuilder();
        AtomicReference<Throwable> failure=new AtomicReference<>();
        Thread t1=new Thread(()-> {try {
            gate.init("t1");
            observed.append("A");
            gate.barrier("t1");
            observed.append("B");
            gate.end("t1");
        } catch(Throwable t) {
            failure.compareAndSet(null,t);
        }
                                  });
        Thread t2=new Thread(()-> {try {
            gate.init("t2");
            observed.append("X");
            gate.barrier("t2");
            observed.append("Y");
            gate.end("t2");
        } catch(Throwable t) {
            failure.compareAndSet(null,t);
        }
                                  });
        t1.start();
        t2.start();
        t1.join();
        t2.join();
        gate.assertScheduleCompleted();
        assertNull(failure.get());
        assertEquals("AXBY",observed.toString());
    }
}
