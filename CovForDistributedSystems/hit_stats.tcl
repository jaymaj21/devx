#!/usr/bin/env tclsh
# hit_stats.tcl - Enhanced hit statistics from trace file
# Reports: hit count, earliest/latest UTC timestamps, and average hits/second

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

proc analyze_hits {filepath} {
    puts "Opening $filepath..."
    set fp [open $filepath rb]
    fconfigure $fp -translation binary -encoding binary
    
    # Read header
    set magic [read $fp 8]
    if {$magic ne "HITTRC01"} {
        close $fp
        error "Bad magic: expected HITTRC01"
    }
    
    set endian [read_u8 $fp]
    set file_start_ms [read_u64_be $fp]
    
    puts "File start (epoch ms): $file_start_ms"
    set fs_secs [expr {int($file_start_ms / 1000)}]
    set fs_utc [clock format $fs_secs -format {%Y-%m-%d %H:%M:%S} -gmt 1]
    puts "File start UTC: $fs_utc UTC"
    
    set trace_records 0
    set total_hits 0
    set min_nanos 9999999999999999
    set max_nanos -1
    
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
                        
                        # Track time range
                        if {$nanos < $min_nanos} { set min_nanos $nanos }
                        if {$nanos > $max_nanos} { set max_nanos $nanos }
                        
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
    
    # Calculate statistics
    puts "\n========================================="
    puts "HIT STATISTICS"
    puts "========================================="
    
    puts "Total Hit Records: $total_hits"
    
    if {$total_hits > 0} {
        # Calculate time range using relative differences only
        # The nanos values are NOT Unix epoch - they're from high_resolution_clock
        # So we can only use differences between nanos values
        set time_range_ns [expr {$max_nanos - $min_nanos}]
        set time_range_s [expr {$time_range_ns / 1e9}]
        
        # The earliest and latest UTC times are:
        # earliest = file_start_utc + (min_nanos in seconds as duration)
        # latest = file_start_utc + (max_nanos in seconds as duration)
        # But we can't convert nanos to absolute time, only relative
        # So: earliest = file_start + smallest duration, latest = file_start + largest duration
        
        set min_duration_ms [expr {$min_nanos / 1000000}]
        set max_duration_ms [expr {$max_nanos / 1000000}]
        
        set earliest_epoch_ms [expr {$file_start_ms + ($min_nanos - $min_nanos) / 1000000}]
        set latest_epoch_ms [expr {$file_start_ms + ($max_nanos - $min_nanos) / 1000000}]
        
        set earliest_secs [expr {int($earliest_epoch_ms / 1000)}]
        set latest_secs [expr {int($latest_epoch_ms / 1000)}]
        
        set earliest_utc [clock format $earliest_secs -format {%Y-%m-%d %H:%M:%S} -gmt 1]
        set latest_utc [clock format $latest_secs -format {%Y-%m-%d %H:%M:%S} -gmt 1]
        
        # Average hits per second
        if {$time_range_s > 0} {
            set hits_per_sec [expr {$total_hits / $time_range_s}]
        } else {
            set hits_per_sec "infinite (all hits at same instant)"
        }
        
        puts "Earliest Hit (UTC): $earliest_utc"
        puts "Latest Hit (UTC):   $latest_utc"
        puts "Duration:           [format %.3f $time_range_s] seconds"
        puts "Average Hits/Sec:   [format %.1f $hits_per_sec]"
    } else {
        puts "No HIT records found in trace file"
    }
    
    puts "=========================================\n"
}

if {[llength $argv] < 1} {
    puts "Usage: tclsh hit_stats.tcl <trace-file>"
    puts ""
    puts "Analyzes a HITTRC01 trace file and reports:"
    puts "  - Total number of hits"
    puts "  - Earliest hit timestamp (UTC)"
    puts "  - Latest hit timestamp (UTC)"
    puts "  - Average hits per second"
    exit 1
}

if {[catch {analyze_hits [lindex $argv 0]} err]} {
    puts "Error: $err"
    exit 1
}
