#!/usr/bin/env wish

# hltshow.tcl
# Left panel: raw HLT stream
# Right panel: rendered HLT
# Vertical scrolling is synchronized and visible line heights are padded so
# row alignment remains stable even with embedded windows/images.

set ::hltdiff_skip_main 1
source [file join [file dirname [info script]] hltdiff.tcl]

array set ::hs {
    syncing 0
    align_pending 0
    align_running 0
    last_align_from 1
    last_align_to 0
    path ""
    hlt_ok 0
}

proc hs:usage {} {
    puts stderr "Usage: wish hltshow.tcl <file.hlt|file.txt>"
}

proc hs:read_utf8 {path} {
    set fp [open $path r]
    fconfigure $fp -encoding utf-8
    set c [read $fp]
    close $fp
    return $c
}

proc hs:update_line_numbers {tw lnw} {
    set endIdx [$tw index end-1c]
    set total [expr {int($endIdx)}]
    if {$total < 1} {
        set total 1
    }
    set buf ""
    for {set i 1} {$i <= $total} {incr i} {
        append buf [format "%6d\n" $i]
    }
    $lnw configure -state normal
    $lnw delete 1.0 end
    $lnw insert 1.0 $buf
    $lnw configure -state disabled
}

proc hs:set_pad {w line px} {
    global hs
    set tag "hltshow_pad_$line"
    set from "$line.0"
    set to "$line.end + 1c"
    if {[info exists hs(pad,$w,$line)] && $hs(pad,$w,$line) == $px} {
        return
    }
    if {$px > 0} {
        $w tag configure $tag -spacing3 $px
        $w tag add $tag $from $to
    } else {
        catch {$w tag remove $tag $from $to}
    }
    set hs(pad,$w,$line) $px
}

proc hs:clear_pad_range {w from to} {
    global hs
    if {$to < $from} {
        return
    }
    for {set line $from} {$line <= $to} {incr line} {
        set tag "hltshow_pad_$line"
        catch {$w tag remove $tag "$line.0" "$line.end + 1c"}
        catch {unset hs(pad,$w,$line)}
    }
}

proc hs:schedule_align {} {
    global hs
    if {$hs(align_pending)} {
        return
    }
    set hs(align_pending) 1
    after idle hs:align_visible_line_heights
}

proc hs:align_visible_line_heights {} {
    global hs w
    set hs(align_pending) 0
    if {$hs(align_running)} {
        return
    }
    set hs(align_running) 1

    if {![winfo exists $w(rawText)] || ![winfo exists $w(renderedText)]} {
        set hs(align_running) 0
        return
    }

    set topL [expr {int([$w(rawText) index @0,0])}]
    set botL [expr {int([$w(rawText) index @0,[winfo height $w(rawText)]])}]
    set topR [expr {int([$w(renderedText) index @0,0])}]
    set botR [expr {int([$w(renderedText) index @0,[winfo height $w(renderedText)]])}]
    set from [expr {min($topL, $topR)}]
    set to [expr {max($botL, $botR)}]
    if {$to - $from > 400} {
        set to [expr {$from + 400}]
    }

    hs:clear_pad_range $w(rawText) $hs(last_align_from) $hs(last_align_to)
    hs:clear_pad_range $w(renderedText) $hs(last_align_from) $hs(last_align_to)
    hs:clear_pad_range $w(rawLn) $hs(last_align_from) $hs(last_align_to)
    hs:clear_pad_range $w(renderedLn) $hs(last_align_from) $hs(last_align_to)

    for {set line $from} {$line <= $to} {incr line} {
        set dL [$w(rawText) dlineinfo "$line.0"]
        set dR [$w(renderedText) dlineinfo "$line.0"]
        if {$dL eq "" || $dR eq ""} {
            continue
        }
        set hL [lindex $dL 3]
        set hR [lindex $dR 3]
        if {$hL > $hR} {
            set padR [expr {$hL - $hR}]
            hs:set_pad $w(rawText) $line 0
            hs:set_pad $w(rawLn) $line 0
            hs:set_pad $w(renderedText) $line $padR
            hs:set_pad $w(renderedLn) $line $padR
        } elseif {$hR > $hL} {
            set padL [expr {$hR - $hL}]
            hs:set_pad $w(renderedText) $line 0
            hs:set_pad $w(renderedLn) $line 0
            hs:set_pad $w(rawText) $line $padL
            hs:set_pad $w(rawLn) $line $padL
        } else {
            hs:set_pad $w(rawText) $line 0
            hs:set_pad $w(renderedText) $line 0
            hs:set_pad $w(rawLn) $line 0
            hs:set_pad $w(renderedLn) $line 0
        }
    }

    set hs(last_align_from) $from
    set hs(last_align_to) $to
    set hs(align_running) 0
}

proc hs:sync_from {which first last} {
    global hs w
    if {$hs(syncing)} {
        return
    }
    set hs(syncing) 1
    $w(vsb) set $first $last
    if {$which eq "raw"} {
        $w(renderedText) yview moveto $first
        $w(renderedLn) yview moveto $first
    } else {
        $w(rawText) yview moveto $first
        $w(rawLn) yview moveto $first
    }
    $w(rawLn) yview moveto $first
    $w(renderedLn) yview moveto $first
    set hs(syncing) 0
    hs:schedule_align
}

proc hs:raw_yscroll {first last} {
    hs:sync_from raw $first $last
}

proc hs:rendered_yscroll {first last} {
    hs:sync_from rendered $first $last
}

