// src/bin/read_trace.rs — standalone reader CLI
use std::io::{self, Write};
use hit_trace::HitTraceReader;

fn main() -> io::Result<()> {
    let path = std::env::args().nth(1).expect("usage: read_trace <file>");
    let mut out = std::io::BufWriter::new(std::io::stdout());
    HitTraceReader::dump_file(path, &mut out)
}
