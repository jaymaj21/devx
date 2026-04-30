//! mprewriter: method-based probe with async UDP, BIG-ENDIAN 16-byte Hit frames
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::fs::File;
use std::io::Write;
use std::net::UdpSocket;
use std::path::Path;
use std::sync::{mpsc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

// ================== Config ==================
const RECEIVER_HOST: &str = "127.0.0.1";
const UDP_PORT: u16 = 8083;
const APPLICATION_ID: u16 = 12345;
const INSTANCE_ID: u32 = 2;
const MAX_LOG_BYTES: usize = 1184;
const BATCH_INTERVAL_MS: u64 = 5;

// ================ Stack depth fathomer === 
use std::cell::Cell;

thread_local! {
    // Per-thread depth counter; starts at 0.
    static CALL_DEPTH: Cell<u32> = Cell::new(0);
}

/// Get the current per-thread call depth.
pub fn call_depth() -> u32 {
    CALL_DEPTH.with(|d| d.get())
}

/// An RAII guard that increments a per-thread call-depth on creation
/// and decrements it on drop (even if unwinding due to panic).
#[must_use] // Warn if you construct and immediately drop it.
pub struct mprewriter_stack_fathomer(());

impl mprewriter_stack_fathomer {
    /// Enter a new call-depth scope. Holding the guard keeps the depth incremented.
    pub fn enter() -> Self {
        CALL_DEPTH.with(|d| d.set(d.get().saturating_add(1)));
        mprewriter_stack_fathomer(())
    }
}

impl Drop for mprewriter_stack_fathomer {
    fn drop(&mut self) {
        CALL_DEPTH.with(|d| {
            let cur = d.get();
            debug_assert!(cur > 0, "call-depth underflow");
            d.set(cur.saturating_sub(1));
        });
    }
}


// ================== Public API ==================
pub static PROBE: Lazy<Mutex<Option<Probe>>> = Lazy::new(|| Mutex::new(None));

pub fn start() { start_with(None); }

pub fn start_with(trace_path: Option<&Path>) {
    let mut g = PROBE.lock().expect("poisoned");
    if g.is_some() { return; }
    *g = Some(Probe::new(trace_path));
}

pub fn shutdown() {
    let mut g = PROBE.lock().expect("poisoned");
    if let Some(mut p) = g.take() { p.shutdown(); }
}

pub fn set_context<S: Into<String>>(name: S) -> usize {
    let mut g = PROBE.lock().expect("poisoned");
    g.as_mut().expect("probe not started").set_context(name.into())
}

pub fn scope_START(loc_id: i32) {
    let mut g = PROBE.lock().expect("poisoned");
    g.as_mut().expect("probe not started").hit(loc_id).ok();
}

pub fn log_message(msg: &str) {
    let g = PROBE.lock().expect("poisoned");
    g.as_ref().expect("probe not started").log(msg);
}

// ================== Impl ==================
pub struct Probe {
    context_id: usize,
    context_names: Vec<String>,
    context_indices: HashMap<String, usize>,
    hit_counts: HashMap<(i32, usize), u32>,
    trace_file: Option<File>,
    tx: mpsc::Sender<Msg>,
    worker: Option<thread::JoinHandle<()>>,
}

impl Probe {
    fn new(trace_path: Option<&Path>) -> Self {
        let (tx, rx) = mpsc::channel::<Msg>();
        let worker = thread::spawn(move || udp_worker(rx));
        let trace_file = trace_path.and_then(|p| File::create(p).ok());
        Self {
            context_id: 0,
            context_names: Vec::new(),
            context_indices: HashMap::new(),
            hit_counts: HashMap::new(),
            trace_file,
            tx,
            worker: Some(worker),
        }
    }
    fn shutdown(&mut self) {
        let _ = self.tx.send(Msg::Shutdown);
        if let Some(h) = self.worker.take() { let _ = h.join(); }
    }
    fn set_context(&mut self, name: String) -> usize {
        if let Some(&idx) = self.context_indices.get(&name) { self.context_id = idx; }
        else {
            let idx = self.context_names.len();
            self.context_names.push(name.clone());
            self.context_indices.insert(name, idx);
            self.context_id = idx;
        }
        self.context_id
    }
    fn hit(&mut self, loc_id: i32) -> std::io::Result<()> {
        *self.hit_counts.entry((loc_id, self.context_id)).or_insert(0) += 1;
        if let Some(f) = self.trace_file.as_mut() {
            writeln!(f, ":1<T{}>", loc_id)?; f.flush()?;
        }
        // call_depth is a free function in this module
        let stack_depth = call_depth();
        let _ = self.tx.send(Msg::Hit(HitWire {
            message_type: 1,
            application_id: APPLICATION_ID,
            instance_id: INSTANCE_ID,
            thread_id: (thread_id::get() as u64) as u32,
            stack_depth: stack_depth,
            loc_id,
        }));
        Ok(())
    }
    fn log(&self, msg: &str) {
        if let Some(tf) = &self.trace_file {
            if let Ok(mut f) = tf.try_clone() {
                let _ = writeln!(f, ":LOG {}", msg);
                let _ = f.flush();
            }
        }
        let mut buf = vec![0u8; MAX_LOG_BYTES];
        let bytes = msg.as_bytes();
        let len = bytes.len().min(MAX_LOG_BYTES);
        buf[..len].copy_from_slice(&bytes[..len]);
        let stack_depth = call_depth();
        let _ = self.tx.send(Msg::Log(LogWire {
            message_type: 2,
            application_id: APPLICATION_ID,
            instance_id: INSTANCE_ID,
            thread_id: (thread_id::get() as u64) as u32,
            stack_depth: stack_depth,
            msg_len: len as u16,
            message: buf,
        }));
    }
}

// ================== Wire types ==================
#[derive(Debug, Clone, Copy)]
struct HitWire {
    message_type: u16,
    application_id: u16,
    instance_id: u32,
    thread_id: u32,
    stack_depth: u32,
    loc_id: i32,
}

#[derive(Debug, Clone)]
struct LogWire {
    message_type: u16,
    application_id: u16,
    instance_id: u32,
    thread_id: u32,
    stack_depth: u32,
    msg_len: u16,
    message: Vec<u8>,
}

#[derive(Debug)]
enum Msg { Hit(HitWire), Log(LogWire), Shutdown }

fn udp_worker(rx: mpsc::Receiver<Msg>) {
    let addr = format!("{}:{}", RECEIVER_HOST, UDP_PORT);
    let sock = UdpSocket::bind("0.0.0.0:0").expect("bind udp");
    sock.set_nonblocking(true).ok();

    let mut batch: Vec<Msg> = Vec::new();
    let mut next_flush = Instant::now() + Duration::from_millis(BATCH_INTERVAL_MS);

    loop {
        let timeout = next_flush.saturating_duration_since(Instant::now());
        match rx.recv_timeout(timeout) {
            Ok(Msg::Shutdown) => { if !batch.is_empty() { send_batch(&sock, &addr, &batch); } break; }
            Ok(m) => {
                batch.push(m);
                if batch.len() >= 64 { send_batch(&sock, &addr, &batch); batch.clear(); next_flush = Instant::now() + Duration::from_millis(BATCH_INTERVAL_MS); }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => { if !batch.is_empty() { send_batch(&sock, &addr, &batch); batch.clear(); } next_flush = Instant::now() + Duration::from_millis(BATCH_INTERVAL_MS); }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
}

fn send_batch(sock: &UdpSocket, addr: &str, batch: &[Msg]) {
    for m in batch {
        let payload = encode_be(m);
        let _ = sock.send_to(&payload, addr);
    }
}

fn encode_be(msg: &Msg) -> Vec<u8> {
    match msg {
        Msg::Hit(h) => {
            let mut v = Vec::with_capacity(20);
            v.extend_from_slice(&h.message_type.to_be_bytes());
            v.extend_from_slice(&h.application_id.to_be_bytes());
            v.extend_from_slice(&h.instance_id.to_be_bytes());
            v.extend_from_slice(&h.thread_id.to_be_bytes());
            // encode the actual stack depth captured when the hit was recorded
            v.extend_from_slice(&h.stack_depth.to_be_bytes());
            v.extend_from_slice(&h.loc_id.to_be_bytes());
            v
        }
        Msg::Log(l) => {
            let mut v = Vec::with_capacity(2+2+4+4+4+2 + (l.msg_len as usize));
            v.extend_from_slice(&l.message_type.to_be_bytes());
            v.extend_from_slice(&l.application_id.to_be_bytes());
            v.extend_from_slice(&l.instance_id.to_be_bytes());
            v.extend_from_slice(&l.thread_id.to_be_bytes());
            v.extend_from_slice(&l.stack_depth.to_be_bytes());
            v.extend_from_slice(&l.msg_len.to_be_bytes());
            v.extend_from_slice(&l.message[..(l.msg_len as usize)]);
            v
        }
        Msg::Shutdown => Vec::new(),
    }
}

// Public probe macro
#[macro_export]
macro_rules! mprewriter_scope_START {
    ($name:ident, $id:expr) => {
        // Enter a per-thread depth guard from the mprewriter module
        let $name = $crate::mprewriter::mprewriter_stack_fathomer::enter();
        // Record a hit using the mprewriter module's API
        $crate::mprewriter::scope_START($id);
    };
}

