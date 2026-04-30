
add_double_click_handler bottomup_chase_refs "Show backlinks on doubleclick";

userproc bottomup_chase_refs {pos} {
  catch {
  set editor [editor];
  set start [$editor index "$pos wordstart"];
  set end [$editor index "$pos wordend"];
  set cont [$editor get $start $end];
  set tags [tags_in_given_ranges [list $start $end]];
  set resultsWindow [createResultsWindow "Backlinks"]
  set resultAdded 0;
  foreach tag $tags {
      if {[string first "target_" $tag] == 0} {
          set reftag "hyperref_[string range $tag 7 end]";
          set refranges [.t tag ranges $reftag];
		  
          foreach {refstart refend} $refranges {
              set refstartpos [split $refstart "."];
              set theLine [lindex $refstartpos 0];
              set theCol [lindex $refstartpos 1];
              set reflinestart [.t index "$refstart linestart"];
              set reflineend [.t index "$refstart lineend"];
              set reflinecontent [.t get $reflinestart $reflineend]
              
              $resultsWindow.results insert end "($theLine):($theCol):" resultHyperlink;
              $resultsWindow.results insert end "$reflinecontent\n";
			  incr resultAdded;
          }
          
      }
  }
  if {!$resultAdded} {
     destroy $resultsWindow;
  }
  
  addToStatus "$resultAdded links found";
  
  } msg;
  
  puts $msg;
 
}
