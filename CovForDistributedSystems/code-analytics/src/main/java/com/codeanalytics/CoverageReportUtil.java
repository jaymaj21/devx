package com.codeanalytics;

import java.io.*;
import java.util.*;
import java.util.concurrent.*;

public class CoverageReportUtil {
    // This method should be called by the ClojureShell
    public static String writeCoverageReport(int appId, int instanceId, String filename) {
        // Invert contextSetToId to id -> set
        Map<Integer, Set<String>> idToContextSet = new TreeMap<>();
        for (Map.Entry<Set<String>, Integer> entry : ContextManager.contextSetToId.entrySet()) {
            idToContextSet.put(entry.getValue(), entry.getKey());
        }

        // Gather hits for given app and instance
        List<String> hitLines = new ArrayList<>();
        int hitCount = 0;
        for (Map.Entry<List<Integer>, Integer> entry : ContextManager.hitCounts.entrySet()) {
            List<Integer> key = entry.getKey();
            if (key.get(0) == appId && key.get(1) == instanceId) {
                int ctxId = key.get(2);
                int locId = key.get(3);
                int count = entry.getValue();
                hitLines.add(String.format("%d %d %d", ctxId, locId, count));
                hitCount++;
            }
        }
        hitLines.sort(Comparator.naturalOrder()); // context id, location id, count

        // Write report
        try (PrintWriter out = new PrintWriter(new FileWriter(filename))) {
            // Contexts section
            out.printf("CONTEXTS %d%n", idToContextSet.size());
            for (Map.Entry<Integer, Set<String>> entry : idToContextSet.entrySet()) {
                int ctxId = entry.getKey();
                Set<String> ctxSet = entry.getValue();
                String label;
                if (ctxId == 1) {
                    label = "default";
                } else {
                    label = String.join(",", new TreeSet<>(ctxSet));
                }
                out.printf("%d %s%n", ctxId, label);
            }
            // Hits section
            out.printf("HITS %d%n", hitCount);
            for (String line : hitLines) {
                out.println(line);
            }
            return "Coverage report written to " + filename;
        } catch (IOException e) {
            return "ERROR writing report: " + e.getMessage();
        }
    }
}
