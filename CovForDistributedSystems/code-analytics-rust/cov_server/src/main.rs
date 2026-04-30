use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::net::{UdpSocket, TcpListener, SocketAddrV4, Ipv4Addr};
use std::sync::Arc;
use std::thread;
use std::io::Read;
use parking_lot::Mutex;
use once_cell::sync::OnceCell;
use std::sync::mpsc;
use socket2::{Socket, Domain, Type, Protocol};

use molt::interp::Interp;
use molt::types::*;

mod hit_trace;      // you already have this
mod trace_hook;     // ADD
use hit_trace::{FLAG_HIT, FLAG_LOG, FLAG_CTX_ATTACH, FLAG_CTX_WITHDRAW};
use trace_hook::{trace_init, trace_write_udp, trace_write_tcp_with_flag, trace_flush, trace_write_ts, trace_persist}; // adjusted

const UDP_PORT: u16 = 8083;
const TCP_PORT: u16 = 8084;

static CONTEXT_MANAGER: OnceCell<Arc<Mutex<ContextManager>>> = OnceCell::new();

// ----- Context Manager -----
#[derive(Default, Debug)]
struct ContextManager {
    current_contexts: BTreeSet<String>,
    context_set_to_id: BTreeMap<BTreeSet<String>, u32>,
    next_id: u32,
    hit_counts: HashMap<(u16, u32, u32, u32), u64>,
}

impl ContextManager {
    fn new() -> Self {
        let mut cm = ContextManager::default();
        cm.context_set_to_id.insert(BTreeSet::new(), 1);
        cm.next_id = 2;
        cm
    }

    fn apply_context(&mut self, ctx: &str) {
        self.current_contexts.insert(ctx.to_string());
        self.update_context_id();
    }

    fn withdraw_context(&mut self, ctx: &str) {
        self.current_contexts.remove(ctx);
        self.update_context_id();
    }

    fn update_context_id(&mut self) {
        let set = self.current_contexts.clone();
        if !self.context_set_to_id.contains_key(&set) {
            self.context_set_to_id.insert(set, self.next_id);
            self.next_id += 1;
        }
    }

    fn get_current_context_id(&self) -> u32 {
        self.context_set_to_id
            .get(&self.current_contexts)
            .cloned()
            .unwrap_or(1)
    }

    fn record_hit(&mut self, app_id: u16, instance_id: u32, location_id: u32) {
        let ctx_id = self.get_current_context_id();
        let key = (app_id, instance_id, ctx_id, location_id);
        *self.hit_counts.entry(key).or_insert(0) += 1;
    }

    fn context_listing(&self) -> Vec<(u32, String)> {
        let mut items: Vec<_> = self.context_set_to_id.iter().map(|(k, &v)| {
            if k.is_empty() {
                (v, "default".to_string())
            } else {
                (v, k.iter().cloned().collect::<Vec<_>>().join(","))
            }
        }).collect();
        items.sort_by_key(|(id,_)| *id);
        items
    }

    fn coverage_report(&self, app_id: u16, instance_id: u32) -> String {
        let mut result = String::new();
        let ctxs = self.context_listing();
        result += &format!("CONTEXTS {}\n", ctxs.len());
        for (id, desc) in &ctxs {
            result += &format!("{} {}\n", id, desc);
        }
        let hits: Vec<_> = self.hit_counts.iter()
            .filter(|((a, i, _, _), _)| *a == app_id && *i == instance_id)
            .map(|((_, _, ctx_id, loc_id), &count)| (ctx_id, loc_id, count))
            .collect();
        result += &format!("HITS {}\n", hits.len());
        for (ctx_id, loc_id, count) in hits {
            result += &format!("{} {} {}\n", ctx_id, loc_id, count);
        }
        result
    }
}

