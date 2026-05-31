#!/usr/bin/env tclsh
# Write a two-column table of fully qualified Java class names and relative paths.
#
# Usage:
#   tclsh list_java_classes.tcl append|overwrite <output-file> <folder>

proc usage {} {
    puts stderr "Usage: tclsh list_java_classes.tcl append|overwrite <output-file> <folder>"
    exit 2
}

proc normalize_relpath {base path} {
    set baseNorm [file normalize $base]
    set pathNorm [file normalize $path]

    if {[string first $baseNorm $pathNorm] != 0} {
        error "File '$pathNorm' is not under base folder '$baseNorm'"
    }

    set rel [string range $pathNorm [string length $baseNorm] end]
    if {[string match {[\\/]*} $rel]} {
        set rel [string range $rel 1 end]
    }
    return [string map {\\ /} $rel]
}

proc find_java_files {folder} {
    set results {}
    foreach entry [glob -nocomplain -directory $folder *] {
        if {[file isdirectory $entry]} {
            foreach child [find_java_files $entry] {
                lappend results $child
            }
        } elseif {[string equal -nocase [file extension $entry] ".java"]} {
            lappend results $entry
        }
    }
    return $results
}

proc extract_package {javaFile} {
    set fh [open $javaFile r]
    set packageName ""
    while {[gets $fh line] >= 0} {
        set trimmed [string trim $line]
        if {[regexp {^package[ \t]+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)[ \t]*;} $trimmed -> packageName]} {
            break
        }
    }
    close $fh
    return $packageName
}

if {[llength $argv] != 3} {
    usage
}

set mode [string tolower [lindex $argv 0]]
set outputFile [lindex $argv 1]
set folder [lindex $argv 2]

if {$mode ne "append" && $mode ne "overwrite"} {
    usage
}

if {![file exists $folder] || ![file isdirectory $folder]} {
    puts stderr "Folder not found: $folder"
    exit 1
}

set accessMode [expr {$mode eq "append" ? "a" : "w"}]
set baseFolder [file normalize $folder]
set javaFiles [lsort [find_java_files $baseFolder]]

set out [open $outputFile $accessMode]
set err [catch {
    foreach javaFile $javaFiles {
        set packageName [extract_package $javaFile]
        set className [file rootname [file tail $javaFile]]
        if {$packageName eq ""} {
            set fullyQualifiedName $className
        } else {
            set fullyQualifiedName "${packageName}.${className}"
        }
        set relativePath [normalize_relpath $baseFolder $javaFile]
        puts $out "$fullyQualifiedName\t$relativePath"
    }
} errMsg]
close $out
if {$err} {
    puts stderr $errMsg
    exit 1
}
