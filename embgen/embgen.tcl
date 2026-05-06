#!/usr/bin/env tclsh
# embgen.tcl
# Command-line embedded generator processor for embedded generator blocks.
#
# Scans files for blocks of the form:
#   //embgen_embedded_generator <type> <uuid>
#   // note text...
#   //embgen_generated_start <uuid>
#   ... old generated code ...
#   //embgen_generated_end <uuid>
#
# For each block, it:
#   - collects the note text (comment prefixes stripped)
#   - calls the registered generator for <type>
#   - replaces the region between embgen_generated_start / embgen_generated_end
#     with the generator output (respecting indentation).

# ------------------------------------------------------------
# Utility procs
# ------------------------------------------------------------
set installdir [file normalize [info script]];
regsub -all {\\} $installdir {/} installdir;
regsub -all {/[^/]*$} $installdir {} installdir;

proc permutations {list {prefix ""}} {
    if {![llength $list]} then {return [list $prefix]}
    set res [list]
    set n 0
    foreach e $list {
        eval [list lappend res] \
          [permutations [lreplace $list $n $n] [linsert $prefix end $e]]
        incr n
    }
    return $res
}

proc comb {m n} {
    set set [list]
    for {set i 0} {$i < $n} {incr i} {lappend set $i}
    return [combinations $set $m]
}

proc combinations {list size} {
    if {$size == 0} {
        return [list [list]]
    }
    set retval {}
    for {set i 0} {($i + $size) <= [llength $list]} {incr i} {
        set firstElement [lindex $list $i]
        set remainingElements [lrange $list [expr {$i + 1}] end]
        foreach subset [combinations $remainingElements [expr {$size - 1}]] {
            lappend retval [linsert $subset 0 $firstElement]
        }
    }
    return $retval
}

proc comma_separate {lst {lparen ""} {rparen ""}} {
   set res ""
   foreach item $lst {
      if {$res != ""} {
          append res ","
      }
      append res "${lparen}${item}${rparen}"
   }
   return $res
}

proc suffixes {lst {result {}}} {
   set len [llength $lst]
   for {set i 0} {$i < $len} {incr i}  {
       lappend result [lrange $lst $i end]
   }
   return $result
}

proc prefixes {lst {result {}}} {
    set len [llength $lst]
    for {set i 0} {$i < $len} {incr i} {
        lappend result [lrange $lst 0 $i]
    }
    return $result
}

proc defmacro {name arglist body} {
    puts "defined macro $name"
    set cmd "proc macroexpand_**_$name { "
    append cmd $arglist
    append cmd " } { subst -nobackslashes -nocommands {"
    append cmd $body
    append cmd "}}"
    uplevel #0 $cmd
}

proc def_p_macro {name arglist body} {
    puts "defined procedural macro $name"
    set cmd "proc macroexpand_**_$name {"
    append cmd $arglist
    append cmd " } { set code {};\n"
    append cmd $body
    append cmd "; return \$code;}"
    uplevel #0 $cmd
}

proc remove-newline {lst} {
  return [regsub -all {[\r\n]} $lst { }]
}

