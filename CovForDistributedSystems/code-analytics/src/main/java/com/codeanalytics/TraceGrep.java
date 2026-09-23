package com.codeanalytics;

import java.io.BufferedReader;
import java.io.EOFException;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.io.PrintStream;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.regex.Pattern;
import java.util.regex.PatternSyntaxException;

/**
 * Grep-like log search for large HITTRC01 trace files.
 *
 * The implementation uses the sparse TraceIndexer TSV only to find a safe
 * outer-frame checkpoint near --start-ts. It then streams complete frames from
 * the trace and only materializes one frame payload at a time.
 */
public final class TraceGrep {
    private static final String MAGIC = "HITTRC01";
    private static final int FILE_HEADER_BYTES = 17;
    private static final int FRAME_HEADER_BYTES = 15;
    private static final String DEFAULT_LOCAL_CFG = "tracegrep.cfg";

    private TraceGrep() {
    }

    public static void main(String[] args) throws Exception {
        int status = runCli(args, System.out, System.err);
        if (status != 0) {
            System.exit(status);
        }
    }

    public static int runCli(String[] args, PrintStream out, PrintStream err) {
        try {
            Options options = Options.fromArgs(args);
            SearchResult result = search(options, out);
            out.println("# scanned_frames=" + result.framesScanned
                    + " scanned_logs=" + result.logsScanned
                    + " matches=" + result.matches);
            return 0;
        } catch (UsageException e) {
            err.println(e.getMessage());
            usage(err);
            return 2;
        } catch (Exception e) {
            err.println("ERROR: " + e.getMessage());
            return 1;
        }
    }

    public static SearchResult search(Options options, PrintStream out) throws IOException {
        options.validate();
        TraceHeader traceHeader = readTraceHeader(options.traceFile);

        List<IndexRow> indexRows = Collections.emptyList();
        IndexMetadata indexMetadata = null;
        if (options.indexFile != null && options.indexFile.exists()) {
            IndexFile index = readIndex(options.indexFile);
            indexRows = index.rows;
            indexMetadata = index.metadata;
        }

        long startNano = resolveTraceNano(options.startTs, traceHeader, indexMetadata, indexRows, true);
        long endNano = resolveTraceNano(options.endTs, traceHeader, indexMetadata, indexRows, false);
        if (startNano != Long.MIN_VALUE && endNano != Long.MAX_VALUE && startNano > endNano) {
            throw new UsageException("--start-ts must be <= --end-ts");
        }

        Checkpoint checkpoint = chooseCheckpoint(indexRows, startNano);
        SearchResult result = new SearchResult();
        ArrayDeque<LogLine> before = new ArrayDeque<>();
        int afterRemaining = 0;
        boolean pendingSeparator = false;

        try (RandomAccessFile raf = new RandomAccessFile(options.traceFile, "r")) {
            long frameSeq = checkpoint.frameSeq;
            raf.seek(checkpoint.offset);

            while (raf.getFilePointer() < raf.length()) {
                long frameOffset = raf.getFilePointer();
                FrameHeader frame;
                try {
                    frame = readFrameHeader(raf);
                } catch (EOFException eof) {
                    break;
                }
                if (frame.payloadLength < 0) {
                    throw new IOException("Negative payload length at offset " + frameOffset);
                }

                if (frame.nanoTime > endNano) {
                    break;
                }

                byte[] payload = new byte[frame.payloadLength];
                raf.readFully(payload);
                result.framesScanned++;

                List<LogLine> logs = extractLogs(frameSeq, frameOffset, frame, payload);
                for (LogLine log : logs) {
                    if (log.nanoTime < startNano) {
                        continue;
                    }
                    if (log.nanoTime > endNano) {
                        break;
                    }
                    result.logsScanned++;
                    boolean matched = matches(options, log.text);
                    if (matched) {
                        if (pendingSeparator && options.groupSeparator) {
                            out.println("--");
                        }
                        for (LogLine prior : before) {
                            out.println(formatLine("-", prior));
                        }
                        before.clear();
                        out.println(formatLine(":", log));
                        result.matches++;
                        afterRemaining = options.logsAfter;
                        pendingSeparator = true;
                    } else if (afterRemaining > 0) {
                        out.println(formatLine("-", log));
                        afterRemaining--;
                    } else {
                        rememberBefore(before, log, options.logsBefore);
                    }
                }
                frameSeq++;
            }
        }
        return result;
    }

