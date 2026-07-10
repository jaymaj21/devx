#!/usr/bin/env tclsh
#
# Annotate Java sources from a sources JAR with branch-probe coverage hits.
#
# Inputs:
#   - a Java sources JAR
#   - one or more branch instrumenter CSV files, or folders containing them
#   - a code-analytics coverage report
#
# Output:
#   - an extracted source tree whose Java lines with reported probe hits have
#     trailing comments like:
#
#       /*COV T+ 42 57 10001*/
#
#     where T+ is the branch edge/sense marker, 42 is the number of distinct
#     matching contexts that hit the probe, 57 is the matching-context hit
#     count, and 10001 is the probe id. If no matching context hit the probe,
#     the context count is written as NOHIT.
#
# Usage:
#   tclsh annotate_source_coverage.tcl ?--context <label-regex>|<id>? <source-jar> <coverage-report> <output-dir> <csv-or-dir> ?<csv-or-dir> ...?
#
# Notes:
#   - Requires the external "unzip" command on PATH.
#   - Existing files in <output-dir> may be overwritten by unzip.
#   - By default, hits are aggregated across all contexts in the coverage report
#     by matching context labels with the regular expression ".*".

namespace eval ::sourcecov {
    proc usage {} {
        puts stderr "Usage:"
        puts stderr "  tclsh annotate_source_coverage.tcl ?--context <label-regex>|<id>? <source-jar> <coverage-report> <output-dir> <csv-or-dir> ?<csv-or-dir> ...?"
        puts stderr ""
        puts stderr "Examples:"
        puts stderr "  tclsh annotate_source_coverage.tcl dstr-0.1.0-sources.jar coverage.txt annotated-src dstr-instrumented-branch-probes.csv"
        puts stderr "  tclsh annotate_source_coverage.tcl --context {.*} app-sources.jar coverage.txt annotated-src probes-folder"
        puts stderr "  tclsh annotate_source_coverage.tcl --context {counter.*} app-sources.jar coverage.txt annotated-src probes-folder"
        exit 2
    }

