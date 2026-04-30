package com.trading.domain;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.ByteBuffer;
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
    private static final String HOST = System.getProperty("mprewriter.host", "127.0.0.1");
    private static final int PORT = Integer.getInteger("mprewriter.port", 8083);
    private static final short APPLICATION_ID = Short.parseShort(System.getProperty("mprewriter.appId", "12345"));
    private static final int INSTANCE_ID = Integer.getInteger("mprewriter.instanceId", 2);

    private static final int MAX_HITS_PER_PACKET = 72; // 72*20 = 1440 bytes
    private static final int QUEUE_CAPACITY = Integer.getInteger("mprewriter.queueCapacity", 1_000_000);
    private static final BlockingQueue<Long> QUEUE = new ArrayBlockingQueue<>(QUEUE_CAPACITY);

    private static DatagramSocket socket;
    private static InetAddress address;
    private static ByteBuffer sendBuffer;
    private static DatagramPacket packet;

    private static volatile boolean running = true;
    private static Thread senderThread;

    // Fast thread-local depth for instrumented method scopes
    private static final ThreadLocal<int[]> DEPTH = ThreadLocal.withInitial(() -> new int[1]);

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

            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                running = false;
                // Wait for sender to drain the queue and exit
                try {
                    while (senderThread.isAlive()) {
                        senderThread.join(500);
                    }
                } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
            }));
        } catch (Exception e) {
            running = false;
        }
    }

    private static void runSender() {
        try {
            while (running || !QUEUE.isEmpty()) {
                Long packed = QUEUE.poll(2, TimeUnit.MILLISECONDS);
                if (packed == null) continue;
                sendBuffer.rewind();
                int hits = 0;
                // Write first record
                hits += writeHitFromPacked(packed);
                // Try to coalesce up to MAX_HITS_PER_PACKET
                for (; hits < MAX_HITS_PER_PACKET; hits++) {
                    Long more = QUEUE.poll();
                    if (more == null) break;
                    writeHitFromPacked(more);
                }
                packet.setLength(hits * 20);
                socket.send(packet);
                sendBuffer.clear();
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
        sendBuffer.putShort((short)1);
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
            QUEUE.put(packed);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }

    /** Backward compatibility: original name used by legacy instruments. */
    public static void scope_START(int locationId) { hit(locationId); }

    // Placeholder for future context features
    public static void add_context_from_callstack() { /* no-op */ }
}
