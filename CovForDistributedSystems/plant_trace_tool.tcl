#!/usr/bin/env tclsh
# Unified entrypoint for Code Analytics HITTRC01 "plant-trace-*.txt" files.
#
# Commands:
#   summary    - high-level counts and timing
#   parsedump  - delegate to code-analytics/parsetrace.tcl
#   legacydump - delegate to code-analytics/dumptrace.tcl
#   rawdump    - delegate to code-analytics/trace_dump.tcl

namespace eval ::planttrace {
    proc usage {} {
        puts stderr "Usage:"
        puts stderr "  tclsh plant_trace_tool.tcl summary <trace-file>"
        puts stderr "  tclsh plant_trace_tool.tcl parsedump <trace-file> ?-start ns|RFC3339? ?-end ns|RFC3339?"
        puts stderr "  tclsh plant_trace_tool.tcl legacydump <trace-file> ?-start ns|RFC3339? ?-end ns|RFC3339?"
        puts stderr "  tclsh plant_trace_tool.tcl rawdump <trace-file> ?-start ns|RFC3339? ?-end ns|RFC3339?"
        exit 2
    }

    proc readExact {chan n} {
        set data [read $chan $n]
        if {[string length $data] != $n} {
            return -code error "unexpected EOF (wanted $n bytes, got [string length $data])"
        }
        return $data
    }

    proc tryRead {chan n} {
        return [read $chan $n]
    }

    proc u8 {bytes} {
        binary scan $bytes c b
        return [expr {$b & 0xFF}]
    }

    proc u16be {bytes} {
        binary scan $bytes cc b1 b2
        return [expr {(($b1 & 0xFF) << 8) | ($b2 & 0xFF)}]
    }

    proc u32be {bytes} {
        binary scan $bytes cccc b1 b2 b3 b4
        return [expr {(($b1 & 0xFF) << 24) | (($b2 & 0xFF) << 16) | (($b3 & 0xFF) << 8) | ($b4 & 0xFF)}]
    }

    proc u64be {bytes} {
        binary scan $bytes cccccccc b1 b2 b3 b4 b5 b6 b7 b8
        return [expr {
            (wide($b1 & 0xFF) << 56) |
            (wide($b2 & 0xFF) << 48) |
            (wide($b3 & 0xFF) << 40) |
            (wide($b4 & 0xFF) << 32) |
            (wide($b5 & 0xFF) << 24) |
            (wide($b6 & 0xFF) << 16) |
            (wide($b7 & 0xFF) << 8) |
            (wide($b8 & 0xFF))
        }]
    }

    proc fmtUtcMillis {millis} {
        set secs [expr {int($millis / 1000)}]
        return [clock format $secs -format {%Y-%m-%dT%H:%M:%SZ} -gmt 1]
    }

    proc topDictPairs {dictValue limit} {
        set pairs {}
        dict for {k v} $dictValue {
            lappend pairs [list $v $k]
        }
        set sorted [lsort -decreasing -integer -index 0 $pairs]
        if {[llength $sorted] > $limit} {
            return [lrange $sorted 0 [expr {$limit - 1}]]
        }
        return $sorted
    }