proc hs:vscroll {args} {
    global hs w
    if {$hs(syncing)} {
        return
    }
    set hs(syncing) 1
    eval [linsert $args 0 $w(rawText) yview]
    eval [linsert $args 0 $w(renderedText) yview]
    eval [linsert $args 0 $w(rawLn) yview]
    eval [linsert $args 0 $w(renderedLn) yview]
    set hs(syncing) 0
    set yv [$w(rawText) yview]
    $w(vsb) set [lindex $yv 0] [lindex $yv 1]
    hs:schedule_align
}

proc hs:load_file {path} {
    global w hs
    set hs(path) $path

    set raw [hs:read_utf8 $path]

    $w(rawText) configure -state normal
    $w(rawText) delete 1.0 end
    $w(rawText) insert 1.0 $raw
    $w(rawText) configure -state disabled

    $w(renderedText) configure -state normal
    $w(renderedText) delete 1.0 end

    set hs(hlt_ok) 0
    if {[hlt:is_file $path]} {
        if {![catch {
            set save [concat $raw]
            hlt:restore $w(renderedText) $save loadingFromFile $path
            set hs(hlt_ok) 1
        } emsg]} {
            # loaded as HLT
        } else {
            $w(renderedText) insert 1.0 "HLT parse failed for:\n$path\n\n$emsg\n\n--- raw content below ---\n\n$raw"
        }
    } else {
        $w(renderedText) insert 1.0 $raw
    }
    $w(renderedText) configure -state disabled

    hs:update_line_numbers $w(rawText) $w(rawLn)
    hs:update_line_numbers $w(renderedText) $w(renderedLn)
    wm title . "hltshow - [file nativename $path]"
    hs:schedule_align
}

proc hs:open_dialog {} {
    set p [tk_getOpenFile -title "Open HLT/Text File"]
    if {$p eq ""} {
        return
    }
    hs:load_file $p
}

proc hs:build_ui {} {
    global w

    wm title . "hltshow"
    catch {wm deiconify .}

    frame .top
    pack .top -side top -fill both -expand 1

    frame .toolbar
    pack .toolbar -side top -fill x

    button .toolbar.open -text "Open..." -command hs:open_dialog
    label .toolbar.hint -text "Left: raw HLT/text   Right: rendered HLT"
    pack .toolbar.open -side left -padx 6 -pady 4
    pack .toolbar.hint -side left -padx 12

    frame .top.left -bd 1 -relief sunken
    frame .top.right -bd 1 -relief sunken
    pack .top.left -side left -fill both -expand 1 -padx 6 -pady 6
    pack .top.right -side left -fill both -expand 1 -padx 6 -pady 6

    set w(rawLn) .top.left.ln
    set w(rawText) .top.left.txt
    set w(rawHsb) .top.left.hsb
    set w(renderedLn) .top.right.ln
    set w(renderedText) .top.right.txt
    set w(renderedHsb) .top.right.hsb
    set w(vsb) .top.vsb

    scrollbar $w(vsb) -orient vertical -command hs:vscroll
    pack $w(vsb) -side right -fill y -in .top

    text $w(rawLn) -width 7 -wrap none -state disabled -takefocus 0 \
      -font {Courier 10} -yscrollcommand hs:raw_yscroll -background #f1f1f1
    text $w(rawText) -wrap none -state disabled -font {Courier 10} \
      -yscrollcommand hs:raw_yscroll -xscrollcommand [list $w(rawHsb) set]
    scrollbar $w(rawHsb) -orient horizontal -command [list $w(rawText) xview]

    text $w(renderedLn) -width 7 -wrap none -state disabled -takefocus 0 \
      -font {Courier 10} -yscrollcommand hs:rendered_yscroll -background #f1f1f1
    text $w(renderedText) -wrap none -state disabled -font {Courier 10} \
      -yscrollcommand hs:rendered_yscroll -xscrollcommand [list $w(renderedHsb) set]
    scrollbar $w(renderedHsb) -orient horizontal -command [list $w(renderedText) xview]

    grid $w(rawLn) -row 0 -column 0 -sticky ns
    grid $w(rawText) -row 0 -column 1 -sticky nsew
    grid $w(rawHsb) -row 1 -column 1 -sticky ew
    grid rowconfigure .top.left 0 -weight 1
    grid columnconfigure .top.left 1 -weight 1

    grid $w(renderedLn) -row 0 -column 0 -sticky ns
    grid $w(renderedText) -row 0 -column 1 -sticky nsew
    grid $w(renderedHsb) -row 1 -column 1 -sticky ew
    grid rowconfigure .top.right 0 -weight 1
    grid columnconfigure .top.right 1 -weight 1

    bind $w(rawText) <Configure> {hs:schedule_align}
    bind $w(renderedText) <Configure> {hs:schedule_align}
    bind $w(rawText) <MouseWheel> {hs:schedule_align}
    bind $w(renderedText) <MouseWheel> {hs:schedule_align}
}

hs:build_ui

if {$argc >= 1} {
    set f [lindex $argv 0]
    if {![file exists $f]} {
        tk_messageBox -icon error -title "hltshow" -message "File not found:\n$f"
        hs:usage
        exit 2
    }
    hs:load_file $f
} else {
    set p [tk_getOpenFile -title "Open HLT/Text File"]
    if {$p eq ""} {
        exit 0
    }
    hs:load_file $p
}

after 50 hs:schedule_align
