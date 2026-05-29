#!/usr/bin/env tclsh
#
# End-to-end demo for annotate_source_coverage.tcl using the external dstr
# Maven project, run_dstr_instrumented_testsuite.tcl, and code-analytics.
#
# Usage:
#   tclsh demo_source_coverage_annotation.tcl ?startId? ?appId? ?instanceId? ?contextRegex? ?specGlob?
#
# Defaults:
#   startId      = 10001
#   appId        = 410
#   instanceId   = 1
#   contextRegex = .*
#   specGlob     = counter.json
#
# Output:
#   artifacts/source-coverage-annotation/<timestamp>/annotated-sources

proc usage {} {
    puts stderr "Usage: tclsh demo_source_coverage_annotation.tcl ?startId? ?appId? ?instanceId? ?contextRegex? ?specGlob?"
    exit 2
}

proc run_checked {workdir argsList} {
    set oldDir [pwd]
    cd $workdir
    puts ""
    puts "RUN $workdir> [join $argsList { }]"
    set rc [catch {exec {*}$argsList 2>@1} output]
    cd $oldDir
    puts $output
    if {$rc != 0} {
        error "Command failed: [join $argsList { }]\n$output"
    }
    return $output
}

proc select_newest_file {pattern label} {
    set matches [glob -nocomplain $pattern]
    set newest ""
    set newestTime -1
    foreach path $matches {
        if {![file isfile $path]} {
            continue
        }
        set mtime [file mtime $path]
        if {$mtime > $newestTime} {
            set newest $path
            set newestTime $mtime
        }
    }
    if {$newest eq ""} {
        error "$label not found: $pattern"
    }
    return [file normalize $newest]
}

proc home_dir {} {
    if {[info exists ::env(USERPROFILE)] && $::env(USERPROFILE) ne ""} {
        return $::env(USERPROFILE)
    }
    if {[info exists ::env(HOME)] && $::env(HOME) ne ""} {
        return $::env(HOME)
    }
    if {[info exists ::env(HOMEDRIVE)] && [info exists ::env(HOMEPATH)]} {
        return "$::env(HOMEDRIVE)$::env(HOMEPATH)"
    }
    error "Unable to determine home directory"
}

proc wait_for_tcp_port {host port timeoutSeconds} {
    set deadline [expr {[clock seconds] + $timeoutSeconds}]
    while {[clock seconds] <= $deadline} {
        set rc [catch {
            set s [socket $host $port]
            close $s
        }]
        if {$rc == 0} {
            return
        }
        after 250
    }
    error "Timed out waiting for $host:$port"
}

proc start_code_analytics {serverJar codeAnalyticsDir serverLog} {
    set oldDir [pwd]
    cd $codeAnalyticsDir
    set cmd [list | java -cp $serverJar com.codeanalytics.ClojureShell > $serverLog 2>@1]
    set chan [open $cmd w]
    fconfigure $chan -buffering line -blocking 0
    cd $oldDir
    return $chan
}

proc stop_code_analytics {chan coverageReport appId instanceId} {
    puts $chan ":coverage-report $appId $instanceId $coverageReport"
    puts $chan ":flush-trace"
    puts $chan ":trace-persist"
    puts $chan ":exit"
    flush $chan
    fconfigure $chan -blocking 1
    if {[catch {close $chan} closeErr]} {
        error "code-analytics did not exit cleanly: $closeErr"
    }
}

proc write_text_file {path text} {
    set fh [open $path w]
    puts $fh $text
    close $fh
}

proc main {argv} {
    if {[llength $argv] > 5} {
        usage
    }

    set startId 10001
    set appId 410
    set instanceId 1
    set contextRegex ".*"
    set specGlob "counter.json"

    if {[llength $argv] >= 1} {
        set startId [lindex $argv 0]
    }
    if {[llength $argv] >= 2} {
        set appId [lindex $argv 1]
    }
    if {[llength $argv] >= 3} {
        set instanceId [lindex $argv 2]
    }
    if {[llength $argv] >= 4} {
        set contextRegex [lindex $argv 3]
    }
    if {[llength $argv] >= 5} {
        set specGlob [lindex $argv 4]
    }

    set repoRoot [file normalize [file dirname [info script]]]
    set dstrRoot [file normalize [file join $repoRoot .. .. dstr]]
    set codeAnalyticsDir [file join $repoRoot code-analytics]
    set runtimeDir [file join $repoRoot branch-probe-suite mprewriter-runtime]
    set instrumenterDir [file join $repoRoot branch-probe-instrumenter]

    set stamp [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
    set runDir [file join $repoRoot artifacts source-coverage-annotation $stamp]
    set annotatedDir [file join $runDir annotated-sources]
    set coverageReport [file join $runDir coverage-report.txt]
    set serverLog [file join $runDir code-analytics-output.txt]
    set manifestPath [file join $runDir manifest.txt]
    file mkdir $runDir

    puts "Building code-analytics, branch instrumenter, runtime, and dstr source jar..."
    run_checked $codeAnalyticsDir [list mvn -DskipTests package]
    run_checked $instrumenterDir [list mvn -DskipTests package]
    run_checked $runtimeDir [list mvn -DskipTests package]
    run_checked $dstrRoot [list mvn -DskipTests verify dependency:copy-dependencies -DincludeScope=runtime]

    set serverJar [select_newest_file [file join $codeAnalyticsDir target "clojure-shell-*-jar-with-dependencies.jar"] "code-analytics runnable jar"]
    set sourceJar [select_newest_file [file join $dstrRoot target "dstr-*-sources.jar"] "dstr sources jar"]

    puts ""
    puts "Starting code-analytics..."
    set serverChan [start_code_analytics $serverJar $codeAnalyticsDir $serverLog]

    if {[catch {
        wait_for_tcp_port 127.0.0.1 8084 30

        puts "Running dstr instrumented test suite through run_dstr_instrumented_testsuite.tcl..."
        run_checked $repoRoot [list [info nameofexecutable] [file join $repoRoot run_dstr_instrumented_testsuite.tcl] $startId $appId $instanceId $specGlob]

        after 1000
        stop_code_analytics $serverChan $coverageReport $appId $instanceId
    } err]} {
        catch {
            puts $serverChan ":exit"
            flush $serverChan
            close $serverChan
        }
        error $err
    }

    if {![file exists $coverageReport]} {
        error "Coverage report was not written: $coverageReport"
    }

    set probeDir [file join [home_dir] tmp probes]
    set probeCsv [select_newest_file [file join $probeDir "*dstr*branch-probes.csv"] "dstr branch-probes CSV"]

    puts ""
    puts "Annotating source jar..."
    run_checked $repoRoot [list [info nameofexecutable] [file join $repoRoot annotate_source_coverage.tcl] --context $contextRegex $sourceJar $coverageReport $annotatedDir $probeCsv]

    set manifest [join [list \
        "Annotated sources: $annotatedDir" \
        "Coverage report: $coverageReport" \
        "Probe CSV: $probeCsv" \
        "Source jar: $sourceJar" \
        "Code Analytics output: $serverLog" \
        "Context regex: $contextRegex" \
        "Spec glob: $specGlob" \
    ] "\n"]
    write_text_file $manifestPath $manifest

    puts ""
    puts "Annotated source files are available at:"
    puts [file normalize $annotatedDir]
    puts ""
    puts "Open Java files under that directory and search for /*COV hit-count probe-id*/ comments."
}

if {[info exists argv0] && [file normalize [info script]] eq [file normalize $argv0]} {
    if {[catch {main $argv} err]} {
        puts stderr $err
        exit 1
    }
}
