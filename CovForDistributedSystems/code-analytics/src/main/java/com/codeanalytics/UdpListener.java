package com.codeanalytics;

import java.io.IOException;
import java.net.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.*;

public class UdpListener implements Runnable {
    private final int port;
    private final Map<String, Integer> hitRecords;
    private final ExecutorService parsePool;

    public UdpListener(int port, Map<String, Integer> hitRecords) {
        this.port = port;
        this.hitRecords = hitRecords;
        int n = Math.max(2, Runtime.getRuntime().availableProcessors());
        this.parsePool = Executors.newFixedThreadPool(n, r -> {
            Thread t = new Thread(r, "UDP-Parser");
            t.setDaemon(true);
            return t;
        });
    }

    @Override
    public void run() {
        try (DatagramSocket serverSocket = new DatagramSocket(port)) {
            // Increase OS receive buffer to reduce packet drops under burst load
            try { serverSocket.setReceiveBufferSize(1 << 24); } catch (Exception ignore) {}
            System.out.println("[UDP] Listening on port " + port + "...");
            while (true) {
                byte[] recvBuf = new byte[65535];
                DatagramPacket packet = new DatagramPacket(recvBuf, recvBuf.length);
                serverSocket.receive(packet);
                int packetLen = packet.getLength();
                if (packetLen <= 0) continue;
                // Copy exact payload slice to avoid holding large arrays
                byte[] payload = new byte[packetLen];
                System.arraycopy(packet.getData(), 0, payload, 0, packetLen);

                if (isRemoteCommand(payload)) {
                    String command = new String(payload, 4, payload.length - 4, StandardCharsets.UTF_8);
                    String result = RuntimeCommands.executeRemoteCommand(command, hitRecords);
                    byte[] response = result.getBytes(StandardCharsets.UTF_8);
                    DatagramPacket responsePacket = new DatagramPacket(
                            response, response.length, packet.getAddress(), packet.getPort());
                    serverSocket.send(responsePacket);
                    System.out.println("[UDP-CMD] " + command.trim() + " -> " + result);
                    continue;
                }

                HitTraceWriter traceWriter = RuntimeCommands.getTraceWriter();
                if (traceWriter != null) {
                    try {
                        short mt = 1;
                        try {
                            mt = ByteBuffer.wrap(payload).getShort(0);
                        } catch (Exception ignore) {}
                        short flag;
                        if (mt == 2) flag = HitTraceWriter.FLAG_LOG;
                        else if (mt == 3) flag = HitTraceWriter.FLAG_CTX_ATTACH;
                        else if (mt == 4) flag = HitTraceWriter.FLAG_CTX_WITHDRAW;
                        else flag = HitTraceWriter.FLAG_HIT;
                        traceWriter.writeRaw(flag, HitTraceWriter.SRC_UDP, payload, 0, packetLen);
                    } catch (IOException e) {
                        System.err.println("[UDP] Trace write error: " + e.getMessage());
                    }
                }

                parsePool.execute(() -> parsePacket(ByteBuffer.wrap(payload), hitRecords));
            }
        } catch (IOException e) {
            System.err.println("[UDP] Socket error: " + e.getMessage());
        }
    }

    private static boolean isRemoteCommand(byte[] payload) {
        return payload.length > 4
                && payload[0] == 'C'
                && payload[1] == 'M'
                && payload[2] == 'D'
                && Character.isWhitespace((char) payload[3]);
    }

    private static void parsePacket(ByteBuffer messageBuffer, Map<String, Integer> hitRecords) {
        while (messageBuffer.remaining() >= 2) {
            messageBuffer.mark();
            short messageType = messageBuffer.getShort();
            messageBuffer.reset();

            if (messageType == 1 && messageBuffer.remaining() >= 20) {
                messageBuffer.getShort(); // type
                short appId = messageBuffer.getShort();
                int instanceId = messageBuffer.getInt();
                int threadId = messageBuffer.getInt();
                int stackDepth = messageBuffer.getInt();
                int locationId = messageBuffer.getInt();

                String record = String.format("%d,%d,%d,%d,%d", appId, instanceId, threadId, stackDepth, locationId);
                hitRecords.merge(record, 1, Integer::sum);
                ContextManager.recordHit(appId, instanceId, locationId);

            } else if (messageType == 2 && messageBuffer.remaining() >= 18) {
                messageBuffer.getShort(); // type
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
                } else {
                    break;
                }
            } else if ((messageType == 3 || messageType == 4) && messageBuffer.remaining() >= 2) {
                messageBuffer.getShort(); // type
                int ctxLen = messageBuffer.remaining();
                byte[] ctxBytes = new byte[ctxLen];
                messageBuffer.get(ctxBytes);
                String context = new String(ctxBytes, StandardCharsets.UTF_8);
                if (messageType == 3) {
                    ContextManager.applyContext(context);
                    System.out.println("[CTX] Applied context: " + context);
                } else {
                    ContextManager.withdrawContext(context);
                    System.out.println("[CTX] Withdrew context: " + context);
                }
            } else {
                break;
            }
        }
    }
}
