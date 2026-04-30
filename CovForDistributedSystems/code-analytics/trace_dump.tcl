# hittrace_dump.tcl
# Tcl 8.5+/JimTcl-friendly binary reader for HitTraceWriter files.
# Usage:    tclsh hittrace_dump.tcl /path/to/hits.trace
# Optional: set ::hittrace::maxHex to change hex preview length (default 32)

namespace eval ::hittrace {
    variable maxHex 32

    # Parse filter value: returns list {ns isEpoch}
    # - If empty: {{} 0}
    # - If integer: {ns 0} (file-clock nanos)
    # - If RFC3339 UTC string: {ns 1} where ns is epoch nanoseconds
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

    # --- low-level IO helpers ---
    proc readExact {chan n} {
        set data [read $chan $n]
        if {[string length $data] != $n} {
            return -code error "unexpected EOF (wanted $n bytes, got [string length $data])"
        }
        return $data
    }
    proc tryRead {chan n} {
        return [read $chan $n] ;# may be empty at EOF
    }

    # --- portable big-endian readers using lowercase 'c' specs ---
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
        # Use wide() to ensure 64-bit shifts on older Tcl
        return [expr {
            (wide($b1 & 0xFF) << 56) |
            (wide($b2 & 0xFF) << 48) |
            (wide($b3 & 0xFF) << 40) |
            (wide($b4 & 0xFF) << 32) |
            (wide($b5 & 0xFF) << 24) |
            (wide($b6 & 0xFF) << 16) |
            (wide($b7 & 0xFF) <<  8) |
            (wide($b8 & 0xFF))
        }]
    }

    # --- formatting helpers ---
    proc srcName {s} {
        switch -- $s {
            0 {return UDP}
            1 {return TCP}
            2 {return INT}
            default {return "UNK($s)"}
        }
    }
    proc isMostlyPrintable {bytes} {
        set n [string length $bytes]
        if {$n == 0} {return 1}
        set sample [expr {$n < 64 ? $n : 64}]
        set printable 0
        for {set i 0} {$i < $sample} {incr i} {
            # string index returns a 1-char string; %c -> signed byte -> mask
            binary scan [string index $bytes $i] c b
            set b [expr {$b & 0xFF}]
            if {$b == 9 || $b == 10 || $b == 13 || ($b >= 32 && $b < 127)} {
                incr printable
            }
        }
        return [expr {$printable * 100 > $sample * 85}]
    }
    proc hexPreview {bytes} {
        variable maxHex
        set slice [string range $bytes 0 [expr {$maxHex-1}]]
        if {[catch {set hex [binary encode hex $slice]}]} {
            # Fallback for builds without binary encode
            binary scan $slice H* hex
        }
        set hex [string toupper $hex]
        if {[string length $bytes] > $maxHex} {append hex ...}
        return $hex
    }
    proc safeUtf8 {bytes} {
        if {[catch {set s [encoding convertfrom utf-8 $bytes]}]} {
            return "<invalid-utf8>"
        }
        # Escape common control chars and backslash/quote
        return [string map {\\ \\\\ \n \\n \r \\r \t \\t \" \\\"} $s]
    }

    # --- main dump ---
    proc dump {path {startNs {}} {endNs {}}} {
        set f [open $path r]
        fconfigure $f -translation binary -encoding binary -eofchar {}
        # Parse filters
        lassign [parseFilter $startNs] startVal startIsEpoch
        lassign [parseFilter $endNs]   endVal   endIsEpoch
        set firstNano {}

        # Header: 8 magic, 1 endian, 8 startMillis
        set magic [readExact $f 8]
        if {$magic ne "HITTRC01"} {
            # Show bytes safely if not ASCII
            set shown $magic
            if {[catch {set shown [encoding convertfrom utf-8 $magic]}]} {
                binary scan $magic H* shown
                set shown "0x[string toupper $shown]"
            }
            puts "# Warning: unknown magic '$shown' (continuing)"
        }
        set endian [u8 [readExact $f 1]]
        set startMillis [u64be [readExact $f 8]]
        set startSecs [expr {$startMillis / 1000}]
        if {[catch {set startIso [clock format $startSecs -format {%Y-%m-%dT%H:%M:%S}]}]} {
            set startIso "N/A"
        }
        puts "# start=$startMillis ($startIso) endian=$endian"

        set idx 0
        while {1} {
            # Try to read flag (2 bytes). If clean EOF, stop.
            set bflag [tryRead $f 2]
            if {[string length $bflag] == 0} {
                break
            } elseif {[string length $bflag] < 2} {
                error "truncated record header (flag)"
            }
            set flag [u16be $bflag]

            set bsrc [readExact $f 1]
            set src  [u8 $bsrc]

            set bnano [readExact $f 8]
            set nano [u64be $bnano]
            if {$firstNano eq {}} { set firstNano $nano }

            set blen [readExact $f 4]
            set n    [u32be $blen]

            set payload [readExact $f $n]

            # Filter by time range if provided
            # Compute comparison time: file-clock or absolute epoch
            set cmpNs $nano
            if {$startIsEpoch || $endIsEpoch} {
                set cmpNs [expr {wide($startMillis)*1000000 + ($nano - $firstNano)}]
            }
            if {($startVal ne {} && $cmpNs < $startVal) || ($endVal ne {} && $cmpNs > $endVal)} {
                # Still allow TS frames to pass to aid context
                if { !($flag == 9 && $n == 8) } {
                    incr idx
                    continue
                }
            }

            # Special-case timestamp frames: flag==9, payload is u64 epochMillis
            if {$flag == 9 && $n == 8} {
                set ms [u64be $payload]
                set secs [expr {$ms / 1000}]
                if {[catch {set iso [clock format $secs -format {%Y-%m-%dT%H:%M:%SZ} -gmt 1]}]} {
                    set iso $secs
                }
                puts [format {TS %s} $iso]
            } else {
                # Heuristic: print text if LOG flag (=2) or looks texty
                set looksText [expr {$flag == 2 || [isMostlyPrintable $payload]}]
                if {$looksText} {
                    set desc [format {text="%s"} [safeUtf8 $payload]]
                } else {
                    set desc [format {hex=%s} [hexPreview $payload]]
                }

                puts [format {[%08d] flag=%d src=%s t(nanos)=%s len=%d %s} \
                            $idx $flag [srcName $src] $nano $n $desc]
            }
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
