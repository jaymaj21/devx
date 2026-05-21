package com.trading.domain;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * UDP probe runtime for JAR-instrumented apps.
 *
 * Payload per HIT (20 bytes, big-endian):
 *   type:u16=1, appId:u16, instanceId:u32, threadId:u32, stackDepth:u32, locationId:u32
 *
 * Defaults can be overridden via system properties:
 *   -Dmprewriter.host=127.0.0.1
 *   -Dmprewriter.port=8083
 *   -Dmprewriter.appId=12345
 *   -Dmprewriter.instanceId=2
 */
public final class mprewriter {
    private static final short MSG_HIT = 1;
    private static final short MSG_LOG = 2;
    private static final short MSG_CTX_ATTACH = 3;
    private static final short MSG_CTX_WITHDRAW = 4;
    private static final String HOST = System.getProperty("mprewriter.host", "127.0.0.1");
    private static final int PORT = Integer.getInteger("mprewriter.port", 8083);
    private static final short APPLICATION_ID = Short.parseShort(System.getProperty("mprewriter.appId", "12345"));
    private static final int INSTANCE_ID = Integer.getInteger("mprewriter.instanceId", 2);

    private static final int MAX_HITS_PER_PACKET = 72; // 72*20 = 1440 bytes
    private static final int QUEUE_CAPACITY = Integer.getInteger("mprewriter.queueCapacity", 1_000_000);
    private static final BlockingQueue<OutboundMessage> QUEUE = new ArrayBlockingQueue<>(QUEUE_CAPACITY);

    private static DatagramSocket socket;
    private static InetAddress address;
    private static ByteBuffer sendBuffer;
    private static DatagramPacket packet;
    private static final Object SHUTDOWN_LOCK = new Object();

    private static volatile boolean running = true;
    private static volatile boolean shutdownComplete = false;
    private static Thread senderThread;

    // Fast thread-local depth for instrumented method scopes
    private static final ThreadLocal<int[]> DEPTH = ThreadLocal.withInitial(() -> new int[1]);

    private interface OutboundMessage { }

    private static final class HitMessage implements OutboundMessage {
        private final long packed;

        private HitMessage(long packed) {
            this.packed = packed;
        }
    }

    private static final class RawMessage implements OutboundMessage {
        private final byte[] payload;

        private RawMessage(byte[] payload) {
            this.payload = payload;
        }
    }

    static {
        try {
            address = InetAddress.getByName(HOST);
            socket = new DatagramSocket();
            try { socket.setSendBufferSize(1 << 20); } catch (Exception ignored) {}
            sendBuffer = ByteBuffer.allocate(MAX_HITS_PER_PACKET * 20);
            packet = new DatagramPacket(sendBuffer.array(), 0, address, PORT);

            senderThread = new Thread(mprewriter::runSender, "mprewriter-udp-sender");
            senderThread.setDaemon(true);
            senderThread.start();

            Runtime.getRuntime().addShutdownHook(new Thread(mprewriter::shutdown));
        } catch (Exception e) {
            running = false;
        }
    }

    private static void runSender() {
        try {
            while (running || !QUEUE.isEmpty()) {
                OutboundMessage first = QUEUE.poll(2, TimeUnit.MILLISECONDS);
                if (first == null) continue;
                if (first instanceof HitMessage) {
                    sendBuffer.rewind();
                    int hits = 0;
                    hits += writeHitFromPacked(((HitMessage) first).packed);
                    // Coalesce only adjacent hit messages so control messages preserve order.
                    while (hits < MAX_HITS_PER_PACKET) {
                        OutboundMessage next = QUEUE.peek();
                        if (!(next instanceof HitMessage)) break;
                        next = QUEUE.poll();
                        if (!(next instanceof HitMessage)) break;
                        writeHitFromPacked(((HitMessage) next).packed);
                        hits++;
                    }
                    packet.setLength(hits * 20);
                    socket.send(packet);
                    sendBuffer.clear();
                } else if (first instanceof RawMessage) {
                    byte[] payload = ((RawMessage) first).payload;
                    DatagramPacket rawPacket = new DatagramPacket(payload, payload.length, address, PORT);
                    socket.send(rawPacket);
                }
            }
        } catch (IOException | InterruptedException ignored) {
        } finally {
            try { socket.close(); } catch (Exception ignored) {}
        }
    }

