# hittrace_dump_oldstyle.tcl
# Dump HitTraceWriter files into your legacy line format:
#   HIT: :1<T<locId>> app_id, instance_id, thread_id
#   LOG: LOG <message>
#
# Usage:
#   tclsh hittrace_dump_oldstyle.tcl /path/to/hits.trace > out.txt

namespace eval ::hittrace {
    # --- IO helpers ---
    proc readExact {chan n} {
        set data [read $chan $n]
        if {[string length $data] != $n} {
            return -code error "unexpected EOF (wanted $n, got [string length $data])"
        }
        return $data
    }
    proc tryRead {chan n} { read $chan $n }

    # --- unified input for plain or .gz files ---
    variable _mode ""
    variable _chan ""
    variable _buf ""
    variable _pos 0

    proc beginInput {path} {
        variable _mode; variable _chan; variable _buf; variable _pos
        set _pos 0
        if {[string match *.gz $path]} {
            if {![llength [info commands zlib]]} {
                return -code error "gzip input requested but Tcl 'zlib' not available"
            }
            set f [open $path r]
            fconfigure $f -translation binary -encoding binary -eofchar {}
            set comp [read $f]
            close $f
            set _buf [zlib gunzip $comp]
            set _mode buf
        } else {
            set _chan [open $path r]
            fconfigure $_chan -translation binary -encoding binary -eofchar {}
            set _mode chan
        }
    }

    proc endInput {} {
        variable _mode; variable _chan; variable _buf; variable _pos
        if {$_mode eq "chan" && [string length $_chan]} { close $_chan }
        set _mode ""; set _chan ""; set _buf ""; set _pos 0
    }

    proc readExactN {n} {
        variable _mode; variable _chan; variable _buf; variable _pos
        if {$_mode eq "chan"} {
            return [readExact $_chan $n]
        } elseif {$_mode eq "buf"} {
            set remain [expr {[string length $_buf] - $_pos}]
            if {$remain < $n} {
                return -code error "unexpected EOF (wanted $n bytes, got $remain)"
            }
            set data [string range $_buf $_pos [expr {$_pos + $n - 1}]]
            incr _pos $n
            return $data
        } else {
            return -code error "input not initialized"
        }
    }

    proc tryReadN {n} {
        variable _mode; variable _chan; variable _buf; variable _pos
        if {$_mode eq "chan"} {
            return [tryRead $_chan $n]
        } elseif {$_mode eq "buf"} {
            set remain [expr {[string length $_buf] - $_pos}]
            if {$remain <= 0} { return "" }
            set take [expr {$n < $remain ? $n : $remain}]
            set data [string range $_buf $_pos [expr {$_pos + $take - 1}]]
            incr _pos $take
            return $data
        } else {
            return -code error "input not initialized"
        }
    }

    # --- portable big-endian readers ---
    proc u8 {bytes}     { binary scan $bytes c b; return [expr {$b & 0xFF}] }
    proc u16be {bytes}  { binary scan $bytes cc b1 b2; return [expr {(($b1&0xFF)<<8) | ($b2&0xFF)}] }
    proc u32be {bytes}  { binary scan $bytes cccc b1 b2 b3 b4; return [expr {(($b1&0xFF)<<24)|(($b2&0xFF)<<16)|(($b3&0xFF)<<8)|($b4&0xFF)}] }
    proc u64be {bytes} {
        binary scan $bytes cccccccc b1 b2 b3 b4 b5 b6 b7 b8
        return [expr {
            (wide($b1&0xFF)<<56)|(wide($b2&0xFF)<<48)|(wide($b3&0xFF)<<40)|(wide($b4&0xFF)<<32)|
            (wide($b5&0xFF)<<24)|(wide($b6&0xFF)<<16)|(wide($b7&0xFF)<<8)|(wide($b8&0xFF))
        }]
    }

