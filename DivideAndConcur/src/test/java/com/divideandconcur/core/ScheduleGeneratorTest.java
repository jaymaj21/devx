package com.divideandconcur.core;
import org.junit.jupiter.api.Test;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import static org.junit.jupiter.api.Assertions.*;
class ScheduleGeneratorTest {
    @Test void generatesAllTwoByTwoInterleavings() {
        List<List<Turn>> schedules=ScheduleGenerator.all(Map.of("t1",2,"t2",2));
        assertEquals(6,schedules.size());
        assertTrue(schedules.contains(List.of(Turn.of("t1",0),Turn.of("t1",1),Turn.of("t2",0),Turn.of("t2",1))));
        assertTrue(schedules.contains(List.of(Turn.of("t1",0),Turn.of("t2",0),Turn.of("t1",1),Turn.of("t2",1))));
    } @Test void beforeConstraintFiltersSchedules() {
        List<List<Turn>> schedules=new ArrayList<>();
        ScheduleGenerator.visitAll(Map.of("t1",2,"t2",2),ScheduleOptions.exhaustive().requireBefore(Turn.of("t1",0),Turn.of("t2",1)),s-> {schedules.add(s); return true;});
        for(List<Turn> s:schedules) assertTrue(s.indexOf(Turn.of("t1",0))<s.indexOf(Turn.of("t2",1)));
    } @Test void lazyVisitorCanStopEarly() {
        AtomicLong visited=new AtomicLong();
        ScheduleGenerator.visitAll(Map.of("t1",4,"t2",4),ScheduleOptions.exhaustive(),s->visited.incrementAndGet()<3);
        assertEquals(3,visited.get());
    }
}
