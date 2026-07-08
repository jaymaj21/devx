package com.codeanalytics;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * In-process metadata loaded from branch-probe CSV sidecars and class-to-file
 * TSVs. The shell uses this to turn class/path filters into probe id filters.
 */
public final class TraceMetadataRegistry {
    private final Map<Long, Probe> probesById = new HashMap<>();
    private final Map<String, String> classToPath = new HashMap<>();
    private final List<File> probeCsvFiles = new ArrayList<>();
    private final List<File> classMapFiles = new ArrayList<>();

    public void clear() {
        probesById.clear();
        classToPath.clear();
        probeCsvFiles.clear();
        classMapFiles.clear();
    }

    public int loadProbeCsv(File file) throws IOException {
        int loaded = 0;
        try (BufferedReader reader = Files.newBufferedReader(file.toPath(), StandardCharsets.UTF_8)) {
            String line;
            boolean first = true;
            while ((line = reader.readLine()) != null) {
                if (line.trim().isEmpty()) {
                    continue;
                }
                List<String> row = parseCsvLine(line);
                if (first && !row.isEmpty() && "id".equalsIgnoreCase(row.get(0))) {
                    first = false;
                    continue;
                }
                first = false;
                if (row.size() < 6) {
                    throw new IOException("Bad branch probe CSV row in " + file + ": " + line);
                }
                long id = Long.parseLong(row.get(0).trim());
                Probe probe = new Probe(id, row.get(1), row.get(2), row.get(3), row.get(4), row.get(5), file);
                probesById.put(id, probe);
                loaded++;
            }
        }
        probeCsvFiles.add(file);
        return loaded;
    }

