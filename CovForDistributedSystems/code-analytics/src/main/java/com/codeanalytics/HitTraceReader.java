package com.codeanalytics;

import java.io.*;
import java.nio.charset.StandardCharsets;

/**
 * Reads/dumps files produced by HitTraceWriter.
 * This is intentionally forgiving: if payload looks like UTF-8, shows it,
 * otherwise shows a compact hex preview.
 */
public final class HitTraceReader {

    public static final short FLAG_HIT = HitTraceWriter.FLAG_HIT;
    public static final short FLAG_LOG = HitTraceWriter.FLAG_LOG;
    public static final short FLAG_CTX_ATTACH = HitTraceWriter.FLAG_CTX_ATTACH;
    public static final short FLAG_CTX_WITHDRAW = HitTraceWriter.FLAG_CTX_WITHDRAW;

    public static void dump(File file, PrintStream out) throws IOException {
        try (InputStream in = new BufferedInputStream(new FileInputStream(file), 1 << 20)) {
            // Header
            byte[] magic = in.readNBytes(8);
            if (magic.length < 8) throw new EOFException("empty/short file");
            String m = new String(magic, StandardCharsets.US_ASCII);
            if (!"HITTRC01".equals(m)) {
                out.println("# Unknown magic: " + m + " (continuing anyway)");
            }
            int endian = in.read();
            if (endian < 0) throw new EOFException();
            long startMillis = readLong(in);
            out.printf("# start=%d (%s) endian=%d\n", startMillis, new java.util.Date(startMillis), endian);

            long idx = 0;
            while (true) {
                int b1 = in.read(); if (b1 < 0) break;
                int b2 = in.read(); if (b2 < 0) break;
                short flag = (short)(((b1 & 0xFF) << 8) | (b2 & 0xFF));
                int src = in.read(); if (src < 0) break;
                long nano = readLong(in);
                int len = readInt(in);
                byte[] payload = in.readNBytes(len);
                if (payload.length < len) throw new EOFException("truncated payload");

                out.printf("[%08d] flag=%d src=%s t(nanos)=%d len=%d ", idx++,
                        (int)flag, srcName(src), nano, len);
                // If log or looks like mostly printable UTF-8, print as text
                boolean looksText = (flag == FLAG_LOG) || isMostlyPrintableUtf8(payload);
                if (looksText) {
                    out.print("text=\"");
                    out.print(safeUtf8(payload));
                    out.println("\"");
                } else {
                    out.print("hex=");
                    out.println(hexPreview(payload, Math.min(32, len)));
                }
            }
        }
    }

    private static String srcName(int s) {
        switch (s) {
            case HitTraceWriter.SRC_UDP: return "UDP";
            case HitTraceWriter.SRC_TCP: return "TCP";
            case HitTraceWriter.SRC_INTERNAL: return "INT";
            default: return "UNK(" + s + ")";
        }
    }

    private static boolean isMostlyPrintableUtf8(byte[] bytes) {
        int printable = 0;
        int sample = Math.min(bytes.length, 64);
        for (int i=0;i<sample;i++) {
            int b = bytes[i] & 0xFF;
            if (b == 9 || b == 10 || b == 13 || (b >= 32 && b < 127)) printable++;
        }
        return printable > (sample * 0.85);
    }

    private static String safeUtf8(byte[] bytes) {
        try {
            return new String(bytes, StandardCharsets.UTF_8).replace("\n", "\\n");
        } catch (Exception e) {
            return hexPreview(bytes, Math.min(32, bytes.length));
        }
    }

    private static String hexPreview(byte[] bytes, int limit) {
        StringBuilder sb = new StringBuilder(limit*2);
        for (int i=0;i<limit;i++) sb.append(String.format("%02X", bytes[i]));
        if (bytes.length > limit) sb.append("...");
        return sb.toString();
    }

    private static int readInt(InputStream in) throws IOException {
        int a=in.read(); if(a<0) throw new EOFException();
        int b=in.read(); if(b<0) throw new EOFException();
        int c=in.read(); if(c<0) throw new EOFException();
        int d=in.read(); if(d<0) throw new EOFException();
        return ((a&0xFF)<<24)|((b&0xFF)<<16)|((c&0xFF)<<8)|(d&0xFF);
    }
    private static long readLong(InputStream in) throws IOException {
        long r=0;
        for(int i=0;i<8;i++){
            int b=in.read(); if(b<0) throw new EOFException();
            r=(r<<8)| (b&0xFF);
        }
        return r;
    }
}
