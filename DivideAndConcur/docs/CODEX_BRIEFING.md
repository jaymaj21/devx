# Codex Briefing: DivideAndConcur

## Project

Maven Java 17 project.

Core package: `com.divideandconcur.core`

Examples package: `com.divideandconcur.examples`

## Core Classes

- `ScheduleGate`: core deterministic gate.
- `Turn`: `(threadId, segmentIndex)`.
- `ScheduleGenerator`: lazy recursive generator of order-preserving schedules.
- `ScheduleOptions`: generation constraints.
- `BeforeConstraint`: `a before b`.
- `DncExplorer`: runs schedules against worker scenarios.
- `ScenarioRun`: workers plus final assertion.
- `Worker`: Java thread body.
- `RunResult`: result of one schedule.
- `ExplorationResult`: aggregate over many schedules.
- `TraceEvent`: recorded start/complete/end events.
- `Invariant`: checked after every segment.

## API Semantics

User code does:

```java
gate.init("t1");
// segment 0
gate.barrier("t1");
// segment 1
gate.end("t1");
```

The gate maintains the segment counter. The schedule still uses explicit `Turn` objects such as `Turn.of("t1", 0)`.

## Critical Correctness Rule

The schedule index must advance only when a running thread completes a segment by reaching `barrier` or `end`.

Do not advance the schedule when a thread starts a segment.

## Next Improvements

1. JSON import/export for schedules.
2. Schedule minimisation for failing schedules.
3. JUnit 5 extension.
4. Read/write-set declarations for partial-order reduction.
5. State snapshot hooks and DOT graph export.
6. Annotation-based probe insertion.
7. CLI runner.
8. Fixed-version examples using `synchronized`, `ConcurrentHashMap.computeIfAbsent`, and `AtomicInteger`.