    public int loadClassMap(File file) throws IOException {
        int loaded = 0;
        try (BufferedReader reader = Files.newBufferedReader(file.toPath(), StandardCharsets.UTF_8)) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.trim().isEmpty()) {
                    continue;
                }
                String[] parts = line.split("\\t", 2);
                if (parts.length != 2) {
                    throw new IOException("Bad class map row in " + file + ": " + line);
                }
                classToPath.put(parts[0].trim(), normalizePath(parts[1].trim()));
                loaded++;
            }
        }
        classMapFiles.add(file);
        return loaded;
    }

    public MetadataSummary summary() {
        MetadataSummary summary = new MetadataSummary();
        summary.probeCount = probesById.size();
        summary.classMapCount = classToPath.size();
        summary.probeCsvFiles = new ArrayList<>(probeCsvFiles);
        summary.classMapFiles = new ArrayList<>(classMapFiles);
        return summary;
    }

    public Set<Long> probeIdsForClassPatterns(Collection<String> patterns) {
        List<Pattern> compiled = compileGlobPatterns(patterns);
        Set<Long> ids = new LinkedHashSet<>();
        for (Probe probe : probesById.values()) {
            if (matchesAny(probe.className, compiled)) {
                ids.add(probe.id);
            }
        }
        return ids;
    }

    public Set<Long> probeIdsForPathPatterns(Collection<String> patterns) {
        List<Pattern> compiled = compileGlobPatterns(patterns);
        Set<Long> ids = new LinkedHashSet<>();
        for (Probe probe : probesById.values()) {
            String path = sourcePathForProbe(probe);
            if (path != null && matchesAny(path, compiled)) {
                ids.add(probe.id);
            }
        }
        return ids;
    }

    public Set<Long> probeIdsForMethodPatterns(Collection<String> patterns) {
        List<Pattern> compiled = compileGlobPatterns(patterns);
        Set<Long> ids = new LinkedHashSet<>();
        for (Probe probe : probesById.values()) {
            if (matchesAny(probe.method, compiled)) {
                ids.add(probe.id);
            }
        }
        return ids;
    }

    public Set<Long> probeIdsForWherePatterns(Collection<String> patterns) {
        List<Pattern> compiled = compileGlobPatterns(patterns);
        Set<Long> ids = new LinkedHashSet<>();
        for (Probe probe : probesById.values()) {
            if (matchesAny(probe.where, compiled)) {
                ids.add(probe.id);
            }
        }
        return ids;
    }

    public Set<Long> probeIdsForMixedFilters(Collection<String> filters) {
        Set<Long> ids = new LinkedHashSet<>();
        for (String filter : filters) {
            int colon = filter.indexOf(':');
            if (colon < 0) {
                ids.addAll(probeIdsForClassPatterns(Collections.singleton(filter)));
                continue;
            }
            String kind = filter.substring(0, colon).toLowerCase(Locale.ROOT);
            String value = filter.substring(colon + 1);
            if ("class".equals(kind)) {
                ids.addAll(probeIdsForClassPatterns(Collections.singleton(value)));
            } else if ("path".equals(kind) || "file".equals(kind)) {
                ids.addAll(probeIdsForPathPatterns(Collections.singleton(value)));
            } else if ("method".equals(kind)) {
                ids.addAll(probeIdsForMethodPatterns(Collections.singleton(value)));
            } else if ("where".equals(kind) || "kind".equals(kind)) {
                ids.addAll(probeIdsForWherePatterns(Collections.singleton(value)));
            } else if ("id".equals(kind) || "probe".equals(kind)) {
                addIdRange(ids, value);
            } else {
                throw new IllegalArgumentException("Unknown filter kind: " + kind);
            }
        }
        return ids;
    }

    public Set<Long> probeIdsForRanges(Collection<String> ranges) {
        Set<Long> ids = new LinkedHashSet<>();
        for (String range : ranges) {
            addIdRange(ids, range);
        }
        return ids;
    }

    public String describeProbeIds(Set<Long> ids, int limit) {
        StringBuilder out = new StringBuilder();
        List<Long> sorted = new ArrayList<>(ids);
        Collections.sort(sorted);
        int shown = Math.min(limit, sorted.size());
        for (int i = 0; i < shown; i++) {
            long id = sorted.get(i);
            Probe probe = probesById.get(id);
            out.append("  ").append(id);
            if (probe != null) {
                out.append(" ").append(probe.className).append(".").append(probe.method);
                if (probe.where != null && !probe.where.isEmpty()) {
                    out.append(" ").append(probe.where);
                }
                if (probe.line != null && !probe.line.isEmpty()) {
                    out.append(":").append(probe.line);
                }
                String path = sourcePathForProbe(probe);
                if (path != null) {
                    out.append(" ").append(path);
                }
            } else {
                out.append(" <no loaded metadata>");
            }
            out.append(System.lineSeparator());
        }
        if (sorted.size() > shown) {
            out.append("  ... ").append(sorted.size() - shown).append(" more").append(System.lineSeparator());
        }
        return out.toString();
    }

    private String sourcePathForProbe(Probe probe) {
        String mapped = classToPath.get(probe.className);
        if (mapped != null) {
            return mapped;
        }
        int nested = probe.className.indexOf('$');
        if (nested > 0) {
            mapped = classToPath.get(probe.className.substring(0, nested));
            if (mapped != null) {
                return mapped;
            }
        }
        if (probe.source == null || probe.source.isEmpty()) {
            return null;
        }
        int dot = probe.className.lastIndexOf('.');
        if (dot < 0) {
            return normalizePath(probe.source);
        }
        return normalizePath(probe.className.substring(0, dot).replace('.', '/') + "/" + probe.source);
    }

    private static void addIdRange(Set<Long> ids, String text) {
        TraceAnalyzer.Range range = TraceAnalyzer.Range.parse(text);
        for (long id = range.start; id <= range.end; id++) {
            ids.add(id);
        }
    }

    private static boolean matchesAny(String value, List<Pattern> patterns) {
        if (value == null) {
            return false;
        }
        String normalized = normalizePath(value);
        for (Pattern pattern : patterns) {
            if (pattern.matcher(normalized).matches()) {
                return true;
            }
        }
        return false;
    }

    private static List<Pattern> compileGlobPatterns(Collection<String> patterns) {
        List<Pattern> compiled = new ArrayList<>();
        for (String pattern : patterns) {
            compiled.add(Pattern.compile(globToRegex(normalizePath(pattern))));
        }
        return compiled;
    }

    private static String normalizePath(String text) {
        return text.replace('\\', '/');
    }

    private static String globToRegex(String glob) {
        StringBuilder regex = new StringBuilder("^");
        for (int i = 0; i < glob.length(); i++) {
            char c = glob.charAt(i);
            if (c == '*') {
                regex.append(".*");
            } else if (c == '?') {
                regex.append('.');
            } else if ("\\.[]{}()+-^$|".indexOf(c) >= 0) {
                regex.append('\\').append(c);
            } else {
                regex.append(c);
            }
        }
        regex.append('$');
        return regex.toString();
    }

    private static List<String> parseCsvLine(String line) {
        List<String> fields = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        boolean quoted = false;
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (quoted) {
                if (c == '"') {
                    if (i + 1 < line.length() && line.charAt(i + 1) == '"') {
                        current.append('"');
                        i++;
                    } else {
                        quoted = false;
                    }
                } else {
                    current.append(c);
                }
            } else if (c == '"') {
                quoted = true;
            } else if (c == ',') {
                fields.add(current.toString());
                current.setLength(0);
            } else {
                current.append(c);
            }
        }
        fields.add(current.toString());
        return fields;
    }

    public static final class MetadataSummary {
        public int probeCount;
        public int classMapCount;
        public List<File> probeCsvFiles;
        public List<File> classMapFiles;
    }

    private static final class Probe {
        final long id;
        final String className;
        final String method;
        final String where;
        final String source;
        final String line;
        final File csvFile;

        Probe(long id, String className, String method, String where, String source, String line, File csvFile) {
            this.id = id;
            this.className = className;
            this.method = method;
            this.where = where;
            this.source = source;
            this.line = line;
            this.csvFile = csvFile;
        }
    }
}
