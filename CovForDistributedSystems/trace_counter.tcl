#!/usr/bin/env tclsh
# trace_counter.tcl
# Simple tool to count hits in a trace file without GUI

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

proc count_hits {filepath} {
    if {![file exists $filepath]} {
        error "File not found: $filepath"
    }
    
    set fp [open $filepath rb]
    
    # Read header: "HITTRC01" (8) + endian (1) + fileStartEpochMillis (8)
    set magic [read $fp 8]
    if {$magic ne "HITTRC01"} {
        close $fp
        error "Bad magic: expected HITTRC01"
    }
    
    set endian [read_u8 $fp]
    if {$endian != 0} {
        close $fp
        error "Unsupported endianness: only big-endian supported"
    }
    
    set file_start_ms [read_u64_be $fp]
    puts "File start (epoch ms): $file_start_ms"
    
    # Count records by flag
    set hit_count 0
    set log_count 0
    set ts_count 0
    set ctx_count 0
    set other_count 0
    set total_records 0
    set min_nanos 9999999999999999
    set max_nanos 0
    
    while {1} {
        set flag [read_u16_be $fp]
        if {$flag == -1} { break }
        
        set source [read_u8 $fp]
        if {$source == -1} { break }
        
        set nanos [read_u64_be $fp]
        if {$nanos == -1} { break }
        
        set len [read_u32_be $fp]
        if {$len == -1} { break }
        
        # Read payload
        set payload [read $fp $len]
        if {[string length $payload] != $len} {
            puts "Warning: incomplete payload"
            break
        }
        
        incr total_records
        
        # Track by flag
        switch $flag {
            1 { incr hit_count }
            2 { incr log_count }
            9 { incr ts_count }
            3 { incr ctx_count }
            4 { incr ctx_count }
            default { incr other_count }
        }
        
        # Track time range
        if {$nanos < $min_nanos} { set min_nanos $nanos }
        if {$nanos > $max_nanos} { set max_nanos $nanos }
        
        # Progress indicator
        if {[expr {$total_records % 100000}] == 0} {
            puts "  Processed $total_records records..."
        }
    }
    
    close $fp
    
    puts "\n=== TRACE FILE STATISTICS ==="
    puts "Total records: $total_records"
    puts "  HIT records (flag=1):  $hit_count"
    puts "  LOG records (flag=2):  $log_count"
    puts "  TS  records (flag=9):  $ts_count"
    puts "  CTX records (flag=3,4): $ctx_count"
    puts "  Other:                 $other_count"
    
    if {$hit_count > 0} {
        set time_range_ns [expr {$max_nanos - $min_nanos}]
        set time_range_ms [expr {$time_range_ns / 1e6}]
        set time_range_s [expr {$time_range_ns / 1e9}]
        puts "\nTime range:"
        puts "  Start (nanos): $min_nanos"
        puts "  End (nanos):   $max_nanos"
        puts "  Duration: ${time_range_s} seconds (${time_range_ms} ms, ${time_range_ns} ns)"
        puts "  Hit rate: [format %.1f [expr {$hit_count / $time_range_s}]] hits/sec"
    }
}

if {[llength $argv] < 1} {
    puts "Usage: tclsh trace_counter.tcl <trace-file>"
    exit 1
}

set filepath [lindex $argv 0]
if {[catch {count_hits $filepath} err]} {
    puts "Error: $err"
    exit 1
}
