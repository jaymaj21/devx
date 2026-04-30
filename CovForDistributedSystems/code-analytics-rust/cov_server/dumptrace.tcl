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
    #   msgType appId instanceId threadId locId text
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
                # HIT: next u32 = locationId
                if {$n >= 16} {
                    dict set d locId [u32be [string range $payload 12 15]]
                }
            }
            2 {
                # LOG: u16 length + utf-8 bytes (fallback: the rest as utf-8)
                if {$n >= 14} {
                    set len [u16be [string range $payload 12 13]]
                    set have [expr {$n - 14}]
                    if {$have >= $len} {
                        dict set d text [safeUtf8 [string range $payload 14 [expr {13+$len}]]]
                    } else {
                        dict set d text [safeUtf8 [string range $payload 14 end]]
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

    # Dump in *old* line format
    proc dumpOld {path} {
        set f [open $path r]
        fconfigure $f -translation binary -encoding binary -eofchar {}

        # Header (magic + endian + startMillis)
        set magic [readExact $f 8]
        if {$magic ne "HITTRC01"} {
            # Not our file; continue anyway
        }
        # endian, startMillis (we don't need them for old format)
        readExact $f 1
        readExact $f 8

        # Records
        while {1} {
            set bflag [tryRead $f 2]
            if {[string length $bflag] == 0} break
            if {[string length $bflag] < 2} { error "truncated record header (flag)" }

            # flag (ignored), src (ignored), time (ignored), len + payload
            # We only care about the payload inner fields.
            # flag := u16
            # src  := u8
            # time := u64
            # len  := u32
            # data := len bytes
            # Read & discard flag/src/time
            # (we still parse exactly to stay in sync)
            # flag
            u16be $bflag
            # src
            readExact $f 1
            # nanos
            readExact $f 8
            # len
            set n [u32be [readExact $f 4]]
            # payload
            set payload [readExact $f $n]

            # Parse inner message
            set d [parsePayload $payload]
            if {![dict exists $d msgType]} {
                continue
            }
            set mt [dict get $d msgType]
            if {$mt == 1 && [dict exists $d locId]} {
                # HIT line:
                # :1<T<locId>> app_id, instance_id, thread_id
                puts [format ":1<T%d> %d, %d, %d" \
                    [dict get $d locId] \
                    [dict get $d appId] \
                    [dict get $d instanceId] \
                    [dict get $d threadId]]
            } elseif {$mt == 2} {
                # LOG line:
                # LOG <message>
                set msg ""
                if {[dict exists $d text]} { set msg [dict get $d text] }
                puts "LOG $msg"
            } else {
                # Ignore other types for the old viewer
                continue
            }
        }
        close $f
    }
}

# --- CLI ---
if {[info exists argv0] && $argv0 eq [info script]} {
    if {[llength $argv] < 1} {
        puts stderr "Usage: tclsh [file tail [info script]] <trace-file> > out.txt"
        exit 2
    }
    ::hittrace::dumpOld [lindex $argv 0]
}