    private static boolean matches(Options options, String text) {
        if (options.substrings.isEmpty() && options.regexPatterns.isEmpty()) {
            return true;
        }
        for (String substring : options.substrings) {
            if (options.ignoreCase) {
                if (text.toLowerCase(Locale.ROOT).contains(substring.toLowerCase(Locale.ROOT))) {
                    return true;
                }
            } else if (text.contains(substring)) {
                return true;
            }
        }
        for (Pattern pattern : options.regexPatterns) {
            if (pattern.matcher(text).find()) {
                return true;
            }
        }
        return false;
    }

    private static void rememberBefore(ArrayDeque<LogLine> before, LogLine log, int limit) {
        if (limit <= 0) {
            return;
        }
        before.addLast(log);
        while (before.size() > limit) {
            before.removeFirst();
        }
    }

    private static String formatLine(String sep, LogLine log) {
        return log.frameSeq + sep
                + log.offset + sep
                + log.nanoTime + sep
                + "LOG app=" + log.appId
                + " inst=" + log.instanceId
                + " thread=" + log.threadId
                + " stackDepth=" + log.stackDepth
                + " text=\"" + escape(log.text) + "\"";
    }

    private static String escape(String text) {
        return text.replace("\\", "\\\\")
                .replace("\r", "\\r")
                .replace("\n", "\\n")
                .replace("\t", "\\t")
                .replace("\"", "\\\"");
    }

    private static List<LogLine> extractLogs(long frameSeq, long frameOffset, FrameHeader frame, byte[] payload) {
        List<LogLine> logs = new ArrayList<>();
        int pos = 0;
        while (pos + 2 <= payload.length) {
            int msgType = u16(payload, pos);
            if (msgType == 1) {
                if (pos + 20 > payload.length) {
                    return logs;
                }
                pos += 20;
            } else if (msgType == 2) {
                if (pos + 18 > payload.length) {
                    return logs;
                }
                int len = u16(payload, pos + 16);
                if (pos + 18 + len > payload.length) {
                    return logs;
                }
                logs.add(new LogLine(frameSeq, frameOffset, frame.nanoTime,
                        u16(payload, pos + 2),
                        u32(payload, pos + 4),
                        u32(payload, pos + 8),
                        u32(payload, pos + 12),
                        new String(payload, pos + 18, len, StandardCharsets.UTF_8)));
                pos += 18 + len;
            } else if (msgType == 3 || msgType == 4) {
                return logs;
            } else {
                return logs;
            }
        }
        return logs;
    }

    private static TraceHeader readTraceHeader(File traceFile) throws IOException {
        try (RandomAccessFile raf = new RandomAccessFile(traceFile, "r")) {
            byte[] magicBytes = new byte[8];
            raf.readFully(magicBytes);
            String magic = new String(magicBytes, StandardCharsets.US_ASCII);
            if (!MAGIC.equals(magic)) {
                throw new IOException("Bad magic: expected " + MAGIC + ", got " + magic);
            }
            int endian = raf.readUnsignedByte();
            if (endian != 0) {
                throw new IOException("Unsupported endianness: " + endian);
            }
            long fileStartMillis = raf.readLong();
            long firstNano = Long.MIN_VALUE;
            if (raf.length() >= FILE_HEADER_BYTES + FRAME_HEADER_BYTES) {
                try {
                    firstNano = readFrameHeader(raf).nanoTime;
                } catch (EOFException ignored) {
                    firstNano = Long.MIN_VALUE;
                }
            }
            return new TraceHeader(fileStartMillis, firstNano);
        }
    }

    private static FrameHeader readFrameHeader(RandomAccessFile raf) throws IOException {
        int flag = raf.readUnsignedShort();
        int source = raf.readUnsignedByte();
        long nanoTime = raf.readLong();
        int payloadLength = raf.readInt();
        return new FrameHeader(flag, source, nanoTime, payloadLength);
    }

    private static long resolveTraceNano(String value, TraceHeader traceHeader, IndexMetadata indexMetadata,
                                         List<IndexRow> indexRows, boolean start) throws IOException {
        if (value == null || value.trim().isEmpty()) {
            return start ? Long.MIN_VALUE : Long.MAX_VALUE;
        }
        String trimmed = value.trim();
        if (isInteger(trimmed)) {
            return Long.parseLong(trimmed);
        }
        try {
            long epochNs = parseEpochNs(trimmed);
            long firstNano;
            if (!indexRows.isEmpty()) {
                firstNano = indexRows.get(0).nanoTime;
            } else if (indexMetadata != null && indexMetadata.firstNano != Long.MIN_VALUE) {
                firstNano = indexMetadata.firstNano;
            } else {
                firstNano = traceHeader.firstNano;
                if (firstNano == Long.MIN_VALUE) {
                    throw new IOException("RFC3339 timestamps need either an index row or at least one trace frame for monotonic conversion");
                }
            }
            return firstNano + (epochNs - traceHeader.fileStartMillis * 1_000_000L);
        } catch (DateTimeParseException e) {
            throw new UsageException("Timestamp must be raw trace nanoseconds or RFC3339 UTC: " + value);
        }
    }

