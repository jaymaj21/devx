package com.codeanalytics;

import java.io.BufferedInputStream;
import java.io.BufferedWriter;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;

/**
 * Builds a compact, human-readable sparse index for HITTRC01 trace files.
 *
 * The index is intended as a seek map for large traces: each row records only a
 * frame sequence number, that frame's timestamp, and its byte offset in the
 * trace. A navigator can binary-search the index, seek to the nearest earlier
 * offset, then scan forward from there.
 */
public final class TraceIndexer {
    private static final String MAGIC = "HITTRC01";
    private static final int FILE_HEADER_BYTES = 17;
    private static final int INPUT_BUFFER_BYTES = 1 << 20;
    private static final long DEFAULT_STRIDE_BYTES = 64L * 1024L * 1024L;

    private TraceIndexer() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            usage(System.err);
            System.exit(2);
        }

        Options options = Options.parse(args);
        IndexResult result = writeIndex(options.traceFile, options.indexFile, options.strideBytes);

        System.out.println("Trace index written: " + options.indexFile.getPath());
        System.out.println("  Trace: " + options.traceFile.getPath());
        System.out.println("  Trace bytes: " + result.traceBytes);
        System.out.println("  Frames scanned: " + result.framesScanned);
        System.out.println("  Index rows: " + result.rowsWritten);
        System.out.println("  Stride bytes: " + options.strideBytes);
    }

    private static void usage(PrintStream err) {
        err.println("Usage:");
        err.println("  java com.codeanalytics.TraceIndexer <trace-file> [index-file] [--stride-bytes N]");
        err.println("  java com.codeanalytics.TraceIndexer <trace-file> [index-file] [--stride-mib N]");
        err.println();
        err.println("Default index file: <trace-file>.idx.tsv");
        err.println("Default stride: 64 MiB");
    }

    public static IndexResult writeIndex(File traceFile, File indexFile, long strideBytes) throws IOException {
        if (strideBytes <= 0) {
            throw new IllegalArgumentException("stride must be positive");
        }

        try (CountingInputStream counter = new CountingInputStream(
                    new BufferedInputStream(new FileInputStream(traceFile), INPUT_BUFFER_BYTES));
             DataInputStream in = new DataInputStream(counter);
             BufferedWriter out = new BufferedWriter(new FileWriter(indexFile, StandardCharsets.UTF_8))) {

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

            writeHeader(out, traceFile, strideBytes, fileStartMillis, endian);

            IndexResult result = new IndexResult();
            result.traceBytes = traceFile.length();
            result.fileStartMillis = fileStartMillis;

            long nextCheckpointOffset = FILE_HEADER_BYTES;
            long frameSeq = 0;
            long firstNano = Long.MIN_VALUE;
            Checkpoint lastWritten = null;
            FrameInfo lastFrame = null;

            while (true) {
                long frameOffset = counter.bytesRead();
                int flag;
                try {
                    flag = in.readUnsignedShort();
                } catch (EOFException eof) {
                    break;
                }
                int source = in.readUnsignedByte();
                long nanoTime = in.readLong();
                int payloadLength = in.readInt();
                if (payloadLength < 0) {
                    throw new IOException("Negative payload length at frame " + frameSeq + ": " + payloadLength);
                }

                skipFully(in, payloadLength);

                long nextFrameOffset = counter.bytesRead();
                lastFrame = new FrameInfo(frameSeq, frameOffset, nanoTime);
                if (firstNano == Long.MIN_VALUE) {
                    firstNano = nanoTime;
                    result.firstNano = nanoTime;
                }
                result.lastNano = nanoTime;

                if (frameOffset >= nextCheckpointOffset || frameSeq == 0) {
                    lastWritten = writeRow(out, frameSeq, frameOffset, nanoTime);
                    result.rowsWritten++;
                    while (nextCheckpointOffset <= frameOffset) {
                        nextCheckpointOffset += strideBytes;
                    }
                }

                result.framesScanned++;
                frameSeq++;
            }

            if (lastFrame != null && (lastWritten == null || lastWritten.frameSeq != lastFrame.frameSeq)) {
                // Always include the final frame as a regular row so readers can
                // use one parser for both checkpoints and the scanned tail.
                writeRow(out, lastFrame.frameSeq, lastFrame.offset, lastFrame.nanoTime);
                result.rowsWritten++;
            }

            return result;
        }
    }

    private static void writeHeader(BufferedWriter out, File traceFile, long strideBytes,
                                    long fileStartMillis, int endian) throws IOException {
        out.write("# HITTRC01_INDEX\tv1\n");
        out.write("# trace_path\t");
        out.write(traceFile.getPath());
        out.write("\n");
        out.write("# trace_bytes\t");
        out.write(Long.toString(traceFile.length()));
        out.write("\n");
        out.write("# stride_bytes\t");
        out.write(Long.toString(strideBytes));
        out.write("\n");
        out.write("# file_header_bytes\t");
        out.write(Integer.toString(FILE_HEADER_BYTES));
        out.write("\n");
        out.write("# file_start_millis\t");
        out.write(Long.toString(fileStartMillis));
        out.write("\n");
        out.write("# file_start_utc\t");
        out.write(Instant.ofEpochMilli(fileStartMillis).toString());
        out.write("\n");
        out.write("# endian\t");
        out.write(Integer.toString(endian));
        out.write("\n");
        out.write("frame_seq\toffset\tt_ns\n");
    }

    private static Checkpoint writeRow(BufferedWriter out, long frameSeq, long frameOffset,
                                       long nanoTime) throws IOException {
        out.write(Long.toString(frameSeq));
        out.write('\t');
        out.write(Long.toString(frameOffset));
        out.write('\t');
        out.write(Long.toString(nanoTime));
        out.write('\n');
        return new Checkpoint(frameSeq);
    }

    private static void skipFully(DataInputStream in, int bytes) throws IOException {
        int remaining = bytes;
        while (remaining > 0) {
            int skipped = in.skipBytes(remaining);
            if (skipped <= 0) {
                if (in.read() < 0) {
                    throw new EOFException("truncated payload");
                }
                skipped = 1;
            }
            remaining -= skipped;
        }
    }

    public static final class IndexResult {
        public long traceBytes;
        public long framesScanned;
        public long rowsWritten;
        public long fileStartMillis;
        public long firstNano = Long.MIN_VALUE;
        public long lastNano = Long.MIN_VALUE;
    }

    private static final class Checkpoint {
        final long frameSeq;

        Checkpoint(long frameSeq) {
            this.frameSeq = frameSeq;
        }
    }

    private static final class FrameInfo {
        final long frameSeq;
        final long offset;
        final long nanoTime;

        FrameInfo(long frameSeq, long offset, long nanoTime) {
            this.frameSeq = frameSeq;
            this.offset = offset;
            this.nanoTime = nanoTime;
        }
    }

    private static final class Options {
        File traceFile;
        File indexFile;
        long strideBytes = DEFAULT_STRIDE_BYTES;

        static Options parse(String[] args) {
            Options options = new Options();
            options.traceFile = new File(args[0]);
            options.indexFile = new File(args[0] + ".idx.tsv");

            int i = 1;
            if (i < args.length && !args[i].startsWith("--")) {
                options.indexFile = new File(args[i]);
                i++;
            }
            while (i < args.length) {
                String arg = args[i++];
                if ("--stride-bytes".equals(arg) && i < args.length) {
                    options.strideBytes = Long.parseLong(args[i++]);
                } else if ("--stride-mib".equals(arg) && i < args.length) {
                    options.strideBytes = Long.parseLong(args[i++]) * 1024L * 1024L;
                } else {
                    throw new IllegalArgumentException("Unknown or incomplete option: " + arg);
                }
            }
            return options;
        }
    }

    private static final class CountingInputStream extends FilterInputStream {
        private long bytesRead;

        CountingInputStream(InputStream in) {
            super(in);
        }

        long bytesRead() {
            return bytesRead;
        }

        @Override
        public int read() throws IOException {
            int value = super.read();
            if (value >= 0) {
                bytesRead++;
            }
            return value;
        }

        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            int count = super.read(b, off, len);
            if (count > 0) {
                bytesRead += count;
            }
            return count;
        }

        @Override
        public long skip(long n) throws IOException {
            long skipped = super.skip(n);
            if (skipped > 0) {
                bytesRead += skipped;
            }
            return skipped;
        }
    }
}
