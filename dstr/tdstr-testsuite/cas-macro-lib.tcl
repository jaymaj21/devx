proc preserve {args} {
    return [unchanged {*}$args]
}

proc start_attempt {pc otherPc} {
    return [concat [list [list and [list = $pc a0] [list = "${pc}+" try]]] [preserve $otherPc mem]]
}
