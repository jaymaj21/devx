#!/usr/bin/env tclsh
#
# Show which code-analytics contexts hit a specific probe id.
#
# Usage:
#   tclsh probe_context_hits.tcl <probe-id> <coverage-report-or-glob> ?<coverage-report-or-glob> ...?
#
# Example:
#   tclsh probe_context_hits.tcl 10108 code-analytics/coverage-*.txt
#   tclsh probe_context_hits.tcl 10108 artifacts/source-coverage-annotation/*/coverage-report.txt

proc usage {} {
    puts stderr "Usage: tclsh probe_context_hits.tcl <probe-id> <coverage-report-or-glob> ?<coverage-report-or-glob> ...?"
    exit 2
}

proc has_glob_chars {path} {
    return [expr {[string first "*" $path] >= 0 || [string first "?" $path] >= 0 || [string first "\[" $path] >= 0}]
}

proc expand_report_paths {patterns} {
    set pathMap [dict create]

    foreach pattern $patterns {
        if {[has_glob_chars $pattern]} {
            set matches [glob -nocomplain $pattern]
            if {[llength $matches] == 0} {
                puts stderr "WARNING: no coverage reports matched: $pattern"
            }
            foreach match $matches {
                if {[file isfile $match]} {
                    dict set pathMap [file normalize $match] 1
                }
            }
        } else {
            if {![file exists $pattern]} {
                error "Coverage report not found: $pattern"
            }
            if {![file isfile $pattern]} {
                error "Not a file: $pattern"
            }
            dict set pathMap [file normalize $pattern] 1
        }
    }

    return [lsort [dict keys $pathMap]]
}

proc read_lines {path} {
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set data [read $fh]
    close $fh

    if {$data eq ""} {
        return {}
    }

    set lines [split $data "\n"]
    if {[lindex $lines end] eq ""} {
        set lines [lrange $lines 0 end-1]
    }
    return $lines
}

proc parse_coverage_report {path probeId} {
    set contexts [dict create]
    set hitsByContext [dict create]
    set mode ""
    set expectedContexts -1
    set expectedHits -1
    set contextsSeen 0
    set hitsSeen 0

    foreach rawLine [read_lines $path] {
        set line [string trim $rawLine]
        if {$line eq ""} {
            continue
        }

        if {[regexp {^CONTEXTS[ \t]+([0-9]+)$} $line -> n]} {
            set mode "contexts"
            set expectedContexts $n
            continue
        }

        if {[regexp {^HITS[ \t]+([0-9]+)$} $line -> n]} {
            set mode "hits"
            set expectedHits $n
            continue
        }

        if {$mode eq "contexts"} {
            if {![regexp {^([0-9]+)[ \t]+(.+)$} $line -> ctxId label]} {
                error "Invalid CONTEXTS row in $path: $line"
            }
            dict set contexts $ctxId $label
            incr contextsSeen
            continue
        }

        if {$mode eq "hits"} {
            if {![regexp {^([0-9]+)[ \t]+([0-9]+)[ \t]+(-?[0-9]+)$} $line -> ctxId locId count]} {
                error "Invalid HITS row in $path: $line"
            }
            if {$locId eq $probeId && $count != 0} {
                dict incr hitsByContext $ctxId $count
            }
            incr hitsSeen
            continue
        }

        error "Coverage report row appeared before a section header in $path: $line"
    }

    if {$expectedContexts >= 0 && $contextsSeen != $expectedContexts} {
        puts stderr "WARNING: $path declared $expectedContexts contexts but contained $contextsSeen"
    }
    if {$expectedHits >= 0 && $hitsSeen != $expectedHits} {
        puts stderr "WARNING: $path declared $expectedHits hits but contained $hitsSeen"
    }

    return [list $contexts $hitsByContext]
}

proc compare_context_rows {a b} {
    set aName [lindex $a 0]
    set bName [lindex $b 0]
    set cmp [string compare $aName $bName]
    if {$cmp != 0} {
        return $cmp
    }
    return [expr {[lindex $a 1] - [lindex $b 1]}]
}

proc context_label {contexts ctxId} {
    if {[dict exists $contexts $ctxId]} {
        return [dict get $contexts $ctxId]
    }
    return "<missing-context-$ctxId>"
}

proc print_report_hits {path probeId contexts hitsByContext totalsVar} {
    upvar 1 $totalsVar totals

    puts ""
    puts "REPORT $path"

    if {[dict size $hitsByContext] == 0} {
        puts "  no hits for probe $probeId"
        return
    }

    set rows {}
    dict for {ctxId count} $hitsByContext {
        set label [context_label $contexts $ctxId]
        lappend rows [list $label $ctxId $count]
        dict incr totals $label $count
    }

    foreach row [lsort -command compare_context_rows $rows] {
        set label [lindex $row 0]
        set ctxId [lindex $row 1]
        set count [lindex $row 2]
        puts [format "  %-40s %12d  (ctx %s)" $label $count $ctxId]
    }
}

proc print_totals {probeId totals reportCount} {
    if {$reportCount <= 1} {
        return
    }

    puts ""
    puts "TOTALS probe $probeId"

    if {[dict size $totals] == 0} {
        puts "  no hits"
        return
    }

    set rows {}
    dict for {label count} $totals {
        lappend rows [list $label $count]
    }

    foreach row [lsort -command compare_context_rows $rows] {
        puts [format "  %-40s %12d" [lindex $row 0] [lindex $row 1]]
    }
}

proc main {argv} {
    if {[llength $argv] < 2} {
        usage
    }

    set probeId [lindex $argv 0]
    if {![string is integer -strict $probeId] || $probeId < 0} {
        puts stderr "Invalid probe id: $probeId"
        usage
    }

    set reports [expand_report_paths [lrange $argv 1 end]]
    if {[llength $reports] == 0} {
        error "No coverage reports found"
    }

    set totals [dict create]
    puts "PROBE $probeId"

    foreach report $reports {
        set parsed [parse_coverage_report $report $probeId]
        print_report_hits $report $probeId [lindex $parsed 0] [lindex $parsed 1] totals
    }

    print_totals $probeId $totals [llength $reports]
}

if {[info exists argv0] && [file normalize [info script]] eq [file normalize $argv0]} {
    if {[catch {main $argv} err]} {
        puts stderr $err
        exit 1
    }
}
