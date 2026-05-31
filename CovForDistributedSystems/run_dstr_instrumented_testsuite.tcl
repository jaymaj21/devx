#!/usr/bin/env tclsh
#
# Instrument the built dstr jar if needed, then run every JSON spec in
# dstr/test-suite/specs against an already running code-analytics server.
#
# Usage:
#   tclsh run_dstr_instrumented_testsuite.tcl ?startId? ?appId? ?instanceId? ?specGlob?
#
# Top-level proc for easy reuse:
#   run_dstr_specs_to_code_analytics ?startId? ?appId? ?instanceId? ?specGlob?

proc usage {} {
    puts stderr "Usage: tclsh run_dstr_instrumented_testsuite.tcl ?startId? ?appId? ?instanceId? ?specGlob?"
    exit 2
}

proc home_dir {} {
    if {[info exists ::env(HOME)] && $::env(HOME) ne ""} {
        return $::env(HOME)
    }
    if {[info exists ::env(USERPROFILE)] && $::env(USERPROFILE) ne ""} {
        return $::env(USERPROFILE)
    }
    if {[info exists ::env(HOMEDRIVE)] && [info exists ::env(HOMEPATH)]} {
        return "$::env(HOMEDRIVE)$::env(HOMEPATH)"
    }
    error "Unable to determine home directory"
}

proc resolve_required_file {path label} {
    if {![file exists $path] || ![file isfile $path]} {
        error "$label not found: $path"
    }
    return [file normalize $path]
}

proc select_artifact {pattern} {
    set matches [glob -nocomplain $pattern]
    if {[llength $matches] == 0} {
        error "No file matched pattern: $pattern"
    }

    set newest ""
    set newestTime -1
    foreach item $matches {
        set name [file tail $item]
        if {[string match "*-sources.jar" $name] || [string match "*-javadoc.jar" $name] || [string match "*-tests.jar" $name] || [string match "original-*.jar" $name]} {
            continue
        }
        set mtime [file mtime $item]
        if {$mtime > $newestTime} {
            set newest $item
            set newestTime $mtime
        }
    }

    if {$newest eq ""} {
        error "No usable artifact matched pattern: $pattern"
    }
    return [file normalize $newest]
}

proc spec_files {specDir {specGlob "*.json"}} {
    set specs [glob -nocomplain -directory $specDir $specGlob]
    return [lsort $specs]
}

proc join_classpath {parts} {
    return [join $parts ";"]
}

proc run_java {argsList workdir} {
    set oldDir [pwd]
    cd $workdir
    set rc [catch {eval exec [linsert $argsList 0 java]} output]
    cd $oldDir
    return [list $rc $output]
}

proc instrument_dstr_jar {instrumentScript startId jarPath repoRoot} {
    set oldDir [pwd]
    cd $repoRoot
    set rc [catch {exec [info nameofexecutable] $instrumentScript $startId $jarPath} output]
    cd $oldDir
    if {$rc != 0} {
        error "Instrumentation failed:\n$output"
    }
    return $output
}

proc run_dstr_specs_to_code_analytics {{startId 10001} {appId 410} {instanceId 1} {specGlob "*.json"}} {
    set repoRoot [file normalize [file dirname [info script]]]
    set dstrRoot [file normalize [file join $repoRoot .. .. dstr]]
    set specDir [file join $dstrRoot test-suite specs]
    set instrumentScript [resolve_required_file [file join $repoRoot instrument_jars.tcl] "instrument_jars.tcl"]
    set dstrJar [select_artifact [file join $dstrRoot target dstr-*.jar]]
    set runtimeJar [select_artifact [file join $repoRoot branch-probe-suite mprewriter-runtime target mprewriter-runtime-*.jar]]

    set home [home_dir]
    set jacksonDatabind [resolve_required_file [file join $home .m2 repository com fasterxml jackson core jackson-databind 2.21.0 jackson-databind-2.21.0.jar] "jackson-databind jar"]
    set jacksonCore [resolve_required_file [file join $home .m2 repository com fasterxml jackson core jackson-core 2.21.0 jackson-core-2.21.0.jar] "jackson-core jar"]
    set jacksonAnnotations [resolve_required_file [file join $home .m2 repository com fasterxml jackson core jackson-annotations 2.21 jackson-annotations-2.21.jar] "jackson-annotations jar"]

    set specs [spec_files $specDir $specGlob]
    if {[llength $specs] == 0} {
        error "No JSON specs matched $specGlob in $specDir"
    }

    puts "Instrumenting dstr jar if needed: $dstrJar"
    puts [instrument_dstr_jar $instrumentScript $startId $dstrJar $repoRoot]

    set classPath [join_classpath [list $runtimeJar $dstrJar $jacksonDatabind $jacksonCore $jacksonAnnotations]]

    puts "Running [llength $specs] specs against code-analytics on UDP 8083"
    foreach spec $specs {
        set specNorm [file normalize $spec]
        puts ""
        puts "=== [file tail $specNorm] ==="
        set javaArgs [list \
            -cp $classPath \
            -Dmprewriter.host=127.0.0.1 \
            -Dmprewriter.port=8083 \
            -Dmprewriter.appId=$appId \
            -Dmprewriter.instanceId=$instanceId \
            org.dstr.cli.DstrCli \
            $specNorm]

        set result [run_java $javaArgs $dstrRoot]
        set rc [lindex $result 0]
        set output [lindex $result 1]
        puts $output
        if {$rc != 0} {
            error "dstr run failed for $specNorm"
        }
        after 200
    }

    puts ""
    puts "Completed all dstr specs."
}

if {[info exists argv0] && [file normalize [info script]] eq [file normalize $argv0]} {
    if {[llength $argv] > 4} {
        usage
    }

    set startId 10001
    set appId 410
    set instanceId 1
    set specGlob "*.json"

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
        set specGlob [lindex $argv 3]
    }

    if {[catch {run_dstr_specs_to_code_analytics $startId $appId $instanceId $specGlob} err]} {
        puts stderr $err
        exit 1
    }
}
