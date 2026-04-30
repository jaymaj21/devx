#!/usr/bin/env tclsh
# Quick debug script to inspect trace file format

proc read_u8 {channel} {
    set b [read $channel 1]
    if {[string length $b] == 0} { return -1 }
    return [scan $b %c]
}

proc read_u16_be {channel} {
    set data [read $channel 2]
    if {[string length $data] != 2} { return -1 }
    set b0 [scan [string index $data 0] %c]
    set b1 [scan [string index $data 1] %c]
    return [expr {($b0 << 8) | $b1}]
}

proc read_u32_be {channel} {
    set data [read $channel 4]
    if {[string length $data] != 4} { return -1 }
    set b0 [scan [string index $data 0] %c]
    set b1 [scan [string index $data 1] %c]
    set b2 [scan [string index $data 2] %c]
    set b3 [scan [string index $data 3] %c]
    return [expr {($b0 << 24) | ($b1 << 16) | ($b2 << 8) | $b3}]
}

proc read_u64_be {channel} {
    set data [read $channel 8]
    if {[string length $data] != 8} { return -1 }
    set val 0
    for {set i 0} {$i < 8} {incr i} {
        set b [scan [string index $data $i] %c]
        set val [expr {($val << 8) | $b}]
    }
    return $val
}

if {[llength $argv] < 1} {
    puts "Usage: tclsh debug_trace.tcl <trace-file>"
    exit 1
}

set filepath [lindex $argv 0]
set fp [open $filepath rb]

# Read header
set magic [read $fp 8]
puts "Magic: $magic"

set endian [read_u8 $fp]
puts "Endian: $endian"

set file_start_ms [read_u64_be $fp]
puts "File start (ms): $file_start_ms"

# Read first 10 records
puts "\nFirst 10 records:"
for {set idx 0} {$idx < 10} {incr idx} {
    set flag [read_u16_be $fp]
    if {$flag == -1} { 
        puts "End of file at record $idx"
        break 
    }
    
    set source [read_u8 $fp]
    set nanos [read_u64_be $fp]
    set len [read_u32_be $fp]
    
    if {$len == -1} { break }
    
    set payload [read $fp $len]
    set payload_len [string length $payload]
    
    puts "Record $idx: flag=$flag src=$source nanos=$nanos len=$len payload_len=$payload_len"
    
    # If it's a hit (flag=1), show the fields
    if {$flag == 1 && $payload_len >= 20} {
        binary scan $payload H* hex
        puts "  Payload hex: $hex"
        
        # Try to parse as hit: type(u16) appId(u16) instId(u32) threadId(u32) stackDepth(u32) locId(u32)
        binary scan [string range $payload 0 1] H* type_hex
        binary scan [string range $payload 2 3] H* app_hex
        puts "  First 4 bytes (type+appId): $type_hex $app_hex"
    }
}

close $fp
puts "\nNote: Check if record count matches expected (960000 hits)"
