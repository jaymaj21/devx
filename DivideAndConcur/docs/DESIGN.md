# DivideAndConcur Design

## Purpose

DivideAndConcur, abbreviated DnC, is a probe-guided deterministic concurrency testing framework.

The purpose is to let a developer take a concurrency-critical piece of Java code, insert a small number of scheduling probes, and then execute the resulting code under systematically generated interleavings.

## API

```java
gate.init("t1");
// segment 0

gate.barrier("t1");
// segment 1

gate.end("t1");
```

The current design removes explicit barrier ids from user code. The gate maintains a thread-specific counter internally.

## Execution Semantics

`init(tid)` starts segment 0 for logical thread `tid`.

`barrier(tid)` completes the current segment for `tid`, increments that thread's internal segment counter, and waits until the global schedule permits the next segment.

`end(tid)` completes the current segment and terminates the controlled region for that thread.

If a thread has `N` scheduled atomic segments, it has one `init`, `N - 1` internal `barrier` calls, and one `end`.

## Schedule Representation

```java
List.of(
    Turn.of("t1", 0),
    Turn.of("t2", 0),
    Turn.of("t1", 1),
    Turn.of("t2", 1)
)
```

This means:

```text
t1 executes segment 0
t2 executes segment 0
t1 executes segment 1
t2 executes segment 1
```

## Critical Correctness Rule

The schedule index advances only when the currently running thread completes its segment by calling `barrier` or `end`. It does not advance when the segment starts.

This prevents the next scheduled segment from starting before the current atomic segment has completed.

## Schedule Generation

`ScheduleGenerator` produces all order-preserving interleavings of per-thread segment sequences. It is lazy via `visitAll` and supports:

- `BeforeConstraint` via `requireBefore`;
- a rough preemption bound via `maxPreemptions`;
- `maxSchedules`.

For threads with segment counts `n1, n2, ..., nk`, the unconstrained schedule count is:

```text
(n1 + n2 + ... + nk)! / (n1! n2! ... nk!)
```

## Invariants

`ScheduleGate.addInvariant` registers checks run after every completed segment. Final assertions are placed in `ScenarioRun`.

## Limitations

DnC is an interleaving-level tester, not a Java Memory Model verifier. It explores interleavings at programmer-chosen probe points. It does not attempt to enumerate all outcomes caused by CPU reordering, JIT compilation, volatile/fence semantics, or weak-memory effects.

## Future Work

- JSON schedule import/export
- state snapshots
- DOT graph output
- schedule minimisation
- JUnit 5 extension
- read/write-set partial-order reduction
- annotation or bytecode-based probe insertion
- PlusCal/TLA+ export
