
add_generator dot generate_dot;
userproc generate_dot {fname index tag} {
   catch {file  delete -force "$fname.png" };
   addToStatus "dot -Tpng $fname -o $fname.png :";
   catch {exec dot -Tpng $fname -o "$fname.png" } msg;
   addToStatus "$msg";
   [editor] insert $index "\n" $tag;      
   insert_image $index "$fname.png" $tag; 
   [editor] insert $index "\n" $tag;   
   return 1;
}

add_generator plantuml generate_plantuml;
userproc generate_plantuml {fname index tag} {
   regsub -all  {\.txt$}  $fname {} fnameroot;
   catch {
	   foreach oldfile [glob "${fnameroot}*.png"] {
		  file  delete -force $oldfile;
	   }
   }
   addToStatus "java -jar [installdir]/plantuml.jar -tpng $fname :";
   catch {exec java -jar "[installdir]/plantuml.jar" -tpng $fname} msg;
   addToStatus "$msg";
   regsub -all  {\.txt$}  $fname {} fnameroot;
   set outfiles [lsort  -decreasing [glob "${fnameroot}*.png"] ];
   foreach imname $outfiles {
      [editor] insert $index "\n" $tag;      
      insert_image $index "$imname" $tag; 
      [editor] insert $index "\n" $tag; 
   }    
   return 1;
}
userproc load_json_package {} {
   package require json
}
load_json_package

