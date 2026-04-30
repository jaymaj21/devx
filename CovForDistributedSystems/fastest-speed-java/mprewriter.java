

import java.io.IOException;
import java.net.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.lang.StackWalker;
import java.util.Arrays;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.atomic.AtomicLong;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;

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
    // Bounded MPSC ring buffer for hits (lock-free)
    private static int RING_CAP = 1 << 20; // configurable via -Dmprewriter.ringCap
    private static long[] HIT_SLOTS;
    private static int[]  HIT_READY;
    private static final AtomicLong HIT_HEAD = new AtomicLong(0);
    private static final AtomicLong HIT_TAIL = new AtomicLong(0);
    private static final VarHandle VH_HIT_READY;
    private static final VarHandle VH_HIT_SLOTS;
    private static final ArrayBlockingQueue<byte[]> logQueue = new ArrayBlockingQueue<>(8192);
    private static final ByteBuffer sendBuffer = ByteBuffer.allocate(20 * MAX_HITS_PER_PACKET);
    private static DatagramPacket batchPacket;

    private static final int MAX_LOG_LENGTH = 1184;
    private static final ByteBuffer logSendBuffer = ByteBuffer.allocate(2+2+4+4+4+2 + MAX_LOG_LENGTH);
    private static final DatagramPacket logPacket;

    private static volatile boolean running = true;
    private static Thread senderThread;

    // Depth computation: configurable for speed
    // Preferred fast flag: -Dmprewriter.depthConstant=true to avoid StackWalker costs.
    // Backward compat: also honors -Dmprewriter.depthMode=constant|stack
    private static final boolean DEPTH_CONSTANT;
    static {
        boolean dc = Boolean.getBoolean("mprewriter.depthConstant");
        if (!dc) {
            String mode = System.getProperty("mprewriter.depthMode", "stack");
            dc = "constant".equalsIgnoreCase(mode) || "const".equalsIgnoreCase(mode);
        }
        DEPTH_CONSTANT = dc;
    }
    private static final StackWalker WALKER = StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE);
    private static final String[] DEFAULT_PREFIXES = new String[]{"com.example.", "com.trading."};
    private static boolean isAppFrame(String cn) {
        for (String p : DEFAULT_PREFIXES) if (cn.startsWith(p)) return true;
        return false;
    }
    private static int computeDepthStack() {
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
    private static int currentDepth() { return DEPTH_CONSTANT ? 1 : computeDepthStack(); }

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

            // Configure ring capacity (power of two)
            try {
                int cap = Integer.getInteger("mprewriter.ringCap", RING_CAP);
                if (cap < 1024) cap = 1024;
                int pow2 = 1;
                while (pow2 < cap && pow2 > 0) pow2 <<= 1;
                // if overflow, fallback to default
                if (pow2 <= 0) pow2 = 1 << 20;
                RING_CAP = pow2;
            } catch (Throwable ignore) { RING_CAP = 1 << 20; }

            // Allocate ring arrays
            HIT_SLOTS = new long[RING_CAP];
            HIT_READY = new int[RING_CAP];

            // VarHandle init
            try {
                VH_HIT_READY = MethodHandles.arrayElementVarHandle(int[].class);
                VH_HIT_SLOTS = MethodHandles.arrayElementVarHandle(long[].class);
            } catch (Exception e) { throw new RuntimeException(e); }

            // Optional: banner
            try { System.out.println("mprewriter: ringCap=" + RING_CAP); } catch (Throwable ignore) {}

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
            // Drain ring up to MAX_HITS_PER_PACKET hits
            while (hitsProcessed < MAX_HITS_PER_PACKET) {
                long h = HIT_HEAD.getAcquire();
                if (h == HIT_TAIL.getAcquire()) break; // empty
                int idx = (int)(h & (RING_CAP - 1));
                int ready = (int) VH_HIT_READY.getAcquire(HIT_READY, idx);
                if (ready == 0) {
                    if (!running) { // skip a hole on shutdown to avoid hang
                        HIT_HEAD.setRelease(h + 1);
                        continue;
                    }
                    break; // wait for producer
                }
                long entry = (long) VH_HIT_SLOTS.getAcquire(HIT_SLOTS, idx);
                VH_HIT_READY.setRelease(HIT_READY, idx, 0);
                HIT_HEAD.setRelease(h + 1);

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

    private static void enqueuePacked(long packed) {
        for (;;) {
            long t = HIT_TAIL.getAcquire();
            long h = HIT_HEAD.getAcquire();
            if (t - h >= RING_CAP) { Thread.onSpinWait(); continue; }
            if (!HIT_TAIL.compareAndSet(t, t + 1)) { Thread.onSpinWait(); continue; }
            int idx = (int)(t & (RING_CAP - 1));
            while (((int) VH_HIT_READY.getAcquire(HIT_READY, idx)) != 0) { Thread.onSpinWait(); }
            VH_HIT_SLOTS.setRelease(HIT_SLOTS, idx, packed);
            VH_HIT_READY.setRelease(HIT_READY, idx, 1);
            break;
        }
    }

    private static void hitPacked(int locationId, int depth) {
        int threadId = (int) (Thread.currentThread().getId() & 0x7FFFFFFF);
        long packed = (((long)threadId & 0xFFFFL) << 48)
                    | (((long)depth & 0xFFFFL) << 32)
                    | (locationId & 0xFFFFFFFFL);
        enqueuePacked(packed);
    }

    // Public API for single-call probe insertion
    public static void hit(int locationId) {
        hitPacked(locationId, currentDepth());
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
            int depth = currentDepth();
            long marker = (((long)threadId & 0xFFFFL) << 48) | (((long)depth & 0xFFFFL) << 32); // locId=0
            enqueuePacked(marker);
            try { logQueue.put(chunk); } catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
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
