// src/trace_hook.rs
use std::sync::Arc;
use parking_lot::Mutex;
use once_cell::sync::OnceCell;

use crate::hit_trace::{HitTraceWriter, FLAG_HIT, FLAG_LOG, FLAG_CTX_ATTACH, FLAG_CTX_WITHDRAW, FLAG_TS, SRC_TCP, SRC_UDP, SRC_INTERNAL};

static TRACE_WRITER: OnceCell<Arc<Mutex<HitTraceWriter>>> = OnceCell::new();
use std::time::{SystemTime, UNIX_EPOCH};

pub fn trace_init() {
    if TRACE_WRITER.get().is_some() { return; }
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis();
    let filename = format!("hits-{}.trace", now_ms);
    println!("[TRACE] Writing to {}", filename);

    let writer = HitTraceWriter::create(&filename, false).expect("open trace file");
    TRACE_WRITER.set(Arc::new(Mutex::new(writer))).ok();
}

pub fn trace_write_udp(data: &[u8]) {
    if let Some(w) = TRACE_WRITER.get() {
        let flag = if data.len() >= 2 {
            let mt = u16::from_be_bytes([data[0], data[1]]);
            match mt { 2 => FLAG_LOG, 3 => FLAG_CTX_ATTACH, 4 => FLAG_CTX_WITHDRAW, _ => FLAG_HIT }
        } else { FLAG_HIT };
        let _ = w.lock().write_raw(flag, SRC_UDP, data);
    }
}

pub fn trace_write_tcp(data: &[u8]) {
    if let Some(w) = TRACE_WRITER.get() {
        let _ = w.lock().write_raw(FLAG_LOG, SRC_TCP, data);
    }
}

pub fn trace_write_tcp_with_flag(flag: u16, data: &[u8]) {
    if let Some(w) = TRACE_WRITER.get() {
        let _ = w.lock().write_raw(flag, SRC_TCP, data);
    }
}

pub fn trace_flush() {
    if let Some(w) = TRACE_WRITER.get() {
        let _ = w.lock().flush();
    }
}

pub fn trace_write_ts() {
    use std::time::{SystemTime, UNIX_EPOCH};
    if let Some(w) = TRACE_WRITER.get() {
        let ms = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64;
        let payload = ms.to_be_bytes();
        let _ = w.lock().write_raw(FLAG_TS, SRC_INTERNAL, &payload);
    }
}

pub fn trace_persist() {
    if let Some(w) = TRACE_WRITER.get() {
        let _ = w.lock().persist();
    }
}
