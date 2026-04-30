use once_cell::sync::Lazy;
use std::net::UdpSocket;
use std::sync::Mutex;
use std::mem;
use thread_id;

const RECEIVER_HOST: &str = "127.0.0.1";
const UDP_PORT: u16 = 8083;
const MAX_LOG_BYTES: usize = 1184;

#[repr(C)]
#[derive(Debug)]
pub struct ScopeStart {
    pub message_type: u16,
    pub scope_id: u32,
    pub thread_id: usize,
    pub stack_depth: u32,
    pub call_site_id: u32,
}

#[repr(C)]
#[derive(Debug)]
pub struct LogMessage {
    pub message_type: u16,
    pub thread_id: usize,
    pub stack_depth: u32,
    pub message: [u8; MAX_LOG_BYTES],
}

pub struct ContextManager {
    udp_socket: UdpSocket,
    pub scope_id: u32,
    pub scope_depth: u32,
}

impl ContextManager {
    fn new() -> Self {
        ContextManager {
            udp_socket: UdpSocket::bind("0.0.0.0:0").expect("Unable to bind UDP socket"),
            scope_id: 0,
            scope_depth: 0,
        }
    }

    fn send_udp_message<T>(&self, message: &T) {
        let addr = format!("{}:{}", RECEIVER_HOST, UDP_PORT);
        let message_bytes = unsafe {
            std::slice::from_raw_parts((message as *const T) as *const u8, mem::size_of::<T>())
        };
        self.udp_socket.send_to(message_bytes, addr).unwrap();
    }

    pub fn scope_start(&mut self, call_site_id: u32) -> u32 {
        self.scope_id += 1;
        self.scope_depth += 1;

        let scope_start = ScopeStart {
            message_type: 1,
            scope_id: self.scope_id,
            thread_id: thread_id::get(),
            stack_depth: 1,
            call_site_id,
        };

        self.send_udp_message(&scope_start);
        self.scope_id
    }

    pub fn log(&self, msg: &str) {
        let mut log_msg = LogMessage {
            message_type: 2,
            thread_id: thread_id::get(),
            stack_depth: 1,
            message: [0; MAX_LOG_BYTES],
        };

        let bytes = msg.as_bytes();
        let len = bytes.len().min(MAX_LOG_BYTES - 1);
        log_msg.message[..len].copy_from_slice(&bytes[..len]);
        self.send_udp_message(&log_msg);
    }
}

pub static GLOBAL_CONTEXT_MANAGER: Lazy<Mutex<ContextManager>> =
    Lazy::new(|| Mutex::new(ContextManager::new()));
