package com.codeanalytics;

import java.io.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.FileChannel;
import java.time.Instant;
import java.util.Objects;

/**
 * Writes a language-agnostic binary trace of incoming records (hits, logs, etc.)
 * in rough arrival order. Records are saved as the raw bytes received, preceded
 * by a tiny header so a reader can split the file into frames.
 *
 * File format (all multi-byte fields are BIG-ENDIAN):
 *   Header (written once at the beginning of a new file):
 *     8 bytes: ASCII "HITTRC01"
 *     1 byte : endianness flag (0 = big-endian)
 *     8 bytes: fileStartEpochMillis (long)
 *
 *   Repeated per record:
 *     2 bytes: flag   (short < 10000 as per user's convention)
 *     1 byte : source (0=UDP, 1=TCP, 2=INTERNAL)
 *     8 bytes: capturedNanoTime at write (long, from System.nanoTime())
 *     4 bytes: payload length N (int, unsigned semantics)
 *     N bytes: raw payload
 */
public final class HitTraceWriter implements Closeable, Flushable {
    public static final short FLAG_HIT = 1;    // raw hit packet
    public static final short FLAG_LOG = 2;    // UTF-8 log line
    public static final short FLAG_CTX_ATTACH = 3; // optional: context attach
    public static final short FLAG_CTX_WITHDRAW = 4; // optional: context withdraw
    public static final short FLAG_TS = 9;    // periodic timestamp record (payload: u64 epochMillis)

    public static final byte SRC_UDP = 0;
    public static final byte SRC_TCP = 1;
    public static final byte SRC_INTERNAL = 2;

    private static final byte[] MAGIC = new byte[]{'H','I','T','T','R','C','0','1'};
    private static final byte ENDIAN_BIG = 0;

    private final File file;
    private final boolean append;
    private final OutputStream out;
    private final FileChannel channel;
    private final ByteBuffer headerBuf = ByteBuffer.allocate(2 + 1 + 8 + 4).order(ByteOrder.BIG_ENDIAN); // reused per record

    // Synchronize all writes to preserve arrival order across threads
    private final Object lock = new Object();
    private volatile boolean headerWritten = false;

    public HitTraceWriter(File file, boolean append) throws IOException {
        this.file = Objects.requireNonNull(file, "file");
        this.append = append;
        RandomAccessFile raf = new RandomAccessFile(file, "rw");
        this.channel = raf.getChannel();
        if (append && file.length() > 0) {
            // Move to end and assume header already exists.
            channel.position(channel.size());
            this.out = new BufferedOutputStream(Channels2.outputStream(channel), 1 << 20);
            headerWritten = true;
        } else {
            // Truncate and write header
            channel.truncate(0);
            this.out = new BufferedOutputStream(Channels2.outputStream(channel), 1 << 20);
            writeHeader();
        }
    }

    private void writeHeader() throws IOException {
        synchronized (lock) {
            out.write(MAGIC);
            out.write(ENDIAN_BIG);
            writeLong(out, System.currentTimeMillis());
            out.flush();
            headerWritten = true;
        }
    }

    public void writeRaw(short flag, byte source, byte[] data) throws IOException {
        writeRaw(flag, source, data, 0, data.length);
    }

    public void writeRaw(short flag, byte source, byte[] data, int off, int len) throws IOException {
        if (!headerWritten) writeHeader();
        if (flag >= 10000) throw new IllegalArgumentException("flag must be < 10000 per convention");
        if (off < 0 || len < 0 || off + len > data.length) throw new IndexOutOfBoundsException();
        long nowNs = System.nanoTime();
        synchronized (lock) {
            // record prefix
            writeShort(out, flag);
            out.write(source & 0xFF);
            writeLong(out, nowNs);
            writeInt(out, len);
            // payload
            out.write(data, off, len);
        }
    }

    public void writeUtf8(short flag, byte source, String text) throws IOException {
        byte[] bytes = text.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        writeRaw(flag, source, bytes, 0, bytes.length);
    }

    @Override public void flush() throws IOException {
        synchronized (lock) {
            out.flush();
            channel.force(false);
        }
    }

    @Override public void close() throws IOException {
        synchronized (lock) {
            try {
                out.flush();
                channel.force(false);
            } finally {
                out.close();
                channel.close();
            }
        }
    }

    /** Force durable persistence (data + metadata). */
    public void persist() throws IOException {
        synchronized (lock) {
            out.flush();
            channel.force(true);
        }
    }

    // --- tiny helpers (big-endian) ---
    private static void writeShort(OutputStream os, int v) throws IOException {
        os.write((v >>> 8) & 0xFF);
        os.write(v & 0xFF);
    }
    private static void writeInt(OutputStream os, int v) throws IOException {
        os.write((v >>> 24) & 0xFF);
        os.write((v >>> 16) & 0xFF);
        os.write((v >>>  8) & 0xFF);
        os.write(v & 0xFF);
    }
    private static void writeLong(OutputStream os, long v) throws IOException {
        os.write((int)((v >>> 56) & 0xFF));
        os.write((int)((v >>> 48) & 0xFF));
        os.write((int)((v >>> 40) & 0xFF));
        os.write((int)((v >>> 32) & 0xFF));
        os.write((int)((v >>> 24) & 0xFF));
        os.write((int)((v >>> 16) & 0xFF));
        os.write((int)((v >>>  8) & 0xFF));
        os.write((int)(v & 0xFF));
    }

    /** Minimal bridge from NIO channel to OutputStream without extra allocations. */
    static final class Channels2 {
        static OutputStream outputStream(final FileChannel ch) {
            return new OutputStream() {
                private final ByteBuffer one = ByteBuffer.allocate(1);
                @Override public void write(int b) throws IOException {
                    one.clear();
                    one.put((byte)(b & 0xFF)).flip();
                    while (one.hasRemaining()) ch.write(one);
                }
                @Override public void write(byte[] b, int off, int len) throws IOException {
                    ByteBuffer buf = ByteBuffer.wrap(b, off, len);
                    while (buf.hasRemaining()) ch.write(buf);
                }
                @Override public void flush() throws IOException { /* no-op for channel */ }
                @Override public void close() throws IOException { ch.close(); }
            };
        }
    }
}
