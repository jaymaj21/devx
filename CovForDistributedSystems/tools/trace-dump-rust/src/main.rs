// Standalone HITTRC01 trace dumper (legacy style with stack-depth digits)
use std::env; use std::fs::File; use std::io::{self, Read}; use std::path::Path;

fn be16(b: &[u8]) -> u16 { u16::from_be_bytes([b[0], b[1]]) }
fn be32(b: &[u8]) -> u32 { u32::from_be_bytes([b[0], b[1], b[2], b[3]]) }
fn be64(b: &[u8]) -> u64 { u64::from_be_bytes([b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]]) }

fn depth_digits(depth: u32) -> String {
    if depth == 0 { return ":<".to_string(); }
    let mut s = String::with_capacity(1 + depth as usize + 1);
    s.push(':');
    for i in 1..=depth { s.push(char::from(b'0' + ((i % 10) as u8))); }
    s.push('<'); s
}

fn dump_hittrc(path: &Path, start_ns: Option<u64>, end_ns: Option<u64>, start_is_epoch: bool, end_is_epoch: bool) -> io::Result<()> {
    let mut f = File::open(path)?; let mut buf = Vec::new(); f.read_to_end(&mut buf)?; let mut off=0usize;
    if buf.len() < 17 { return Ok(()); }
    off+=8; off+=1; let start_ms = be64(&buf[off..off+8]); off+=8; // magic, endian, startMillis
    let mut first_nano: Option<u64> = None;
    while off + 15 <= buf.len() {
        // flag:2, src:1, nanos:8, len:4
        let flag = be16(&buf[off..off+2]); off += 2;
        off += 1;
        let nanos = be64(&buf[off..off+8]); off += 8;
        if first_nano.is_none() { first_nano = Some(nanos); }
        let len = be32(&buf[off..off+4]) as usize; off += 4;
        if off + len > buf.len() { break; }
        let payload = &buf[off..off+len]; off += len;
        // Always include TS frames for context regardless of filter
        if flag == 9 && payload.len() == 8 {
            let ms_hi = be32(&payload[0..4]) as u64; let ms_lo = be32(&payload[4..8]) as u64;
            let ms = (ms_hi<<32) | ms_lo;
            let dt = chrono::DateTime::<chrono::Utc>::from(std::time::UNIX_EPOCH + std::time::Duration::from_millis(ms));
            println!("TS {}", dt.to_rfc3339());
            continue;
        }
        let mut cmp = nanos;
        if start_is_epoch || end_is_epoch {
            if let Some(first) = first_nano { cmp = start_ms*1_000_000 + (nanos - first); }
        }
        if let Some(s) = start_ns { if cmp < s { continue; } }
        if let Some(e) = end_ns { if cmp > e { continue; } }
        if payload.len() < 2 { continue; }
        let mut off = 0usize;
        while off + 2 <= payload.len() {
            let mt = be16(&payload[off..off+2]);
            if mt == 1 && off + 20 <= payload.len() {
                let app = be16(&payload[off+2..off+4]) as u32; let inst = be32(&payload[off+4..off+8]); let thr = be32(&payload[off+8..off+12]);
                let depth = be32(&payload[off+12..off+16]); let loc = be32(&payload[off+16..off+20]);
                println!("{}T{}> {}, {}, {}", depth_digits(depth), loc, app, inst, thr);
                off += 20;
            } else if mt == 2 && off + 18 <= payload.len() {
                let mlen = be16(&payload[off+16..off+18]) as usize; let have = mlen.min(payload.len().saturating_sub(off+18));
                let s = String::from_utf8_lossy(&payload[off+18..off+18+have]).replace(['\n','\r','\t'], " ");
                println!("LOG {}", s);
                off += 18 + have;
            } else if mt == 3 || mt == 4 {
                break;
            } else {
                break;
            }
        }
    }
    Ok(())
}

fn parse_ns(v: &str) -> (Option<u64>, bool) {
    if v.contains('T') || v.contains('-') {
        if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(v) {
            let ts = dt.timestamp(); let nanos = dt.timestamp_subsec_nanos() as u64;
            if ts >= 0 { return (Some((ts as u64)*1_000_000_000u64 + nanos), true); }
        }
        (None, false)
    } else { (v.parse::<u64>().ok(), false) }
}

fn main(){
    let args: Vec<String> = env::args().collect();
    if args.len()<2{ eprintln!("Usage: dump_old <hits.trace> [-start <nanos|RFC3339>] [-end <nanos|RFC3339>]"); std::process::exit(2);} 
    let p=Path::new(&args[1]);
    let mut start_ns: Option<u64> = None; let mut end_ns: Option<u64> = None; 
    let mut start_is_epoch = false; let mut end_is_epoch = false;
    let mut i = 2; 
    while i + 1 < args.len() { 
        if args[i] == "-start" { let (v,ep) = parse_ns(&args[i+1]); start_ns = v; start_is_epoch = ep; i += 2; }
        else if args[i] == "-end" { let (v,ep) = parse_ns(&args[i+1]); end_ns = v; end_is_epoch = ep; i += 2; }
        else { i += 1; }
    }
    if let Err(e)=dump_hittrc(p, start_ns, end_ns, start_is_epoch, end_is_epoch){ eprintln!("error: {}", e); std::process::exit(1);} 
}
