#!/usr/bin/env tclsh
# Compatible with both Spectral Tcl/Tk and Spectral Web command servers.
namespace eval ::spectral_cmd_client { variable nextId 0 }

proc ::spectral_cmd_client::finish {id error value} {
    variable requests
    if {![info exists requests($id,done)] || $requests($id,done)} return
    set requests($id,error) $error
    set requests($id,value) $value
    set requests($id,done) 1
}

proc ::spectral_cmd_client::connected {id} {
    variable requests
    set channel $requests($id,channel)
    fileevent $channel writable {}
    if {[catch {
        set error [fconfigure $channel -error]
        if {$error ne ""} {error $error}
        puts -nonewline $channel "[encoding convertto utf-8 $requests($id,command)]\x00"
        flush $channel
    } error]} {
        finish $id 1 $error
        return
    }
    fileevent $channel readable [list ::spectral_cmd_client::readable $id]
    fileevent $channel writable [list ::spectral_cmd_client::flushOutput $id]
}

proc ::spectral_cmd_client::flushOutput {id} {
    variable requests
    set channel $requests($id,channel)
    if {[catch {flush $channel; set pending [chan pending output $channel]} error]} {
        finish $id 1 $error
    } elseif {$pending == 0} {fileevent $channel writable {}}
}

proc ::spectral_cmd_client::readable {id} {
    variable requests
    set channel $requests($id,channel)
    if {[catch {set bytes [read $channel 65536]} error]} {
        finish $id 1 $error
        return
    }
    append requests($id,buffer) $bytes
    set delimiter [string first \x00 $requests($id,buffer)]
    if {$delimiter >= 0} {
        finish $id 0 [encoding convertfrom utf-8 [string range $requests($id,buffer) 0 [expr {$delimiter - 1}]]]
    } elseif {[eof $channel]} {
        finish $id 1 {Server closed the connection before a NUL-terminated response arrived.}
    }
}

proc ::spectral_cmd_client::sendCommand {port command {timeoutMs 30000}} {
    variable nextId; variable requests
    if {![string is integer -strict $port] || $port < 1 || $port > 65535} {
        error "Port must be an integer from 1 to 65535."
    }
    if {[string first \x00 $command] >= 0} {error "The command contains a NUL byte, reserved as the protocol delimiter."}
    set id [incr nextId]
    set channel [socket -async 127.0.0.1 $port]
    fconfigure $channel -blocking 0 -translation binary -encoding binary -buffering none
    set requests($id,channel) $channel
    set requests($id,command) $command
    set requests($id,buffer) ""
    set requests($id,done) 0
    set timer [after $timeoutMs [list ::spectral_cmd_client::finish $id 1 "Timed out after $timeoutMs ms waiting for a response."]]
    fileevent $channel writable [list ::spectral_cmd_client::connected $id]
    vwait ::spectral_cmd_client::requests($id,done)
    after cancel $timer
    catch {close $channel}
    set error $requests($id,error)
    set result $requests($id,value)
    array unset requests "$id,*"
    if {$error} {return -code error $result}
    return $result
}

proc ::spectral_cmd_client::usage {} {
    return {Usage:
  tclsh cmd_client.tcl <port> -c <command>
  tclsh cmd_client.tcl <port> -f <UTF-8 script file>
  tclsh cmd_client.tcl --help

Example: tclsh cmd_client.tcl 32124 -c "expr {6 * 7}"}
}

proc ::spectral_cmd_client::main {args} {
    if {[lsearch -exact $args --help] >= 0 || [lsearch -exact $args -h] >= 0} {puts [usage]; return 0}
    if {[llength $args] != 3} {puts stderr [usage]; return 2}
    lassign $args port mode value
    if {$mode ni {-c --command -f --file} || $value eq "" || ![string is integer -strict $port] || $port < 1 || $port > 65535} {
        puts stderr [usage]; return 2
    }
    if {[catch {
        if {$mode in {-f --file}} {
            set file [open $value r]
            try {fconfigure $file -encoding utf-8; set command [read $file]} finally {close $file}
        } else {set command $value}
        set response [sendCommand $port $command]
    } error]} {puts stderr "Error: $error"; return 1}
    puts $response
    return [expr {[string match {Error:*} $response] ? 1 : 0}]
}

if {[info exists argv0] && [file normalize [info script]] eq [file normalize $argv0]} {
    fconfigure stdout -encoding utf-8
    fconfigure stderr -encoding utf-8
    exit [::spectral_cmd_client::main {*}$argv]
}
