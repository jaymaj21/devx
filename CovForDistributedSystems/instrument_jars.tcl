#!/usr/bin/env tclsh
#
# Instrument JARs in place while keeping probe ids globally unique.
#
# Usage:
#   tclsh instrument_jars.tcl <startId> <path> ?<path> ...?
#
# Each <path> may be either:
#   - a folder, which is searched recursively for .jar files
#   - a single .jar file
#
# If no arguments are given, a folder chooser is shown and the selected folder
# is processed with startId 1.
#
# Top-level proc for easy reuse:
#   instrument_jars startId path ?path ...?

set ::BRANCH_PROBE_INSTRUMENTER_JAR [file normalize [file join [file dirname [info script]] branch-probe-instrumenter target branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar]]

proc instrument_jars_usage {} {
    puts stderr "Usage: tclsh instrument_jars.tcl <startId> <path> ?<path> ...?"
    exit 2
}

proc find_jar_files {folder} {
    set results {}
    foreach entry [glob -nocomplain -directory $folder *] {
        if {[file isdirectory $entry]} {
            foreach child [find_jar_files $entry] {
                lappend results $child
            }
        } elseif {[string equal -nocase [file extension $entry] ".jar"]} {
            lappend results $entry
        }
    }
    return $results
}

proc should_process_jar {jarPath instrumenterJar} {
    set tail [file tail $jarPath]
    if {[string match *_uninstrumented.jar $tail]} {
        return 0
    }
    if {[file normalize $jarPath] eq [file normalize $instrumenterJar]} {
        return 0
    }
    return 1
}

proc make_temp_output_path {jarPath} {
    set dir [file dirname $jarPath]
    set root [file rootname [file tail $jarPath]]
    return [file join $dir "${root}.__branch_probe_tmp__[pid].jar"]
}

proc backup_jar_path {jarPath} {
    set dir [file dirname $jarPath]
    set root [file rootname [file tail $jarPath]]
    return [file join $dir "${root}_uninstrumented.jar"]
}

proc run_branch_probe_instrumenter {instrumenterJar inputJar outputJar startId} {
    set cmd [list java -jar $instrumenterJar "--startid=$startId" --sidecar $inputJar $outputJar]
    set rc [catch {exec {*}$cmd 2>@1} output]
    return [list $rc $output]
}

proc parse_last_id {toolOutput defaultLastId} {
    if {[regexp {LAST_ID=([0-9]+)} $toolOutput -> lastId]} {
        return $lastId
    }
    return $defaultLastId
}

proc gather_target_jars {paths instrumenterJar} {
    set jarMap [dict create]
    foreach path $paths {
        set normPath [file normalize $path]
        if {![file exists $normPath]} {
            error "Path not found: $path"
        }
        if {[file isdirectory $normPath]} {
            foreach jarPath [find_jar_files $normPath] {
                if {[should_process_jar $jarPath $instrumenterJar]} {
                    dict set jarMap [file normalize $jarPath] 1
                }
            }
        } else {
            if {![string equal -nocase [file extension $normPath] ".jar"]} {
                error "Not a jar file: $path"
            }
            if {[should_process_jar $normPath $instrumenterJar]} {
                dict set jarMap $normPath 1
            }
        }
    }
    return [lsort [dict keys $jarMap]]
}

proc choose_folder_interactively {} {
    if {[catch {package require Tk} tkErr]} {
        error "No arguments were provided and Tk is unavailable: $tkErr"
    }
    set folder [tk_chooseDirectory -title "Select folder containing jars to instrument"]
    if {$folder eq ""} {
        error "No folder selected"
    }
    return $folder
}

proc probe_archive_dir {} {
    return [file join [file normalize ~] tmp probes]
}

proc sidecar_csv_path {outputJar} {
    set dir [file dirname $outputJar]
    set root [file rootname [file tail $outputJar]]
    return [file join $dir "${root}-branch-probes.csv"]
}