// ----- UDP Listener -----
fn udp_listener(cm_arc: Arc<Mutex<ContextManager>>) {
    // Bind with large receive buffer
    let addr = SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, UDP_PORT);
    let sock2 = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP)).expect("socket");
    let _ = sock2.set_reuse_address(true);
    let _ = sock2.set_recv_buffer_size(1 << 24); // 16 MiB, best-effort
    sock2.bind(&addr.into()).expect("bind UDP");
    let sock: UdpSocket = sock2.into();
    println!("[UDP] Listening on port {}", UDP_PORT);

    // Channel to offload parsing
    let (tx, rx) = mpsc::channel::<Vec<u8>>();
    {
        let cm = cm_arc.clone();
        thread::spawn(move || {
            while let Ok(payload) = rx.recv() {
                trace_write_udp(&payload);
                parse_packet(&payload, &cm);
            }
        });
    }

    loop {
        // Receive a full datagram; allocate a fresh buffer for each packet
        let mut buf = vec![0u8; 65535];
        let (len, _) = match sock.recv_from(&mut buf) {
            Ok(r) => r,
            Err(e) => { eprintln!("UDP recv error: {}", e); continue; }
        };
        buf.truncate(len);
        // Hand off to parser pool; drop if channel closed
        if tx.send(buf).is_err() { break; }
    }
}

fn parse_packet(buffer: &[u8], cm_arc: &Arc<Mutex<ContextManager>>) {
    let len = buffer.len();
    let mut offset = 0usize;
    while offset + 2 <= len {
        let msg_type = u16::from_be_bytes([buffer[offset], buffer[offset+1]]);
        match msg_type {
            1 if offset + 20 <= len => {
                let app_id = u16::from_be_bytes([buffer[offset+2], buffer[offset+3]]);
                let instance_id = u32::from_be_bytes(buffer[offset+4..offset+8].try_into().unwrap());
                let _thread_id = u32::from_be_bytes(buffer[offset+8..offset+12].try_into().unwrap());
                let _stack_depth = u32::from_be_bytes(buffer[offset+12..offset+16].try_into().unwrap());
                let location_id = u32::from_be_bytes(buffer[offset+16..offset+20].try_into().unwrap());
                cm_arc.lock().record_hit(app_id, instance_id, location_id);
                offset += 20;
            }
            2 if offset + 18 <= len => {
                let app_id = u16::from_be_bytes([buffer[offset+2], buffer[offset+3]]);
                let instance_id = u32::from_be_bytes(buffer[offset+4..offset+8].try_into().unwrap());
                let thread_id = u32::from_be_bytes(buffer[offset+8..offset+12].try_into().unwrap());
                let stack_depth = u32::from_be_bytes(buffer[offset+12..offset+16].try_into().unwrap());
                let log_len = u16::from_be_bytes([buffer[offset+16], buffer[offset+17]]) as usize;
                if offset + 18 + log_len <= len {
                    let msg = String::from_utf8_lossy(&buffer[offset+18..offset+18+log_len]);
                    println!("[LOG] app={} inst={} thread={} sd={} : {}", app_id, instance_id, thread_id, stack_depth, msg);
                    offset += 18 + log_len;
                } else { break; }
            }
            3 | 4 => {
                let ctx = String::from_utf8_lossy(&buffer[offset+2..len]).to_string();
                if msg_type == 3 {
                    cm_arc.lock().apply_context(&ctx);
                    println!("[CTX] Applied: {}", ctx);
                } else {
                    cm_arc.lock().withdraw_context(&ctx);
                    println!("[CTX] Withdrew: {}", ctx);
                }
                break;
            }
            _ => break,
        }
    }
}