userproc gen_code_from_json {fname path code } {
    global result_cT28aymy3bA;
    if {$fname == ""} {
	   set result_cT28aymy3bA "";
	   catch {eval $code;} msg;
	   addToStatus $msg;
	   return $result_cT28aymy3bA;
    }
    set fname_arg $fname;   
    if {![file exists $fname] } {
	   set filename   [get_current_filename]
           set folder $filename
	   regsub -all {/[^/]+$} $folder {} folder;
	   set fname $folder/$fname;
    }
    if {![file exists $fname]} {
       tk_messageBox -message "Generating code from json : Referenced json file $fname_arg was not found"
    }
    set fp [open $fname r];set json [read $fp]; close $fp;
    set data [::json::json2dict $json];
    set target $data;
    
    foreach pathelem $path {
       if {[llength $pathelem] > 1} {
	      set found 0;
          foreach x $target {
		      if {[evaluate_pathelem_predicate $pathelem $x]} {
			    set target $x;
				set found 1;
				break;
			  }
          }
		  if {!$found} {
		     return "";
		  }
		  
       } elseif {[string first {[} $pathelem] == 0} {
          set idx [string range $pathelem 1 end-1];
          set target [lindex $target $idx]; 
       } else {
          set target [dict get $target $pathelem]; 
       }
    }

    # [gen_code_from_json c:/JMWrap/types.json {types {name Person} fields}  {}]
    # target takes the value {name id javatype int dbtype INTEGER} {name firstName javatype String dbtype VARCHAR(255)} {name lastName javatype String dbtype VARCHAR(255)} {name age javatype int dbtype INTEGER} {name email javatype String dbtype VARCHAR(255)}
    #puts "target=$target"
    set result_cT28aymy3bA "";
    foreach generation_source $target {
      #puts "generation_source=$generation_source"
       
       foreach {key value} $generation_source {
          set $key $value;
          #puts "$key $value"
       }
       eval $code;
    }
    return $result_cT28aymy3bA;
     
}

userproc evaluate_pathelem_predicate {pathelem target} {
    #puts "pathelem=$pathelem target=$target"
    set firstword [lindex $pathelem 0];
	if {$firstword == "AND"} {
	   set rest [lrange $pathelem 1 end];
	   
	   foreach subexpr $rest {
	       set subexpr_value [evaluate_pathelem_predicate $subexpr $target];
		   if {$subexpr_value == 0} {return 0;}
	   }
	   return 1;
	} elseif {$firstword == "OR"} {
	   set rest [lrange $pathelem 1 end];
	   foreach subexpr $rest {
	       set subexpr_value [evaluate_pathelem_predicate $subexpr $target];
		   if {$subexpr_value == 1} {return 1;}
	   }
	   return 0;
	} elseif {$firstword == "NOT"} {
	   set rest [lrange $pathelem 1 end];
	   foreach subexpr $rest {
	       set subexpr_value [evaluate_pathelem_predicate $subexpr $target];
		   if {$subexpr_value == 1} {return 0;}
	   }
	   return 1;
	} else {
        foreach {key op value} $pathelem {
		    set data_value [dict get $target $key];
			#puts "key=$key op=$op value=$value data_value=$data_value target=$target";
		    if { $op == "EQUALS" } {
				   set retval [string equal $data_value $value];
				   
		    } elseif {$op == "MATCHES" } {
			      set retval [regexp $value $data_value]; 
			} 
			#puts "retval=$retval";
			return $retval;
        }		
    }	
}

userproc gen_code_from_xml {fname xpath code} {
    global result_cT28aymy3bA;
    if {$fname == ""} {
	   set result_cT28aymy3bA "";
	   catch {eval $code;} msg;
	   addToStatus $msg;
	   return $result_cT28aymy3bA;
	}
    set fname_arg $fname;
    
	if {![file exists $fname] } {
	   set filename   [get_current_filename]
       set folder $filename
	   regsub -all {/[^/]+$} $folder {} folder;
	   set fname $folder/$fname;
	}
	if {![file exists $fname] } {
	   tk_messageBox -message "Generating code from xml : Referenced xml file $fname_arg was not found"
	}
    set fp [open $fname r];set xml [read $fp]; close $fp;
    set dom [dom parse $xml];
    set root [$dom documentElement];
    set fieldElems [$root selectNodes $xpath]
	set result_cT28aymy3bA "";
    foreach fieldElem $fieldElems {
        catch {set xml_attributes [$fieldElem attributeNames]};
        catch {set xml_attributes [$fieldElem attributes]};
        set xml_values {};
		set xml_attribute_values {};
        foreach attributeName $xml_attributes {
            set attrValue [$fieldElem "@$attributeName"];
            set $attributeName $attrValue;
			lappend xml_values $attrValue;
			lappend xml_attribute_values $attributeName;
			lappend xml_attribute_values $attrValue;
        }
        eval $code;
    }
	return $result_cT28aymy3bA;
}

userproc emit {str} {
   global result_cT28aymy3bA;
   append result_cT28aymy3bA $str;   
}

userproc emitted {} {
   global result_cT28aymy3bA;
   return $result_cT28aymy3bA;   
}
# "types.xml"  {/types/type[@name='Person']/fields/field} {
#    emit "$javatype $name; // $dbtype\n";
#}

add_generator xml_driven_macro generate_xml_driven_macro;
userproc generate_xml_driven_macro {fname index tag} {
   set script [read_ascii_file_contents $fname];
   regsub -all {^@} $script "\1" script;
   regsub -all {[\r\n]@} $script "\1" script;
   set lines [split $script "\1"];
   set generated "";
   foreach line $lines {
      if {[llength $line] == 0} continue;
      append generated [gen_code_from_xml {*}$line];
   }
   [editor] insert $index "\n" $tag;      
   [editor] insert $index $generated $tag; 
   [editor] insert $index "\n" $tag; 
   
   return 1;
}

add_generator json_driven_macro generate_json_driven_macro;
userproc generate_json_driven_macro {fname index tag} {
   set script [read_ascii_file_contents $fname];
   regsub -all {^@} $script "\1" script;
   regsub -all {[\r\n]@} $script "\1" script;
   set lines [split $script "\1"];
   set generated "";
   foreach line $lines {
      if {[llength $line] == 0} continue;
      append generated [gen_code_from_json {*}$line];
   }
   [editor] insert $index "\n" $tag;      
   [editor] insert $index $generated $tag; 
   [editor] insert $index "\n" $tag; 
   
   return 1;
}

add_generator plantuml_ascii generate_plantuml_ascii;
userproc generate_plantuml_ascii {fname index tag} {
   regsub -all  {\.txt$}  $fname {} fnameroot;
   catch {
	   foreach oldfile [glob "${fnameroot}*.atxt"]  {
		  file  delete -force $oldfile;
	   }
   }
   
   addToStatus "java -jar [installdir]/plantuml.jar -ttxt $fname :";
   catch {exec java -jar "[installdir]/plantuml.jar" -ttxt $fname} msg;
   regsub -all "\....$" $fname ".atxt" outname;
   addToStatus "$msg";
   set outfiles [lsort  -decreasing [glob "${fnameroot}*.atxt"] ];
   foreach outname $outfiles {
      [editor] insert $index "\n" $tag;      
      [editor] insert $index [read_ascii_file_contents $outname] $tag;   
      [editor] insert $index "\n" $tag; 
   }  
   return 1;
}

add_generator latex generate_latex;
add_generator latex generate_latex_inline;
userproc generate_latex {fname index tag} {
  generate_latex_aux $fname $index $tag 0  
}
userproc generate_latex_inline {fname index tag} {
  generate_latex_aux $fname $index $tag 1  
}
userproc generate_latex_aux {fname index tag inline} {
	# Your input string
	set input_string "Hello, LaTeX!"

	# Define the LaTeX preamble
	set latex_preamble {
\documentclass{article}
\usepackage[utf8]{inputenc}
\usepackage{mathtools}
\pagestyle{empty}
	}
	set input_string [read_ascii_file_contents $fname];

	# Define the LaTeX document body with the encapsulated string
	set latex_body_template {
\begin{document}
		%s
\end{document}
	}

	# Format the LaTeX body with the input string
	set formatted_latex_body [format $latex_body_template  $input_string]
	addToStatus $latex_preamble;
    addToStatus $formatted_latex_body;
	# Create a temporary LaTeX file
	set latex_file "$fname.temp.tex"
	set latex_file_handle [open $latex_file w]
	puts $latex_file_handle "$latex_preamble"
	puts $latex_file_handle "$formatted_latex_body"
	close $latex_file_handle
    
	regsub -all {^.*/} "$fname" {} fname_leaf 
   
	# Compile the LaTeX file to DVI using LaTeX
	addToStatus "latex $latex_file :"
	catch {exec latex $latex_file} msg;
	addToStatus "$msg"

	# Convert DVI to PNG using dvipng
	addToStatus "dvipng -T tight -o $fname.png ${fname_leaf}.temp.dvi : "
	catch {exec dvipng -T tight -o "$fname.png" "${fname_leaf}.temp.dvi"} msg;
	addToStatus "$msg"

	# Clean up temporary files
	file delete -force $latex_file
	set tempfiles [list "${fname_leaf}.temp.aux" "${fname_leaf}.temp.log" "${fname_leaf}.temp.dvi" ];
	foreach tempfile $tempfiles {
	    file delete -force $tempfile
	}
	puts "PNG file generated: output.png"
    if {!$inline} { [editor] insert $index "\n" $tag };      
    insert_image $index "$fname.png" $tag; 
    if {!$inline} { [editor] insert $index "\n" $tag };   
    return 1;
}

add_generator using_command_line generate_using_command_line;
userproc generate_using_command_line {fname index tag} {
   set cmdline [read_ascii_file_contents $fname];
   catch {
      exec {*}$cmdline;
	} msg;
   
  [editor] insert $index "\n" $tag;      
  [editor] insert $index $msg $tag;   
  [editor] insert $index "\n" $tag; 
   
   return 1;
}

userproc verify_from_xml {text fname xpath code} {

    if {$fname == ""} {
	   catch {eval $code;} msg;
       return;
	}
    set fname_arg $fname;
    
	if {![file exists $fname] } {
	   set filename   [get_current_filename]
       set folder $filename
	   regsub -all {/[^/]+$} $folder {} folder;
	   set fname $folder/$fname;
	}
	if {![file exists $fname] } {
	   tk_messageBox -message "Verifying code from xml : Referenced xml file $fname_arg was not found"
	}
    set fp [open $fname r];set xml [read $fp]; close $fp;
    set dom [dom parse $xml];
    set root [$dom documentElement];
    set fieldElems [$root selectNodes $xpath]

    foreach fieldElem $fieldElems {
        catch {set xml_attributes [$fieldElem attributeNames]};
        catch {set xml_attributes [$fieldElem attributes]};
        set xml_values {};
		set xml_attribute_values {};
        foreach attributeName $xml_attributes {
            set attrValue [$fieldElem "@$attributeName"];
            set $attributeName $attrValue;
			lappend xml_values $attrValue;
			lappend xml_attribute_values $attributeName;
			lappend xml_attribute_values $attrValue;
        }
        eval $code;
    }

}

userproc verify_xml_based {filename index verifier_tag} {
    addToStatus "*** Checking xml based verifier at $index  ***"
    set ranges [.t tag ranges $verifier_tag];
    set text "";
    foreach {start end} $ranges {
        append text [.t get $start $end];
    }
    
   set script [read_ascii_file_contents $filename];
   regsub -all {^@} $script "\1" script;
   regsub -all {[\r\n]@} $script "\1" script;
   set lines [split $script "\1"];
   set generated "";
   foreach line $lines {
      if {[llength $line] == 0} continue;
      verify_from_xml $text {*}$line;
   }
}

add_verifier xml_based_assert verify_xml_based;
 