    private static long parseEpochNs(String value) {
        Instant instant = Instant.parse(value);
        return instant.getEpochSecond() * 1_000_000_000L + instant.getNano();
    }

    private static Checkpoint chooseCheckpoint(List<IndexRow> rows, long startNano) {
        if (rows.isEmpty() || startNano == Long.MIN_VALUE) {
            return new Checkpoint(0, FILE_HEADER_BYTES);
        }
        IndexRow best = rows.get(0);
        for (IndexRow row : rows) {
            if (row.nanoTime <= startNano) {
                best = row;
            } else {
                break;
            }
        }
        return new Checkpoint(best.frameSeq, best.offset);
    }

    private static IndexFile readIndex(File indexFile) throws IOException {
        IndexMetadata metadata = new IndexMetadata();
        List<IndexRow> rows = new ArrayList<>();
        try (BufferedReader reader = new BufferedReader(new FileReader(indexFile, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isEmpty()) {
                    continue;
                }
                if (line.startsWith("#")) {
                    String[] parts = line.substring(1).trim().split("\\t", 2);
                    if (parts.length == 2) {
                        if ("file_start_millis".equals(parts[0])) {
                            metadata.fileStartMillis = Long.parseLong(parts[1]);
                        }
                    }
                    continue;
                }
                if (line.startsWith("frame_seq\t")) {
                    continue;
                }
                String[] parts = line.split("\\t");
                if (parts.length < 3) {
                    throw new IOException("Bad index row: " + line);
                }
                IndexRow row = new IndexRow(Long.parseLong(parts[0]), Long.parseLong(parts[1]), Long.parseLong(parts[2]));
                rows.add(row);
                if (metadata.firstNano == Long.MIN_VALUE) {
                    metadata.firstNano = row.nanoTime;
                }
            }
        }
        return new IndexFile(metadata, rows);
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

    private static boolean isInteger(String text) {
        try {
            Long.parseLong(text);
            return true;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    public static String[] splitCommandLine(String text) {
        List<String> tokens = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        boolean inQuote = false;
        char quote = 0;
        boolean escaping = false;
        for (int i = 0; i < text.length(); i++) {
            char ch = text.charAt(i);
            if (escaping) {
                current.append(ch);
                escaping = false;
            } else if (ch == '\\') {
                if (i + 1 < text.length()) {
                    char next = text.charAt(i + 1);
                    if (next == '\\' || next == '"' || next == '\'' || Character.isWhitespace(next)) {
                        escaping = true;
                    } else {
                        current.append(ch);
                    }
                } else {
                    current.append(ch);
                }
            } else if (inQuote) {
                if (ch == quote) {
                    inQuote = false;
                } else {
                    current.append(ch);
                }
            } else if (ch == '"' || ch == '\'') {
                inQuote = true;
                quote = ch;
            } else if (Character.isWhitespace(ch)) {
                if (current.length() > 0) {
                    tokens.add(current.toString());
                    current.setLength(0);
                }
            } else {
                current.append(ch);
            }
        }
        if (escaping) {
            current.append('\\');
        }
        if (current.length() > 0) {
            tokens.add(current.toString());
        }
        return tokens.toArray(new String[0]);
    }

    private static void usage(PrintStream err) {
        err.println("Usage:");
        err.println("  java com.codeanalytics.TraceGrep --trace-file TRACE [--index-file INDEX]");
        err.println("      [--start-ts NANO|RFC3339] [--end-ts NANO|RFC3339]");
        err.println("      [--regex PATTERN ...] [--substring TEXT ...]");
        err.println("      [--logs-before N] [--logs-after N] [--cfg FILE] [--ignore-case]");
        err.println();
        err.println("Config defaults are read from tracegrep.cfg next to the trace file, then --cfg, then CLI flags.");
    }

    public static final class Options {
        public File traceFile;
        public File indexFile;
        public String startTs;
        public String endTs;
        public int logsBefore;
        public int logsAfter;
        public boolean ignoreCase;
        public boolean groupSeparator = true;
        final List<String> regexTexts = new ArrayList<>();
        final List<Pattern> regexPatterns = new ArrayList<>();
        final List<String> substrings = new ArrayList<>();

        static Options fromArgs(String[] args) throws IOException {
            PartialArgs firstPass = PartialArgs.parse(args, false);
            Options options = new Options();
            if (firstPass.traceFile != null) {
                File local = new File(firstPass.traceFile.getAbsoluteFile().getParentFile(), DEFAULT_LOCAL_CFG);
                if (local.exists()) {
                    applyConfig(options, local);
                }
            }
            if (firstPass.cfgFile != null) {
                applyConfig(options, firstPass.cfgFile);
            }
            applyPartial(options, PartialArgs.parse(args, true), true);
            compilePatterns(options);
            return options;
        }

        private void validate() {
            if (traceFile == null) {
                throw new UsageException("--trace-file is required");
            }
            if (!traceFile.exists()) {
                throw new UsageException("Trace file not found: " + traceFile.getPath());
            }
            if (logsBefore < 0 || logsAfter < 0) {
                throw new UsageException("--logs-before and --logs-after must be non-negative");
            }
        }
    }

    private static void applyConfig(Options options, File cfgFile) throws IOException {
        File baseDir = cfgFile.getAbsoluteFile().getParentFile();
        try (BufferedReader reader = new BufferedReader(new FileReader(cfgFile, StandardCharsets.UTF_8))) {
            String line;
            int lineNo = 0;
            while ((line = reader.readLine()) != null) {
                lineNo++;
                String trimmed = line.trim();
                if (trimmed.isEmpty() || trimmed.startsWith("#")) {
                    continue;
                }
                int eq = trimmed.indexOf('=');
                if (eq < 0) {
                    throw new UsageException("Bad config line " + cfgFile + ":" + lineNo + " expected key=value");
                }
                String key = trimmed.substring(0, eq).trim();
                String value = trimmed.substring(eq + 1).trim();
                applyConfigValue(options, baseDir, key, value);
            }
        }
    }

    private static void applyConfigValue(Options options, File baseDir, String key, String value) {
        switch (key) {
            case "trace-file":
                options.traceFile = resolveConfigPath(baseDir, value);
                break;
            case "index-file":
                options.indexFile = resolveConfigPath(baseDir, value);
                break;
            case "start-ts":
                options.startTs = value;
                break;
            case "end-ts":
                options.endTs = value;
                break;
            case "logs-before":
                options.logsBefore = Integer.parseInt(value);
                break;
            case "logs-after":
                options.logsAfter = Integer.parseInt(value);
                break;
            case "ignore-case":
                options.ignoreCase = Boolean.parseBoolean(value);
                break;
            case "group-separator":
                options.groupSeparator = Boolean.parseBoolean(value);
                break;
            case "regex":
                if (!value.isEmpty()) {
                    options.regexTexts.add(value);
                }
                break;
            case "substring":
                if (!value.isEmpty()) {
                    options.substrings.add(value);
                }
                break;
            default:
                throw new UsageException("Unknown config key: " + key);
        }
    }

    private static File resolveConfigPath(File baseDir, String value) {
        File file = new File(value);
        return file.isAbsolute() ? file : new File(baseDir, value);
    }

    private static void applyPartial(Options options, PartialArgs partial, boolean overrideMatchers) {
        if (partial.traceFile != null) {
            options.traceFile = partial.traceFile;
        }
        if (partial.indexFile != null) {
            options.indexFile = partial.indexFile;
        } else if (options.indexFile == null && options.traceFile != null) {
            File candidate = new File(options.traceFile.getPath() + ".idx.tsv");
            if (candidate.exists()) {
                options.indexFile = candidate;
            }
        }
        if (partial.startTs != null) {
            options.startTs = partial.startTs;
        }
        if (partial.endTs != null) {
            options.endTs = partial.endTs;
        }
        if (partial.logsBefore != null) {
            options.logsBefore = partial.logsBefore;
        }
        if (partial.logsAfter != null) {
            options.logsAfter = partial.logsAfter;
        }
        if (partial.ignoreCase != null) {
            options.ignoreCase = partial.ignoreCase;
        }
        if (partial.groupSeparator != null) {
            options.groupSeparator = partial.groupSeparator;
        }
        if (overrideMatchers && (!partial.regexTexts.isEmpty() || !partial.substrings.isEmpty())) {
            options.regexTexts.clear();
            options.substrings.clear();
        }
        options.regexTexts.addAll(partial.regexTexts);
        options.substrings.addAll(partial.substrings);
    }

    private static void compilePatterns(Options options) {
        int flags = options.ignoreCase ? Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE : 0;
        for (String regex : options.regexTexts) {
            try {
                options.regexPatterns.add(Pattern.compile(regex, flags));
            } catch (PatternSyntaxException e) {
                throw new UsageException("Bad regex: " + regex + " (" + e.getMessage() + ")");
            }
        }
    }

    private static final class PartialArgs {
        File traceFile;
        File indexFile;
        File cfgFile;
        String startTs;
        String endTs;
        Integer logsBefore;
        Integer logsAfter;
        Boolean ignoreCase;
        Boolean groupSeparator;
        final List<String> regexTexts = new ArrayList<>();
        final List<String> substrings = new ArrayList<>();

        static PartialArgs parse(String[] args, boolean strict) {
            PartialArgs parsed = new PartialArgs();
            for (int i = 0; i < args.length; i++) {
                String arg = args[i];
                if ("--trace-file".equals(arg)) {
                    parsed.traceFile = new File(require(args, ++i, arg));
                } else if ("--index-file".equals(arg)) {
                    parsed.indexFile = new File(require(args, ++i, arg));
                } else if ("--cfg".equals(arg)) {
                    parsed.cfgFile = new File(require(args, ++i, arg));
                } else if ("--start-ts".equals(arg)) {
                    parsed.startTs = require(args, ++i, arg);
                } else if ("--end-ts".equals(arg)) {
                    parsed.endTs = require(args, ++i, arg);
                } else if ("--regex".equals(arg)) {
                    parsed.regexTexts.add(require(args, ++i, arg));
                } else if ("--substring".equals(arg)) {
                    parsed.substrings.add(require(args, ++i, arg));
                } else if ("--logs-before".equals(arg) || "-B".equals(arg)) {
                    parsed.logsBefore = Integer.parseInt(require(args, ++i, arg));
                } else if ("--logs-after".equals(arg) || "-A".equals(arg)) {
                    parsed.logsAfter = Integer.parseInt(require(args, ++i, arg));
                } else if ("--ignore-case".equals(arg) || "-i".equals(arg)) {
                    parsed.ignoreCase = true;
                } else if ("--no-group-separator".equals(arg)) {
                    parsed.groupSeparator = false;
                } else if (strict) {
                    throw new UsageException("Unknown option: " + arg);
                }
            }
            return parsed;
        }

        private static String require(String[] args, int index, String opt) {
            if (index >= args.length) {
                throw new UsageException(opt + " requires a value");
            }
            return args[index];
        }
    }

    public static final class SearchResult {
        public long framesScanned;
        public long logsScanned;
        public long matches;
    }

    private static final class TraceHeader {
        final long fileStartMillis;
        final long firstNano;

        TraceHeader(long fileStartMillis, long firstNano) {
            this.fileStartMillis = fileStartMillis;
            this.firstNano = firstNano;
        }
    }

    private static final class FrameHeader {
        final int flag;
        final int source;
        final long nanoTime;
        final int payloadLength;

        FrameHeader(int flag, int source, long nanoTime, int payloadLength) {
            this.flag = flag;
            this.source = source;
            this.nanoTime = nanoTime;
            this.payloadLength = payloadLength;
        }
    }

    private static final class LogLine {
        final long frameSeq;
        final long offset;
        final long nanoTime;
        final int appId;
        final long instanceId;
        final long threadId;
        final long stackDepth;
        final String text;

        LogLine(long frameSeq, long offset, long nanoTime, int appId, long instanceId,
                long threadId, long stackDepth, String text) {
            this.frameSeq = frameSeq;
            this.offset = offset;
            this.nanoTime = nanoTime;
            this.appId = appId;
            this.instanceId = instanceId;
            this.threadId = threadId;
            this.stackDepth = stackDepth;
            this.text = Objects.requireNonNull(text);
        }
    }

    private static final class Checkpoint {
        final long frameSeq;
        final long offset;

        Checkpoint(long frameSeq, long offset) {
            this.frameSeq = frameSeq;
            this.offset = offset;
        }
    }

    private static final class IndexRow {
        final long frameSeq;
        final long offset;
        final long nanoTime;

        IndexRow(long frameSeq, long offset, long nanoTime) {
            this.frameSeq = frameSeq;
            this.offset = offset;
            this.nanoTime = nanoTime;
        }
    }

    private static final class IndexMetadata {
        long fileStartMillis;
        long firstNano = Long.MIN_VALUE;
    }

    private static final class IndexFile {
        final IndexMetadata metadata;
        final List<IndexRow> rows;

        IndexFile(IndexMetadata metadata, List<IndexRow> rows) {
            this.metadata = metadata;
            this.rows = rows;
        }
    }

    private static final class UsageException extends RuntimeException {
        UsageException(String message) {
            super(message);
        }
    }
}
