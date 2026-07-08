package com.codeanalytics;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Fast streaming analyzer for HITTRC01 trace files written by HitTraceWriter.
 *
 * The analyzer does not materialize all trace records. Summary mode keeps only
 * counters and top-key maps; histogram mode uses two passes so massive files do
 * not require a timestamp list in memory.
 */
public final class TraceAnalyzer {
    private static final String MAGIC = "HITTRC01";
    private static final int INPUT_BUFFER_BYTES = 1 << 20;

    private TraceAnalyzer() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            usage(System.err);
            System.exit(2);
        }

        String command = args[0].toLowerCase();
        File traceFile = new File(args[1]);

        switch (command) {
            case "summary":
                Options summaryOptions = Options.parse(args, 2);
                printSummary(traceFile, summaryOptions, System.out);
                break;
            case "dump":
                Options dumpOptions = Options.parse(args, 2);
                dump(traceFile, dumpOptions, System.out);
                break;
            case "histogram":
                Options histogramOptions = Options.parse(args, 2);
                printHistogram(traceFile, histogramOptions, System.out);
                break;
            case "subset":
                if (args.length < 6) {
                    usage(System.err);
                    System.exit(2);
                }
                File targetFile = new File(args[2]);
                int preContext = Integer.parseInt(args[3]);
                int postContext = Integer.parseInt(args[4]);
                List<Range> ranges = parseRanges(args, 5);
                SubsetResult result = saveSubset(traceFile, targetFile, preContext, postContext, ranges);
                printSubsetResult(result, System.out);
                break;
            default:
                usage(System.err);
                System.exit(2);
        }
    }

    private static void usage(PrintStream err) {
        err.println("Usage:");
        err.println("  java com.codeanalytics.TraceAnalyzer summary <trace-file> [--top N]");
        err.println("  java com.codeanalytics.TraceAnalyzer dump <trace-file> [--limit N]");
        err.println("  java com.codeanalytics.TraceAnalyzer histogram <trace-file> [--buckets N]");
        err.println("  java com.codeanalytics.TraceAnalyzer subset <source-trace> <target-trace> <pre> <post> <range>...");
    }

    public static void printSummary(File file, PrintStream out, int top) throws IOException {
        printSummary(file, Options.withTop(top), out);
    }

    public static void printDump(File file, PrintStream out, long limit) throws IOException {
        dump(file, Options.withLimit(limit), out);
    }

    public static void printHistogram(File file, PrintStream out, int buckets) throws IOException {
        printHistogram(file, Options.withBuckets(buckets), out);
    }

    public static SubsetResult saveSubset(File sourceFile, File targetFile, int preContext, int postContext, List<Range> locationRanges) throws IOException {
        if (preContext < 0 || postContext < 0) {
            throw new IllegalArgumentException("pre/post context must be non-negative");
        }
        if (locationRanges.isEmpty()) {
            throw new IllegalArgumentException("at least one probe-id/locationId range is required");
        }
        return saveSubsetMatching(sourceFile, targetFile, preContext, postContext, value -> matchesAny(value, locationRanges));
    }

    public static SubsetResult saveSubsetMatching(File sourceFile, File targetFile, int preContext, int postContext, LocationMatcher matcher) throws IOException {
        if (preContext < 0 || postContext < 0) {
            throw new IllegalArgumentException("pre/post context must be non-negative");
        }

        List<HitInterval> intervals = findMatchingHitIntervals(sourceFile, preContext, postContext, matcher);
        SubsetResult result = new SubsetResult();
        result.sourceFile = sourceFile;
        result.targetFile = targetFile;
        result.matchingHitWindows = intervals.size();

        try (TraceFileWriter writer = new TraceFileWriter(targetFile)) {
            readTrace(sourceFile, new TraceVisitor() {
                long hitOrdinal;
                int intervalIndex;

                @Override
                public void header(long fileStartMillis, int endian) throws IOException {
                    writer.writeHeader(fileStartMillis);
                    result.fileStartMillis = fileStartMillis;
                }

                @Override
                public void record(int flag, int source, long nanoTime, byte[] payload) throws IOException {
                    result.sourceOuterRecords++;
                    if (flag == HitTraceWriter.FLAG_HIT) {
                        FilteredPayload filtered = filterHitPayload(payload, hitOrdinal, intervals, intervalIndex);
                        hitOrdinal = filtered.nextHitOrdinal;
                        intervalIndex = filtered.nextIntervalIndex;
                        result.sourceHitMessages += filtered.seenHitMessages;
                        result.writtenHitMessages += filtered.writtenHitMessages;
                        if (filtered.payload.length > 0) {
                            writer.writeRecord(flag, source, nanoTime, filtered.payload);
                            result.writtenOuterRecords++;
                        }
                    } else if (isInsideInterval(hitOrdinal, intervals, intervalIndex)) {
                        writer.writeRecord(flag, source, nanoTime, payload);
                        result.writtenOuterRecords++;
                    }
                }
            });
        }

        return result;
    }

    public interface LocationMatcher {
        boolean matches(long locationId);
    }

    public static List<Range> parseRanges(String[] args, int offset) {
        List<Range> ranges = new ArrayList<>();
        for (int i = offset; i < args.length; i++) {
            ranges.add(Range.parse(args[i]));
        }
        return ranges;
    }

    public static void printSubsetResult(SubsetResult result, PrintStream out) {
        out.println("Trace subset written: " + result.targetFile.getPath());
        out.println("  Source: " + result.sourceFile.getPath());
        out.println("  Matching/context windows: " + result.matchingHitWindows);
        out.println("  Source outer records scanned: " + result.sourceOuterRecords);
        out.println("  Source HIT messages scanned: " + result.sourceHitMessages);
        out.println("  Written outer records: " + result.writtenOuterRecords);
        out.println("  Written HIT messages: " + result.writtenHitMessages);
    }

    private static void printSummary(File file, Options options, PrintStream out) throws IOException {
        Summary summary = analyze(file);
        int top = options.top;

        out.println("Trace file: " + file.getPath());
        out.println("Header:");
        out.println("  File start UTC: " + Instant.ofEpochMilli(summary.fileStartMillis));
        out.println("  Endianness: big-endian");
        out.println();
        out.println("Outer records:");
        out.println("  Total: " + summary.records);
        out.println("  HIT: " + summary.hitRecords);
        out.println("  LOG: " + summary.logRecords);
        out.println("  TS: " + summary.tsRecords);
        out.println("  CTX attach: " + summary.ctxAttachRecords);
        out.println("  CTX withdraw: " + summary.ctxWithdrawRecords);
        out.println("  Other: " + summary.otherRecords);
        out.println();
        out.println("Inner messages:");
        out.println("  HIT messages: " + summary.hitMessages);
        out.println("  LOG messages: " + summary.logMessages);
        out.println("  CTX attach messages: " + summary.ctxAttachMessages);
        out.println("  CTX withdraw messages: " + summary.ctxWithdrawMessages);
        out.println("  Unknown inner messages: " + summary.unknownInnerMessages);
        out.println("  Truncated payloads/messages: " + summary.truncatedMessages);

        if (summary.firstNano != Long.MIN_VALUE && summary.lastNano != Long.MIN_VALUE) {
            long durationNs = summary.lastNano - summary.firstNano;
            double durationSecs = durationNs / 1_000_000_000.0d;
            out.println();
            out.println("Timing:");
            out.println("  First record UTC approx: " + Instant.ofEpochMilli(summary.fileStartMillis));
            out.println("  Last record UTC approx:  " + Instant.ofEpochMilli(summary.fileStartMillis + (durationNs / 1_000_000L)));
            out.printf("  Duration: %.6f seconds%n", durationSecs);
            if (durationSecs > 0.0d && summary.hitMessages > 0) {
                out.printf("  Average hit rate: %.2f hits/sec%n", summary.hitMessages / durationSecs);
            }
        }

        printTop(out, "Top app/instance pairs:", summary.appCounts, top);
        printTop(out, "Top locations:", summary.locationCounts, top);

        out.println();
        out.println("Cardinality:");
        out.println("  Unique app/instance/thread keys: " + summary.threadKeys.size());
        out.println("  Unique stack depths: " + summary.stackDepths.size());
    }

    private static <K> void printTop(PrintStream out, String title, Map<K, Long> counts, int limit) {
        if (counts.isEmpty()) {
            return;
        }
        out.println();
        out.println(title);
        List<Map.Entry<K, Long>> entries = new ArrayList<>(counts.entrySet());
        entries.sort(Map.Entry.<K, Long>comparingByValue().reversed());
        int n = Math.min(limit, entries.size());
        for (int i = 0; i < n; i++) {
            Map.Entry<K, Long> entry = entries.get(i);
            out.println("  " + entry.getKey() + " -> " + entry.getValue() + " hits");
        }
    }

    private static Summary analyze(File file) throws IOException {
        Summary summary = new Summary();
        readTrace(file, new TraceVisitor() {
            @Override
            public void header(long fileStartMillis, int endian) {
                summary.fileStartMillis = fileStartMillis;
            }

            @Override
            public void record(int flag, int source, long nanoTime, byte[] payload) {
                summary.records++;
                if (summary.firstNano == Long.MIN_VALUE) {
                    summary.firstNano = nanoTime;
                }
                summary.lastNano = nanoTime;

                switch (flag) {
                    case HitTraceWriter.FLAG_HIT:
                        summary.hitRecords++;
                        parseInnerMessages(payload, summary);
                        break;
                    case HitTraceWriter.FLAG_LOG:
                        summary.logRecords++;
                        parseInnerMessages(payload, summary);
                        break;
                    case HitTraceWriter.FLAG_CTX_ATTACH:
                        summary.ctxAttachRecords++;
                        summary.ctxAttachMessages++;
                        break;
                    case HitTraceWriter.FLAG_CTX_WITHDRAW:
                        summary.ctxWithdrawRecords++;
                        summary.ctxWithdrawMessages++;
                        break;
                    case HitTraceWriter.FLAG_TS:
                        summary.tsRecords++;
                        break;
                    default:
                        summary.otherRecords++;
                        break;
                }
            }
        });
        return summary;
    }

    private static void dump(File file, Options options, PrintStream out) throws IOException {
        readTrace(file, new TraceVisitor() {
            long index;
            long shown;

            @Override
            public void header(long fileStartMillis, int endian) {
                out.printf("# start=%d (%s) endian=%d%n", fileStartMillis, Instant.ofEpochMilli(fileStartMillis), endian);
            }

            @Override
            public void record(int flag, int source, long nanoTime, byte[] payload) {
                if (shown >= options.limit) {
                    index++;
                    return;
                }
                String sourceName = sourceName(source);
                if (flag == HitTraceWriter.FLAG_TS && payload.length == 8) {
                    out.printf("[%08d] flag=%d src=%s t(nanos)=%d len=%d TS %s%n",
                            index++, flag, sourceName, nanoTime, payload.length, Instant.ofEpochMilli(u64(payload, 0)));
                    shown++;
                    return;
                }
                List<String> messages = parsePayloadForDump(payload);
                if (messages.isEmpty()) {
                    out.printf("[%08d] flag=%d src=%s t(nanos)=%d len=%d hex=%s%n",
                            index, flag, sourceName, nanoTime, payload.length, hex(payload, Math.min(payload.length, 32)));
                } else {
                    for (String message : messages) {
                        out.printf("[%08d] flag=%d src=%s t(nanos)=%d len=%d %s%n",
                                index, flag, sourceName, nanoTime, payload.length, message);
                    }
                }
                index++;
                shown++;
            }
        });
    }

    private static void printHistogram(File file, Options options, PrintStream out) throws IOException {
        TimeRange range = hitTimeRange(file);
        if (range.hitCount == 0) {
            out.println("No HIT messages found.");
            return;
        }

        long[] buckets = new long[options.buckets];
        long interval = Math.max(1L, range.maxNano - range.minNano);
        readTrace(file, new TraceVisitor() {
            @Override
            public void record(int flag, int source, long nanoTime, byte[] payload) {
                if (flag != HitTraceWriter.FLAG_HIT) {
                    return;
                }
                long hitsInFrame = countHits(payload);
                if (hitsInFrame == 0) {
                    return;
                }
                int bucket = (int) (((nanoTime - range.minNano) * (long) buckets.length) / interval);
                if (bucket < 0) {
                    bucket = 0;
                } else if (bucket >= buckets.length) {
                    bucket = buckets.length - 1;
                }
                buckets[bucket] += hitsInFrame;
            }
        });

        out.println("Hit histogram:");
        out.println("  Hits: " + range.hitCount);
        out.printf("  Range: %.6f seconds%n", (range.maxNano - range.minNano) / 1_000_000_000.0d);
        out.println("  Buckets: " + buckets.length);
        for (int i = 0; i < buckets.length; i++) {
            double start = ((range.maxNano - range.minNano) / 1_000_000_000.0d) * i / buckets.length;
            double end = ((range.maxNano - range.minNano) / 1_000_000_000.0d) * (i + 1) / buckets.length;
            out.printf("%4d  %.6f..%.6f  %d%n", i, start, end, buckets[i]);
        }
    }

    private static TimeRange hitTimeRange(File file) throws IOException {
        TimeRange range = new TimeRange();
        readTrace(file, new TraceVisitor() {
            @Override
            public void record(int flag, int source, long nanoTime, byte[] payload) {
                if (flag != HitTraceWriter.FLAG_HIT) {
                    return;
                }
                long hits = countHits(payload);
                if (hits == 0) {
                    return;
                }
                range.hitCount += hits;
                range.minNano = Math.min(range.minNano, nanoTime);
                range.maxNano = Math.max(range.maxNano, nanoTime);
            }
        });
        return range;
    }

    private static List<HitInterval> findMatchingHitIntervals(File file, int preContext, int postContext, LocationMatcher matcher) throws IOException {
        List<HitInterval> intervals = new ArrayList<>();
        readTrace(file, new TraceVisitor() {
            long hitOrdinal;

            @Override
            public void record(int flag, int source, long nanoTime, byte[] payload) {
                if (flag != HitTraceWriter.FLAG_HIT) {
                    return;
                }
                int pos = 0;
                while (pos + 2 <= payload.length) {
                    int msgType = u16(payload, pos);
                    if (msgType == 1) {
                        if (pos + 20 > payload.length) {
                            return;
                        }
                        long locationId = u32(payload, pos + 16);
                        if (matcher.matches(locationId)) {
                            addInterval(intervals, Math.max(0L, hitOrdinal - preContext), hitOrdinal + postContext);
                        }
                        hitOrdinal++;
                        pos += 20;
                    } else if (msgType == 2) {
                        if (pos + 18 > payload.length) {
                            return;
                        }
                        int msgLen = u16(payload, pos + 16);
                        if (pos + 18 + msgLen > payload.length) {
                            return;
                        }
                        pos += 18 + msgLen;
                    } else {
                        return;
                    }
                }
            }
        });
        return intervals;
    }

    private static FilteredPayload filterHitPayload(byte[] payload, long startHitOrdinal, List<HitInterval> intervals, int intervalIndex) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(payload.length);
        long hitOrdinal = startHitOrdinal;
        long seenHits = 0L;
        long writtenHits = 0L;
        int pos = 0;
        int idx = intervalIndex;

        while (pos + 2 <= payload.length) {
            idx = advanceInterval(hitOrdinal, intervals, idx);
            int msgType = u16(payload, pos);
            if (msgType == 1) {
                if (pos + 20 > payload.length) {
                    break;
                }
                seenHits++;
                if (isInsideInterval(hitOrdinal, intervals, idx)) {
                    out.write(payload, pos, 20);
                    writtenHits++;
                }
                hitOrdinal++;
                pos += 20;
            } else if (msgType == 2) {
                if (pos + 18 > payload.length) {
                    break;
                }
                int msgLen = u16(payload, pos + 16);
                int len = 18 + msgLen;
                if (pos + len > payload.length) {
                    break;
                }
                if (isInsideInterval(hitOrdinal, intervals, idx)) {
                    out.write(payload, pos, len);
                }
                pos += len;
            } else {
                break;
            }
        }

        FilteredPayload filtered = new FilteredPayload();
        filtered.payload = out.toByteArray();
        filtered.nextHitOrdinal = hitOrdinal;
        filtered.nextIntervalIndex = idx;
        filtered.seenHitMessages = seenHits;
        filtered.writtenHitMessages = writtenHits;
        return filtered;
    }

    private static void addInterval(List<HitInterval> intervals, long start, long end) {
        if (intervals.isEmpty()) {
            intervals.add(new HitInterval(start, end));
            return;
        }
        HitInterval last = intervals.get(intervals.size() - 1);
        if (start <= last.end + 1) {
            last.end = Math.max(last.end, end);
        } else {
            intervals.add(new HitInterval(start, end));
        }
    }

    private static boolean matchesAny(long value, List<Range> ranges) {
        for (Range range : ranges) {
            if (range.contains(value)) {
                return true;
            }
        }
        return false;
    }

    private static int advanceInterval(long hitOrdinal, List<HitInterval> intervals, int intervalIndex) {
        int idx = intervalIndex;
        while (idx < intervals.size() && hitOrdinal > intervals.get(idx).end) {
            idx++;
        }
        return idx;
    }

    private static boolean isInsideInterval(long hitOrdinal, List<HitInterval> intervals, int intervalIndex) {
        int idx = advanceInterval(hitOrdinal, intervals, intervalIndex);
        return idx < intervals.size() && intervals.get(idx).contains(hitOrdinal);
    }

    private static void readTrace(File file, TraceVisitor visitor) throws IOException {
        try (DataInputStream in = new DataInputStream(new BufferedInputStream(new FileInputStream(file), INPUT_BUFFER_BYTES))) {
            byte[] magicBytes = new byte[8];
            in.readFully(magicBytes);
            String magic = new String(magicBytes, StandardCharsets.US_ASCII);
            if (!MAGIC.equals(magic)) {
                throw new IOException("Bad magic: expected " + MAGIC + ", got " + magic);
            }
            int endian = in.readUnsignedByte();
            if (endian != 0) {
                throw new IOException("Unsupported endianness: " + endian);
            }
            long fileStartMillis = in.readLong();
            visitor.header(fileStartMillis, endian);

            while (true) {
                int flag;
                try {
                    flag = in.readUnsignedShort();
                } catch (EOFException eof) {
                    break;
                }
                int source = in.readUnsignedByte();
                long nanoTime = in.readLong();
                int len = in.readInt();
                if (len < 0) {
                    throw new IOException("Negative payload length: " + len);
                }
                byte[] payload = new byte[len];
                in.readFully(payload);
                visitor.record(flag, source, nanoTime, payload);
            }
        }
    }

    private static void parseInnerMessages(byte[] payload, Summary summary) {
        int pos = 0;
        while (pos + 2 <= payload.length) {
            int msgType = u16(payload, pos);
            if (msgType == 1) {
                if (pos + 20 > payload.length) {
                    summary.truncatedMessages++;
                    return;
                }
                int appId = u16(payload, pos + 2);
                long instanceId = u32(payload, pos + 4);
                long threadId = u32(payload, pos + 8);
                long stackDepth = u32(payload, pos + 12);
                long locationId = u32(payload, pos + 16);
                summary.hitMessages++;
                increment(summary.appCounts, new AppInstanceKey(appId, instanceId));
                increment(summary.locationCounts, new LocationKey(appId, instanceId, locationId));
                summary.threadKeys.put(new ThreadKey(appId, instanceId, threadId), Boolean.TRUE);
                summary.stackDepths.put(stackDepth, Boolean.TRUE);
                pos += 20;
            } else if (msgType == 2) {
                if (pos + 18 > payload.length) {
                    summary.truncatedMessages++;
                    return;
                }
                int msgLen = u16(payload, pos + 16);
                if (pos + 18 + msgLen > payload.length) {
                    summary.truncatedMessages++;
                    return;
                }
                summary.logMessages++;
                pos += 18 + msgLen;
            } else if (msgType == 3) {
                summary.ctxAttachMessages++;
                return;
            } else if (msgType == 4) {
                summary.ctxWithdrawMessages++;
                return;
            } else {
                summary.unknownInnerMessages++;
                return;
            }
        }
    }

    private static List<String> parsePayloadForDump(byte[] payload) {
        List<String> messages = new ArrayList<>();
        int pos = 0;
        while (pos + 2 <= payload.length) {
            int msgType = u16(payload, pos);
            if (msgType == 1) {
                if (pos + 20 > payload.length) {
                    messages.add("HIT truncated hex=" + hex(payload, Math.min(payload.length, 32)));
                    return messages;
                }
                messages.add("HIT app=" + u16(payload, pos + 2)
                        + " inst=" + u32(payload, pos + 4)
                        + " thread=" + u32(payload, pos + 8)
                        + " stackDepth=" + u32(payload, pos + 12)
                        + " loc=" + u32(payload, pos + 16));
                pos += 20;
            } else if (msgType == 2) {
                if (pos + 18 > payload.length) {
                    messages.add("LOG truncated hex=" + hex(payload, Math.min(payload.length, 32)));
                    return messages;
                }
                int len = u16(payload, pos + 16);
                if (pos + 18 + len > payload.length) {
                    messages.add("LOG truncated hex=" + hex(payload, Math.min(payload.length, 32)));
                    return messages;
                }
                String text = new String(payload, pos + 18, len, StandardCharsets.UTF_8)
                        .replace("\\", "\\\\")
                        .replace("\r", "\\r")
                        .replace("\n", "\\n")
                        .replace("\t", "\\t")
                        .replace("\"", "\\\"");
                messages.add("LOG app=" + u16(payload, pos + 2)
                        + " inst=" + u32(payload, pos + 4)
                        + " thread=" + u32(payload, pos + 8)
                        + " stackDepth=" + u32(payload, pos + 12)
                        + " text=\"" + text + "\"");
                pos += 18 + len;
            } else if (msgType == 3 || msgType == 4) {
                String text = new String(payload, pos + 2, payload.length - (pos + 2), StandardCharsets.UTF_8)
                        .replace("\\", "\\\\")
                        .replace("\r", "\\r")
                        .replace("\n", "\\n")
                        .replace("\t", "\\t")
                        .replace("\"", "\\\"");
                messages.add((msgType == 3 ? "CTX_ATTACH" : "CTX_WITHDRAW") + " ctx=\"" + text + "\"");
                return messages;
            } else {
                if (messages.isEmpty()) {
                    messages.add("UNKNOWN type=" + msgType + " hex=" + hex(payload, Math.min(payload.length, 32)));
                }
                return messages;
            }
        }
        return messages;
    }

    private static long countHits(byte[] payload) {
        long hits = 0;
        int pos = 0;
        while (pos + 2 <= payload.length) {
            int msgType = u16(payload, pos);
            if (msgType == 1) {
                if (pos + 20 > payload.length) {
                    return hits;
                }
                hits++;
                pos += 20;
            } else if (msgType == 2) {
                if (pos + 18 > payload.length) {
                    return hits;
                }
                int msgLen = u16(payload, pos + 16);
                if (pos + 18 + msgLen > payload.length) {
                    return hits;
                }
                pos += 18 + msgLen;
            } else {
                return hits;
            }
        }
        return hits;
    }

    private static <K> void increment(Map<K, Long> map, K key) {
        Long current = map.get(key);
        map.put(key, current == null ? 1L : current + 1L);
    }

    private static int u16(byte[] bytes, int offset) {
        return ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);
    }

    private static long u32(byte[] bytes, int offset) {
        return ((long) (bytes[offset] & 0xFF) << 24)
                | ((long) (bytes[offset + 1] & 0xFF) << 16)
                | ((long) (bytes[offset + 2] & 0xFF) << 8)
                | (long) (bytes[offset + 3] & 0xFF);
    }

    private static long u64(byte[] bytes, int offset) {
        long value = 0L;
        for (int i = 0; i < 8; i++) {
            value = (value << 8) | (bytes[offset + i] & 0xFFL);
        }
        return value;
    }

    private static void writeShort(OutputStream out, int value) throws IOException {
        out.write((value >>> 8) & 0xFF);
        out.write(value & 0xFF);
    }

    private static void writeInt(OutputStream out, int value) throws IOException {
        out.write((value >>> 24) & 0xFF);
        out.write((value >>> 16) & 0xFF);
        out.write((value >>> 8) & 0xFF);
        out.write(value & 0xFF);
    }

    private static void writeLong(OutputStream out, long value) throws IOException {
        out.write((int) ((value >>> 56) & 0xFF));
        out.write((int) ((value >>> 48) & 0xFF));
        out.write((int) ((value >>> 40) & 0xFF));
        out.write((int) ((value >>> 32) & 0xFF));
        out.write((int) ((value >>> 24) & 0xFF));
        out.write((int) ((value >>> 16) & 0xFF));
        out.write((int) ((value >>> 8) & 0xFF));
        out.write((int) (value & 0xFF));
    }

    private static String hex(byte[] bytes, int limit) {
        char[] out = new char[limit * 2 + (bytes.length > limit ? 3 : 0)];
        char[] digits = "0123456789ABCDEF".toCharArray();
        int j = 0;
        for (int i = 0; i < limit; i++) {
            int b = bytes[i] & 0xFF;
            out[j++] = digits[b >>> 4];
            out[j++] = digits[b & 0x0F];
        }
        if (bytes.length > limit) {
            out[j++] = '.';
            out[j++] = '.';
            out[j] = '.';
        }
        return new String(out);
    }

    private static String sourceName(int source) {
        switch (source) {
            case HitTraceWriter.SRC_UDP:
                return "UDP";
            case HitTraceWriter.SRC_TCP:
                return "TCP";
            case HitTraceWriter.SRC_INTERNAL:
                return "INT";
            default:
                return "UNK(" + source + ")";
        }
    }

    private interface TraceVisitor {
        default void header(long fileStartMillis, int endian) throws IOException {
        }

        default void record(int flag, int source, long nanoTime, byte[] payload) throws IOException {
        }
    }

    private static final class Options {
        int top = 10;
        int buckets = 50;
        long limit = 100;

        static Options withTop(int top) {
            Options options = new Options();
            options.top = top;
            return options;
        }

        static Options withBuckets(int buckets) {
            Options options = new Options();
            options.buckets = buckets;
            return options;
        }

        static Options withLimit(long limit) {
            Options options = new Options();
            options.limit = limit;
            return options;
        }

        static Options parse(String[] args, int offset) {
            Options options = new Options();
            for (int i = offset; i < args.length; i++) {
                String arg = args[i];
                if ("--top".equals(arg) && i + 1 < args.length) {
                    options.top = Integer.parseInt(args[++i]);
                } else if ("--buckets".equals(arg) && i + 1 < args.length) {
                    options.buckets = Integer.parseInt(args[++i]);
                    if (options.buckets <= 0) {
                        throw new IllegalArgumentException("--buckets must be positive");
                    }
                } else if ("--limit".equals(arg) && i + 1 < args.length) {
                    options.limit = Long.parseLong(args[++i]);
                    if (options.limit < 0) {
                        throw new IllegalArgumentException("--limit must be non-negative");
                    }
                } else {
                    throw new IllegalArgumentException("Unknown option: " + arg);
                }
            }
            return options;
        }
    }

    private static final class Summary {
        long fileStartMillis;
        long records;
        long hitRecords;
        long logRecords;
        long tsRecords;
        long ctxAttachRecords;
        long ctxWithdrawRecords;
        long otherRecords;
        long hitMessages;
        long logMessages;
        long ctxAttachMessages;
        long ctxWithdrawMessages;
        long unknownInnerMessages;
        long truncatedMessages;
        long firstNano = Long.MIN_VALUE;
        long lastNano = Long.MIN_VALUE;
        final Map<AppInstanceKey, Long> appCounts = new HashMap<>();
        final Map<LocationKey, Long> locationCounts = new HashMap<>();
        final Map<ThreadKey, Boolean> threadKeys = new HashMap<>();
        final Map<Long, Boolean> stackDepths = new HashMap<>();
    }

    private static final class TimeRange {
        long hitCount;
        long minNano = Long.MAX_VALUE;
        long maxNano = Long.MIN_VALUE;
    }

    public static final class Range {
        final long start;
        final long end;

        Range(long start, long end) {
            if (start > end) {
                throw new IllegalArgumentException("range start must be <= end");
            }
            this.start = start;
            this.end = end;
        }

        public static Range parse(String text) {
            int dash = text.indexOf('-');
            if (dash < 0) {
                long value = Long.parseLong(text);
                return new Range(value, value);
            }
            long start = Long.parseLong(text.substring(0, dash));
            long end = Long.parseLong(text.substring(dash + 1));
            return new Range(start, end);
        }

        boolean contains(long value) {
            return value >= start && value <= end;
        }

        @Override
        public String toString() {
            return start == end ? Long.toString(start) : start + "-" + end;
        }
    }

    public static final class SubsetResult {
        public File sourceFile;
        public File targetFile;
        public long fileStartMillis;
        public long matchingHitWindows;
        public long sourceOuterRecords;
        public long sourceHitMessages;
        public long writtenOuterRecords;
        public long writtenHitMessages;
    }

    private static final class HitInterval {
        final long start;
        long end;

        HitInterval(long start, long end) {
            this.start = start;
            this.end = end;
        }

        boolean contains(long hitOrdinal) {
            return hitOrdinal >= start && hitOrdinal <= end;
        }
    }

    private static final class FilteredPayload {
        byte[] payload;
        long nextHitOrdinal;
        int nextIntervalIndex;
        long seenHitMessages;
        long writtenHitMessages;
    }

    private static final class TraceFileWriter implements AutoCloseable {
        private static final byte[] MAGIC_BYTES = new byte[]{'H', 'I', 'T', 'T', 'R', 'C', '0', '1'};
        private final OutputStream out;

        TraceFileWriter(File file) throws IOException {
            this.out = new BufferedOutputStream(new FileOutputStream(file), INPUT_BUFFER_BYTES);
        }

        void writeHeader(long fileStartMillis) throws IOException {
            out.write(MAGIC_BYTES);
            out.write(0);
            writeLong(out, fileStartMillis);
        }

        void writeRecord(int flag, int source, long nanoTime, byte[] payload) throws IOException {
            writeShort(out, flag);
            out.write(source & 0xFF);
            writeLong(out, nanoTime);
            writeInt(out, payload.length);
            out.write(payload);
        }

        @Override
        public void close() throws IOException {
            out.close();
        }
    }

    private static final class AppInstanceKey {
        final int appId;
        final long instanceId;

        AppInstanceKey(int appId, long instanceId) {
            this.appId = appId;
            this.instanceId = instanceId;
        }

        @Override
        public boolean equals(Object obj) {
            if (!(obj instanceof AppInstanceKey)) {
                return false;
            }
            AppInstanceKey other = (AppInstanceKey) obj;
            return appId == other.appId && instanceId == other.instanceId;
        }

        @Override
        public int hashCode() {
            return 31 * appId + Long.hashCode(instanceId);
        }

        @Override
        public String toString() {
            return appId + "/" + instanceId;
        }
    }

    private static final class LocationKey {
        final int appId;
        final long instanceId;
        final long locationId;

        LocationKey(int appId, long instanceId, long locationId) {
            this.appId = appId;
            this.instanceId = instanceId;
            this.locationId = locationId;
        }

        @Override
        public boolean equals(Object obj) {
            if (!(obj instanceof LocationKey)) {
                return false;
            }
            LocationKey other = (LocationKey) obj;
            return appId == other.appId && instanceId == other.instanceId && locationId == other.locationId;
        }

        @Override
        public int hashCode() {
            int result = appId;
            result = 31 * result + Long.hashCode(instanceId);
            result = 31 * result + Long.hashCode(locationId);
            return result;
        }

        @Override
        public String toString() {
            return appId + "/" + instanceId + "/" + locationId;
        }
    }

    private static final class ThreadKey {
        final int appId;
        final long instanceId;
        final long threadId;

        ThreadKey(int appId, long instanceId, long threadId) {
            this.appId = appId;
            this.instanceId = instanceId;
            this.threadId = threadId;
        }

        @Override
        public boolean equals(Object obj) {
            if (!(obj instanceof ThreadKey)) {
                return false;
            }
            ThreadKey other = (ThreadKey) obj;
            return appId == other.appId && instanceId == other.instanceId && threadId == other.threadId;
        }

        @Override
        public int hashCode() {
            int result = appId;
            result = 31 * result + Long.hashCode(instanceId);
            result = 31 * result + Long.hashCode(threadId);
            return result;
        }
    }
}