    # --- UTF-8 safe decode ---
    proc safeUtf8 {bytes} {
        if {[catch {set s [encoding convertfrom utf-8 $bytes]}]} { return "<invalid-utf8>" }
        # Ensure one line for the old viewer
        return [string map {"\r" " " "\n" " " "\t" " "} $s]
    }

    # Parse inner payload: returns dict with keys:
    #   msgType appId instanceId threadId depth locId text
    proc parsePayload {payload} {
        set n [string length $payload]
        set d [dict create]
        if {$n < 12} { return $d }

        set msgType   [u16be [string range $payload 0 1]]
        set appId     [u16be [string range $payload 2 3]]
        set instance  [u32be [string range $payload 4 7]]
        set threadId  [u32be [string range $payload 8 11]]

        dict set d msgType $msgType
        dict set d appId $appId
        dict set d instanceId $instance
        dict set d threadId $threadId

        switch -- $msgType {
            1 {
                # HIT: stackDepth (u32) then locationId (u32)
                if {$n >= 20} {
                    dict set d depth [u32be [string range $payload 12 15]]
                    dict set d locId [u32be [string range $payload 16 19]]
                }
            }
            2 {
                # LOG: stackDepth(u32), msgLen(u16), msg
                if {$n >= 18} {
                    # Optional: record stack depth
                    dict set d depth [u32be [string range $payload 12 15]]
                    set len [u16be [string range $payload 16 17]]
                    set have [expr {$n - 18}]
                    if {$have >= $len} {
                        dict set d text [safeUtf8 [string range $payload 18 [expr {17+$len}]]]
                    } else {
                        dict set d text [safeUtf8 [string range $payload 18 end]]
                    }
                } else {
                    dict set d text ""
                }
            }
            default {
                # Other types ignored for old format
            }
        }
        return $d
    }

    # Build depth digits prefix, e.g., depth=5 => ":12345<"
    proc depthDigits {depth} {
        if {$depth <= 0} { return ":<" }
        set s ":"
        for {set i 1} {$i <= $depth} {incr i} {
            append s [format %c [expr {48 + ($i % 10)}]]
        }
        append s "<"
        return $s
    }

    # Dump in *old* line format with stack-depth digits
    proc parseFilter {s} {
        if {$s eq {}} { return [list {} 0] }
        if {[string is entier -strict $s]} { return [list $s 0] }
        if {[string first T $s] < 0 || [string index $s end] ne "Z"} { return [list $s 0] }
        set main [string range $s 0 end-1]
        set frac {}
        set dot [string first . $main]
        if {$dot >= 0} { set frac [string range $main [expr {$dot+1}] end]; set main [string range $main 0 [expr {$dot-1}]] }
        if {[string length $main] != 19} { return [list $s 0] }
        if {[catch { set secs [clock scan $main -format {%Y-%m-%dT%H:%M:%S} -gmt 1] }]} { return [list $s 0] }
        set ns [expr {wide($secs) * 1000000000}]
        if {$frac ne {}} {
            if {[string length $frac] > 9} { set frac [string range $frac 0 8] }
            while {[string length $frac] < 9} { append frac 0 }
            if {![string is entier -strict $frac]} { return [list $s 0] }
            set ns [expr {$ns + wide($frac)}]
        }
        return [list $ns 1]
    }

