#!/usr/bin/env tclsh
# count_hits.tcl - Simple hit counter from trace file

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
    return [expr {($b0 << 8) | ($b1 & 0xFF)}]
}

proc read_u32_be {channel} {
    set data [read $channel 4]
    if {[string length $data] != 4} { return -1 }
    set b0 [scan [string index $data 0] %c]
    set b1 [scan [string index $data 1] %c]
    set b2 [scan [string index $data 2] %c]
    set b3 [scan [string index $data 3] %c]
    return [expr {($b0 << 24) | (($b1 & 0xFF) << 16) | (($b2 & 0xFF) << 8) | ($b3 & 0xFF)}]
}

proc read_u64_be {channel} {
    set data [read $channel 8]
    if {[string length $data] != 8} { return -1 }
    set val 0
    for {set i 0} {$i < 8} {incr i} {
        set b [scan [string index $data $i] %c]
        set val [expr {($val << 8) | ($b & 0xFF)}]
    }
    return $val
}

proc read_u16_be_str {str pos} {
    set b0 [scan [string index $str $pos] %c]
    set b1 [scan [string index $str [expr {$pos + 1}]] %c]
    return [expr {($b0 << 8) | ($b1 & 0xFF)}]
}

proc count_hits {filepath} {
    puts "Opening $filepath..."
    set fp [open $filepath rb]
    fconfigure $fp -translation binary -encoding binary
    
    # Read header
    set magic [read $fp 8]
    if {$magic ne "HITTRC01"} {
        close $fp
        error "Bad magic"
    }
    
    set endian [read_u8 $fp]
    set file_start_ms [read_u64_be $fp]
    puts "File start: $file_start_ms"
    
    set trace_records 0
    set total_hits 0
    
    while {1} {
        set flag [read_u16_be $fp]
        if {$flag == -1} { break }
        
        set source [read_u8 $fp]
        if {$source == -1} { break }
        
        set nanos [read_u64_be $fp]
        if {$nanos == -1} { break }
        
        set len [read_u32_be $fp]
        if {$len == -1} { break }
        
        set payload [read $fp $len]
        if {[string length $payload] != $len} { break }
        
        incr trace_records
        
        # Count hit messages in payload (they can be batched)
        if {$flag == 1 && $len > 0} {
            set pos 0
            while {$pos + 2 <= $len} {
                set msg_type [read_u16_be_str $payload $pos]
                if {$msg_type == 1} {
                    if {$pos + 20 <= $len} {
                        incr total_hits
                        set pos [expr {$pos + 20}]
                    } else {
                        break
                    }
                } elseif {$msg_type == 2} {
                    if {$pos + 18 <= $len} {
                        set b0 [scan [string index $payload [expr {$pos + 16}]] %c]
                        set b1 [scan [string index $payload [expr {$pos + 17}]] %c]
                        set msg_len [expr {($b0 << 8) | ($b1 & 0xFF)}]
                        if {$pos + 18 + $msg_len <= $len} {
                            set pos [expr {$pos + 18 + $msg_len}]
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
        }
        
        if {[expr {$trace_records % 1000}] == 0} {
            puts "  $trace_records trace records, $total_hits hits..."
        }
    }
    
    close $fp
    puts "\n=== RESULT ==="
    puts "Trace records: $trace_records"
    puts "Total hits: $total_hits"
}

if {[llength $argv] < 1} {
    puts "Usage: tclsh count_hits.tcl <trace-file>"
    exit 1
}

count_hits [lindex $argv 0]
