package com.trading.domain;

import java.io.*;
import java.net.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.lang.StackWalker;
import java.nio.file.*;
import java.util.Arrays;
import java.util.concurrent.ArrayBlockingQueue;

public class mprewriter {
    private static final String RECEIVER_HOST = "127.0.0.1";
    private static final int UDP_PORT = 8083;
    private static final short APPLICATION_ID = 12345;
    private static final int INSTANCE_ID = 2;
    //private static final String TIMING_FILE = "timings.csv";

    private static DatagramSocket udpSocket;
    private static InetAddress receiverAddress;

    private static final int MAX_HITS_PER_PACKET = 72;
    private static final int BATCH_INTERVAL_MS = 5;
    private static final int QUEUE_CAPACITY = 10000;
    private static final ArrayBlockingQueue<Long> probeQueue = new ArrayBlockingQueue<>(QUEUE_CAPACITY);
    private static final ArrayBlockingQueue<byte[]> logQueue = new ArrayBlockingQueue<>(QUEUE_CAPACITY);
    private static final ByteBuffer sendBuffer = ByteBuffer.allocate(20 * MAX_HITS_PER_PACKET);
    private static DatagramPacket batchPacket;

    private static final int MAX_LOG_LENGTH = 1400;
    private static final ByteBuffer logSendBuffer = ByteBuffer.allocate(MAX_LOG_LENGTH);
    private static final DatagramPacket logPacket;

    private static volatile boolean running = true;
    private static Thread senderThread;

