# DivideAndConcur Usage Guide

## Instrument existing code

```java
gate.init("t1");
local = counter.value;

gate.barrier("t1");
counter.value = local + 1;

gate.end("t1");
```

The thread id is a logical id. It does not have to be the actual Java thread name.

## Define segment counts

```java
Map.of("t1", 2, "t2", 2)
```

This means each logical thread has two atomic segments.

## Explore all schedules

```java
ExplorationResult result = DncExplorer.explore(
    Map.of("t1", 2, "t2", 2),
    ScheduleOptions.exhaustive(),
    gate -> {
        Counter counter = new Counter();
        Worker t1 = new Worker("java-t1", () -> new Inc(counter).run("t1", gate));
        Worker t2 = new Worker("java-t2", () -> new Inc(counter).run("t2", gate));
        return new ScenarioRun(List.of(t1, t2),
            () -> Assertions.check(counter.value == 2, "lost update"));
    }
);
```

## Run one prescribed schedule

```java
RunResult result = DncExplorer.runOneSchedule(
    List.of(Turn.of("t1", 0), Turn.of("t2", 0), Turn.of("t1", 1), Turn.of("t2", 1)),
    gate -> ...
);
```

## Add constraints

```java
ScheduleOptions options = ScheduleOptions.exhaustive()
    .requireBefore(Turn.of("t1", 0), Turn.of("t2", 1))
    .maxPreemptions(1);
```

## Modelling discipline

Code between DnC calls is treated as atomic. Place probes around the operations where a context switch is semantically meaningful.
