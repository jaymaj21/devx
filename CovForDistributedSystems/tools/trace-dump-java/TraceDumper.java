import java.io.*;
import java.nio.charset.StandardCharsets;

// Standalone HITTRC01 trace dumper (legacy format with stack-depth digits)
public final class TraceDumper {
    private static int u8(byte[] b,int o){ return b[o]&0xFF; }
    private static int u16(byte[] b,int o){ return ((b[o]&0xFF)<<8) | (b[o+1]&0xFF); }
    private static int u32(byte[] b,int o){ return ((b[o]&0xFF)<<24)|((b[o+1]&0xFF)<<16)|((b[o+2]&0xFF)<<8)|(b[o+3]&0xFF); }
    private static long u64(byte[] b,int o){
        return ((long)(b[o]&0xFF) << 56) | ((long)(b[o+1]&0xFF) << 48) | ((long)(b[o+2]&0xFF) << 40) |
               ((long)(b[o+3]&0xFF) << 32) | ((long)(b[o+4]&0xFF) << 24) | ((long)(b[o+5]&0xFF) << 16) |
               ((long)(b[o+6]&0xFF) <<  8) | ((long)(b[o+7]&0xFF));
    }

    private static String depthDigits(int depth){
        if (depth<=0) return ":<";
        StringBuilder sb = new StringBuilder(1+depth+1);
        sb.append(':');
        for (int i=1;i<=depth;i++) sb.append((char)('0'+(i%10)));
        sb.append('<');
        return sb.toString();
    }

    public static void main(String[] args) throws Exception {
        if (args.length<1){ System.err.println("Usage: java TraceDumper <hits.trace> [-start <nanos|RFC3339>] [-end <nanos|RFC3339>]"); System.exit(2);}        
        String path = args[0];
        long startNs = Long.MIN_VALUE; boolean startIsEpoch = false;
        long endNs = Long.MAX_VALUE;   boolean endIsEpoch = false;
        for (int i=1;i+1<args.length;i++){
            if ("-start".equals(args[i])) {
                String v = args[i+1];
                try {
                    if (v.indexOf('T')>=0 || v.indexOf('-')>=0) {
                        java.time.Instant inst = java.time.Instant.parse(v);
                        startNs = inst.getEpochSecond()*1_000_000_000L + inst.getNano();
                        startIsEpoch = true;
                    } else {
                        startNs = Long.parseLong(v);
                    }
                } catch (Exception e) { startNs = Long.parseLong(v); }
                i++;
            }
            else if ("-end".equals(args[i])) {
                String v = args[i+1];
                try {
                    if (v.indexOf('T')>=0 || v.indexOf('-')>=0) {
                        java.time.Instant inst = java.time.Instant.parse(v);
                        endNs = inst.getEpochSecond()*1_000_000_000L + inst.getNano();
                        endIsEpoch = true;
                    } else {
                        endNs = Long.parseLong(v);
                    }
                } catch (Exception e) { endNs = Long.parseLong(v); }
                i++;
            }
        }
        try (InputStream in = new BufferedInputStream(new FileInputStream(path))) {
            byte[] magic = in.readNBytes(8); if (magic.length<8) return; // "HITTRC01"
            in.readNBytes(1); // endian
            long startMillis = u64(in.readNBytes(8), 0); // startMillis
            byte[] hdr = new byte[15];
            long firstNano = Long.MIN_VALUE;
            while (true){
                int r = in.readNBytes(hdr,0,2); if (r==0) break; if (r<2) break; // flag
                int flag = u16(hdr,0);
                r = in.readNBytes(hdr,0,13); if (r<13) break; // src(1), nanos(8), len(4)
                long nanos = u64(hdr,1);
                int len = u32(hdr,9);
                byte[] payload = in.readNBytes(len); if (payload.length<len) break;
                if (firstNano == Long.MIN_VALUE) firstNano = nanos;
                long cmp = nanos;
                if (startIsEpoch || endIsEpoch) {
                    cmp = startMillis*1_000_000L + (nanos - firstNano);
                }
                if (!(cmp >= startNs && cmp <= endNs)) {
                    // Allow TS frames (flag==9) to be printed regardless of filter
                    if (!(flag==9 && len==8)) { continue; }
                }
                if (flag == 9 && len == 8) {
                    long ms = ((long)u32(payload,0) << 32) | (u32(payload,4) & 0xffffffffL);
                    java.time.Instant inst = java.time.Instant.ofEpochMilli(ms);
                    System.out.println("TS " + java.time.ZonedDateTime.ofInstant(inst, java.time.ZoneOffset.UTC));
                } else if (len>=2){
                    int off = 0;
                    while (off + 2 <= len) {
                        int mt = u16(payload,off);
                        if (mt==1 && off + 20 <= len){
                            int app = u16(payload,off+2);
                            int inst2 = u32(payload,off+4);
                            int thr = u32(payload,off+8);
                            int depth = u32(payload,off+12);
                            int loc = u32(payload,off+16);
                            String pref = depthDigits(depth);
                            System.out.printf("%sT%d> %d, %d, %d%n", pref, loc, app, inst2, thr);
                            off += 20;
                        } else if (mt==2 && off + 18 <= len){
                            int msglen = u16(payload,off+16);
                            int have = Math.min(msglen, len-(off+18));
                            String msg = new String(payload,off+18,have, StandardCharsets.UTF_8)
                                    .replace('\n',' ').replace('\r',' ').replace('\t',' ');
                            System.out.println("LOG " + msg);
                            off += 18 + have;
                        } else if (mt==3 || mt==4){
                            break;
                        } else {
                            break;
                        }
                    }
                }
            }
        }
    }
}