    proc fail {message} {
        puts stderr $message
        exit 1
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

    proc write_lines {path lines} {
        set fh [open $path w]
        fconfigure $fh -encoding utf-8 -translation lf
        foreach line $lines {
            puts $fh $line
        }
        close $fh
    }

    proc parse_csv_line {line} {
        if {[string length $line] > 0 && [scan [string index $line 0] %c] == 0xFEFF} {
            set line [string range $line 1 end]
        }
        set fields {}
        set current ""
        set inQuotes 0
        set len [string length $line]
        for {set i 0} {$i < $len} {incr i} {
            set ch [string index $line $i]
            if {$inQuotes} {
                if {$ch eq "\""} {
                    if {$i + 1 < $len && [string index $line [expr {$i + 1}]] eq "\""} {
                        append current "\""
                        incr i
                    } else {
                        set inQuotes 0
                    }
                } else {
                    append current $ch
                }
            } else {
                if {$ch eq ","} {
                    lappend fields $current
                    set current ""
                } elseif {$ch eq "\""} {
                    set inQuotes 1
                } else {
                    append current $ch
                }
            }
        }
        lappend fields $current
        return $fields
    }

    proc find_files_by_extension {folder extension} {
        set results {}
        foreach entry [glob -nocomplain -directory $folder *] {
            if {[file isdirectory $entry]} {
                foreach child [find_files_by_extension $entry $extension] {
                    lappend results $child
                }
            } elseif {[string equal -nocase [file extension $entry] $extension]} {
                lappend results $entry
            }
        }
        return $results
    }

    proc gather_csv_files {paths} {
        set csvMap [dict create]
        foreach path $paths {
            if {![file exists $path]} {
                error "CSV path not found: $path"
            }
            if {[file isdirectory $path]} {
                foreach csv [find_files_by_extension $path ".csv"] {
                    dict set csvMap [file normalize $csv] 1
                }
            } else {
                if {![string equal -nocase [file extension $path] ".csv"]} {
                    error "Not a CSV file: $path"
                }
                dict set csvMap [file normalize $path] 1
            }
        }
        return [lsort [dict keys $csvMap]]
    }

    proc parse_coverage_report {path contextSpec} {
        if {![file exists $path]} {
            error "Coverage report not found: $path"
        }

        set lines [read_lines $path]
        set contexts [dict create]
        set contextLabels [dict create]
        set contextHitCounts [dict create]
        set selectedHitCounts [dict create]
        set totalHitCounts [dict create]
        set mode ""
        set expectedContexts -1
        set expectedHits -1
        set contextsSeen 0
        set hitsSeen 0

        foreach rawLine $lines {
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
                dict set contextLabels $label $ctxId
                incr contextsSeen
                continue
            }

            if {$mode eq "hits"} {
                if {![regexp {^([0-9]+)[ \t]+([0-9]+)[ \t]+(-?[0-9]+)$} $line -> ctxId locId count]} {
                    error "Invalid HITS row in $path: $line"
                }
                dict incr totalHitCounts $locId $count
                if {[context_matches $ctxId $contextSpec $contexts $contextLabels]} {
                    dict incr contextHitCounts $locId 1
                    dict incr selectedHitCounts $locId $count
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

        return [list $contexts $contextHitCounts $selectedHitCounts $totalHitCounts]
    }

    proc context_matches {ctxId contextSpec contexts contextLabels} {
        if {$contextSpec eq "all"} {
            return 1
        }
        if {$contextSpec eq $ctxId} {
            return 1
        }
        if {[dict exists $contexts $ctxId]} {
            set label [dict get $contexts $ctxId]
            if {[regexp -- $contextSpec $label]} {
                return 1
            }
        }
        return 0
    }

    proc class_source_relpath {className sourceName} {
        if {$sourceName eq ""} {
            return ""
        }
        if {[string first "/" $sourceName] >= 0} {
            return $sourceName
        }
        set parts [split $className "."]
        if {[llength $parts] <= 1} {
            return $sourceName
        }
        set packageParts [lrange $parts 0 end-1]
        return [join [concat $packageParts [list $sourceName]] "/"]
    }

    proc index_extracted_sources {outputDir} {
        set fileByRel [dict create]
        set filesByBase [dict create]
        set javaFiles [find_files_by_extension $outputDir ".java"]
        set root [file normalize $outputDir]
        foreach path $javaFiles {
            set norm [file normalize $path]
            set rel [string range $norm [string length $root] end]
            if {[string match {[\\/]*} $rel]} {
                set rel [string range $rel 1 end]
            }
            set rel [string map {\\ /} $rel]
            dict set fileByRel $rel $norm
            dict lappend filesByBase [file tail $rel] $rel
        }
        return [list $fileByRel $filesByBase]
    }

    proc resolve_source_relpath {className sourceName fileByRel filesByBase} {
        set rel [class_source_relpath $className $sourceName]
        if {$rel ne "" && [dict exists $fileByRel $rel]} {
            return $rel
        }

        set base [lindex [split $sourceName "/"] end]
        if {$base ne "" && [dict exists $filesByBase $base]} {
            set candidates [dict get $filesByBase $base]
            if {[llength $candidates] == 1} {
                return [lindex $candidates 0]
            }

            set classRel [string map {. /} $className]
            foreach candidate $candidates {
                set withoutExt [file rootname $candidate]
                if {[string match "${withoutExt}*" $classRel]} {
                    return $candidate
                }
            }
        }

        return $rel
    }

    proc branch_marker {edge sense} {
        if {$edge ne "" && $sense ne ""} {
            return "$edge$sense"
        }
        return ""
    }

    proc load_probe_annotations {csvFiles contextHitCounts selectedHitCounts totalHitCounts fileByRel filesByBase} {
        set annotations [dict create]
        set stats [dict create csv_files 0 csv_rows 0 probe_rows 0 matched_probes 0 skipped_no_line 0 zero_context_hits 0 zero_selected_hits 0 unresolved_sources 0]

        foreach csvFile $csvFiles {
            dict incr stats csv_files 1
            set lines [read_lines $csvFile]
            if {[llength $lines] == 0} {
                continue
            }

            set header [parse_csv_line [lindex $lines 0]]
            if {[llength $header] < 9 || [lrange $header 0 8] ne [list id class method where source line edge opcode sense]} {
                puts stderr "WARNING: skipping non branch-probe CSV: $csvFile"
                continue
            }

            foreach line [lrange $lines 1 end] {
                if {[string trim $line] eq ""} {
                    continue
                }
                dict incr stats csv_rows 1
                set fields [parse_csv_line $line]
                if {[llength $fields] < 9} {
                    puts stderr "WARNING: skipping malformed CSV row in $csvFile: $line"
                    continue
                }
                set id [string trim [lindex $fields 0]]
                set className [string trim [lindex $fields 1]]
                set methodName [string trim [lindex $fields 2]]
                set where [string trim [lindex $fields 3]]
                set sourceName [string trim [lindex $fields 4]]
                set lineNo [string trim [lindex $fields 5]]
                set edge [string trim [lindex $fields 6]]
                set sense [string trim [lindex $fields 8]]
                dict incr stats probe_rows 1

                if {$lineNo eq "" || ![string is integer -strict $lineNo] || $lineNo < 1} {
                    dict incr stats skipped_no_line 1
                    continue
                }

                set rel [resolve_source_relpath $className $sourceName $fileByRel $filesByBase]
                if {$rel eq "" || ![dict exists $fileByRel $rel]} {
                    dict incr stats unresolved_sources 1
                    puts stderr "WARNING: source file not found for probe $id ($className $sourceName:$lineNo)"
                    continue
                }

                set contextHits 0
                if {[dict exists $contextHitCounts $id]} {
                    set contextHits [dict get $contextHitCounts $id]
                } else {
                    dict incr stats zero_context_hits 1
                }
                set selectedHits 0
                if {[dict exists $selectedHitCounts $id]} {
                    set selectedHits [dict get $selectedHitCounts $id]
                } else {
                    dict incr stats zero_selected_hits 1
                }
                set key "$rel\t$lineNo"
                dict lappend annotations $key [list $id $contextHits $selectedHits [branch_marker $edge $sense] $where $methodName]
                dict incr stats matched_probes 1
            }
        }

        return [list $annotations $stats]
    }

    proc compare_annotation_entry {a b} {
        set aId [lindex $a 0]
        set bId [lindex $b 0]
        if {$aId < $bId} {
            return -1
        }
        if {$aId > $bId} {
            return 1
        }
        return 0
    }

    proc annotation_comment {entries} {
        set pieces {}
        foreach entry [lsort -command ::sourcecov::compare_annotation_entry $entries] {
            set id [lindex $entry 0]
            set contextHits [lindex $entry 1]
            set totalHits [lindex $entry 2]
            set marker [lindex $entry 3]
            if {$contextHits == 0} {
                set contextText "NOHIT"
            } else {
                set contextText $contextHits
            }
            if {$marker eq ""} {
                lappend pieces "/*COV $contextText $totalHits $id*/"
            } else {
                lappend pieces "/*COV $marker $contextText $totalHits $id*/"
            }
        }
        return [join $pieces " "]
    }

    proc apply_annotations {outputDir annotations fileByRel} {
        set byFile [dict create]
        dict for {key entries} $annotations {
            set parts [split $key "\t"]
            set rel [lindex $parts 0]
            set lineNo [lindex $parts 1]
            dict set byFile $rel $lineNo $entries
        }

        set filesAnnotated 0
        set linesAnnotated 0
        set commentsInserted 0

        dict for {rel lineMap} $byFile {
            if {![dict exists $fileByRel $rel]} {
                continue
            }
            set path [dict get $fileByRel $rel]
            set lines [read_lines $path]
            set changed 0
            dict for {lineNo entries} $lineMap {
                if {$lineNo < 1 || $lineNo > [llength $lines]} {
                    puts stderr "WARNING: line $lineNo is outside $rel ([llength $lines] lines)"
                    continue
                }
                set idx [expr {$lineNo - 1}]
                set line [lindex $lines $idx]
                set comment [annotation_comment $entries]
                lset lines $idx "$line $comment"
                set changed 1
                incr linesAnnotated
                incr commentsInserted [llength $entries]
            }
            if {$changed} {
                write_lines $path $lines
                incr filesAnnotated
            }
        }

        return [dict create files_annotated $filesAnnotated lines_annotated $linesAnnotated comments_inserted $commentsInserted]
    }

    proc unzip_sources {sourceJar outputDir} {
        file mkdir $outputDir
        set cmd [list unzip -q -o $sourceJar -d $outputDir]
        set rc [catch {exec {*}$cmd 2>@1} output]
        if {$rc != 0} {
            error "unzip failed for $sourceJar:\n$output"
        }
    }

    proc parse_args {argv} {
        set contextSpec ".*"
        set positional {}
        set i 0
        while {$i < [llength $argv]} {
            set arg [lindex $argv $i]
            if {$arg eq "--context"} {
                incr i
                if {$i >= [llength $argv]} {
                    usage
                }
                set contextSpec [lindex $argv $i]
            } elseif {[string match "--context=*" $arg]} {
                set contextSpec [string range $arg [string length "--context="] end]
            } elseif {$arg eq "--help" || $arg eq "-h"} {
                usage
            } elseif {[string match "--*" $arg]} {
                puts stderr "Unknown option: $arg"
                usage
            } else {
                lappend positional $arg
            }
            incr i
        }

        if {[llength $positional] < 4} {
            usage
        }
        return [list $contextSpec [lindex $positional 0] [lindex $positional 1] [lindex $positional 2] [lrange $positional 3 end]]
    }

    proc annotate {sourceJar coverageReport outputDir csvPaths contextSpec} {
        if {![file exists $sourceJar] || [file isdirectory $sourceJar]} {
            error "Source jar not found: $sourceJar"
        }
        if {![file exists $coverageReport] || [file isdirectory $coverageReport]} {
            error "Coverage report not found: $coverageReport"
        }

        set csvFiles [gather_csv_files $csvPaths]
        if {[llength $csvFiles] == 0} {
            error "No CSV files found"
        }

        unzip_sources $sourceJar $outputDir

        set sourceIndexes [index_extracted_sources $outputDir]
        set fileByRel [lindex $sourceIndexes 0]
        set filesByBase [lindex $sourceIndexes 1]

        set coverage [parse_coverage_report $coverageReport $contextSpec]
        set contexts [lindex $coverage 0]
        set contextHitCounts [lindex $coverage 1]
        set selectedHitCounts [lindex $coverage 2]
        set totalHitCounts [lindex $coverage 3]

        set loaded [load_probe_annotations $csvFiles $contextHitCounts $selectedHitCounts $totalHitCounts $fileByRel $filesByBase]
        set annotations [lindex $loaded 0]
        set loadStats [lindex $loaded 1]
        set applyStats [apply_annotations $outputDir $annotations $fileByRel]

        puts "SOURCE_JAR [file normalize $sourceJar]"
        puts "OUTPUT_DIR [file normalize $outputDir]"
        puts "CONTEXT $contextSpec"
        puts "CONTEXTS_IN_REPORT [dict size $contexts]"
        puts "HIT_PROBES_IN_SCOPE [dict size $selectedHitCounts]"
        puts "HIT_PROBES_TOTAL [dict size $totalHitCounts]"
        puts "CSV_FILES [dict get $loadStats csv_files]"
        puts "CSV_ROWS [dict get $loadStats csv_rows]"
        puts "MATCHED_PROBES [dict get $loadStats matched_probes]"
        puts "SKIPPED_NO_LINE [dict get $loadStats skipped_no_line]"
        puts "ZERO_CONTEXT_HITS [dict get $loadStats zero_context_hits]"
        puts "ZERO_SELECTED_HITS [dict get $loadStats zero_selected_hits]"
        puts "UNRESOLVED_SOURCES [dict get $loadStats unresolved_sources]"
        puts "FILES_ANNOTATED [dict get $applyStats files_annotated]"
        puts "LINES_ANNOTATED [dict get $applyStats lines_annotated]"
        puts "COMMENTS_INSERTED [dict get $applyStats comments_inserted]"
    }
}

if {[info exists argv0] && [file normalize [info script]] eq [file normalize $argv0]} {
    set parsed [::sourcecov::parse_args $argv]
    set contextSpec [lindex $parsed 0]
    set sourceJar [lindex $parsed 1]
    set coverageReport [lindex $parsed 2]
    set outputDir [lindex $parsed 3]
    set csvPaths [lindex $parsed 4]
    if {[catch {::sourcecov::annotate $sourceJar $coverageReport $outputDir $csvPaths $contextSpec} err]} {
        puts stderr $err
        exit 1
    }
}