    private static int writeHitFromPacked(long packed) {
        int threadId = (int) ((packed >>> 48) & 0xFFFF);
        int depth    = (int) ((packed >>> 32) & 0xFFFF);
        int locId    = (int) (packed & 0xFFFFFFFFL);
        sendBuffer.putShort(MSG_HIT);
        sendBuffer.putShort(APPLICATION_ID);
        sendBuffer.putInt(INSTANCE_ID);
        sendBuffer.putInt(threadId);
        sendBuffer.putInt(depth);
        sendBuffer.putInt(locId);
        return 1;
    }

    // --- API for instrumenter ---
    public static void scope_ENTER() {
        DEPTH.get()[0]++;
    }
    public static void scope_EXIT() {
        int[] d = DEPTH.get();
        if (d[0] > 0) d[0]--;
    }
    public static int current_depth() { return DEPTH.get()[0]; }

    /** Single-call probe site: reads current_depth and enqueues. */
    public static void hit(int locationId) {
        if (!running) return;
        int threadId = (int) (Thread.currentThread().getId() & 0x7fffffff);
        int depth = current_depth();
        long packed = ((((long)threadId) & 0xFFFFL) << 48)
                    | ((((long)depth) & 0xFFFFL) << 32)
                    | (locationId & 0xFFFFFFFFL);
        try {
            // Block when queue is full to avoid dropping hits under burst load
            QUEUE.put(new HitMessage(packed));
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }

    /** Backward compatibility: original name used by legacy instruments. */
    public static void scope_START(int locationId) { hit(locationId); }

    public static void apply_context(String context) {
        sendContextMessage(MSG_CTX_ATTACH, context);
    }

    public static void withdraw_context(String context) {
        sendContextMessage(MSG_CTX_WITHDRAW, context);
    }

    public static void reset_context_to(String context) {
        withdraw_context("ALL");
        apply_context(context);
    }

    public static void add_context_from_callstack() { /* no-op */ }

    public static void log(String message) {
        if (!running || message == null) return;
        byte[] utf8 = message.getBytes(StandardCharsets.UTF_8);
        int offset = 0;
        while (offset < utf8.length) {
            int chunkLen = Math.min(utf8.length - offset, 1184);
            while (chunkLen > 0 && offset + chunkLen < utf8.length && (utf8[offset + chunkLen] & 0xC0) == 0x80) {
                chunkLen--;
            }
            if (chunkLen <= 0) {
                chunkLen = Math.min(utf8.length - offset, 1184);
            }
            byte[] payload = buildLogPayload(utf8, offset, chunkLen);
            try {
                QUEUE.put(new RawMessage(payload));
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                return;
            }
            offset += chunkLen;
        }
    }

    public static void shutdown() {
        synchronized (SHUTDOWN_LOCK) {
            if (shutdownComplete) return;
            running = false;
            try {
                if (senderThread != null) {
                    while (senderThread.isAlive()) {
                        senderThread.join(500);
                    }
                }
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            } finally {
                shutdownComplete = true;
            }
        }
    }

    private static void sendContextMessage(short messageType, String context) {
        if (!running || context == null) return;
        byte[] contextBytes = context.getBytes(StandardCharsets.UTF_8);
        ByteBuffer buffer = ByteBuffer.allocate(2 + contextBytes.length);
        buffer.putShort(messageType);
        buffer.put(contextBytes);
        byte[] payload = new byte[buffer.position()];
        System.arraycopy(buffer.array(), 0, payload, 0, payload.length);
        try {
            QUEUE.put(new RawMessage(payload));
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }

    private static byte[] buildLogPayload(byte[] utf8, int offset, int length) {
        int threadId = (int) (Thread.currentThread().getId() & 0x7fffffff);
        int depth = current_depth();
        ByteBuffer buffer = ByteBuffer.allocate(18 + length);
        buffer.putShort(MSG_LOG);
        buffer.putShort(APPLICATION_ID);
        buffer.putInt(INSTANCE_ID);
        buffer.putInt(threadId);
        buffer.putInt(depth);
        buffer.putShort((short) length);
        buffer.put(utf8, offset, length);
        return buffer.array();
    }
}