    // StackWalker-based app-frame depth
    private static final StackWalker WALKER = StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE);
    private static final String[] DEFAULT_PREFIXES = new String[]{"com.trading.", "com.example."};
    private static boolean isAppFrame(String cn) {
        for (String p : DEFAULT_PREFIXES) if (cn.startsWith(p)) return true;
        return false;
    }
    private static int stackDepth() {
        return WALKER.walk(stream -> {
            int depth = 0;
            for (StackWalker.StackFrame f : (Iterable<StackWalker.StackFrame>) stream::iterator) {
                String cn = f.getClassName();
                if (cn.equals(mprewriter.class.getName())) continue; // skip probe utility frames
                if (isAppFrame(cn)) depth++;
            }
            return depth;
        });
    }

    static {
        try {
            receiverAddress = InetAddress.getByName(RECEIVER_HOST);
            udpSocket = new DatagramSocket();
            batchPacket = new DatagramPacket(sendBuffer.array(), 0, receiverAddress, UDP_PORT);
            logPacket = new DatagramPacket(logSendBuffer.array(), 0, receiverAddress, UDP_PORT);

            // Initialize timings file with header if it does not exist
            /*
            if (!Files.exists(Paths.get(TIMING_FILE))) {
                Files.write(Paths.get(TIMING_FILE), "locationId,timeTakenNanos\n".getBytes(), StandardOpenOption.CREATE);
            }
            */

            senderThread = new Thread(() -> {
                while (running && !Thread.currentThread().isInterrupted()) {
                    try {
                        Thread.sleep(BATCH_INTERVAL_MS);
                        sendBuffer.clear();
                        int hitsProcessed = 0;

                        Long hit;
                        while (hitsProcessed < MAX_HITS_PER_PACKET && (hit = probeQueue.poll()) != null) {
                            int threadId = (int)((hit >>> 48) & 0xFFFF);
                            int depth    = (int)((hit >>> 32) & 0xFFFF);
                            int locationId = (int)(hit & 0xFFFFFFFFL);

                            if (locationId == 0) {
                                // If locationId == 0, that's not treated as a hit
                                // Instead it's a marker for the presence of a log message
                                byte[] logBytes = logQueue.poll();
                                if (logBytes != null) {
                                    logSendBuffer.rewind();
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
                            } else {
                                    sendBuffer.putShort((short) 1); // messageType
                                    sendBuffer.putShort(APPLICATION_ID);
                                    sendBuffer.putInt(INSTANCE_ID);
                                    sendBuffer.putInt(threadId);
                                    sendBuffer.putInt(depth);
                                    sendBuffer.putInt(locationId);
                                hitsProcessed++;
                            }
                        }

                        if (hitsProcessed > 0) {
                            //Files.write(Paths.get(TIMING_FILE), ("Hits processed "+hitsProcessed + "\n").getBytes(), StandardOpenOption.APPEND);
                            batchPacket.setLength(hitsProcessed * 20);
                            udpSocket.send(batchPacket);
                        }
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                    } catch (IOException ioe) {
                        ioe.printStackTrace();
                    }
                }
            }, "ProbeSenderThread");

            senderThread.setDaemon(true);
            senderThread.start();

        } catch (IOException e) {
            throw new RuntimeException("Initialization failed", e);
        }
    }

    public static void scope_START(int locationId) {
        int threadId = (int) (Thread.currentThread().getId() & 0x7FFFFFFF);
        int depth = stackDepth();
        long packed = ((((long)threadId) & 0xFFFFL) << 48)
                    | ((((long)depth) & 0xFFFFL) << 32)
                    | (locationId & 0xFFFFFFFFL);
        probeQueue.offer(packed);
        /*
        long endTime = System.nanoTime();
        long duration = endTime - startTime;
        try {
            Files.write(Paths.get(TIMING_FILE), (locationId + "," + duration + "\n").getBytes(), StandardOpenOption.APPEND);
        } catch (IOException e) {
            e.printStackTrace();
        }
         */
    }

    public static void log(String logMessage) {
        String remainingMessage = logMessage;
        while (true) {
            if(remainingMessage.isEmpty()) {
                return;
            }
            boolean isWithinRange = false;
            byte[] logBytes = remainingMessage.getBytes(StandardCharsets.UTF_8);

            // 2. Final check
            final int MAX_LOG_BYTES = 1184;
            if (logBytes.length > MAX_LOG_BYTES) {
                // Fallback: keep only first MAX_LOG_BYTES bytes (may split character)
                // For safety: decode bytes to string and back, to ensure no partial characters
                int safeLen = MAX_LOG_BYTES;
                while (safeLen > 0 && (logBytes[safeLen - 1] & 0xC0) == 0x80) {
                    // UTF-8 continuation byte, step back to char boundary
                    safeLen--;
                }
                logBytes = Arrays.copyOf(logBytes, safeLen);
                String truncatedMessage = new String(logBytes, StandardCharsets.UTF_8);
                int lengthCoveredSoFar = truncatedMessage.length();
                logBytes = truncatedMessage.getBytes(StandardCharsets.UTF_8); // Re-encode for safety
                remainingMessage = remainingMessage.substring(lengthCoveredSoFar);
            } else {
                isWithinRange = true;
            }
            // Now logBytes is always <= MAX_LOG_BYTES
            int threadId = (int) (Thread.currentThread().getId() & 0x7FFFFFFF);
            int depth = stackDepth();
            long packed = ((((long)threadId) & 0xFFFFL) << 48) | ((((long)depth) & 0xFFFFL) << 32);
            synchronized (mprewriter.class) {
                probeQueue.offer(packed);
                logQueue.offer(logBytes);
            }

            if(isWithinRange) break;
        }

    }

    public static void close() {
        running = false;
        senderThread.interrupt();

        try {
            senderThread.join();

            // Final flush: drain any remaining hits
            sendBuffer.clear();
            int hitsProcessed = 0;
            Long hit;
            while ((hit = probeQueue.poll()) != null) {
                int threadId = (int)((hit >>> 48) & 0xFFFF);
                int depth    = (int)((hit >>> 32) & 0xFFFF);
                int locationId = (int)(hit & 0xFFFFFFFFL);

                if (locationId == 0) {
                    byte[] logBytes = logQueue.poll();
                    if (logBytes != null) {
                        logSendBuffer.rewind();
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
                } else {

                    sendBuffer.putShort((short) 1);
                    sendBuffer.putShort(APPLICATION_ID);
                    sendBuffer.putInt(INSTANCE_ID);
                    sendBuffer.putInt(threadId);
                    sendBuffer.putInt(depth);
                    sendBuffer.putInt(locationId);
                    hitsProcessed++;

                    if (hitsProcessed == MAX_HITS_PER_PACKET) {
                        batchPacket.setLength(hitsProcessed * 20);
                        //Files.write(Paths.get(TIMING_FILE), ("Hits processed "+hitsProcessed + "\n").getBytes(), StandardOpenOption.APPEND);
                        udpSocket.send(batchPacket);
                        sendBuffer.clear();
                        hitsProcessed = 0;
                    }
                }
            }

            if (hitsProcessed > 0) {
                batchPacket.setLength(hitsProcessed * 20);
                //Files.write(Paths.get(TIMING_FILE), ("Hits processed "+hitsProcessed + "\n").getBytes(), StandardOpenOption.APPEND);
                udpSocket.send(batchPacket);
            }
        } catch (InterruptedException | IOException e) {
            e.printStackTrace();
        }

        udpSocket.close();
    }

    public static void add_context_from_callstack() {
        // Implementation placeholder
    }
}
