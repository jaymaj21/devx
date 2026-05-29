#!/usr/bin/env tclsh

if {$argc != 2} {
    puts "Usage: test_runner.tcl <file_list.txt> <generaltest|curltest|rebaseline>"
    exit 1
}

set filelist [lindex $argv 0]
set mode [lindex $argv 1]
set curltest_runCount 0
set curltest_failCount 0

proc read_file_contents {fname} {
    set f [open $fname r]
    set data [read $f]
    close $f
    return $data
}

proc find_in_folder_or_parents {folder filename} {
    set tryfolder $folder
    while {$tryfolder != ""} {
        set fullpath "$tryfolder/$filename"
        if {[file exists $fullpath]} {
            return $fullpath
        }
        set parent [file dirname $tryfolder]
        if {$parent == $tryfolder} { break }
        set tryfolder $parent
    }
    return ""
}

proc reindent_json_file {fname} {
    if {[catch {exec python -m json.tool $fname > $fname.tmp} msg]} {
        puts stderr $msg
    } else {
        file copy -force ${fname}.tmp $fname
        file delete -force ${fname}.tmp
    }
}

proc curltest {filename {lnum ""}} {
    set default_url "http://localhost:9990"
    set default_endpoint "/api/servicestatus"
    resttest_helper $filename $default_url $default_endpoint 0 0 $lnum
}

proc make_tempfile {} {
    set tmpdir "c:/tmp"
    set prefix "tcltmp_"
    set maxtries 1000

    for {set i 0} {$i < $maxtries} {incr i} {
        # Generate a random string
        set rand [format %08x [expr {int(rand()*0x7fffffff)}]]
        set tmpfile [file join $tmpdir "${prefix}${rand}.tmp"]

        # Check if file exists
        if {![file exists $tmpfile]} {
            # Create the file to reserve it
            set fh [open $tmpfile "w"]
            close $fh
            return $tmpfile
        }
    }

    error "Unable to create temporary file after $maxtries attempts"
}


proc generaltest {filename {lnum ""}} {
    global curltest_runCount curltest_failCount
    set folder [file dirname $filename]
    set filebase [regsub -all {\.[^.]*$} $filename ""]
    set executable "bash"
    set execfile [find_in_folder_or_parents $folder "executable.txt"]
    if {$execfile ne ""} {
        set executable [string trim [read_file_contents $execfile]]
    }
    set args {}
    set argsfile [find_in_folder_or_parents $folder "args.txt"]
    if {$argsfile ne ""} {
        set args [string trim [read_file_contents $argsfile]]
    }
    set difftool "diff"
    set difftool_file [find_in_folder_or_parents $folder "difftool.txt"]
    if {$difftool_file ne ""} {
        set difftool [string trim [read_file_contents $difftool_file]]
    }
    set filtertool "";
    set filtertool_file [find_in_folder_or_parents $folder "filtertool.txt"]
    if {$filtertool_file ne ""} {
        set filtertool [string trim [read_file_contents $filtertool_file]]
    }
    set filterpipe {}
    if {$filtertool != "" } {
        set filterpipe [list "|" {*}$filtertool];
    }
    
    set difftool_args {}
    set difftool_args_file [find_in_folder_or_parents $folder "difftool_args.txt"]
    if {$difftool_args_file ne ""} {
        set difftool_args [string trim [read_file_contents $difftool_args_file]]
    }
    set preamblefile [find_in_folder_or_parents $folder "preamble.txt"]
    set preamble ""
    if {$preamblefile ne ""} {
        set preamble [read_file_contents $preamblefile]
    }
    set tmpfile [make_tempfile]
    set out [open $tmpfile w]
    puts $out $preamble
    puts $out [read_file_contents $filename]
    close $out
    set rundir [pwd];
    
    cd $folder;
    #puts "running from [pwd]";
    if {[catch {exec $executable {*}$args $tmpfile {*}$filterpipe > ${tmpfile}.out} msg]} {
        puts stderr $msg
    }
    cd $rundir;
    file copy -force ${tmpfile}.out ${filebase}.out;
    #puts "right after running [pwd]";
    file delete -force $tmpfile
    file delete -force ${tmpfile}.out
    if {![file exists "${filebase}.golden"]} {
        file copy -force "${filebase}.out" "${filebase}.golden"
        puts "$filename: GOLDEN OUTPUT CREATED"
    } else {
        catch {exec $difftool {*}$difftool_args "${filebase}.golden" "${filebase}.out" > "${filebase}.diff"} msg
        set diffcont [string trim [read_file_contents "${filebase}.diff"]]
        
        #######
        set fpout [open "${filebase}.out" r];
        set outcont [read $fpout]
        close $fpout;
       
        set fail 0;
        
        set dont_fail_on_diff [string match *DONT_FAIL_ON_DIFF* $outcont]
        set dont_fail_on_error [string match *DONT_FAIL_ON_ERROR* $outcont]
        set has_error [string match *ERROR* $outcont]
        set has_test_failed [string match *TEST_FAILED* $outcont]
        set failby "";
        if { $dont_fail_on_diff } {
            if {$dont_fail_on_error} {
                set fail $has_test_failed;
                set failby " : has TEST_FAILED in output"
            } else {
                set fail $has_error;
                set failby " : has ERROR in output"
            }
        } else {
            set failby " : output has non-empty diff with golden" 
            set fail [expr [string length $diffcont] != 0]
        }
        ######
        
        if {$fail} {
            incr curltest_failCount
            puts "$filename: FAILED$failby"
        } else {
            puts "$filename: PASS"
        }
    }
    incr curltest_runCount
}

