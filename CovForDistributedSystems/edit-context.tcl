# edit-context.tcl
# Sends a context apply/withdraw message over UDP to the hit server.
#
# Usage:
#   tclsh edit-context.tcl apply CONTEXT_NAME ?options...?
#   tclsh edit-context.tcl withdraw CONTEXT_NAME ?options...?
#
# Options (any mix and order):
#   host=IP_OR_NAME           or  -h HOST    or  -host HOST
#   port=NUMBER               or  -p PORT    or  -port PORT
#   protocol=tcp|udp          or  -proto X   or  -protocol X
#
# Defaults:
#   host: 127.0.0.1   (or env EDITCTX_HOST)
#   port: 8083        (or env EDITCTX_PORT)
#   protocol: udp

proc usage {} {
    puts stderr "Usage: tclsh edit-context.tcl apply|withdraw CONTEXT_NAME"
    exit 2
}

if {[llength $argv] < 2} { usage }
set action [string tolower [lindex $argv 0]]
set ctx     [lindex $argv 1]

if {$action ne "apply" && $action ne "withdraw"} { usage }

# Determine message type (big-endian u16)
set msgType [expr {$action eq "apply" ? 3 : 4}]
set b1 [expr {($msgType >> 8) & 0xFF}]
set b2 [expr {$msgType & 0xFF}]

# UTF-8 encode the context name
set ctxBytes [encoding convertto utf-8 $ctx]

# Build payload: [u16 type BE][utf8 bytes]
set payload [binary format {cc a*} $b1 $b2 $ctxBytes]

# Defaults (env overrides)
set host [expr {[info exists ::env(EDITCTX_HOST)] ? $::env(EDITCTX_HOST) : "127.0.0.1"}]
set portStr [expr {[info exists ::env(EDITCTX_PORT)] ? $::env(EDITCTX_PORT) : "8083"}]
set protocol udp

set argcnt [llength $argv]
set i 2
while {$i < $argcnt} {
    set tok [lindex $argv $i]
    # Support key=value form
    if {[string match *\=* $tok] && ![string match -* $tok]} {
        set key [string tolower [string trim [lindex [split $tok =] 0]]]
        set val [string trim [join [lrange [split $tok =] 1 end] =]]
        switch -- $key {
            host      { set host $val }
            port      { set portStr $val }
            protocol  - proto { set protocol [string tolower $val] }
            default   { puts stderr "Unknown key: $key (ignored)" }
        }
        incr i
        continue
    }
    # Support -k=val form
    if {[string match -*=* $tok]} {
        set pair [split [string range $tok 1 end] =]
        set key [string tolower [lindex $pair 0]]
        set val [join [lrange $pair 1 end] =]
        switch -- $key {
            h - host { set host $val }
            p - port { set portStr $val }
            proto - protocol { set protocol [string tolower $val] }
            default { puts stderr "Unknown option: -$key (ignored)" }
        }
        incr i
        continue
    }
    # Support -k val form
    if {[string match -* $tok]} {
        set key [string tolower [string range $tok 1 end]]
        incr i
        if {$i >= $argcnt} { puts stderr "Missing value for -$key"; exit 2 }
        set val [lindex $argv $i]
        switch -- $key {
            h - host { set host $val }
            p - port { set portStr $val }
            proto - protocol { set protocol [string tolower $val] }
            default { puts stderr "Unknown option: -$key (ignored)" }
        }
        incr i
        continue
    }
    puts stderr "Ignoring invalid arg: $tok (expected key=value or -k val)"
    incr i
}

if {[catch {set port [expr {int($portStr)}]}]} {
    puts stderr "Invalid port: $portStr"; exit 2
}
if {![string match {udp|tcp} $protocol]} {
    if {$protocol ne "udp" && $protocol ne "tcp"} {
        puts stderr "Invalid protocol: $protocol (use tcp or udp)"; exit 2
    }
}

if {$protocol eq "udp"} {
    if {[catch {package require udp}]} {
        puts stderr "Error: Tcl UDP package not available (package 'udp' required)."; exit 1
    }
    set sock [udp_open]
    fconfigure $sock -translation binary -encoding binary
    # For tcludp, -remote expects a single value: {host port}
    fconfigure $sock -remote [list $host $port]
    puts -nonewline $sock $payload
    flush $sock
    close $sock
} else {
    set sock [socket $host $port]
    fconfigure $sock -translation binary -encoding binary -buffering none
    puts -nonewline $sock $payload
    flush $sock
    close $sock
}

puts "Sent $action for context '$ctx' via $protocol to $host:$port"
