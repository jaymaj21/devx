#!/usr/bin/env tclsh
# trace_histogram.tcl
# 
# A Tcl/Tk program to visualize hits from trace files as a histogram
# over a time interval divided into specified buckets.
#
# Usage: tclsh trace_histogram.tcl <trace-file> [num-buckets]
#

package require Tk

# ============================================================================
# Binary parsing utilities (big-endian)
# ============================================================================

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

# ============================================================================
# Trace file parsing
# ============================================================================

proc read_trace_file {filepath} {
    # Returns: list of {timestamp_nanos}
    # Reads ALL hit messages (flag==1) from trace records.
    # Note: a single trace record can contain MULTIPLE batched hit messages!
    
    if {![file exists $filepath]} {
        error "File not found: $filepath"
    }
    
    set hits {}
    set hit_count 0
    set total_records 0
    set fp [open $filepath rb]
    fconfigure $fp -translation binary -encoding binary
    
    # Read header: "HITTRC01" (8) + endian (1) + fileStartEpochMillis (8)
    set magic [read $fp 8]
    if {$magic ne "HITTRC01"} {
        close $fp
        error "Bad magic: expected HITTRC01, got $magic"
    }
    
    set endian [read_u8 $fp]
    if {$endian != 0} {
        close $fp
        error "Unsupported endianness: $endian (only big-endian supported)"
    }
    
    set file_start_ms [read_u64_be $fp]
    if {$file_start_ms == -1} {
        close $fp
        error "Failed to read file start time"
    }
    
    puts "Reading trace file: file_start_ms=$file_start_ms"
    
    # Parse trace records: frame header is 15 bytes (flag:u16 + src:u8 + nanos:u64 + len:u32)
    while {1} {
        # Read record header: flag (u16) + source (u8) + nanoTime (u64) + len (u32)
        set flag [read_u16_be $fp]
        if {$flag == -1} { 
            puts "Reached EOF after $total_records total trace records, $hit_count individual hits"
            break 
        }
        
        incr total_records
        
        set source [read_u8 $fp]
        if {$source == -1} { break }
        
        set nanos [read_u64_be $fp]
        if {$nanos == -1} { break }
        
        set len [read_u32_be $fp]
        if {$len == -1} { break }
        
        # Read payload
        set payload [read $fp $len]
        if {[string length $payload] != $len} {
            puts "Warning: incomplete payload, got [string length $payload] of $len bytes"
            break
        }
        
        # Parse messages WITHIN this trace record's payload
        # Payloads can contain batched messages: each starts with msgType (u16)
        if {$flag == 1 && $len > 0} {
            # This trace record carries hit messages
            set pos 0
            while {$pos + 2 <= $len} {
                set msg_type [read_u16_be_at $payload $pos]
                if {$msg_type == 1} {
                    # HIT message: type(u16) + appId(u16) + instanceId(u32) + threadId(u32) + stackDepth(u32) + locationId(u32)
                    if {$pos + 20 <= $len} {
                        # Found one hit message
                        incr hit_count
                        lappend hits $nanos
                        set pos [expr {$pos + 20}]
                    } else {
                        break
                    }
                } elseif {$msg_type == 2} {
                    # LOG message: type(u16) + appId(u16) + instanceId(u32) + threadId(u32) + stackDepth(u32) + msgLen(u16) + msg
                    if {$pos + 18 <= $len} {
                        set msg_len [read_u16_be_at $payload [expr {$pos + 16}]]
                        if {$pos + 18 + $msg_len <= $len} {
                            set pos [expr {$pos + 18 + $msg_len}]
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                } elseif {$msg_type == 3 || $msg_type == 4} {
                    # Context message consumes rest of payload
                    break
                } else {
                    # Unknown message type
                    break
                }
            }
        }
        
        # Progress indicator
        if {[expr {$total_records % 1000}] == 0} {
            puts "Processed $total_records trace records, found $hit_count individual hits so far..."
        }
    }
    
    close $fp
    puts "Trace file parsing complete: $total_records trace records, $hit_count individual HIT messages"
    return $hits
}

# Helper: read u16 big-endian from string at position
proc read_u16_be_at {str pos} {
    set b0 [scan [string index $str $pos] %c]
    set b1 [scan [string index $str [expr {$pos + 1}]] %c]
    return [expr {($b0 << 8) | ($b1 & 0xFF)}]
}

# Helper: read u32 big-endian from string at position
proc read_u32_be_at {str pos} {
    set b0 [scan [string index $str $pos] %c]
    set b1 [scan [string index $str [expr {$pos + 1}]] %c]
    set b2 [scan [string index $str [expr {$pos + 2}]] %c]
    set b3 [scan [string index $str [expr {$pos + 3}]] %c]
    return [expr {($b0 << 24) | (($b1 & 0xFF) << 16) | (($b2 & 0xFF) << 8) | ($b3 & 0xFF)}]
}

# ============================================================================
# Histogram calculation
# ============================================================================

proc compute_histogram {hits num_buckets} {
    # Returns: {min_time max_time bucket_counts}
    # where bucket_counts is a list of counts for each bucket
    
    if {[llength $hits] == 0} {
        return [list 0 0 {}]
    }
    
    # Find min and max timestamps
    set min_time [lindex [lindex $hits 0] 0]
    set max_time [lindex [lindex $hits 0] 0]
    
    foreach hit $hits {
        set ts [lindex $hit 0]
        if {$ts < $min_time} { set min_time $ts }
        if {$ts > $max_time} { set max_time $ts }
    }
    
    # Initialize bucket counts
    set buckets [list]
    for {set i 0} {$i < $num_buckets} {incr i} {
        lappend buckets 0
    }
    
    # Distribute hits into buckets
    if {$max_time > $min_time} {
        set interval [expr {$max_time - $min_time}]
        foreach hit $hits {
            set ts [lindex $hit 0]
            set offset [expr {$ts - $min_time}]
            set bucket_idx [expr {int($offset * $num_buckets / $interval)}]
            
            # Clamp to [0, num_buckets-1]
            if {$bucket_idx >= $num_buckets} { set bucket_idx [expr {$num_buckets - 1}] }
            if {$bucket_idx < 0} { set bucket_idx 0 }
            
            set count [lindex $buckets $bucket_idx]
            lset buckets $bucket_idx [expr {$count + 1}]
        }
    } else {
        # All hits at same time -> one bucket
        lset buckets 0 [llength $hits]
    }
    
    return [list $min_time $max_time $buckets]
}

# ============================================================================
# GUI: Tcl/Tk histogram visualization
# ============================================================================

proc draw_histogram {canvas_w canvas_h min_time max_time buckets} {
    # Create canvas and draw histogram
    
    set c [canvas .canvas -width $canvas_w -height $canvas_h -bg white]
    pack $c -fill both -expand 1
    
    set margin_left 60
    set margin_right 30
    set margin_top 30
    set margin_bottom 60
    
    set plot_w [expr {$canvas_w - $margin_left - $margin_right}]
    set plot_h [expr {$canvas_h - $margin_top - $margin_bottom}]
    set x_offset $margin_left
    set y_offset [expr {$canvas_h - $margin_bottom}]
    
    # Find max bucket count for scaling
    set max_count 0
    foreach count $buckets {
        if {$count > $max_count} { set max_count $count }
    }
    if {$max_count == 0} { set max_count 1 }
    
    # Draw axes
    $c create line $x_offset $y_offset [expr {$x_offset + $plot_w}] $y_offset -fill black -width 2
    $c create line $x_offset [expr {$y_offset - $plot_h}] $x_offset $y_offset -fill black -width 2
    
    # Draw y-axis label
    $c create text 20 [expr {$y_offset - $plot_h / 2}] -text "Count" -angle 90 -font {Arial 10}
    
    # Draw x-axis label
    set time_interval [expr {($max_time - $min_time) / 1e9}]
    $c create text [expr {$x_offset + $plot_w / 2}] [expr {$canvas_h - 10}] \
        -text "Time (seconds)" -font {Arial 10}
    
    # Draw bars
    set num_buckets [llength $buckets]
    if {$num_buckets > 0} {
        set bar_width [expr {$plot_w / $num_buckets}]
        set bar_padding 2
        
        for {set i 0} {$i < $num_buckets} {incr i} {
            set count [lindex $buckets $i]
            set height [expr {$plot_h * $count / $max_count}]
            
            set x1 [expr {$x_offset + $i * $bar_width + $bar_padding}]
            set x2 [expr {$x1 + $bar_width - 2 * $bar_padding}]
            set y1 [expr {$y_offset - $height}]
            set y2 $y_offset
            
            $c create rectangle $x1 $y1 $x2 $y2 -fill steelblue -outline darkblue
            
            # Add count label on top of bar if count > 0
            if {$count > 0} {
                $c create text [expr {($x1 + $x2) / 2}] [expr {$y1 - 5}] \
                    -text $count -font {Arial 8}
            }
        }
    }
    
    # Draw y-axis ticks and labels
    set y_ticks 5
    for {set i 0} {$i <= $y_ticks} {incr i} {
        set y_tick_val [expr {$max_count * $i / $y_ticks}]
        set y_pos [expr {$y_offset - $plot_h * $i / $y_ticks}]
        $c create line [expr {$x_offset - 5}] $y_pos $x_offset $y_pos -fill black
        $c create text [expr {$x_offset - 10}] $y_pos -text $y_tick_val -anchor e -font {Arial 8}
    }
    
    # Draw x-axis tick labels (time buckets)
    set x_ticks 5
    for {set i 0} {$i <= $x_ticks} {incr i} {
        set x_pos [expr {$x_offset + $plot_w * $i / $x_ticks}]
        $c create line $x_pos $y_offset $x_pos [expr {$y_offset + 5}] -fill black
        set time_label [expr {$time_interval * $i / $x_ticks}]
        $c create text $x_pos [expr {$y_offset + 20}] -text [format "%.2f" $time_label] \
            -anchor n -font {Arial 8}
    }
    
    return $c
}

# ============================================================================
# Main program
# ============================================================================

proc main {} {
    global argc argv
    
    # Parse command line arguments
    set trace_file ""
    set num_buckets 50
    
    if {$argc < 1} {
        puts "Usage: wish trace_histogram.tcl <trace-file> \[num-buckets\]"
        puts "  trace-file:  path to HITTRC01 trace file"
        puts "  num-buckets: number of histogram buckets (default 50)"
        exit 1
    }
    
    set trace_file [lindex $argv 0]
    if {$argc >= 2} {
        set num_buckets [lindex $argv 1]
    }
    
    # Read trace file
    puts "Reading trace file: $trace_file"
    if {[catch {set hits [read_trace_file $trace_file]} err]} {
        puts "Error reading trace file: $err"
        exit 1
    }
    
    set hit_count [llength $hits]
    puts "Found $hit_count hits"
    
    if {$hit_count == 0} {
        puts "No HIT records (flag=1) found in trace file"
        puts "Note: The file may contain other types of records (LOG, timestamps, etc)"
        exit 1
    }
    
    # Compute histogram
    puts "Computing histogram with $num_buckets buckets..."
    if {[catch {set hist [compute_histogram $hits $num_buckets]} err]} {
        puts "Error computing histogram: $err"
        exit 1
    }
    
    lassign $hist min_time max_time buckets
    set time_interval_ms [expr {($max_time - $min_time) / 1e6}]
    set time_interval_s [expr {($max_time - $min_time) / 1e9}]
    puts "Time range: 0 to ${time_interval_s} seconds (${time_interval_ms} ms)"
    puts "Max bucket count: [lindex [lsort -integer $buckets] end]"
    
    # Create GUI window - requires wish/Tk
    if {![catch {package require Tk}]} {
        wm title . "Hit Histogram - [file tail $trace_file]"
        wm geometry . 900x600
        
        # Add header with statistics
        set stats_frame [frame .stats]
        pack $stats_frame -fill x -padx 10 -pady 5
        
        label $stats_frame.title -text "Hit Histogram: [file tail $trace_file]" -font {Arial 12 bold}
        pack $stats_frame.title -side left
        
        label $stats_frame.info -text "  Hits: $hit_count | Time: ${time_interval_s} sec | Buckets: $num_buckets" -font {Arial 10}
        pack $stats_frame.info -side left
        
        # Draw histogram
        draw_histogram 900 500 $min_time $max_time $buckets
        
        # Add export button
        set button_frame [frame .buttons]
        pack $button_frame -fill x -padx 10 -pady 5
        
        button $button_frame.export -text "Export to PNG" -command {
            set filename [tk_getSaveFile -defaultextension .png -filetypes {{"PNG files" .png} {"All files" *}}]
            if {$filename ne ""} {
                catch {.canvas postscript -file "$filename.eps"} err
                puts "Exported to $filename (via EPS)"
            }
        }
        pack $button_frame.export -side left
        
        button $button_frame.quit -text "Quit" -command exit
        pack $button_frame.quit -side left
    } else {
        puts "Tk not available - displaying histogram data only (use 'wish' instead of 'tclsh' for GUI)"
        puts "Histogram buckets: $buckets"
    }
}

# Run main
if {[catch {main} err]} {
    puts "Fatal error: $err"
    puts $::errorInfo
    exit 1
}