proc resttest_helper {filename url endpoint _ _ {lnum ""}} {
    global curltest_runCount curltest_failCount
    set folder [file dirname $filename]
    set filebase [regsub -all {\.[^.]*$} $filename ""]
    set tokenfile [find_in_folder_or_parents $folder "localhost.token"]
    set xtokenfile [find_in_folder_or_parents $folder "localhost.xtoken"]
    set access_token ""
    if {$tokenfile ne ""} {
        set access_token [string trim [read_file_contents $tokenfile]]
    }
    set xtoken_header ""
    if {$xtokenfile ne ""} {
        set xtoken_header "-H X-SECURITY-TOKEN:[string trim [read_file_contents $xtokenfile]]"
    }
    if {[catch {
        exec curl -s -d "@$filename" -H "Content-Type: application/json" $xtoken_header $url$endpoint > "${filebase}.out"
    } msg]} {
        puts stderr $msg
    }
    if {![file exists "${filebase}.golden"]} {
        file copy -force "${filebase}.out" "${filebase}.golden"
        puts "$filename: GOLDEN OUTPUT CREATED"
    } else {
        catch {exec diff "${filebase}.golden" "${filebase}.out" > "${filebase}.diff"} msg
        set diffcont [string trim [read_file_contents "${filebase}.diff"]]
        
        #######
        #######
        set fpout [open "${filebase}.out" r];
        set outcont [read $fpout]
        close $fpout;
       
        set fail 0;
        
        set dont_fail_on_diff [string match *DONT_FAIL_ON_DIFF* $outcont]
        set dont_fail_on_error [string match *DONT_FAIL_ON_ERROR* $outcont]
        set has_error [string match *ERROR* $outcont]
        set has_test_failed [string match *TEST_FAILED* $outcont]
        set failby "";
        if { $dont_fail_on_diff } {
            if {$dont_fail_on_error} {
                set fail $has_test_failed;
                set failby " : has TEST_FAILED in output"
            } else {
                set fail $has_error;
                set failby " : has ERROR in output"
            }
        } else {
            set failby " : output has non-empty diff with golden" 
            set fail [expr [string length $diffcont] != 0]
        }
        ######
        ######
        if {$fail} {
            incr curltest_failCount
            puts "$filename: FAILED"
        } else {
            puts "$filename: PASS"
        }
    }
    incr curltest_runCount
}

# Start test run
set f [open $filelist r]
set content [read $f]
close $f
set lines [split $content "\n"]
set n 0

if {$mode == "rebaseline"} {
    set f [open $filelist r]
    set lines [split [read $f] "\n"]
    close $f
    foreach line $lines {
        set line [string trim $line]
        if {$line == "" || [string index $line 0] == "#"} continue
        set filebase [regsub -all {\.[^.]*$} $line ""]
        if {[file exists "${filebase}.out"]} {
            file copy -force "${filebase}.out" "${filebase}.golden"
            puts "Rebaselined $line"
        } else {
            puts "Output file not found for $line"
        }
    }
    exit 0
}


foreach line $lines {
    set line [string trim $line]
    if {$line == "" || [string index $line 0] == "#"} continue
    incr n
    if {[catch {
        if {$mode == "curltest"} {
            curltest $line $n
        } else {
            generaltest $line $n
        }
    } msg]} { 
        puts stderr $msg 
    }
}
puts "FINISHED: Ran $curltest_runCount tests, $curltest_failCount failed"