    proc dumpOld {path {startNs {}} {endNs {}}} {
        beginInput $path

        # Header (magic + endian + startMillis)
        set magic [readExactN 8]
        if {$magic ne "HITTRC01"} {
            # Not our file; continue anyway
        }
        # endian, startMillis
        readExactN 1
        set file_start_ms [u64be [readExactN 8]]

        # Records
        while {1} {
            set bflag [tryReadN 2]
            if {[string length $bflag] == 0} break
            if {[string length $bflag] < 2} { error "truncated record header (flag)" }

            # flag, src (ignored), time (nanos), len + payload
            # We only care about the payload inner fields.
            # flag := u16
            # src  := u8
            # time := u64
            # len  := u32
            # data := len bytes
            # Read & discard flag/src/time
            # (we still parse exactly to stay in sync)
            # flag
            set flag [u16be $bflag]
            # src
            readExactN 1
            # nanos
            set nano [u64be [readExactN 8]]
            # len
            set n [u32be [readExactN 4]]
            # payload
            set payload [readExactN $n]

        # Timestamp frame: print TS <UTC>
        if {$flag == 9 && $n == 8} {
            set ms [u64be $payload]
            set secs [expr {$ms / 1000}]
            if {[catch {set iso [clock format $secs -format {%Y-%m-%dT%H:%M:%SZ} -gmt 1]}]} {
                set iso $secs
            }
            puts "TS $iso"
            continue
        }

            # Parse filters once
            if {![info exists __filterParsed]} {
                lassign [parseFilter $startNs] startVal startIsEpoch
                lassign [parseFilter $endNs]   endVal   endIsEpoch
                set __filterParsed 1
                set firstNano {}
            }
            if {$firstNano eq {}} { set firstNano $nano }

            # Filter by time range if provided (non-TS frames only)
            set cmpNs $nano
            if {$startIsEpoch || $endIsEpoch} {
                set cmpNs [expr {wide($file_start_ms)*1000000 + ($nano - $firstNano)}]
            }
            if {($startVal ne {} && $cmpNs < $startVal) || ($endVal ne {} && $cmpNs > $endVal)} {
                continue
            }

            # Parse all inner messages in the payload (batched UDP may contain many)
            set pos 0
            while {$pos + 2 <= $n} {
                set mt [u16be [string range $payload $pos [expr {$pos+1}]]]
                if {$mt == 1} {
                    if {$pos + 20 <= $n} {
                        set appId     [u16be [string range $payload [expr {$pos+2}] [expr {$pos+3}]]]
                        set instance  [u32be [string range $payload [expr {$pos+4}] [expr {$pos+7}]]]
                        set threadId  [u32be [string range $payload [expr {$pos+8}] [expr {$pos+11}]]]
                        set depth     [u32be [string range $payload [expr {$pos+12}] [expr {$pos+15}]]]
                        set locId     [u32be [string range $payload [expr {$pos+16}] [expr {$pos+19}]]]
                        set pref [depthDigits $depth]
                        puts [format "%sT%d> %d, %d, %d" $pref $locId $appId $instance $threadId]
                        set pos [expr {$pos + 20}]
                    } else { break }
                } elseif {$mt == 2} {
                    if {$pos + 18 <= $n} {
                        # stackDepth at pos+12..15 (optional)
                        set len [u16be [string range $payload [expr {$pos+16}] [expr {$pos+17}]]]
                        if {$pos + 18 + $len <= $n} {
                            set msg [safeUtf8 [string range $payload [expr {$pos+18}] [expr {$pos+17+$len}]]]
                            puts "LOG $msg"
                            set pos [expr {$pos + 18 + $len}]
                        } else { break }
                    } else { break }
                } elseif {$mt == 3 || $mt == 4} {
                    # context message consumes the rest; skip in legacy view
                    break
                } else {
                    break
                }
            }
        }
        endInput
    }
}

# --- CLI ---
if {[info exists argv0] && $argv0 eq [info script]} {
    if {[llength $argv] < 1} {
        puts stderr "Usage: tclsh [file tail [info script]] <trace-file> ?-start ns|RFC3339? ?-end ns|RFC3339? > out.txt"
        exit 2
    }
    set path [lindex $argv 0]
    set start {}
    set end {}
    for {set i 1} {$i < [llength $argv]} {incr i} {
        set a [lindex $argv $i]
        if {$a eq "-start" && $i+1 < [llength $argv]} { set start [lindex $argv [incr i]] } elseif {$a eq "-end" && $i+1 < [llength $argv]} { set end [lindex $argv [incr i]] }
    }
    ::hittrace::dumpOld $path $start $end
}
