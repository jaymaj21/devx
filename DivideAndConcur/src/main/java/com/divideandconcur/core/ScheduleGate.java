package com.divideandconcur.core;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;

/** Core DivideAndConcur gate. User code calls init(tid), barrier(tid), end(tid). */
public final class ScheduleGate {
    private final ReentrantLock lock = new ReentrantLock(true);
    private final Condition changed = lock.newCondition();

    private final List<Turn> schedule;
    private final Duration stuckTimeout;
    private final List<TraceEvent> trace = new ArrayList<>();
    private final List<Invariant> invariants = new ArrayList<>();

    private final Map<String, Integer> currentSegmentByThread = new HashMap<>();
    private final Set<String> startedThreads = new HashSet<>();
    private final Set<String> endedThreads = new HashSet<>();

    private int currentScheduleIndex = 0;
    private String runningThreadId = null;
    private Turn runningTurn = null;
    private Throwable invariantFailure = null;

    private ScheduleGate(List<Turn> schedule, Duration stuckTimeout) {
        if (schedule.isEmpty()) {
            throw new IllegalArgumentException("schedule must not be empty");
        }
        this.schedule = List.copyOf(schedule);
        this.stuckTimeout = Objects.requireNonNull(stuckTimeout, "stuckTimeout");
    }

    public static ScheduleGate forSchedule(List<Turn> schedule) {
        return new ScheduleGate(schedule, Duration.ofSeconds(5));
    }

    public static ScheduleGate forSchedule(List<Turn> schedule, Duration stuckTimeout) {
        return new ScheduleGate(schedule, stuckTimeout);
    }

    public List<Turn> schedule() {
        return schedule;
    }

    public List<TraceEvent> trace() {
        lock.lock();
        try {
            return List.copyOf(trace);
        } finally {
            lock.unlock();
        }
    }

    public void addInvariant(Invariant invariant) {
        lock.lock();
        try {
            invariants.add(Objects.requireNonNull(invariant, "invariant"));
        } finally {
            lock.unlock();
        }
    }

    public void init(String threadId) {
        Objects.requireNonNull(threadId, "threadId");
        lock.lock();
        try {
            throwIfInvariantAlreadyFailed();
            if (startedThreads.contains(threadId)) {
                throw new DncException("Thread already initialised: " + threadId);
            }
            if (endedThreads.contains(threadId)) {
                throw new DncException("Thread already ended: " + threadId);
            }
            startedThreads.add(threadId);
            currentSegmentByThread.put(threadId, 0);
            waitAndStart(Turn.of(threadId, 0));
        } finally {
            lock.unlock();
        }
    }

    public void barrier(String threadId) {
        Objects.requireNonNull(threadId, "threadId");
        lock.lock();
        try {
            throwIfInvariantAlreadyFailed();
            requireStartedAndNotEnded(threadId);
            completeCurrentlyRunningSegmentFor(threadId);
            int next = currentSegmentByThread.get(threadId) + 1;
            currentSegmentByThread.put(threadId, next);
            waitAndStart(Turn.of(threadId, next));
        } finally {
            lock.unlock();
        }
    }

    public void end(String threadId) {
        Objects.requireNonNull(threadId, "threadId");
        lock.lock();
        try {
            throwIfInvariantAlreadyFailed();
            requireStartedAndNotEnded(threadId);
            completeCurrentlyRunningSegmentFor(threadId);
            endedThreads.add(threadId);
            trace.add(new TraceEvent(currentScheduleIndex, null, "ended " + threadId,
                                     Instant.now(), Thread.currentThread().getName()));
            changed.signalAll();
        } finally {
            lock.unlock();
        }
    }

    public void assertScheduleCompleted() {
        lock.lock();
        try {
            throwIfInvariantAlreadyFailed();
            if (runningThreadId != null) {
                throw new ScheduleFailure(
                    "Schedule not completed: " + runningThreadId + " is still running " + runningTurn +
                    ". Did that thread miss barrier() or end()?",
                    schedule,
                    trace);
            }
            if (currentScheduleIndex != schedule.size()) {
                throw new ScheduleFailure(
                    "Schedule not completed: consumed " + currentScheduleIndex + " of " + schedule.size() +
                    ". Next expected turn: " + schedule.get(currentScheduleIndex),
                    schedule,
                    trace);
            }
        } finally {
            lock.unlock();
        }
    }

    private void waitAndStart(Turn desired) {
        if (currentScheduleIndex >= schedule.size()) {
            throw new ScheduleFailure(
                "Thread " + desired.threadId() + " tried to start extra segment " +
                desired.segmentIndex() + " after schedule completed.",
                schedule,
                trace);
        }

        Instant deadline = Instant.now().plus(stuckTimeout);

        while (runningThreadId != null || !schedule.get(currentScheduleIndex).equals(desired)) {
            throwIfInvariantAlreadyFailed();
            long remaining = Duration.between(Instant.now(), deadline).toMillis();
            if (remaining <= 0) {
                throw stuck(desired);
            }
            try {
                changed.awaitNanos(Duration.ofMillis(remaining).toNanos());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new DncException("Interrupted while waiting to start " + desired, e);
            }
        }

        runningThreadId = desired.threadId();
        runningTurn = desired;
        trace.add(new TraceEvent(currentScheduleIndex, desired, "started",
                                 Instant.now(), Thread.currentThread().getName()));
        changed.signalAll();
    }

    private void completeCurrentlyRunningSegmentFor(String threadId) {
        if (!threadId.equals(runningThreadId)) {
            throw new ScheduleFailure(
                "Thread " + threadId + " called barrier/end, but currently running thread is " +
                runningThreadId + ". This usually means barrier/end was called without matching init, " +
                "or a thread reached a DnC call outside its scheduled segment.",
                schedule,
                trace);
        }

        Turn completed = runningTurn;
        trace.add(new TraceEvent(currentScheduleIndex, completed, "completed",
                                 Instant.now(), Thread.currentThread().getName()));

        try {
            for (Invariant invariant : invariants) {
                invariant.check();
            }
        } catch (Throwable t) {
            invariantFailure = t;
            changed.signalAll();
            throw new ScheduleFailure("Invariant failed after " + completed + ": " + t.getMessage(),
                                      t, schedule, trace);
        }

        runningThreadId = null;
        runningTurn = null;
        currentScheduleIndex++;
        changed.signalAll();
    }

    private void requireStartedAndNotEnded(String threadId) {
        if (!startedThreads.contains(threadId)) {
            throw new DncException("Thread has not called init: " + threadId);
        }
        if (endedThreads.contains(threadId)) {
            throw new DncException("Thread has already called end: " + threadId);
        }
    }

    private void throwIfInvariantAlreadyFailed() {
        if (invariantFailure != null) {
            throw new ScheduleFailure("Another thread already observed invariant failure: " +
                                      invariantFailure.getMessage(), invariantFailure, schedule, trace);
        }
    }

    private ScheduleFailure stuck(Turn desired) {
        String next = currentScheduleIndex < schedule.size()
                      ? schedule.get(currentScheduleIndex).toString()
                      : "<schedule complete>";
        String message = "Timed out while trying to start " + desired + ".\n" +
                         "Current schedule index: " + currentScheduleIndex + "\n" +
                         "Next expected turn: " + next + "\n" +
                         "Currently running thread: " + runningThreadId + "\n" +
                         "Currently running turn: " + runningTurn + "\n" +
                         "Possible causes: missing init/barrier/end, bad schedule, deadlock inside a segment, " +
                         "or a thread exception before it reached the next DnC call.";
        return new ScheduleFailure(message, schedule, trace);
    }
}
