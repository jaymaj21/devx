userproc enlargeFonts {w {inc 2}} {
    proc _inc_font {w inc} {
        if {[catch {$w cget -font} curFont]} {
            return
        }
        set fontSpec [font actual $curFont]
        set curSize [dict get $fontSpec -size]
        set newSize [expr {$curSize + $inc}]
        if {$newSize < 6} {set newSize 6}   ;# Prevent tiny/invisible fonts
        set newFont [font create -family [dict get $fontSpec -family] \
            -size $newSize -weight [dict get $fontSpec -weight] \
            -slant [dict get $fontSpec -slant] -underline [dict get $fontSpec -underline] \
            -overstrike [dict get $fontSpec -overstrike]]
        $w configure -font $newFont
    }

    _inc_font $w $inc
    foreach child [winfo children $w] {
        enlargeFonts $child $inc
    }
}