// ----- TCP Listener -----
fn tcp_listener(cm_arc: Arc<Mutex<ContextManager>>, port: u16) {
    let listener = TcpListener::bind(("0.0.0.0", port)).expect("TCP bind failed");
    println!("[TCP] Listening on port {}", port);
    for stream in listener.incoming() {
        let cm_arc = Arc::clone(&cm_arc);
        thread::spawn(move || {
            let mut stream = stream.unwrap();
            let mut buffer = [0u8; 1204];
            loop {
                let len = match stream.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(n) => n,
                    Err(_) => break,
                };
                let mut offset = 0usize;
                while offset + 2 <= len {
                    let record_start = offset;
                    let msg_type = u16::from_be_bytes([buffer[offset], buffer[offset+1]]);
                    match msg_type {
                        1 if offset + 20 <= len => {
                            let app_id = u16::from_be_bytes([buffer[offset+2], buffer[offset+3]]);
                            let instance_id = u32::from_be_bytes(buffer[offset+4..offset+8].try_into().unwrap());
                            let thread_id = u32::from_be_bytes(buffer[offset+8..offset+12].try_into().unwrap());
                            let stack_depth = u32::from_be_bytes(buffer[offset+12..offset+16].try_into().unwrap());
                            let location_id = u32::from_be_bytes(buffer[offset+16..offset+20].try_into().unwrap());
                            let _ = stack_depth;
                            cm_arc.lock().record_hit(app_id, instance_id, location_id);
                            // trace exact frame slice with correct flag
                            trace_write_tcp_with_flag(FLAG_HIT, &buffer[record_start..record_start+20]);
                            offset += 20;
                        }
                        2 if offset + 18 <= len => {
                            let app_id = u16::from_be_bytes([buffer[offset+2], buffer[offset+3]]);
                            let instance_id = u32::from_be_bytes(buffer[offset+4..offset+8].try_into().unwrap());
                            let thread_id = u32::from_be_bytes(buffer[offset+8..offset+12].try_into().unwrap());
                            let stack_depth = u32::from_be_bytes(buffer[offset+12..offset+16].try_into().unwrap());
                            let log_len = u16::from_be_bytes([buffer[offset+16], buffer[offset+17]]) as usize;
                            if offset + 18 + log_len <= len {
                                let msg = String::from_utf8_lossy(&buffer[offset+18..offset+18+log_len]);
                                println!("[LOG] app={} inst={} thread={} sd={} : {}", app_id, instance_id, thread_id, stack_depth, msg);
                                trace_write_tcp_with_flag(FLAG_LOG, &buffer[record_start..record_start+18+log_len]);
                                offset += 18 + log_len;
                            } else {
                                break;
                            }
                        }
                        3 | 4 => {
                            let ctx = String::from_utf8_lossy(&buffer[offset+2..len]).to_string();
                            if msg_type == 3 {
                                cm_arc.lock().apply_context(&ctx);
                                println!("[CTX] Applied: {}", ctx);
                                trace_write_tcp_with_flag(FLAG_CTX_ATTACH, &buffer[record_start..len]);
                            } else {
                                cm_arc.lock().withdraw_context(&ctx);
                                println!("[CTX] Withdrew: {}", ctx);
                                trace_write_tcp_with_flag(FLAG_CTX_WITHDRAW, &buffer[record_start..len]);
                            }
                            break;
                        }
                        _ => break,
                    }
                }
            }
        });
    }
}

// ----- Molt Admin Shell -----
fn tcl_apply_context(_interp: &mut Interp, _ctx: ContextID, args: &[Value]) -> Result<Value, Exception> {
    if args.len() < 2 { return Ok(Value::from("Usage: apply_context <label>")); }
    let cm = CONTEXT_MANAGER.get().unwrap();
    cm.lock().apply_context(&args[1].to_string());
    Ok(Value::from(format!("Applied: {}", args[1])))
}

fn tcl_withdraw_context(_interp: &mut Interp, _ctx: ContextID, args: &[Value]) -> Result<Value, Exception> {
    if args.len() < 2 { return Ok(Value::from("Usage: withdraw_context <label>")); }
    let cm = CONTEXT_MANAGER.get().unwrap();
    cm.lock().withdraw_context(&args[1].to_string());
    Ok(Value::from(format!("Withdrew: {}", args[1])))
}

fn tcl_coverage_report(_interp: &mut Interp, _ctx: ContextID, args: &[Value]) -> Result<Value, Exception> {
    if args.len() < 3 { return Ok(Value::from("Usage: coverage_report <appId> <instanceId>")); }
    let app_id = args[1].to_string().parse::<u16>().unwrap_or(0);
    let inst = args[2].to_string().parse::<u32>().unwrap_or(0);
    let cm = CONTEXT_MANAGER.get().unwrap();
    let rpt = cm.lock().coverage_report(app_id, inst);
    Ok(Value::from(rpt))
}

// Java shell compatible aliases and missing commands
fn tcl_colon_apply_context(interp: &mut Interp, ctx: ContextID, args: &[Value]) -> Result<Value, Exception> {
    tcl_apply_context(interp, ctx, args)
}
fn tcl_colon_withdraw_context(interp: &mut Interp, ctx: ContextID, args: &[Value]) -> Result<Value, Exception> {
    tcl_withdraw_context(interp, ctx, args)
}