proc expand_macro {name args}  {
    puts "expanding macro $name with arguments $args"
    set cmd "macroexpand_**_$name "
    append cmd $args
    set result [uplevel #0 $cmd]
    # By default, expand_macro appends into the emit buffer
    emit $result
}

proc seq {from to} {
    if {$from <= $to} {
        for {set i $from} {$i <= $to} {incr i}    {lappend out $i}
    } else {
        for {set i $from} {$i >= $to} {incr i -1} {lappend out $i}
    }
    return $out
}

# Simple file reader (ASCII/UTF-8)
proc read_ascii_file_contents {fname} {
    set fh [open $fname r]
    fconfigure $fh -encoding utf-8 -translation lf
    set data [read $fh]
    close $fh
    return $data
}

# Status logging: CLI version just prints to stderr
proc addToStatus {msg} {
    if {$msg ne ""} {
        puts stderr "embgen: $msg"
    }
}

# Shared buffer for emit/emitted + JSON/XML generators
set ::macro_buffer ""

proc emit {str} {
   global macro_buffer
   append macro_buffer $str
}

proc emitted {} {
   global macro_buffer
   return $macro_buffer
}

# ------------------------------------------------------------
# Multi-file emission helpers
# ------------------------------------------------------------
namespace eval ::embgen {
    variable pending_file_outputs
    array set pending_file_outputs {}
}

# Normalize an output path relative to the file being processed.
proc ::embgen::normalize_output_path {path} {
    if {[file pathtype $path] eq "absolute"} {
        return [file normalize $path]
    }
    if {[info exists ::embgen::current_file]} {
        set baseDir [file dirname $::embgen::current_file]
    } else {
        set baseDir [pwd]
    }
    return [file normalize [file join $baseDir $path]]
}

# Queue content for a to-be-written file (overwrites on flush).
proc ::embgen::queue_file_output {path content} {
    variable pending_file_outputs
    set outPath [normalize_output_path $path]
    append pending_file_outputs($outPath) $content
}

# Evaluate a body that uses emit to build content, then queue it.
proc ::embgen::with_file_buffer {path body} {
    global macro_buffer
    set old_buffer $macro_buffer
    set macro_buffer ""
    # Evaluate body in the caller's scope (two frames up from here).
    set status [catch {uplevel 2 $body} msg]
    set file_content $macro_buffer
    set macro_buffer $old_buffer
    if {$status} {
        addToStatus "emit_file error for $path: $msg"
        return
    }
    queue_file_output $path $file_content
}

# Flush pending file outputs to disk.
proc ::embgen::flush_pending_files {} {
    variable pending_file_outputs
    foreach outPath [array names pending_file_outputs] {
        set dir [file dirname $outPath]
        if {![file exists $dir]} {
            if {[catch {file mkdir $dir} msg]} {
                addToStatus "could not create directory $dir: $msg"
                continue
            }
        }
        if {[catch {set fh [open $outPath w]} msg]} {
            addToStatus "could not open $outPath for writing: $msg"
            continue
        }
        fconfigure $fh -encoding utf-8 -translation lf
        puts -nonewline $fh $pending_file_outputs($outPath)
        close $fh
        addToStatus "wrote generated file: $outPath"
    }
    catch {array unset pending_file_outputs}
    array set pending_file_outputs {}
}

# Public helpers accessible from embedded code.
proc emit_to_file {path content} { ::embgen::queue_file_output $path $content }
proc emit_file {path body} { ::embgen::with_file_buffer $path $body }

proc upper_case {string} {
    return [string toupper $string];
}

proc lower_case {string} {
    return [string tolower $string];
}

proc camel_case {string} {
   set string [string tolower $string];
   foreach range [lreverse [regexp -all -inline -indices {(?:^|\W|_|-)[a-zA-Z0-9]} $string]] {
      set match [string range $string {*}$range]
      set replacement [string toupper [string trimleft $match "_- "]]
      set string [string replace $string {*}$range $replacement]
   }
   set result [string tolower [string range $string 0 0]];
   append result [string range $string 1 end];
   return $result;
}

proc pascal_case {string} {
   set string [string tolower $string];
   foreach range [lreverse [regexp -all -inline -indices {(?:^|\W|_|-)[a-zA-Z0-9]} $string]] {
      set match [string range $string {*}$range]
      set replacement [string toupper [string trimleft $match "_- "]]
      set string [string replace $string {*}$range $replacement]
   }
   return $string;
}

proc snake_case {string} {
    set result [string range $string 0 0];
    append result [regsub -all {[A-Z]} [string range $string 1 end] {_&}];
    regsub -all {\-} $result "_" result;
    return [string tolower $result]
}

proc kebab_case {string} {
    set result [string range $string 0 0];
    append result [regsub -all {[A-Z]} [string range $string 1 end] {-&}];
    regsub -all "_" $result "-" result;
    return [string tolower $result]
}


# Evaluate predicates in JSON path spec
proc evaluate_pathelem_predicate {pathelem target} {
    set firstword [lindex $pathelem 0]
    if {$firstword eq "AND"} {
        foreach subexpr [lrange $pathelem 1 end] {
            if {![evaluate_pathelem_predicate $subexpr $target]} {
                return 0
            }
        }
        return 1
    } elseif {$firstword eq "OR"} {
        foreach subexpr [lrange $pathelem 1 end] {
            if {[evaluate_pathelem_predicate $subexpr $target]} {
                return 1
            }
        }
        return 0
    } elseif {$firstword eq "NOT"} {
        foreach subexpr [lrange $pathelem 1 end] {
            if {[evaluate_pathelem_predicate $subexpr $target]} {
                return 0
            }
        }
        return 1
    } else {
        # allow {key value} as shorthand for EQUALS
        if {[llength $pathelem] == 2} {
            lassign $pathelem key value
            set op "EQUALS"
        } else {
            foreach {key op value} $pathelem break
        }
        set data_value [dict get $target $key]
        if {$op eq "EQUALS"} {
            return [string equal $data_value $value]
        } elseif {$op eq "MATCHES"} {
            return [regexp $value $data_value]
        }
        return 0
    }
}

# JSON-driven codegen:
#   gen_code_from_json <jsonFileOrEmpty> <pathSpecList> <codeBody>
# pathSpec is a list of "path elements".
proc gen_code_from_json {fname path code} {
    global macro_buffer
    set macro_buffer ""

    # Special form: no JSON file, run emitter body only.
    if {$fname eq "" || $fname eq "{}"} {
        catch {eval $code} msg
        addToStatus $msg
        return $macro_buffer
    }

    set fname_arg $fname
    if {[info exists ::embgen::current_file]} {
        set resolved [::embgen::resolve_embgen_path $::embgen::current_file $fname]
        if {$resolved ne ""} {
            set fname $resolved
        }
    }
    if {![file exists $fname]} {
        addToStatus "JSON file not found: $fname_arg"
        return ""
    }

    if {[catch {package require json} msg]} {
        addToStatus "JSON support not available: $msg"
        return ""
    }
    set json [read_ascii_file_contents $fname]
    set data [::json::json2dict $json]
    set target $data

    foreach pathelem $path {
        if {[llength $pathelem] > 1} {
            set found 0
            foreach x $target {
                if {[evaluate_pathelem_predicate $pathelem $x]} {
                    set target $x
                    set found 1
                    break
                }
            }
            if {!$found} { return "" }
        } elseif {[string first {[} $pathelem] == 0} {
            set idx [string range $pathelem 1 end-1]
            set target [lindex $target $idx]
        } else {
            set target [dict get $target $pathelem]
        }
    }

    set macro_buffer ""
    foreach generation_source $target {
        foreach {key value} $generation_source {
            set $key $value
        }
        eval $code
    }
    return $macro_buffer
}

# XML-driven codegen using tDOM
proc gen_code_from_xml {fname xpath code} {
    global macro_buffer
    set macro_buffer ""

    # Special form: no XML file, run emitter body only.
    if {$fname eq "" || $fname eq "{}"} {
        catch {eval $code} msg
        addToStatus $msg
        return $macro_buffer
    }

    set fname_arg $fname
    if {[info exists ::embgen::current_file]} {
        set resolved [::embgen::resolve_embgen_path $::embgen::current_file $fname]
        if {$resolved ne ""} {
            set fname $resolved
        }
    }
    if {![file exists $fname]} {
        addToStatus "XML file not found: $fname_arg"
        return ""
    }

    if {[catch {package require tdom} msg]} {
        addToStatus "XML/tdom support not available: $msg"
        return ""
    }
	
    set xml [read_ascii_file_contents $fname]
    set dom [dom parse $xml]
    set root [$dom documentElement]
    set xpathnodes [$root selectNodes $xpath]

    set macro_buffer ""
    foreach xpathnode $xpathnodes {
        catch {set xml_attributes [$xpathnode attributeNames]}
        catch {set xml_attributes [$xpathnode attributes]}
        foreach attributeName $xml_attributes {
            set attrValue [$xpathnode "@$attributeName"]
            set $attributeName $attrValue
        }
		if { [ catch {eval $code} msg ] } { emit $msg }; 
    }
    $dom delete
    return $macro_buffer
}

# ------------------------------------------------------------
# embgen embedded generator engine
# ------------------------------------------------------------

namespace eval ::embgen {
    variable generators
    variable current_comment_prefix ""
    array set generators {}

    # Resolve a referenced data file (e.g. a/b/c/types.xml) relative to the
    # file being processed, walking up directories as:
    #   /x/y/z/w/sample.txt + a/b/c/types.xml ->
    #       /x/y/z/w/a/b/c/types.xml
    #       /x/y/z/a/b/c/types.xml
    #       /x/y/a/b/c/types.xml
    #       /x/a/b/c/types.xml
    #       /a/b/c/types.xml
    proc resolve_embgen_path {currentFile refPath} {
        # Absolute paths are left as-is
        if {[file pathtype $refPath] eq "absolute"} {
            return $refPath
        }

        set searchDir [file dirname $currentFile]

        while {1} {
            set candidate [file join $searchDir $refPath]
            if {[file exists $candidate]} {
                return $candidate
            }
            set parent [file dirname $searchDir]
            if {$parent eq $searchDir} {
                break
            }
            set searchDir $parent
        }
        return ""
    }

    # Helper to format a line using the current comment prefix (//, #, --, ;, %, ...).
    proc comment_line {text} {
        variable current_comment_prefix
        if {$current_comment_prefix eq ""} {
            set prefix "#"
        } else {
            set prefix $current_comment_prefix
        }
        return "$prefix $text"
    }

    # Register a generator type with a handler proc
    proc add_generator {type procName} {
        variable generators
        set generators($type) $procName
    }

    # Run a registered generator
    #   type      : generator_type from embgen_embedded_generator line
    #   noteText  : text between embedded_generator and generated_start (comment-stripped)
    #   uuid      : UUID from the block
    #   filename  : file being processed (for context)
    proc run_generator {type noteText uuid filename} {
        variable generators
        variable pending_file_outputs
        catch {array unset pending_file_outputs}
        array set pending_file_outputs {}
        if {![info exists generators($type)]} {
            puts stderr "embgen: No generator registered for type '$type' in $filename (uuid $uuid)"
            return ""
        }
        set procName $generators($type)
        set generated [$procName $noteText $uuid $filename]
        flush_pending_files
        return $generated
    }

    # Process a single file in-place
    proc process_file {filename} {
        if {![file exists $filename]} {
            puts stderr "embgen: File not found: $filename"
            return
        }

        set fh [open $filename r]
        fconfigure $fh -encoding utf-8 -translation lf
        set content [read $fh]
        close $fh

        set lines [split $content "\n"]
        set outLines {}

        # State machine
        set inGeneratorHeader 0
        set inGeneratedSection 0
        set currentGenType ""
        set currentUuid ""
        set currentNoteLines {}
        set currentIndent ""
        set currentCommentPrefix ""

        foreach line $lines {
            # Allow both historical \"g4_\" and current \"embgen_\" markers
            set normalized [string map {g4_ embgen_} $line]
            # 1) Normal state
            if {!$inGeneratorHeader && !$inGeneratedSection} {
                if {[regexp {^\s*(//+|#+|--+|;+|%+|/+)\s*embgen_embedded_generator\s+(\S+)\s+(\S+)} \
                          $normalized -> commentPrefix genType uuid]} {
                    set inGeneratorHeader 1
                    set currentGenType $genType
                    set currentUuid $uuid
                    set currentNoteLines {}
                    set currentIndent ""
                    set currentCommentPrefix $commentPrefix
                    lappend outLines $line
                    continue
                } else {
                    lappend outLines $line
                    continue
                }
            }

            # 2) Collecting note text
            if {$inGeneratorHeader && !$inGeneratedSection} {
                if {[regexp {^\s*(/+|#+|--+|;+|%+)\s*embgen_generated_start\s+(\S+)} \
                          $normalized -> dummy uuid]} {
                    if {$uuid ne $currentUuid} {
                        puts stderr "embgen: UUID mismatch (start) in $filename: header=$currentUuid, start=$uuid"
                    }
                    set inGeneratedSection 1
                    if {[regexp {^(\s*)} $line -> ind]} {
                        set currentIndent $ind
                    } else {
                        set currentIndent ""
                    }
                    lappend outLines $line
                    continue
                }

                if {[regexp {^\s*(/+|#+|--+|;+|%+)\s?(.*)$} $line -> cp body]} {
                    lappend currentNoteLines $body
                } else {
                    lappend currentNoteLines $line
                }
                lappend outLines $line
                continue
            }

            # 3) Inside generated section
            if {$inGeneratedSection} {
                if {[regexp {^\s*(/+|#+|--+|;+|%+)\s*embgen_generated_end\s+(\S+)} \
                          $normalized -> dummy uuid]} {

                    if {$uuid ne $currentUuid} {
                        puts stderr "embgen: UUID mismatch (end) in $filename: header=$currentUuid, end=$uuid"
                    }

                    set noteText [join $currentNoteLines "\n"]
                    set ::embgen::current_file $filename
                    set ::embgen::current_comment_prefix $currentCommentPrefix
                    set generated [::embgen::run_generator $currentGenType $noteText $currentUuid $filename]

                    if {$generated ne ""} {
                        foreach genLine [split $generated "\n"] {
                            if {$genLine eq ""} {
                                lappend outLines ""
                            } else {
                                lappend outLines "${currentIndent}$genLine"
                            }
                        }
                    }

                    lappend outLines $line

                    set inGeneratedSection 0
                    set inGeneratorHeader 0
                    set currentGenType ""
                    set currentUuid ""
                    set currentNoteLines {}
                    set currentIndent ""

                    continue
                }

                # Skip old generated body
                continue
            }
        }

        set fh [open $filename w]
        fconfigure $fh -encoding utf-8 -translation lf
        puts -nonewline $fh [join $outLines "\n"]
        close $fh
    }

    # --------------------------------------------------------
    # Generators
    # --------------------------------------------------------

    # echo: emit noteText as-is
    proc gen_echo {noteText uuid filename} {
        return $noteText
    }

    # Graphviz DOT generator: noteText is DOT source.
    proc gen_dot {noteText uuid filename} {
        set dir  [file dirname $filename]
        set base [file rootname [file tail $filename]]
        set dotFile [file join $dir "${base}.${uuid}.dot"]
        set pngFile [file join $dir "${base}.${uuid}.png"]

        set fh [open $dotFile w]
        fconfigure $fh -encoding utf-8 -translation lf
        puts $fh $noteText
        close $fh

        set msg ""
        if {[catch {exec dot -Tpng $dotFile -o $pngFile} msg]} {
            addToStatus "dot error ($dotFile): $msg"
            return [comment_line "dot generation failed: $msg"]
        }
        addToStatus "dot -Tpng $dotFile -o $pngFile"
        # Remove intermediate .dot file on success
        catch {file delete -force $dotFile}
        return [comment_line "DOT graph generated at: $pngFile"]
    }

    # PlantUML PNG generator: noteText is PlantUML script (@startuml ... @enduml).
    proc gen_plantuml {noteText uuid filename} {
	    global installdir;
        set dir  [file dirname $filename]
        set base [file rootname [file tail $filename]]
        set puFile  [file join $dir "${base}.${uuid}.puml"]

        set fh [open $puFile w]
        fconfigure $fh -encoding utf-8 -translation lf
        puts $fh $noteText
        close $fh

        set msg ""
        if {[catch {exec java -jar $installdir/plantuml/plantuml.jar -tpng $puFile} msg]} {
            addToStatus "plantuml error ($puFile): $msg"
            return [comment_line "plantuml generation failed: $msg"]
        }

        # Look for PNG generated by PlantUML
        set pngFile [file rootname $puFile].png
        if {![file exists $pngFile]} {
            set candidates [glob -nocomplain [file join $dir "${base}.${uuid}*.png"]]
            if {[llength $candidates] > 0} {
                set pngFile [lindex $candidates 0]
            }
        }
        addToStatus "plantuml -tpng $puFile"
        # Remove intermediate .puml file on success
        catch {file delete -force $puFile}
        return [comment_line "PlantUML image generated at: $pngFile"]
    }

    # PlantUML ASCII generator: returns ASCII art from -ttxt
    proc gen_plantuml_ascii {noteText uuid filename} {
	    global installdir;
        set dir  [file dirname $filename]
        set base [file rootname [file tail $filename]]
        set puFile  [file join $dir "${base}.${uuid}.puml"]

        set fh [open $puFile w]
        fconfigure $fh -encoding utf-8 -translation lf
        puts $fh $noteText
        close $fh

        set msg ""
        if {[catch {exec java -jar $installdir/plantuml/plantuml.jar -ttxt $puFile} msg]} {
            addToStatus "plantuml -ttxt error ($puFile): $msg"
            return [comment_line "plantuml ascii generation failed: $msg"]
        }

        set outfiles [lsort -decreasing [glob -nocomplain [file join $dir "${base}.${uuid}*.atxt"]]]
        set generated ""
        foreach out $outfiles {
            append generated [read_ascii_file_contents $out]
            append generated "\n"
            # Remove intermediate .atxt files after reading
            catch {file delete -force $out}
        }
        if {$generated eq ""} {
            return [comment_line "No ASCII PlantUML output found for $puFile"]
        }
        # Remove intermediate .puml file too
        catch {file delete -force $puFile}
        return $generated
    }

    # XML-driven macro
    proc gen_xml_driven_macro {noteText uuid filename} {
        set ::embgen::current_file $filename
        set script $noteText
        regsub -all {^@} $script "\1" script
        regsub -all {[\r\n][ \t]*@} $script "\1" script
        set lines [split $script "\1"]

        set generated ""
        foreach line $lines {
            if {[string trim $line] eq ""} continue
            # Each directive should form a valid Tcl list of three elements:
            #   fname xpath codeBody
            if {[catch {set n [llength $line]}]} continue
            if {$n != 3} continue
            set parts $line
            lassign $parts fname xpath codeBody
            append generated [gen_code_from_xml $fname $xpath $codeBody]
        }
        return $generated
    }

    # JSON-driven macro
    proc gen_json_driven_macro {noteText uuid filename} {
        set ::embgen::current_file $filename
        set script $noteText
        regsub -all {^@} $script "\1" script
        regsub -all {[\r\n][ \t]*@} $script "\1" script
        set lines [split $script "\1"]

        set generated ""
        foreach line $lines {
            if {[string trim $line] eq ""} continue
            if {[catch {set n [llength $line]}]} continue
            if {$n != 3} continue
            set parts $line
            lassign $parts fname pathSpec codeBody
            append generated [gen_code_from_json $fname $pathSpec $codeBody]
        }
        return $generated
    }

    # tcl_macro: eval the note text as Tcl and use the macro buffer
    # as the generated content.
    proc gen_tcl_macro {noteText uuid filename} {
        global macro_buffer
        set macro_buffer ""
        set ::embgen::current_file $filename
        if {[catch {eval $noteText} msg]} {
            addToStatus "tcl_macro error ($filename, $uuid): $msg"
        }
        return $macro_buffer
    }

    # LaTeX generator: noteText is LaTeX body
    proc gen_latex {noteText uuid filename} {
        return [::embgen::gen_latex_aux $noteText $uuid $filename 0]
    }

    proc gen_latex_inline {noteText uuid filename} {
        return [::embgen::gen_latex_aux $noteText $uuid $filename 1]
    }

    proc gen_latex_aux {noteText uuid filename inline} {
        set dir  [file dirname $filename]
        set base [file rootname [file tail $filename]]

        set latex_preamble {
\documentclass{article}
\usepackage[utf8]{inputenc}
\usepackage{mathtools}
\pagestyle{empty}
}
        set latex_body_template {
\begin{document}
%s
\end{document}
}
        set formatted_latex_body [format $latex_body_template $noteText]

        set texFile [file join $dir "${base}.${uuid}.temp.tex"]
        set fh [open $texFile w]
        fconfigure $fh -encoding utf-8 -translation lf
        puts $fh $latex_preamble
        puts $fh $formatted_latex_body
        close $fh

        # Force LaTeX outputs (dvi/aux/log) into the same directory as the source.
        set msg ""
        if {[catch {exec latex -output-directory $dir $texFile} msg]} {
            addToStatus "latex error ($texFile): $msg"
            return [comment_line "LaTeX compile failed: $msg"]
        }

        set dviFile [file join $dir "${base}.${uuid}.temp.dvi"]
        set pngFile [file join $dir "${base}.${uuid}.png"]
        if {[catch {exec dvipng -T tight -o $pngFile $dviFile} msg]} {
            addToStatus "dvipng error ($dviFile): $msg"
            return [comment_line "dvipng failed: $msg"]
        }

        # Clean up some temp files (best-effort)
        foreach tf [list $texFile $dviFile \
                        [file join $dir "${base}.${uuid}.temp.aux"] \
                        [file join $dir "${base}.${uuid}.temp.log"]] {
            catch {file delete -force $tf}
        }

        if {$inline} {
            return [comment_line "LaTeX inline PNG: $pngFile"]
        } else {
            return [comment_line "LaTeX PNG generated at: $pngFile"]
        }
    }

    # using_command_line: noteText is a shell command line
    proc gen_using_command_line {noteText uuid filename} {
        set cmdline [string trim $noteText]
        if {$cmdline eq ""} {
            return [comment_line "using_command_line: empty command"]
        }
        set msg ""
        if {[catch {set out [eval exec $cmdline]} msg]} {
            addToStatus "Command failed: $cmdline : $msg"
            return [comment_line "CMD ERROR: $msg"]
        }
        return $out
    }

    proc usage {} {
        puts stderr "Usage:"
        puts stderr "  embgen.tcl FILE ...                              # process explicit files"
        puts stderr "  embgen.tcl -r ROOT ... [-i PATTERN|--include=PAT] [-x PATTERN|--exclude=PAT]"
        puts stderr "  embgen.tcl -l LISTFILE                          # one file path per line"
        puts stderr "Options:"
        puts stderr "  -r ROOT               recurse ROOT (may repeat)"
        puts stderr "  -i/--include=PATTERN  include glob (full path)  "
        puts stderr "  -x/--exclude=PATTERN  exclude glob (full path)  "
        puts stderr "  -l LISTFILE           read files from list file"
        exit 1
    }

    proc should_include {path includePats excludePats} {
        set npath [file normalize $path]

        set ok 0
        foreach pat $includePats {
            if {[string match $pat $npath]} {
                set ok 1
                break
            }
        }
        if {!$ok} {
            return 0
        }

        foreach pat $excludePats {
            if {[string match $pat $npath]} {
                return 0
            }
        }
        return 1
    }

    proc collect_files {dir includePats excludePats resultVar} {
        upvar 1 $resultVar result
        set entries [glob -nocomplain -directory $dir *]
        foreach e $entries {
            if {[file isdirectory $e]} {
                collect_files $e $includePats $excludePats result
            } elseif {[file isfile $e]} {
                if {[should_include $e $includePats $excludePats]} {
                    lappend result [file normalize $e]
                }
            }
        }
    }

    proc read_list_file {listFile} {
        set paths {}

        if {![file exists $listFile]} {
            addToStatus "list file not found: $listFile"
            return $paths
        }
        if {[catch {set fh [open $listFile r]} msg]} {
            addToStatus "could not open list file $listFile: $msg"
            return $paths
        }
        fconfigure $fh -encoding utf-8 -translation lf
        set data [split [read $fh] "\n"]
        close $fh

        set listDir [file dirname [file normalize $listFile]]
        foreach raw $data {
            set p [string trim $raw]
            if {$p eq ""} {
                continue
            }

            set candidates {}
            if {[file pathtype $p] eq "absolute"} {
                lappend candidates $p
            } else {
                lappend candidates [file join [pwd] $p]
                lappend candidates [file join $listDir $p]
            }

            set resolved ""
            foreach c $candidates {
                if {[catch {set normalized [file normalize $c]}]} {
                    continue
                }
                if {[file exists $normalized]} {
                    set resolved $normalized
                    break
                }
            }

            if {$resolved eq ""} {
                addToStatus "list entry not found: $p"
                continue
            }
            if {![file isfile $resolved]} {
                addToStatus "list entry is not a file: $resolved"
                continue
            }
            lappend paths $resolved
        }
        return $paths
    }

    proc main {} {
        global argv

        # Generator registrations
        ::embgen::add_generator echo              ::embgen::gen_echo
        ::embgen::add_generator dot               ::embgen::gen_dot
        ::embgen::add_generator plantuml          ::embgen::gen_plantuml
        ::embgen::add_generator plantuml_ascii    ::embgen::gen_plantuml_ascii
        ::embgen::add_generator xml_driven_macro  ::embgen::gen_xml_driven_macro
        ::embgen::add_generator json_driven_macro ::embgen::gen_json_driven_macro
        ::embgen::add_generator tcl_macro         ::embgen::gen_tcl_macro
        ::embgen::add_generator latex             ::embgen::gen_latex
        ::embgen::add_generator latex_inline      ::embgen::gen_latex_inline
        ::embgen::add_generator using_command_line ::embgen::gen_using_command_line

        if {[llength $argv] == 0} {
            usage
        }

        set roots {}
        set includePats {}
        set excludePats {}
        set listFiles {}
        set files {}

        set args $argv
        while {[llength $args] > 0} {
            set arg [lindex $args 0]
            if {$arg eq "-r"} {
                if {[llength $args] < 2} {
                    puts stderr "embgen: -r requires a directory"
                    usage
                }
                lappend roots [lindex $args 1]
                set args [lrange $args 2 end]
            } elseif {[string match "--include=*" $arg]} {
                lappend includePats [string range $arg [string length "--include="] end]
                set args [lrange $args 1 end]
            } elseif {[string match "--exclude=*" $arg]} {
                lappend excludePats [string range $arg [string length "--exclude="] end]
                set args [lrange $args 1 end]
            } elseif {$arg eq "-i"} {
                if {[llength $args] < 2} {
                    puts stderr "embgen: -i requires a pattern"
                    usage
                }
                lappend includePats [lindex $args 1]
                set args [lrange $args 2 end]
            } elseif {$arg eq "-x"} {
                if {[llength $args] < 2} {
                    puts stderr "embgen: -x requires a pattern"
                    usage
                }
                lappend excludePats [lindex $args 1]
                set args [lrange $args 2 end]
            } elseif {$arg eq "-l"} {
                if {[llength $args] < 2} {
                    puts stderr "embgen: -l requires a list file"
                    usage
                }
                lappend listFiles [lindex $args 1]
                set args [lrange $args 2 end]
            } elseif {[string match "-*" $arg]} {
                puts stderr "embgen: unknown option: $arg"
                usage
            } else {
                lappend files $arg
                set args [lrange $args 1 end]
            }
        }

        if {[llength $includePats] == 0} {
            set includePats [list *]
        }

        set targets {}
        set errors 0

        foreach root $roots {
            if {![file isdirectory $root]} {
                addToStatus "ROOTDIR is not a directory: $root"
                incr errors
                continue
            }
            collect_files $root $includePats $excludePats targets
        }

        foreach lf $listFiles {
            foreach p [read_list_file $lf] {
                lappend targets $p
            }
        }

        foreach f $files {
            if {[catch {set nf [file normalize $f]}]} {
                addToStatus "could not normalize path: $f"
                incr errors
                continue
            }
            lappend targets $nf
        }

        # De-duplicate targets
        array set seen {}
        set uniqueTargets {}
        foreach t $targets {
            if {![info exists seen($t)]} {
                set seen($t) 1
                lappend uniqueTargets $t
            }
        }
        set targets $uniqueTargets

        if {[llength $targets] == 0} {
            if {$errors > 0} {
                exit 1
            }
            addToStatus "no files to process"
            exit 0
        }

        foreach f $targets {
            if {![file exists $f] || ![file isfile $f]} {
                addToStatus "skipping non-file: $f"
                incr errors
                continue
            }
            if {[catch {::embgen::process_file $f} msg]} {
                incr errors
                addToStatus "error processing $f: $msg"
            }
        }

        if {$errors > 0} {
            exit 1
        }
    }
}

# Run main if executed directly
if {[info exists argv0] && [file tail $argv0] eq [file tail [info script]]} {
    ::embgen::main
}
