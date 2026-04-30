#!/usr/bin/env tclsh
# debug_epoch.tcl - Debug epoch calculations

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

set filepath [lindex $argv 0]
set fp [open $filepath rb]
fconfigure $fp -translation binary -encoding binary

set magic [read $fp 8]
set endian [read_u8 $fp]
set file_start_ms [read_u64_be $fp]

puts "File start ms: $file_start_ms"

set hit_count 0
set first_hit_nanos 0
set last_hit_nanos 0

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
    
    if {$flag == 1 && $len > 0} {
        set pos 0
        while {$pos + 2 <= $len} {
            set msg_type [read_u16_be_str $payload $pos]
            if {$msg_type == 1} {
                if {$pos + 20 <= $len} {
                    incr hit_count
                    if {$hit_count == 1} {
                        set first_hit_nanos $nanos
                    }
                    set last_hit_nanos $nanos
                    set pos [expr {$pos + 20}]
                } else {
                    break
                }
            } else {
                break
            }
        }
    }
    
    if {$hit_count > 0 && [expr {$hit_count % 100000}] == 0} {
        puts "Found $hit_count hits, last nanos: $last_hit_nanos"
    }
}

close $fp

puts "\n=== ANALYSIS ==="
puts "Total hits: $hit_count"
puts "First hit nanos (relative): $first_hit_nanos"
puts "Last hit nanos (relative):  $last_hit_nanos"
puts "Duration (nanos): [expr {$last_hit_nanos - $first_hit_nanos}]"
puts "Duration (secs): [expr {($last_hit_nanos - $first_hit_nanos) / 1e9}]"

# Convert to UTC
set first_hit_ms_offset [expr {$first_hit_nanos / 1000000}]
set last_hit_ms_offset [expr {$last_hit_nanos / 1000000}]

set first_hit_epoch_ms [expr {$file_start_ms + $first_hit_ms_offset}]
set last_hit_epoch_ms [expr {$file_start_ms + $last_hit_ms_offset}]

set first_secs [expr {int($first_hit_epoch_ms / 1000)}]
set last_secs [expr {int($last_hit_epoch_ms / 1000)}]

puts "\nFirst hit:"
puts "  Epoch ms: $first_hit_epoch_ms"
puts "  UTC: [clock format $first_secs -format {%Y-%m-%d %H:%M:%S} -gmt 1]"

puts "\nLast hit:"
puts "  Epoch ms: $last_hit_epoch_ms"
puts "  UTC: [clock format $last_secs -format {%Y-%m-%d %H:%M:%S} -gmt 1]"
