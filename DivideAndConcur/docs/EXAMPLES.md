# DivideAndConcur Examples

## Lost Update

Source: `LostUpdateExample.java`

Failing schedule:

```text
t1:0, t2:0, t1:1, t2:1
```

Meaning:

```text
t1 reads 0
t2 reads 0
t1 writes 1
t2 writes 1
```

## Lazy Initialisation Race

Source: `LazyInitBugExample.java`

Exposes:

```text
t1 checks: missing
t2 checks: missing
t1 constructs
t2 constructs
```

## Constrained Schedule

Source: `ConstrainedScheduleExample.java`

Demonstrates `requireBefore` and `maxPreemptions`.

## Bakery Sketch with Correct Tie-Breaker

Source: `BakerySketchCorrectExample.java`

This is a bounded safety sketch of Lamport's bakery idea. It includes:

- a `choosing[id]` flag;
- ticket selection;
- lexicographic comparison of `(ticket, process-id)`;
- a critical-section invariant `inCritical <= 1`.

It is not a full liveness proof because the waiting loop is represented by a bounded entry check. Across the bounded schedules explored by the example, the mutual-exclusion invariant holds.

## Broken Bakery Without Tie-Breaker

Source: `BrokenBakeryNoTieBreakExample.java`

Uses `number[id] <= number[other]` and ignores the process-id tie-breaker. DnC finds a mutual exclusion violation.