    proc parseHitBatch {payload statsVar} {
        upvar 1 $statsVar stats
        set n [string length $payload]
        set pos 0
        set appCounts [dict get $stats stats_by_app]
        set locCounts [dict get $stats stats_by_location]
        set threadKeys [dict get $stats stats_threads]
        set depthKeys [dict get $stats stats_depths]

        while {$pos + 2 <= $n} {
            set msgType [u16be [string range $payload $pos [expr {$pos + 1}]]]

            if {$msgType == 1} {
                if {$pos + 20 > $n} {
                    dict incr stats truncated_messages 1
                    break
                }
                set appId [u16be [string range $payload [expr {$pos + 2}] [expr {$pos + 3}]]]
                set instanceId [u32be [string range $payload [expr {$pos + 4}] [expr {$pos + 7}]]]
                set threadId [u32be [string range $payload [expr {$pos + 8}] [expr {$pos + 11}]]]
                set stackDepth [u32be [string range $payload [expr {$pos + 12}] [expr {$pos + 15}]]]
                set locationId [u32be [string range $payload [expr {$pos + 16}] [expr {$pos + 19}]]]

                dict incr stats hit_messages 1
                dict incr appCounts [format "%d/%d" $appId $instanceId] 1
                dict incr locCounts [format "%d/%d/%d" $appId $instanceId $locationId] 1
                dict set threadKeys [format "%d/%d/%d" $appId $instanceId $threadId] 1
                dict set depthKeys $stackDepth 1

                set pos [expr {$pos + 20}]
                continue
            }

            if {$msgType == 2} {
                if {$pos + 18 > $n} {
                    dict incr stats truncated_messages 1
                    break
                }
                set msgLen [u16be [string range $payload [expr {$pos + 16}] [expr {$pos + 17}]]]
                if {$pos + 18 + $msgLen > $n} {
                    dict incr stats truncated_messages 1
                    break
                }
                dict incr stats log_messages 1
                set pos [expr {$pos + 18 + $msgLen}]
                continue
            }

            if {$msgType == 3} {
                dict incr stats ctx_attach_messages 1
                break
            }

            if {$msgType == 4} {
                dict incr stats ctx_withdraw_messages 1
                break
            }

            dict incr stats unknown_inner_messages 1
            break
        }

        dict set stats stats_by_app $appCounts
        dict set stats stats_by_location $locCounts
        dict set stats stats_threads $threadKeys
        dict set stats stats_depths $depthKeys
    }

    proc summary {path} {
        if {![file exists $path]} {
            error "Trace file not found: $path"
        }

        set f [open $path r]
        fconfigure $f -translation binary -encoding binary -eofchar {}

        set magic [readExact $f 8]
        if {$magic ne "HITTRC01"} {
            close $f
            error "Bad magic: expected HITTRC01"
        }

        set endian [u8 [readExact $f 1]]
        if {$endian != 0} {
            close $f
            error "Unsupported endianness: $endian"
        }

        set fileStartMillis [u64be [readExact $f 8]]

        set stats [dict create \
            records 0 \
            hit_records 0 \
            log_records 0 \
            ts_records 0 \
            ctx_attach_records 0 \
            ctx_withdraw_records 0 \
            other_records 0 \
            hit_messages 0 \
            log_messages 0 \
            ctx_attach_messages 0 \
            ctx_withdraw_messages 0 \
            unknown_inner_messages 0 \
            truncated_messages 0 \
            stats_by_app {} \
            stats_by_location {} \
            stats_threads {} \
            stats_depths {}]

        set firstNano {}
        set lastNano {}

        while {1} {
            set bflag [tryRead $f 2]
            if {[string length $bflag] == 0} {
                break
            }
            if {[string length $bflag] < 2} {
                dict incr stats truncated_messages 1
                break
            }

            set flag [u16be $bflag]
            set src [u8 [readExact $f 1]]
            set nano [u64be [readExact $f 8]]
            set len [u32be [readExact $f 4]]
            set payload [readExact $f $len]

            if {$firstNano eq {}} {
                set firstNano $nano
            }
            set lastNano $nano

            dict incr stats records 1

            switch -- $flag {
                1 {
                    dict incr stats hit_records 1
                    parseHitBatch $payload stats
                }
                2 {
                    dict incr stats log_records 1
                    dict incr stats log_messages 1
                }
                3 {
                    dict incr stats ctx_attach_records 1
                    dict incr stats ctx_attach_messages 1
                }
                4 {
                    dict incr stats ctx_withdraw_records 1
                    dict incr stats ctx_withdraw_messages 1
                }
                9 {
                    dict incr stats ts_records 1
                }
                default {
                    dict incr stats other_records 1
                }
            }
        }

        close $f

        puts "Trace file: $path"
        puts "Header:"
        puts "  File start UTC: [fmtUtcMillis $fileStartMillis]"
        puts "  Endianness: big-endian"
        puts ""
        puts "Outer records:"
        puts "  Total: [dict get $stats records]"
        puts "  HIT: [dict get $stats hit_records]"
        puts "  LOG: [dict get $stats log_records]"
        puts "  TS: [dict get $stats ts_records]"
        puts "  CTX attach: [dict get $stats ctx_attach_records]"
        puts "  CTX withdraw: [dict get $stats ctx_withdraw_records]"
        puts "  Other: [dict get $stats other_records]"
        puts ""
        puts "Inner messages:"
        puts "  HIT messages: [dict get $stats hit_messages]"
        puts "  LOG messages: [dict get $stats log_messages]"
        puts "  CTX attach messages: [dict get $stats ctx_attach_messages]"
        puts "  CTX withdraw messages: [dict get $stats ctx_withdraw_messages]"
        puts "  Unknown inner messages: [dict get $stats unknown_inner_messages]"
        puts "  Truncated payloads/messages: [dict get $stats truncated_messages]"

        if {$firstNano ne {} && $lastNano ne {}} {
            set durationNs [expr {$lastNano - $firstNano}]
            set durationSecs [expr {$durationNs / 1e9}]
            set approxStartMillis $fileStartMillis
            set approxEndMillis [expr {$fileStartMillis + int($durationNs / 1000000)}]
            puts ""
            puts "Timing:"
            puts "  First record UTC approx: [fmtUtcMillis $approxStartMillis]"
            puts "  Last record UTC approx:  [fmtUtcMillis $approxEndMillis]"
            puts "  Duration: [format %.6f $durationSecs] seconds"
            if {$durationSecs > 0 && [dict get $stats hit_messages] > 0} {
                puts "  Average hit rate: [format %.2f [expr {[dict get $stats hit_messages] / $durationSecs}]] hits/sec"
            }
        }

        set appCounts [dict get $stats stats_by_app]
        if {[dict size $appCounts] > 0} {
            puts ""
            puts "Top app/instance pairs:"
            foreach pair [topDictPairs $appCounts 10] {
                lassign $pair count key
                puts "  $key -> $count hits"
            }
        }

        set locCounts [dict get $stats stats_by_location]
        if {[dict size $locCounts] > 0} {
            puts ""
            puts "Top locations:"
            foreach pair [topDictPairs $locCounts 10] {
                lassign $pair count key
                puts "  $key -> $count hits"
            }
        }

        set threads [dict get $stats stats_threads]
        set depths [dict get $stats stats_depths]
        puts ""
        puts "Cardinality:"
        puts "  Unique app/instance/thread keys: [dict size $threads]"
        puts "  Unique stack depths: [dict size $depths]"
    }

