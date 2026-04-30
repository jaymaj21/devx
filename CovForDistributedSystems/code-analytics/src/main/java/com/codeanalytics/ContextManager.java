package com.codeanalytics;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class ContextManager {
    // Thread-safe set of current contexts
    private static final Set<String> currentContexts = ConcurrentHashMap.newKeySet();

    // Bijective mapping from context sets (as immutable TreeSets) to unique context ids
    public static final Map<Set<String>, Integer> contextSetToId = new ConcurrentHashMap<>();

    // Next context set id to assign (starts from 2, since 1 is reserved for the empty set)
    private static final AtomicInteger nextContextId = new AtomicInteger(2);

    // Current active context set id (volatile for cross-thread visibility)
    private static volatile int currentContextSetId = 1;

    // Hit counter: key is [appId, instanceId, contextSetId, locationId], value is count
    public static final Map<List<Integer>, Integer> hitCounts = new ConcurrentHashMap<>();

    static {
        // Ensure empty set has id 1 at startup
        contextSetToId.put(Collections.emptySet(), 1);
        currentContextSetId = 1;
    }

    // --- Context Management Methods ---

    // Apply a context (add to current context set)
    public static void applyContext(String ctx) {
        currentContexts.add(ctx);
        updateContextSetId();
    }

    // Withdraw a context (remove from current context set)
    public static void withdrawContext(String ctx) {
        currentContexts.remove(ctx);
        updateContextSetId();
    }

    // Assign or get a unique context id for the current context set
    private static int getOrAssignContextSetId(Set<String> ctxSet) {
        // Canonicalize as unmodifiable TreeSet (order-independent)
        Set<String> canonical = Collections.unmodifiableSet(new TreeSet<>(ctxSet));
        Integer id = contextSetToId.get(canonical);
        if (id == null) {
            id = nextContextId.getAndIncrement();
            contextSetToId.put(canonical, id);
        }
        return id;
    }

    // Update the currentContextSetId after any change in contexts
    private static void updateContextSetId() {
        currentContextSetId = getOrAssignContextSetId(currentContexts);
    }

    // Get the current context set id (for hit tagging)
    public static int getCurrentContextSetId() {
        return currentContextSetId;
    }

    // Get a snapshot of the current contexts (as a TreeSet for stable representation)
    public static Set<String> getCurrentContexts() {
        return new TreeSet<>(currentContexts);
    }

    // --- Hit Counting Methods ---

    // Record a hit for the given app, instance, and location (uses current context id)
    public static void recordHit(int appId, int instanceId, int locationId) {
        int ctxId = currentContextSetId;
        List<Integer> key = Arrays.asList(appId, instanceId, ctxId, locationId);
        hitCounts.merge(key, 1, Integer::sum);
    }

    // For testing: record a hit for a specified context set id (optional utility)
    public static void recordHit(int appId, int instanceId, int contextSetId, int locationId) {
        List<Integer> key = Arrays.asList(appId, instanceId, contextSetId, locationId);
        hitCounts.merge(key, 1, Integer::sum);
    }

    // --- Introspection Methods (for report generation, debugging, etc.) ---

    // Return a copy of contextSetToId (id -> set), sorted by context id
    public static Map<Integer, Set<String>> getIdToContextSetMap() {
        Map<Integer, Set<String>> idToSet = new TreeMap<>();
        for (Map.Entry<Set<String>, Integer> entry : contextSetToId.entrySet()) {
            idToSet.put(entry.getValue(), entry.getKey());
        }
        return idToSet;
    }

    // Return a copy of the hitCounts map
    public static Map<List<Integer>, Integer> getHitCountsSnapshot() {
        return new HashMap<>(hitCounts);
    }
}
