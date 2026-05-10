# DivideAndConcur

**DivideAndConcur** (**DnC**) is a Java prototype for deterministic, probe-guided concurrency testing.

The core idea is to divide concurrent code into semantic atomic segments and then systematically concur those segments under generated or prescribed schedules.

```java
gate.init("t1");
// segment 0

gate.barrier("t1");
// segment 1

gate.barrier("t1");
// segment 2

gate.end("t1");
```

The developer does not need to rewrite existing code as lambdas. In many cases, they can copy a concurrency-critical method into a test harness and insert `init`, `barrier`, and `end` calls.

## Run

```bash
mvn test
mvn exec:java
```

The example suite includes:

- a lost-update bug;
- a check-then-act lazy-initialisation bug;
- a constrained schedule example;
- a Lamport bakery-style mutual exclusion sketch;
- a broken bakery/no-tie-breaker example that exposes a mutual exclusion violation.

See `docs/` and `paper/` for design documentation and an academic-style LaTeX paper.