    proc delegate {scriptName traceFile extraArgs} {
        set scriptPath [file join [file dirname [info script]] code-analytics $scriptName]
        if {![file exists $scriptPath]} {
            error "Delegate script not found: $scriptPath"
        }

        set cmd [list [info nameofexecutable] $scriptPath $traceFile]
        foreach arg $extraArgs {
            lappend cmd $arg
        }

        set output [exec {*}$cmd]
        if {$output ne ""} {
            puts $output
        }
    }
}

if {[llength $argv] < 2} {
    ::planttrace::usage
}

set command [string tolower [lindex $argv 0]]
set traceFile [lindex $argv 1]
set restArgs [lrange $argv 2 end]

if {$command eq "summary"} {
    if {[llength $restArgs] != 0} {
        ::planttrace::usage
    }
    if {[catch {::planttrace::summary $traceFile} err]} {
        puts stderr "Error: $err"
        exit 1
    }
    exit 0
}

if {$command eq "parsedump"} {
    if {[catch {::planttrace::delegate parsetrace.tcl $traceFile $restArgs} err]} {
        puts stderr "Error: $err"
        exit 1
    }
    exit 0
}

if {$command eq "legacydump"} {
    if {[catch {::planttrace::delegate dumptrace.tcl $traceFile $restArgs} err]} {
        puts stderr "Error: $err"
        exit 1
    }
    exit 0
}

if {$command eq "rawdump"} {
    if {[catch {::planttrace::delegate trace_dump.tcl $traceFile $restArgs} err]} {
        puts stderr "Error: $err"
        exit 1
    }
    exit 0
}

::planttrace::usage