fn tcl_colon_hits(_interp: &mut Interp, _ctx: ContextID, _args: &[Value]) -> Result<Value, Exception> {
    // Aggregate hits by (appId, instanceId, ctxId, locId)
    let cm = CONTEXT_MANAGER.get().unwrap();
    let m = &cm.lock().hit_counts;
    let mut lines: Vec<String> = Vec::new();
    for (&(app, inst, ctx, loc), count) in m.iter() {
        lines.push(format!("{} {} {} {} {}", app, inst, ctx, loc, count));
    }
    Ok(Value::from(lines.join("\n")))
}

fn tcl_colon_coverage_report(_interp: &mut Interp, _ctx: ContextID, args: &[Value]) -> Result<Value, Exception> {
    if args.len() < 4 { return Ok(Value::from("Usage: :coverage-report <appId> <instanceId> <filename>")); }
    let app_id = args[1].to_string().parse::<u16>().unwrap_or(0);
    let inst = args[2].to_string().parse::<u32>().unwrap_or(0);
    let filename = args[3].to_string();
    let cm = CONTEXT_MANAGER.get().unwrap();
    let cm = cm.lock();
    // Build contexts section
    let mut items = cm.context_listing();
    items.sort_by_key(|(id,_)| *id);
    let mut out = String::new();
    out.push_str(&format!("CONTEXTS {}\n", items.len()));
    for (id, desc) in items {
        out.push_str(&format!("{} {}\n", id, if id==1 { String::from("default") } else { desc }));
    }
    // Hits section
    let hits: Vec<_> = cm.hit_counts.iter()
        .filter(|((a,i,_,_),_)| *a==app_id && *i==inst)
        .map(|((_,_,ctx,loc),cnt)| (*ctx, *loc, *cnt))
        .collect();
    out.push_str(&format!("HITS {}\n", hits.len()));
    for (ctx, loc, cnt) in hits { out.push_str(&format!("{} {} {}\n", ctx, loc, cnt)); }
    // Write file
    match std::fs::write(&filename, out) {
        Ok(_) => Ok(Value::from(format!("Coverage report written to {}", filename))),
        Err(e) => Ok(Value::from(format!("ERROR writing report: {}", e))),
    }
}

fn molt_shell() {
    let mut interp = Interp::new();
    interp.add_command("apply_context", tcl_apply_context);
    interp.add_command("withdraw_context", tcl_withdraw_context);
    interp.add_command("coverage_report", tcl_coverage_report);
    // Java-style aliases
    interp.add_command(":apply-context", tcl_colon_apply_context);
    interp.add_command(":withdraw-context", tcl_colon_withdraw_context);
    interp.add_command(":hits", tcl_colon_hits);
    interp.add_command(":coverage-report", tcl_colon_coverage_report);
    interp.add_command(":help", |_i, _c, _a| Ok(Value::from(":hits, :apply-context, :withdraw-context, :coverage-report <appId> <instanceId> <file>, exit")));
    interp.add_command(":exit", |_i, _c, _a| { std::process::exit(0); });
    interp.add_command(":flush-trace", |_i, _c, _a| { trace_flush(); Ok(Value::from("Trace flushed")) });
    interp.add_command(":trace-persist", |_i, _c, _a| { trace_persist(); Ok(Value::from("Trace persisted")) });
    println!("Molt admin shell. Type `exit` to quit.");
    loop {
        print!("admin> ");
        use std::io::Write;
        std::io::stdout().flush().unwrap();
        let mut line = String::new();
        if std::io::stdin().read_line(&mut line).is_err() { break; }
        let script = line.trim();
        if script == "exit" { trace_flush(); break; }
        match interp.eval(script) {
            Ok(val) => println!("{}", val),
            Err(e) => println!("Error: {:?}", e),
        }
    }
}

fn main() {
    trace_init(); 

    let cm_arc = Arc::new(Mutex::new(ContextManager::new()));
    CONTEXT_MANAGER.set(cm_arc.clone()).unwrap();
    {
        let cm_clone = cm_arc.clone();
        thread::spawn(move || udp_listener(cm_clone));
    }
    {
        let cm_clone = cm_arc.clone();
        thread::spawn(move || tcp_listener(cm_clone, TCP_PORT));
    }
    // Periodic TS writer
    thread::spawn(move || {
        loop {
            std::thread::sleep(std::time::Duration::from_secs(10));
            trace_write_ts();
        }
    });
    molt_shell();
    trace_flush();
}
