package com.example.fractal;

import java.io.IOException;
import java.net.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.lang.StackWalker;
import java.util.Arrays;
import java.util.concurrent.ArrayBlockingQueue;

/** Minimal UDP probe with thread-local stack depth and try-with-resources guard. */
public class mprewriter {
    private static final String RECEIVER_HOST = "127.0.0.1";
    private static final int UDP_PORT = 8083;
    private static final short APPLICATION_ID = 12345;
    private static final int INSTANCE_ID = 2;

    private static DatagramSocket udpSocket;
    private static InetAddress receiverAddress;

    private static final int MAX_HITS_PER_PACKET = 72; // 72*20 = 1440 bytes
    private static final int BATCH_INTERVAL_MS = 2;
    private static final int QUEUE_CAPACITY = 500_000;
    private static final ArrayBlockingQueue<Long> probeQueue = new ArrayBlockingQueue<>(QUEUE_CAPACITY);
    private static final ArrayBlockingQueue<byte[]> logQueue = new ArrayBlockingQueue<>(8192);
    private static final ByteBuffer sendBuffer = ByteBuffer.allocate(20 * MAX_HITS_PER_PACKET);
    private static DatagramPacket batchPacket;

    private static final int MAX_LOG_LENGTH = 1184;
    private static final ByteBuffer logSendBuffer = ByteBuffer.allocate(2+2+4+4+4+2 + MAX_LOG_LENGTH);
    private static final DatagramPacket logPacket;

    private static volatile boolean running = true;
    private static Thread senderThread;

    // StackWalker-based depth computation (single-call probes)
    private static final StackWalker WALKER = StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE);
    private static final String[] DEFAULT_PREFIXES = new String[]{"com.example.", "com.trading."};
    private static boolean isAppFrame(String cn) {
        for (String p : DEFAULT_PREFIXES) if (cn.startsWith(p)) return true;
        return false;
    }
    private static int stackDepth() {
        return WALKER.walk(stream -> {
            int depth = 0;
            for (StackWalker.StackFrame f : (Iterable<StackWalker.StackFrame>) stream::iterator) {
                String cn = f.getClassName();
                if (cn.equals(mprewriter.class.getName())) continue; // skip probe frames
                if (isAppFrame(cn)) depth++;
            }
            return depth;
        });
    }

    // Optional helper to mirror earlier API; not required by instrumenter
    public static final class Scope implements AutoCloseable {
        public Scope(int locationId) { hit(locationId); }
        @Override public void close() { /* no-op */ }
    }
    public static Scope scopeStart(int locationId) { return new Scope(locationId); }

    static {
        try {
            receiverAddress = InetAddress.getByName(RECEIVER_HOST);
            udpSocket = new DatagramSocket();
            try { udpSocket.setSendBufferSize(1<<20); } catch (Exception ignore) {}
            batchPacket = new DatagramPacket(sendBuffer.array(), 0, receiverAddress, UDP_PORT);
            logPacket = new DatagramPacket(logSendBuffer.array(), 0, receiverAddress, UDP_PORT);

            senderThread = new Thread(() -> {
                while (running && !Thread.currentThread().isInterrupted()) {
                    try {
                        Thread.sleep(BATCH_INTERVAL_MS);
                        flushHits();
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                    } catch (IOException ioe) {
                        ioe.printStackTrace();
                    }
                }
                try { flushHits(); } catch (IOException ignore) {}
            }, "ProbeSenderThread");
            senderThread.setDaemon(true);
            senderThread.start();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static void flushHits() throws IOException {
        while (true) {
            sendBuffer.clear();
            int hitsProcessed = 0;
            Long entry;
            // Pack up to MAX_HITS_PER_PACKET hits per datagram
            while (hitsProcessed < MAX_HITS_PER_PACKET && (entry = probeQueue.poll()) != null) {
                int threadId = (int)(entry >>> 48);
                int depth    = (int)((entry >>> 32) & 0xFFFF);
                int locId    = (int)(entry & 0xFFFFFFFFL);
                if (locId == 0) {
                    byte[] logBytes = logQueue.poll();
                    if (logBytes != null) sendLog(threadId, depth, logBytes);
                } else {
                    sendBuffer.putShort((short)1);
                    sendBuffer.putShort(APPLICATION_ID);
                    sendBuffer.putInt(INSTANCE_ID);
                    sendBuffer.putInt(threadId);
                    sendBuffer.putInt(depth);
                    sendBuffer.putInt(locId);
                    hitsProcessed++;
                }
            }
            if (hitsProcessed > 0) {
                batchPacket.setLength(hitsProcessed * 20);
                udpSocket.send(batchPacket);
            } else {
                // Nothing left to send
                break;
            }
        }
    }

    private static void hitPacked(int locationId, int depth) {
        int threadId = (int) (Thread.currentThread().getId() & 0x7FFFFFFF);
        long packed = (((long)threadId & 0xFFFFL) << 48)
                    | (((long)depth & 0xFFFFL) << 32)
                    | (locationId & 0xFFFFFFFFL);
        // Block if needed to avoid dropping hits under burst load
        try { probeQueue.put(packed); } catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
    }

    // Public API for single-call probe insertion
    public static void hit(int locationId) {
        hitPacked(locationId, stackDepth());
    }

    // Preserve original API name expected by source-level instrumenter
    public static void scope_START(int locationId) {
        hit(locationId);
    }

    private static void sendLog(int threadId, int depth, byte[] logBytes) throws IOException {
        logSendBuffer.clear();
        logSendBuffer.putShort((short)2);
        logSendBuffer.putShort(APPLICATION_ID);
        logSendBuffer.putInt(INSTANCE_ID);
        logSendBuffer.putInt(threadId);
        logSendBuffer.putInt(depth);
        logSendBuffer.putShort((short)logBytes.length);
        logSendBuffer.put(logBytes);
        logPacket.setLength(18+logBytes.length);
        udpSocket.send(logPacket);
    }

    public static void log(String msg) {
        byte[] bytes = msg.getBytes(StandardCharsets.UTF_8);
        while (bytes.length > 0) {
            int len = Math.min(bytes.length, MAX_LOG_LENGTH);
            int safe = len;
            while (safe > 0 && (bytes[safe-1] & 0xC0) == 0x80) safe--; // avoid splitting UTF-8
            byte[] chunk = Arrays.copyOf(bytes, safe);
            int threadId = (int) (Thread.currentThread().getId() & 0x7FFFFFFF);
            int depth = stackDepth();
            long marker = (((long)threadId & 0xFFFFL) << 48) | (((long)depth & 0xFFFFL) << 32);
            synchronized (mprewriter.class) {
                try {
                    probeQueue.put(marker); // locId=0 signals log follows
                    logQueue.put(chunk);
                } catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
            }
            bytes = Arrays.copyOfRange(bytes, safe, bytes.length);
        }
    }

    public static void shutdown() {
        running = false;
        senderThread.interrupt();
        try { senderThread.join(); } catch (InterruptedException ignore) {}
        try { flushHits(); } catch (IOException ignore) {}
        udpSocket.close();
    }
}
