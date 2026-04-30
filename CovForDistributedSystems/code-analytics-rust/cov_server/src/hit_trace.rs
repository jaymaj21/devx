// src/hit_trace.rs
use std::fs::{File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::Path;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const MAGIC: &[u8;8] = b"HITTRC01";
const ENDIAN_BIG: u8 = 0;

pub const FLAG_HIT: u16 = 1;
pub const FLAG_LOG: u16 = 2;
pub const FLAG_CTX_ATTACH: u16 = 3;
pub const FLAG_CTX_WITHDRAW: u16 = 4;
pub const FLAG_TS: u16 = 9; // periodic timestamp (payload: u64 epochMillis)

pub const SRC_UDP: u8 = 0;
pub const SRC_TCP: u8 = 1;
pub const SRC_INTERNAL: u8 = 2;

/// Writer for the binary trace format used by the Java HitTraceWriter.
/// Big-endian layout:
/// Header once: "HITTRC01" (8) + endian flag (1, 0=big) + fileStartEpochMillis (8)
/// Per record: flag(u16) + source(u8) + capturedNanoTime(u64) + len(u32) + payload[len]
pub struct HitTraceWriter {
    file: File,
    wrote_header: bool,
    start_instant: Instant,
}

impl HitTraceWriter {
    /// Create a new writer. If `append` is true and the file already exists and is non-empty,
    /// we assume the header is present and will append records. Otherwise we write the header.
    pub fn create<P: AsRef<Path>>(path: P, append: bool) -> io::Result<Self> {
        let mut opts = OpenOptions::new();
        opts.write(true).create(true);
        if append { opts.append(true); } else { opts.truncate(true); }
        let file = opts.open(path)?;
        let meta_len = file.metadata()?.len();
        let mut w = HitTraceWriter {
            file,
            wrote_header: false,
            start_instant: Instant::now(),
        };
        if append && meta_len > 0 {
            w.wrote_header = true;
        } else {
            w.write_header()?;
        }
        Ok(w)
    }

    fn write_header(&mut self) -> io::Result<()> {
        if self.wrote_header { return Ok(()); }
        self.file.write_all(MAGIC)?;
        self.file.write_all(&[ENDIAN_BIG])?;
        let now_ms = SystemTime::now().duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::from_millis(0)).as_millis() as u64;
        self.write_u64_be(now_ms)?;
        self.file.flush()?;
        self.wrote_header = true;
        Ok(())
    }

    pub fn write_raw(&mut self, flag: u16, source: u8, payload: &[u8]) -> io::Result<()> {
        if !self.wrote_header { self.write_header()?; }
        if flag >= 10000 { return Err(io::Error::new(io::ErrorKind::InvalidInput, "flag must be < 10000")); }
        // Captured "nanoTime": duration since start of process, like Java's System.nanoTime semantics.
        let nanos = self.start_instant.elapsed().as_nanos() as u64;
        self.write_u16_be(flag)?;
        self.file.write_all(&[source])?;
        self.write_u64_be(nanos)?;
        self.write_u32_be(payload.len() as u32)?;
        self.file.write_all(payload)?;
        Ok(())
    }

    pub fn write_utf8(&mut self, flag: u16, source: u8, text: &str) -> io::Result<()> {
        self.write_raw(flag, source, text.as_bytes())
    }

    pub fn flush(&mut self) -> io::Result<()> { self.file.flush() }
    pub fn persist(&mut self) -> io::Result<()> { self.file.sync_all() }
    pub fn close(mut self) -> io::Result<()> { self.file.flush() }
    fn write_u16_be(&mut self, v: u16) -> io::Result<()> { self.file.write_all(&v.to_be_bytes()) }
    fn write_u32_be(&mut self, v: u32) -> io::Result<()> { self.file.write_all(&v.to_be_bytes()) }
    fn write_u64_be(&mut self, v: u64) -> io::Result<()> { self.file.write_all(&v.to_be_bytes()) }
}

/// Reader/dumper for the same format.
pub struct HitTraceReader;

impl HitTraceReader {
    pub fn dump_file<P: AsRef<Path>>(path: P, mut out: impl Write) -> io::Result<()> {
        let mut f = File::open(path)?;
        let mut header = [0u8; 17];
        f.read_exact(&mut header)?;
        if &header[0..8] != MAGIC { return Err(io::Error::new(io::ErrorKind::InvalidData, "bad magic")); }
        if header[8] != ENDIAN_BIG { return Err(io::Error::new(io::ErrorKind::InvalidData, "unsupported endianness")); }
        let file_start_ms = u64::from_be_bytes(header[9..17].try_into().unwrap());
        writeln!(out, "# Trace start epochMillis={}", file_start_ms)?;
        let mut idx: u64 = 0;
        loop {
            let mut rec_hdr = [0u8; 15];
            match f.read_exact(&mut rec_hdr) {
                Ok(()) => (),
                Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => break,
                Err(e) => return Err(e),
            }
            let flag = u16::from_be_bytes([rec_hdr[0], rec_hdr[1]]);
            let src = rec_hdr[2];
            let nanos = u64::from_be_bytes(rec_hdr[3..11].try_into().unwrap());
            let len = u32::from_be_bytes(rec_hdr[11..15].try_into().unwrap()) as usize;
            let mut payload = vec![0u8; len];
            f.read_exact(&mut payload)?;
            write!(out, "[{:08}] flag={} src={} t(nanos)={} len={} ", idx, flag, src_name(src), nanos, len)?;
            let looks_text = flag == FLAG_LOG || looks_printable_utf8(&payload);
            if looks_text {
                let txt = String::from_utf8_lossy(&payload).replace('\n', "\\n");
                writeln!(out, "\"{}\"", txt)?;
            } else {
                writeln!(out, "hex={}", hex_preview(&payload, 32))?;
            }
            idx += 1;
        }
        Ok(())
    }
}

fn looks_printable_utf8(bytes: &[u8]) -> bool {
    if bytes.is_empty() { return false; }
    if std::str::from_utf8(bytes).is_err() { return false; }
    let printable = bytes.iter().filter(|b| {
        let c = **b;
        (c >= 0x20 && c <= 0x7E) || c == b' ' || c == b'\t' || c == b'\n' || c == b'\r'
    }).count();
    printable * 100 / bytes.len().max(1) >= 85
}

fn hex_preview(bytes: &[u8], limit: usize) -> String {
    let mut s = String::new();
    let n = bytes.len().min(limit);
    for b in &bytes[..n] { s.push_str(&format!("{:02X}", b)); }
    if bytes.len() > limit { s.push_str("..."); }
    s
}

fn src_name(s: u8) -> &'static str {
    match s {
        SRC_UDP => "UDP",
        SRC_TCP => "TCP",
        SRC_INTERNAL => "INT",
        _ => "UNK",
    }
}