proc sanitize_probe_filename {jarPath} {
    set normalized [string map {\\ /} [file normalize $jarPath]]
    set root [file rootname $normalized]
    set safe [string map {":" "_" "/" "_" " " "_" "(" "_" ")" "_" "[" "_" "]" "_" "{" "_" "}" "_" "&" "_" ";" "_" "," "_" "=" "_" "+" "_" "'" "_" "\"" "_" } $root]
    return "${safe}-branch-probes.csv"
}

proc archive_probe_csv {jarPath sidecarPath} {
    if {![file exists $sidecarPath]} {
        error "Expected sidecar CSV not found: $sidecarPath"
    }
    set archiveDir [probe_archive_dir]
    file mkdir $archiveDir
    set archivePath [file join $archiveDir [sanitize_probe_filename $jarPath]]
    file copy -force $sidecarPath $archivePath
    return $archivePath
}

proc instrument_jars {startId args} {
    set instrumenterJar $::BRANCH_PROBE_INSTRUMENTER_JAR

    if {![file exists $instrumenterJar]} {
        error "Instrumenter jar not found: $instrumenterJar"
    }
    if {[catch {set nextId [expr {int($startId)}]}]} {
        error "Invalid startId: $startId"
    }
    if {$nextId < 1} {
        error "startId must be >= 1"
    }
    if {[llength $args] == 0} {
        error "At least one folder or jar path is required"
    }

    set jarFiles [gather_target_jars $args $instrumenterJar]
    set processedCount 0
    set instrumentedCount 0
    set skippedCount 0
    set failedCount 0

    foreach jarPath $jarFiles {
        incr processedCount
        set tmpOut [make_temp_output_path $jarPath]
        set backupJar [backup_jar_path $jarPath]
        set tmpSidecar [sidecar_csv_path $tmpOut]
        catch {file delete -force $tmpOut}
        catch {file delete -force $tmpSidecar}

        set result [run_branch_probe_instrumenter $instrumenterJar $jarPath $tmpOut $nextId]
        set rc [lindex $result 0]
        set output [lindex $result 1]

        if {$rc != 0} {
            incr failedCount
            catch {file delete -force $tmpOut}
            catch {file delete -force $tmpSidecar}
            puts stderr "FAILED $jarPath"
            puts stderr $output
            continue
        }

        set lastId [parse_last_id $output [expr {$nextId - 1}]]
        if {[regexp {SKIPPED_ALREADY_INSTRUMENTED=} $output]} {
            incr skippedCount
            catch {file delete -force $tmpOut}
            catch {file delete -force $tmpSidecar}
            puts "SKIPPED $jarPath"
        } else {
            file copy -force $jarPath $backupJar
            file rename -force $tmpOut $jarPath
            set archivedCsv [archive_probe_csv $jarPath $tmpSidecar]
            catch {file delete -force $tmpSidecar}
            incr instrumentedCount
            puts "INSTRUMENTED $jarPath backup=$backupJar probes=$archivedCsv LAST_ID=$lastId"
        }

        set nextId [expr {$lastId + 1}]
    }

    set finalLastId [expr {$nextId - 1}]
    puts "SUMMARY processed=$processedCount instrumented=$instrumentedCount skipped=$skippedCount failed=$failedCount LAST_ID=$finalLastId"
    return $finalLastId
}

if {[info exists argv0] && [file normalize [info script]] eq [file normalize $argv0]} {
    if {[llength $argv] == 0} {
        if {[catch {
            set selectedFolder [choose_folder_interactively]
            instrument_jars 1 $selectedFolder
        } err]} {
            puts stderr $err
            exit 1
        }
    } else {
        if {[llength $argv] < 2} {
            instrument_jars_usage
        }
        set startId [lindex $argv 0]
        set paths [lrange $argv 1 end]
        if {[catch {instrument_jars $startId {*}$paths} err]} {
            puts stderr $err
            exit 1
        }
    }
}
