userproc load_packages {} {
package require tdom
package require fileutil
}
load_packages;


userproc get_base_dirs {} {
    return {
        /etc/app/shared-spring
        /usr/local/myapp/spring-config
    }
}

userproc readFile {path} {
    set f [open $path r]
    set data [read $f]
    close $f
    return $data
}


userproc expandSpringContext {file baseDir} {
    set fullPath [file normalize [file join $baseDir $file]]
    set doc [dom parse [readFile $fullPath]]
    set root [$doc documentElement]
    set ns [$root namespaceURI]

    expandImports $root [file dirname $fullPath]
    return [$doc asXML]
}

userproc set_nsmap {} {
    global nsmap;
    set nsmap [list b http://www.springframework.org/schema/beans]
    
}
set_nsmap;

userproc expandImports {node currentDir} {
    global nsmap;
    set imports [$node selectNodes -namespaces  $nsmap {//b:import}]
    
    foreach imp $imports {
        
        addToStatus "import [$imp asXML]s";
        
        set resource [$imp getAttribute resource]
        set candidatePaths {}
        

        # Try current file's directory first
        lappend candidatePaths [file join $currentDir $resource]

        # Then try any user-supplied base directories
        foreach dir [get_base_dirs] {
            lappend candidatePaths [file join $dir $resource]
        }

        # Locate the first existing path
        set importPath ""
        foreach path $candidatePaths {
            if {[file exists $path]} {
                set importPath [file normalize $path]
                break
            }
        }
        

        if {$importPath eq ""} {
            addToStatus "‚ö†Ô∏è  Warning: Could not find imported resource '$resource' in any base directory"
            continue
        }
  
        addToStatus "importPath = $importPath";

        # ‚úÖ Log where the import was found
        addToStatus "Ì†ΩÌ≥• Inserting resource '$resource' from: $importPath";


        # Parse and inline the XML
        set importDoc [dom parse [readFile $importPath]]
        set importRoot [$importDoc documentElement]

  
        
        
        set parent [$imp parentNode]
        
        if {$parent == ""} {
             addToStatus "empty parent!";     
             continue; 
        }
        
        set startComment "<inserted file=\"$resource\"/>"
        set comment [dom parse $startComment]
        $parent insertBefore [$comment documentElement] $imp;
        
        foreach child [$importRoot childNodes] {
            set imported [$child cloneNode -deep]
            $parent insertBefore $imported $imp  
        }
        
        $parent removeChild $imp

        $importDoc delete


        # Recursively expand any imports in the inserted content
        expandImports $parent [file dirname $importPath];
        
    }
}

add_double_click_handler pick_bean_from_grepline  "Doubleclick picks bean from grepline";
userproc pick_bean_from_grepline {pos} {
    catch {
        set editor [editor]
        set linestart [$editor index "$pos linestart"]
        set lineend   [$editor index "$pos lineend"]
        set input_line [$editor get $linestart $lineend]

        # Extract file and line from the grep-formatted line
        if {![regexp {^\s*(.+?):([0-9]+):} $input_line -> loc_file loc_line]} {
            addToStatus "Could not parse grep line: $input_line"
            return
        }

        if {![file exists $loc_file]} {
            addToStatus "File <$loc_file> was not found"
            return
        }

        set output ""
        set fp [open $loc_file r]
        set cont [read $fp]
        close $fp

        set lines [split $cont "\n"]
        set total_lines [llength $lines]
        set depth 0

        # Traverse backwards to find the start of the <bean>
        for {set i $loc_line} {$i >= 1} {incr i -1} {
            set line [lindex $lines [expr {$i - 1}]]
            if {[regexp {</bean} $line]} {
                incr depth
            }
            set output "$line\n$output"
            if {[regexp {<bean} $line]} {
                if {$depth == 0} {
                    break
                }
                incr depth -1
            }
        }

        # Traverse forward to find the end of the <bean>
        set depth 0
        for {set i [expr {$loc_line + 1}]} {$i <= $total_lines} {incr i} {
            set line [lindex $lines [expr {$i - 1}]]
            set output "$output\n$line"
            if {[regexp {<bean} $line]} {
                incr depth
            }
            if {[regexp {</bean} $line]} {
                if {$depth == 0} {
                    break
                }
                incr depth -1
            }
        }

        set output "${loc_file}:${loc_line}:\n$output\n"
        clipboard clear
        clipboard append $output
    } msg
    if {$msg ne ""} {
        puts "Error: $msg"
    }
}


userproc findSpringImportPathMatchingPattern {file baseDir regex} {
    set fullPath [file normalize [file join $baseDir $file]]
    return [findMatchRecursive $fullPath $regex {}]
}

userproc findMatchRecursive {filepath regex pathSoFar} {
    global nsmap
    if {![file exists $filepath]} {
        addToStatus "‚õî File not found: $filepath"
        return ""
    }

    lappend pathSoFar $filepath
    set doc [dom parse [readFile $filepath]]
    set root [$doc documentElement]

    # Check for pattern match in current file
    foreach node [$root selectNodes "//*"] {
        set xml [$node asXML]
        if {[regexp -- $regex $xml]} {
            $doc delete
            return $pathSoFar
        }
    }

    # Check <import> tags
    set currentDir [file dirname $filepath]
    set imports [$root selectNodes -namespaces $nsmap {//b:import}]
    foreach imp $imports {
        set resource [$imp getAttribute resource]
        set candidatePaths {}

        # First, try current file's directory
        lappend candidatePaths [file join $currentDir $resource]

        # Then try user-supplied base directories
        foreach dir [get_base_dirs] {
            lappend candidatePaths [file join $dir $resource]
        }

        # Try each candidate path until match found
        foreach path $candidatePaths {
            if {[file exists $path]} {
                set result [findMatchRecursive [file normalize $path] $regex $pathSoFar]
                if {$result ne ""} {
                    $doc delete
                    return $result
                }
            }
        }
    }

    $doc delete
    return ""
}
