import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.SocketTimeoutException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class capinger {
    private static final String DEFAULT_HOST = "127.0.0.1";
    private static final int DEFAULT_PORT = 8083;
    private static final int DEFAULT_TIMEOUT_MS = 3000;

    private static final short MSG_HIT = 1;
    private static final short MSG_LOG = 2;
    private static final short MSG_CTX_ATTACH = 3;
    private static final short MSG_CTX_WITHDRAW = 4;

    public static void main(String[] args) throws Exception {
        try {
            run(args);
        } catch (IllegalArgumentException e) {
            System.err.println(e.getMessage());
            System.exit(1);
        }
    }

    private static void run(String[] args) throws Exception {
        Config config = parseConfig(args);
        if (config.remaining.isEmpty() || isHelp(config.remaining.get(0))) {
            printUsage();
            return;
        }

        String mode = config.remaining.get(0).toUpperCase();
        List<String> modeArgs = config.remaining.subList(1, config.remaining.size());
        byte[] payload;
        boolean expectReply = false;

        switch (mode) {
            case "CMD":
                payload = commandPayload(modeArgs);
                expectReply = true;
                break;
            case "HIT":
                payload = hitPayload(modeArgs);
                break;
            case "LOG":
                payload = logPayload(modeArgs);
                break;
            case "CTX":
            case "CTX_ATTACH":
            case "CONTEXT":
            case "APPLY_CONTEXT":
                payload = contextPayload(MSG_CTX_ATTACH, modeArgs);
                break;
            case "CTX_WITHDRAW":
            case "WITHDRAW_CONTEXT":
                payload = contextPayload(MSG_CTX_WITHDRAW, modeArgs);
                break;
            default:
                throw usageError("Unknown packet type: " + config.remaining.get(0));
        }

        send(config, payload, expectReply);
    }

    private static Config parseConfig(String[] args) {
        Config config = new Config();
        for (int i = 0; i < args.length; i++) {
            String arg = args[i];
            if ("--host".equals(arg)) {
                config.host = requireValue(args, ++i, "--host");
            } else if ("--port".equals(arg)) {
                config.port = parseInt(requireValue(args, ++i, "--port"), "--port");
            } else if ("--timeout".equals(arg) || "--timeout-ms".equals(arg)) {
                config.timeoutMs = parseInt(requireValue(args, ++i, arg), arg);
            } else {
                config.remaining.add(arg);
            }
        }
        return config;
    }

    private static byte[] commandPayload(List<String> args) {
        if (args.isEmpty()) {
            throw usageError("CMD requires a remote command");
        }

        List<String> remote = new ArrayList<>(args);
        String command = remote.get(0);
        String normalized = command.startsWith(":") ? command.substring(1) : command;
        if ("coverage-hits".equalsIgnoreCase(normalized) || "hits".equalsIgnoreCase(normalized)) {
            remote.set(0, "save-hits");
        } else if ("coverage".equalsIgnoreCase(normalized)) {
            remote.set(0, "coverage-report");
        } else if (command.startsWith(":")) {
            remote.set(0, normalized);
        }

        return ("CMD " + join(remote, 0)).getBytes(StandardCharsets.UTF_8);
    }

    private static byte[] hitPayload(List<String> args) {
        if (args.size() < 5 || args.size() > 6) {
            throw usageError("HIT usage: HIT <appId> <instanceId> <threadId> <stackDepth> <locationId> [repeatCount]");
        }
        short appId = parseShort(args.get(0), "appId");
        int instanceId = parseInt(args.get(1), "instanceId");
        int threadId = parseInt(args.get(2), "threadId");
        int stackDepth = parseInt(args.get(3), "stackDepth");
        int locationId = parseInt(args.get(4), "locationId");
        int repeatCount = args.size() == 6 ? parseInt(args.get(5), "repeatCount") : 1;
        if (repeatCount < 1) {
            throw usageError("repeatCount must be >= 1");
        }

        ByteBuffer buffer = ByteBuffer.allocate(20 * repeatCount).order(ByteOrder.BIG_ENDIAN);
        for (int i = 0; i < repeatCount; i++) {
            buffer.putShort(MSG_HIT);
            buffer.putShort(appId);
            buffer.putInt(instanceId);
            buffer.putInt(threadId);
            buffer.putInt(stackDepth);
            buffer.putInt(locationId);
        }
        return buffer.array();
    }

    private static byte[] logPayload(List<String> args) {
        if (args.size() < 5) {
            throw usageError("LOG usage: LOG <appId> <instanceId> <threadId> <stackDepth> <message...>");
        }
        short appId = parseShort(args.get(0), "appId");
        int instanceId = parseInt(args.get(1), "instanceId");
        int threadId = parseInt(args.get(2), "threadId");
        int stackDepth = parseInt(args.get(3), "stackDepth");
        byte[] message = join(args, 4).getBytes(StandardCharsets.UTF_8);
        if (message.length > Short.MAX_VALUE) {
            throw usageError("LOG message is too large: " + message.length + " bytes");
        }

        ByteBuffer buffer = ByteBuffer.allocate(18 + message.length).order(ByteOrder.BIG_ENDIAN);
        buffer.putShort(MSG_LOG);
        buffer.putShort(appId);
        buffer.putInt(instanceId);
        buffer.putInt(threadId);
        buffer.putInt(stackDepth);
        buffer.putShort((short) message.length);
        buffer.put(message);
        return buffer.array();
    }

    private static byte[] contextPayload(short messageType, List<String> args) {
        if (args.isEmpty()) {
            throw usageError("Context usage: CTX <label...> or CTX_WITHDRAW <label...>");
        }
        byte[] context = join(args, 0).getBytes(StandardCharsets.UTF_8);
        ByteBuffer buffer = ByteBuffer.allocate(2 + context.length).order(ByteOrder.BIG_ENDIAN);
        buffer.putShort(messageType);
        buffer.put(context);
        return buffer.array();
    }

    private static void send(Config config, byte[] payload, boolean expectReply) throws IOException {
        InetAddress address = InetAddress.getByName(config.host);
        DatagramPacket packet = new DatagramPacket(payload, payload.length, address, config.port);
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.send(packet);
            System.out.println("Sent " + payload.length + " bytes to " + config.host + ":" + config.port);
            if (expectReply) {
                socket.setSoTimeout(config.timeoutMs);
                byte[] replyBytes = new byte[65535];
                DatagramPacket reply = new DatagramPacket(replyBytes, replyBytes.length);
                try {
                    socket.receive(reply);
                    String text = new String(reply.getData(), reply.getOffset(), reply.getLength(), StandardCharsets.UTF_8);
                    System.out.println(text);
                } catch (SocketTimeoutException e) {
                    System.out.println("No UDP reply within " + config.timeoutMs + "ms");
                    System.exit(2);
                }
            }
        }
    }

    private static String requireValue(String[] args, int index, String option) {
        if (index >= args.length) {
            throw usageError(option + " requires a value");
        }
        return args[index];
    }

    private static boolean isHelp(String text) {
        return "-h".equals(text) || "--help".equals(text) || "help".equalsIgnoreCase(text);
    }

    private static int parseInt(String text, String name) {
        try {
            return Integer.parseInt(text);
        } catch (NumberFormatException e) {
            throw usageError(name + " must be an integer: " + text);
        }
    }

    private static short parseShort(String text, String name) {
        int value = parseInt(text, name);
        if (value < 0 || value > 0xFFFF) {
            throw usageError(name + " must fit in an unsigned 16-bit value: " + text);
        }
        return (short) value;
    }

    private static String join(List<String> args, int start) {
        StringBuilder sb = new StringBuilder();
        for (int i = start; i < args.size(); i++) {
            if (i > start) {
                sb.append(' ');
            }
            sb.append(args.get(i));
        }
        return sb.toString();
    }

    private static IllegalArgumentException usageError(String message) {
        return new IllegalArgumentException(message + System.lineSeparator()
                + "Run: java capinger --help");
    }

    private static void printUsage() {
        System.out.println("Usage:");
        System.out.println("  javac capinger.java");
        System.out.println("  java capinger [--host HOST] [--port PORT] [--timeout MS] CMD <remote-command> [args...]");
        System.out.println("  java capinger [--host HOST] [--port PORT] HIT <appId> <instanceId> <threadId> <stackDepth> <locationId> [repeatCount]");
        System.out.println("  java capinger [--host HOST] [--port PORT] LOG <appId> <instanceId> <threadId> <stackDepth> <message...>");
        System.out.println("  java capinger [--host HOST] [--port PORT] CTX <context-label...>");
        System.out.println("  java capinger [--host HOST] [--port PORT] CTX_WITHDRAW <context-label...>");
        System.out.println();
        System.out.println("Examples:");
        System.out.println("  java capinger CMD status");
        System.out.println("  java capinger CMD coverage-report 1 1 app.cov");
        System.out.println("  java capinger CMD coverage-hits hits.csv");
        System.out.println("  java capinger HIT 1 1 7 2 1234");
        System.out.println("  java capinger HIT 1 1 7 2 1234 100");
        System.out.println("  java capinger LOG 1 1 7 2 hello from capinger");
        System.out.println("  java capinger CTX test-run-42");
        System.out.println("  java capinger CTX_WITHDRAW test-run-42");
        System.out.println("  java capinger CMD exit");
        System.out.println();
        System.out.println("Remote CMD aliases:");
        System.out.println("  coverage-hits -> save-hits");
        System.out.println("  coverage      -> coverage-report");
    }

    private static final class Config {
        String host = DEFAULT_HOST;
        int port = DEFAULT_PORT;
        int timeoutMs = DEFAULT_TIMEOUT_MS;
        List<String> remaining = new ArrayList<>();
    }
}
