package com.codeanalytics;

import java.io.*;
import java.net.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class TcpListener implements Runnable {
    private final int port;
    private final Map<String, Integer> hitRecords;
    private final HitTraceWriter traceWriter;

    public TcpListener(int port, Map<String, Integer> hitRecords, HitTraceWriter traceWriter) {
        this.port = port;
        this.hitRecords = hitRecords;
        this.traceWriter = traceWriter;
    }

    @Override
    public void run() {
        try (ServerSocket serverSocket = new ServerSocket(port)) {
            System.out.println("[TCP] Listening on port " + port + "...");
            while (true) {
                Socket client = serverSocket.accept();
                new Thread(() -> handleClient(client)).start();
            }
        } catch (IOException e) {
            System.err.println("[TCP] Server socket error: " + e.getMessage());
        }
    }

    private void handleClient(Socket client) {
        String clientAddr = client.getInetAddress().getHostAddress() + ":" + client.getPort();
        try (InputStream in = client.getInputStream()) {
            byte[] buffer = new byte[1204];
            int bytesRead;
            ByteArrayOutputStream baos = new ByteArrayOutputStream();

            while ((bytesRead = in.read(buffer)) != -1) {
                if (bytesRead == 0) continue;
                baos.write(buffer, 0, bytesRead);

                byte[] data = baos.toByteArray();
                ByteBuffer messageBuffer = ByteBuffer.wrap(data);

                int processed = 0;

                while (messageBuffer.remaining() >= 2) {
                    int recordStart = processed;
                    messageBuffer.mark();
                    short messageType = messageBuffer.getShort();
                    messageBuffer.reset();

                    // HIT
                    if (messageType == 1 && messageBuffer.remaining() >= 20) {
                        short msgType = messageBuffer.getShort();
                        short appId = messageBuffer.getShort();
                        int instanceId = messageBuffer.getInt();
                        int threadId = messageBuffer.getInt();
                        int stackDepth = messageBuffer.getInt();
                        int locationId = messageBuffer.getInt();

                        String record = String.format("%d,%d,%d,%d,%d", appId, instanceId, threadId, stackDepth, locationId);
                        hitRecords.merge(record, 1, Integer::sum);

                        ContextManager.recordHit(appId, instanceId, locationId);

                        // Trace with per-record flag
                        if (traceWriter != null) {
                            int recLen = 20;
                            traceWriter.writeRaw(HitTraceWriter.FLAG_HIT, HitTraceWriter.SRC_TCP, data, recordStart, recLen);
                        }

                        processed += 20;
                        messageBuffer.position(processed);

                        // LOG
                    } else if (messageType == 2 && messageBuffer.remaining() >= 18) {
                        short msgType = messageBuffer.getShort();
                        short appId = messageBuffer.getShort();
                        int instanceId = messageBuffer.getInt();
                        int threadId = messageBuffer.getInt();
                        int stackDepth = messageBuffer.getInt();
                        short logLen = messageBuffer.getShort();

                        if (messageBuffer.remaining() >= logLen) {
                            byte[] logBytes = new byte[logLen];
                            messageBuffer.get(logBytes);
                            String logMsg = new String(logBytes, StandardCharsets.UTF_8);
                            System.out.printf("[LOG] AppID=%d InstanceID=%d ThreadID=%d StackDepth=%d: %s%n", appId, instanceId, threadId, stackDepth, logMsg);

                            if (traceWriter != null) {
                                int recLen = 18 + logLen;
                                traceWriter.writeRaw(HitTraceWriter.FLAG_LOG, HitTraceWriter.SRC_TCP, data, recordStart, recLen);
                            }

                            processed += (18 + logLen);
                            messageBuffer.position(processed);
                        } else {
                            // Not enough bytes for the declared log string length
                            break;
                        }

                        // CONTEXTS
                    } else if ((messageType == 3 || messageType == 4) && messageBuffer.remaining() >= 2) {
                        short msgType = messageBuffer.getShort();
                        int ctxLen = messageBuffer.remaining();
                        byte[] ctxBytes = new byte[ctxLen];
                        messageBuffer.get(ctxBytes);
                        String context = new String(ctxBytes, StandardCharsets.UTF_8);

                        if (messageType == 3) {
                            ContextManager.applyContext(context);
                            System.out.println("[CTX] Applied context: " + context);
                            if (traceWriter != null) {
                                int recLen = 2 + ctxLen;
                                traceWriter.writeRaw(HitTraceWriter.FLAG_CTX_ATTACH, HitTraceWriter.SRC_TCP, data, recordStart, recLen);
                            }
                        } else {
                            ContextManager.withdrawContext(context);
                            System.out.println("[CTX] Withdrew context: " + context);
                            if (traceWriter != null) {
                                int recLen = 2 + ctxLen;
                                traceWriter.writeRaw(HitTraceWriter.FLAG_CTX_WITHDRAW, HitTraceWriter.SRC_TCP, data, recordStart, recLen);
                            }
                        }
                        processed = messageBuffer.position();

                    } else {
                        break; // Unrecognized or incomplete message, wait for more data
                    }
                }

                // Remove processed bytes from baos
                if (processed > 0) {
                    byte[] leftover = new byte[messageBuffer.remaining()];
                    messageBuffer.get(leftover);
                    baos.reset();
                    baos.write(leftover, 0, leftover.length);
                }
            }
        } catch (IOException e) {
            System.err.println("[TCP] Client error (" + clientAddr + "): " + e.getMessage());
        } finally {
            try { client.close(); } catch (IOException ignore) {}
        }
    }
}
