# UTF-8, NUL-delimited loopback command server for Spectral Tcl/Tk.
# Source this module; no listener is started until startCmdServer is called.
namespace eval ::spectral_cmd_server {
    variable listeners; array set listeners {}
    variable clients; array set clients {}
    variable buffers; array set buffers {}
    variable busy; array set busy {}
    variable closing; array set closing {}
    variable maxBytes 1048576
}

proc startCmdServer {port} {
    if {![string is integer -strict $port] || $port < 1 || $port > 65535} {
        error "Port must be an integer from 1 to 65535."
    }
    set port [expr {int($port)}]
    if {[info exists ::spectral_cmd_server::listeners($port)]} {
        error "Command server is already listening on port $port."
    }
    set ::spectral_cmd_server::listeners($port) [socket -server [list ::spectral_cmd_server::accept $port] -myaddr 127.0.0.1 $port]
    return $port
}

proc stopCmdServer {port} {
    if {![string is integer -strict $port] || $port < 1 || $port > 65535} {
        error "Port must be an integer from 1 to 65535."
    }
    set port [expr {int($port)}]
    if {![info exists ::spectral_cmd_server::listeners($port)]} {
        error "No command server is listening on port $port."
    }
    close $::spectral_cmd_server::listeners($port)
    unset ::spectral_cmd_server::listeners($port)
    foreach channel [array names ::spectral_cmd_server::clients] {
        if {$::spectral_cmd_server::clients($channel) == $port} {
            ::spectral_cmd_server::closeClient $channel
        }
    }
    return $port
}

proc ::spectral_cmd_server::closeClient {channel} {
    variable clients; variable buffers; variable busy; variable closing
    catch {fileevent $channel readable {}}
    catch {fileevent $channel writable {}}
    catch {close $channel}
    unset -nocomplain clients($channel) buffers($channel) busy($channel) closing($channel)
}

proc ::spectral_cmd_server::accept {port channel address remotePort} {
    variable clients; variable buffers; variable busy
    fconfigure $channel -blocking 0 -translation binary -encoding binary -buffering none
    set clients($channel) $port
    set buffers($channel) ""
    set busy($channel) 0
    fileevent $channel readable [list ::spectral_cmd_server::readable $channel]
}

proc ::spectral_cmd_server::reply {channel prefix value} {
    # Reserve literal NUL exclusively for framing, including in evaluation results.
    set value [string map [list \x00 {\0}] $value]
    if {[catch {
        puts -nonewline $channel "[encoding convertto utf-8 "$prefix$value"]\x00"
        flush $channel
    }]} {
        closeClient $channel
        return
    }
    fileevent $channel writable [list ::spectral_cmd_server::writable $channel]
}

proc ::spectral_cmd_server::writable {channel} {
    if {[catch {flush $channel; set pending [chan pending output $channel]}]} {
        closeClient $channel
    } elseif {$pending == 0} {
        if {[info exists ::spectral_cmd_server::closing($channel)]} {
            closeClient $channel
        } else {fileevent $channel writable {}}
    }
}

proc ::spectral_cmd_server::readable {channel} {
    variable buffers; variable busy; variable maxBytes
    if {![info exists buffers($channel)] || $busy($channel)} return
    if {[catch {set bytes [read $channel 65536]}]} {
        closeClient $channel
        return
    }
    append buffers($channel) $bytes
    set busy($channel) 1
    # Disable reentrant evaluation if a script calls update or vwait.
    fileevent $channel readable {}
    while {[info exists buffers($channel)]} {
        set delimiter [string first \x00 $buffers($channel)]
        if {$delimiter < 0} {
            if {[string length $buffers($channel)] > $maxBytes} {
                reply $channel {Error: } {command exceeds 1 MiB}
                if {[info exists buffers($channel)]} {set ::spectral_cmd_server::closing($channel) 1}
            }
            break
        }
        set payload [string range $buffers($channel) 0 [expr {$delimiter - 1}]]
        set buffers($channel) [string range $buffers($channel) [expr {$delimiter + 1}] end]
        if {[string length $payload] > $maxBytes} {
            reply $channel {Error: } {command exceeds 1 MiB}
            if {[info exists buffers($channel)]} {set ::spectral_cmd_server::closing($channel) 1}
            break
        }
        if {[catch {set script [encoding convertfrom utf-8 $payload]} result]} {
            reply $channel {Error: } $result
        } elseif {[string trim $script] eq ""} {
            reply $channel {Error: } {empty command}
        } else {
            set code [catch {uplevel #0 $script} result options]
            if {$code == 2 && [dict get $options -code] == 0} {set code 0}
            if {[info exists buffers($channel)]} {
                reply $channel [expr {$code == 0 ? "Result: " : "Error: "}] $result
            }
        }
    }
    if {[info exists buffers($channel)]} {
        set busy($channel) 0
        if {[info exists ::spectral_cmd_server::closing($channel)]} return
        if {[eof $channel]} {closeClient $channel} else {
            fileevent $channel readable [list ::spectral_cmd_server::readable $channel]
        }
    }
}
