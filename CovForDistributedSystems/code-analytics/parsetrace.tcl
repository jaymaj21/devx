# hittrace_dump_parsed.tcl
# Portable Tcl 8.5+/JimTcl friendly reader for HitTraceWriter files,
# with parsing of inner UDP/TCP message structure inferred from samples.
#
# Usage:
#    tclsh hittrace_dump_parsed.tcl /path/to/hits.trace
# Options (env/vars):
#    set ::hittrace::maxHex 32     ;# hex preview length for unknown/remainder
#    set ::hittrace::showRema 0    ;# show remainder bytes after parsed fields (0/1)

namespace eval ::hittrace {
    variable maxHex 32
    variable showRema 0

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

    # --- IO helpers ---
    proc readExact {chan n} {
        set data [read $chan $n]
        if {[string length $data] != $n} {
            return -code error "unexpected EOF (wanted $n, got [string length $data])"
        }
        return $data
    }
    proc tryRead {chan n} { read $chan $n } ;# may be empty at EOF

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

    # --- formatting helpers ---
    proc srcName {s} {
        switch -- $s { 0 {return UDP} 1 {return TCP} 2 {return INT} default {return "UNK($s)"} }
    }
    proc hexPreview {bytes} {
        variable maxHex
        set slice [string range $bytes 0 [expr {$maxHex-1}]]
        if {[catch {set hex [binary encode hex $slice]}]} { binary scan $slice H* hex }
        set hex [string toupper $hex]
        if {[string length $bytes] > $maxHex} {append hex ...}
        return $hex
    }
    proc safeUtf8 {bytes} {
        if {[catch {set s [encoding convertfrom utf-8 $bytes]}]} { return "<invalid-utf8>" }
        return [string map {\\ \\\\ \n \\n \r \\r \t \\t \" \\\"} $s]
    }

    # --- parse inner payload according to inferred schema ---
    proc parsePayload {payload} {
        set n [string length $payload]
        if {$n < 12} {
            return [list UNKNOWN [format "truncated(%d) hex=%s" $n [hexPreview $payload]]]
        }

        set msgType   [u16be [string range $payload 0 1]]
        set appId     [u16be [string range $payload 2 3]]
        set instance  [u32be [string range $payload 4 7]]
        set threadId  [u32be [string range $payload 8 11]]

        switch -- $msgType {
            1 {
                # HIT: need 4 more bytes for locationId
                if {$n < 16} {
                    return [list HIT [format "app=%d inst=%d thread=%d truncated(%d) hex=%s" \
                                $appId $instance $threadId $n [hexPreview $payload]]]
                }
                set locId [u32be [string range $payload 12 15]]
                set info  [format "app=%d inst=%d thread=%d loc=%d" $appId $instance $threadId $locId]
                if {$n > 16} {
                    variable showRema
                    if {$showRema} {
                        set rem [string range $payload 16 end]
                        append info [format " +remainder(%d) hex=%s" [string length $rem] [hexPreview $rem]]
                    }
                }
                return [list HIT $info]
            }
            2 {
                # LOG: expect u16 length + that many UTF-8 bytes
                if {$n < 14} {
                    return [list LOG [format "app=%d inst=%d thread=%d truncated(%d) hex=%s" \
                               $appId $instance $threadId $n [hexPreview $payload]]]
                }
                set len [u16be [string range $payload 12 13]]
                set have [expr {$n - 14}]
                if {$have < $len} {
                    # length says more than present — print what we have
                    set text [safeUtf8 [string range $payload 14 end]]
                    return [list LOG [format "app=%d inst=%d thread=%d text=\"%s\" (truncated, need %d more bytes)" \
                               $appId $instance $threadId $text [expr {$len - $have}]]]
                }
                set text [safeUtf8 [string range $payload 14 [expr {13 + $len}]]]
                set info [format "app=%d inst=%d thread=%d text=\"%s\"" $appId $instance $threadId $text]
                if {$have > $len} {
                    variable showRema
                    if {$showRema} {
                        set rem [string range $payload [expr {14+$len}] end]
                        append info [format " +remainder(%d) hex=%s" [string length $rem] [hexPreview $rem]]
                    }
                }
                return [list LOG $info]
            }
            3 - 4 {
                # CTX attach/withdraw — treat remaining as length-prefixed UTF-8 if present,
                # else dump remainder as UTF-8.
                set kind [expr {$msgType == 3 ? "CTX+" : "CTX-"}]
                set rest [string range $payload 12 end]
                set rn [string length $rest]
                set text ""
                if {$rn >= 2} {
                    set l2 [u16be [string range $rest 0 1]]
                    if {$rn-2 >= $l2} {
                        set text [safeUtf8 [string range $rest 2 [expr {1+$l2}]]]
                        set extra [string range $rest [expr {2+$l2}] end]
                        set info [format "app=%d inst=%d thread=%d ctx=\"%s\"" $appId $instance $threadId $text]
                        if {[string length $extra] > 0} {
                            variable showRema
                            if {$showRema} { append info [format " +remainder(%d) hex=%s" [string length $extra] [hexPreview $extra]] }
                        }
                        return [list $kind $info]
                    }
                }
                # Fallback: treat all rest as UTF-8
                set text [safeUtf8 $rest]
                set info [format "app=%d inst=%d thread=%d ctx=\"%s\"" $appId $instance $threadId $text]
                return [list $kind $info]
            }
            default {
                return [list UNKNOWN [format "type=%d app=%d inst=%d thread=%d hex=%s" \
                        $msgType $appId $instance $threadId [hexPreview $payload]]]
            }
        }
    }

    # --- outer trace reader (frames) ---
    proc dump {path {startNs {}} {endNs {}}} {
        set f [open $path r]
        fconfigure $f -translation binary -encoding binary -eofchar {}

        lassign [parseFilter $startNs] startVal startIsEpoch
        lassign [parseFilter $endNs]   endVal   endIsEpoch
        set firstNano {}

        # Header
        set magic [readExact $f 8]
        if {$magic ne "HITTRC01"} {
            set shown $magic
            if {[catch {set shown [encoding convertfrom utf-8 $magic]}]} {
                binary scan $magic H* shown; set shown "0x[string toupper $shown]"
            }
            puts "# Warning: unknown magic '$shown' (continuing)"
        }
        set endian [u8 [readExact $f 1]]
        set startMillis [u64be [readExact $f 8]]
        set startSecs [expr {$startMillis / 1000}]
        if {[catch {set startIso [clock format $startSecs -format {%Y-%m-%dT%H:%M:%S}]}]} { set startIso "N/A" }
        puts "# start=$startMillis ($startIso) endian=$endian"

        set idx 0
        while {1} {
            set bflag [tryRead $f 2]
            if {[string length $bflag] == 0} break
            if {[string length $bflag] < 2} { error "truncated record header (flag)" }
            set flag [u16be $bflag]
            set src  [u8 [readExact $f 1]]
            set nano [u64be [readExact $f 8]]
            if {$firstNano eq {}} { set firstNano $nano }
            set n    [u32be [readExact $f 4]]
            set payload [readExact $f $n]

            # Always include timestamp frames for context
            if {$flag == 9 && $n == 8} {
                set ms [u64be $payload]
                set secs [expr {$ms / 1000}]
                if {[catch {set iso [clock format $secs -format {%Y-%m-%dT%H:%M:%SZ} -gmt 1]}]} { set iso $secs }
                puts [format {TS %s} $iso]
                incr idx
                continue
            }

            # Filter by time range if provided
            set cmpNs $nano
            if {$startIsEpoch || $endIsEpoch} {
                set cmpNs [expr {wide($startMillis)*1000000 + ($nano - $firstNano)}]
            }
            if {($startVal ne {} && $cmpNs < $startVal) || ($endVal ne {} && $cmpNs > $endVal)} {
                incr idx
                continue
            }

            # Parse inner message bytes
            set parsed [parsePayload $payload]
            lassign $parsed kind info

            puts [format {[%08d] src=%s t(nanos)=%s len=%d %-6s %s} \
                        $idx [srcName $src] $nano $n $kind $info]
            incr idx
        }
        close $f
    }
}

# --- CLI ---
if {[info exists argv0] && $argv0 eq [info script]} {
    if {[llength $argv] < 1} {
        puts stderr "Usage: tclsh [file tail [info script]] <trace-file> ?-start ns|RFC3339? ?-end ns|RFC3339?"
        exit 2
    }
    set path [lindex $argv 0]
    set start {}
    set end {}
    for {set i 1} {$i < [llength $argv]} {incr i} {
        set a [lindex $argv $i]
        if {$a eq "-start" && $i+1 < [llength $argv]} { set start [lindex $argv [incr i]] } elseif {$a eq "-end" && $i+1 < [llength $argv]} { set end [lindex $argv [incr i]] }
    }
    ::hittrace::dump $path $start $end
}
