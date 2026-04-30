set all_commands "";
set spectral_script [info script];
catch {package require Tkhtml};

if {[catch {package require Tk} tk_err]} {
    puts stderr "Tk is required but was not found: $tk_err"
    exit 1
}

# Compatibility mode for barebones Tcl/Tk distributions (for example Git for Windows).
set ::spectral_has_real_ctext 1
set ::spectral_has_real_iwidgets 1

proc spectral_script {} {
    global spectral_script;
    return $spectral_script;
}
set spectral_version "0.0.7"
set datestamp "20230206"
set license_version 591;
if {[catch {package require sqlite3}]} {
    namespace eval ::_spectral_sqlite {
        variable reg_kv
        array set reg_kv {}
    }
    proc sqlite3 {handle dbfile} {
        interp alias {} $handle {} ::_spectral_sqlite::dispatch $handle
        return $handle
    }
    proc ::_spectral_sqlite::dispatch {handle subcmd args} {
        variable reg_kv
        if {$subcmd eq "close"} {
            return
        }
        if {$subcmd ne "eval"} {
            return ""
        }
        set sql [string trim [lindex $args 0]]
        if {[regexp -nocase {^select count\(\*\) from keyvals where key='([^']+)'} $sql -> key]} {
            return [expr {[info exists reg_kv($key)] ? 1 : 0}]
        }
        if {[regexp -nocase {^insert into keyvals values\('([^']+)','(.*)'\)} $sql -> key val]} {
            set reg_kv($key) $val
            return
        }
        if {[regexp -nocase {^update keyvals set val='(.*)' where key='([^']+)'} $sql -> val key]} {
            set reg_kv($key) $val
            return
        }
        if {[regexp -nocase {^select val from keyvals where key='([^']+)'} $sql -> key]} {
            if {[info exists reg_kv($key)]} {
                return [list [list $reg_kv($key)]]
            }
            return {}
        }
        if {[regexp -nocase {^select \* from } $sql]} {
            return {}
        }
        return
    }
    package provide sqlite3 3.0
}

catch {package require tdom}
catch {package require struct}
catch {package require struct::list}
set sepdepth 0;
set image_editor mspaint.exe;
set last_overpainted_stuff {};
set last_op_was_overpainting 0;
if {[catch {package require base64}]} {
    namespace eval base64 {}
    proc base64::encode {data} { binary encode base64 $data }
    proc base64::decode {data} { binary decode base64 $data }
    package provide base64 1.0
}

if {[catch {package require struct::set}]} {
    namespace eval struct::set {}
    proc struct::set::difference {lhs rhs} {
        set out {}
        foreach it $lhs {
            if {[lsearch -exact $rhs $it] < 0} {
                lappend out $it
            }
        }
        return $out
    }
    package provide struct::set 1.0
}

if {[catch {package require struct::list}]} {
    namespace eval struct::list {}
    proc struct::list::longestCommonSubsequence {a b} { return {} }
    proc struct::list::lcsInvertMerge {lcs a b} { return [list $a $b] }
    package provide struct::list 1.0
}

if {[catch {package require md5}]} {
    namespace eval md5 {}
    proc md5::md5 {args} {
        set txt [lindex $args end]
        set c [zlib crc32 $txt]
        set h [format %08x $c]
        return "${h}${h}${h}${h}"
    }
    package provide md5 2.0
}

if {[catch {package require uuid}]} {
    namespace eval uuid {}
    proc uuid::uuid {subcmd args} {
        if {$subcmd ne "generate"} { return "" }
        set t [clock microseconds]
        set r [expr {int(rand()*0x7fffffff)}]
        return [format "%08x-%04x-%04x-%04x-%012x" \
            [expr {$t & 0xffffffff}] [expr {($t >> 16) & 0xffff}] [expr {($t >> 4) & 0xffff}] [expr {$r & 0xffff}] [expr {($r << 16) & 0xffffffffffff}]]
    }
    package provide uuid 1.0
}

if {[catch {package require safe}]} {
    namespace eval ::safe {}
    proc ::safe::interpCreate {} { return [interp create] }
    proc ::safe::interpDelete {slave} { catch {interp delete $slave} }
    package provide safe 1.0
}

if {[catch {package require fileutil}]} {
    namespace eval fileutil {}
    proc fileutil::foreachLine {var filename body} {
        upvar 1 $var line
        set fp [open $filename r]
        while {[gets $fp line] >= 0} {
            uplevel 1 $body
        }
        close $fp
    }
    package provide fileutil 1.0
}

if {[catch {package require tdom}]} {
    package provide tdom 0.0
    proc dom {subcmd args} {
        error "tdom is not available in this Tcl/Tk build"
    }
}

if {[catch {package require json}]} {
    namespace eval json {}
    proc json::json2dict {args} { return [dict create] }
    proc json::dict2json {args} { return "{}" }
    proc json::write {args} { return "{}" }
    package provide json 1.0
}

if {[catch {package require twapi}]} {
    namespace eval twapi {}
    proc twapi::open_clipboard {} { error "twapi is unavailable" }
    proc twapi::read_clipboard {fmt} { error "twapi is unavailable" }
    proc twapi::close_clipboard {} { return }
    proc twapi::end_process {pid args} { return }
    proc twapi::comobj {name} {
        set cmd ::twapi::obj_[clock clicks]
        proc $cmd {args} { return }
        return $cmd
    }
    package provide twapi 1.0
}

if {[catch {package require tkdnd}]} {
    namespace eval tkdnd {}
    namespace eval tkdnd::drop_target {}
    proc tkdnd::drop_target::register {w args} { return }
    package provide tkdnd 1.0
}
set do_embed_images 0;
set embedded_content_on_single_line 0;
set update_frozen 0;
set global_tagsonly 0;
set replace_existing_hyperlinks 1;
set default_font "courier 10 normal";
set disable_follow_target 0;

array set external_hyperrefs {};

array set global_all_generators {};
array set global_all_verifiers {};

array set global_verifier_tags {};#maps btn to tag
array set global_generator_tags {}; #maps btn to tag

array set global_verifier_names {}; #maps btn to verifier name
array set global_generator_names {}; #maps btn to verifier name


proc reset_metadata {} {
  global external_hyperrefs  
  global global_verifier_tags 
  global global_generator_tags
  global global_verifier_names 
  global global_generator_names 
  
  array unset external_hyperrefs
  array unset global_verifier_tags
  array unset global_generator_tags
  array unset global_verifier_names 
  array unset global_generator_names
      
  array set external_hyperrefs {};
  array set global_verifier_tags {};
  array set global_generator_tags {}
  array set global_verifier_names {}; 
  array set global_generator_names {};
}

proc add_verifier {verifier_tag verifier_proc} {
    global global_all_verifiers;
    set global_all_verifiers($verifier_tag) $verifier_proc;
}

proc add_generator {generator_tag generator_proc} {
    global global_all_generators;
    set global_all_generators($generator_tag) $generator_proc;
}



if {[info command verify_license] == ""} {
 proc verify_license {args} {return 1;}
}



proc embed_images {val} {

    global do_embed_images;
    set do_embed_images $val;

}
proc embedded_content_on_single_line {val} {
    global embedded_content_on_single_line;
    set embedded_content_on_single_line $val;
}
proc dbg {args} {
 # set fp [open "c:/temp/spectral.log" a+];
 # puts $fp $args;
 # close $fp;
}
set regroot {HKEY_CURRENT_USER\Software\tcltktools}
set installdir [info nameofexecutable];
regsub -all {\\} $installdir {/} installdir;
regsub -all {/[^/]*$} $installdir {} installdir;
if {[info command registry] != "registry" ||
    [catch {[registry set $regroot "install_privilege" "yes"]}] } {
  proc registry {subcmd root key args} {
     global installdir;
     global default_font;
     
     if {[info commands regdbconn] == "regdbconn"} {
         #do nothing
     } elseif { [file exists "$installdir/registry.db"]} {
         sqlite3 regdbconn "$installdir/registry.db";
     } else {
         sqlite3 regdbconn "$installdir/registry.db";
         regdbconn eval {create table keyvals (key text, val text)};
     }
     if {$subcmd == "set"} {
        if {[regdbconn eval "select count(*) from keyvals where key='$key'"] == 0} {
            regdbconn eval "insert into keyvals values('$key','$args')";
        } else {
            regdbconn eval "update keyvals set val='$args' where key='$key'";
        }
     } elseif {$subcmd == "get"} {
             if {$key == "spectral_installdir"} {
                  return $installdir;
             } elseif {$key == "default_font"} {
                  return $default_font;
             } else {
                  return [lindex [lindex [regdbconn eval "select val from keyvals where key='$key'"] 0] 0];
             }
     } 
     return "";
  }
}
set allResultWindows {};
set viewpoints {};
set _viewpointPosition 0;
set _historyPosition 0;
set old_dump {}
set old_dump_pos 1.0;
set old_mode default;
set stay_in_quick_command 0;
set title_prefix "";
set action_on_dnd "edit"; 
set isWindowsExecutable 0;
if {$tcl_platform(platform) == "windows" && [regexp "spectral.exe$" [info nameofexecutable]] } {set isWindowsExecutable 1;}


if {$isWindowsExecutable} { set installdir [info nameofexecutable] } else { set installdir [info script];}
if {$installdir ne ""} {
    set installdir [file dirname [file normalize $installdir]]
}
regsub -all {\\} $installdir {/} installdir

if { [catch {[registry set $regroot "install_privilege" "yes"]}]} {
   rename registry 33de5b5a-4f48-4c5a-a210-0464cd0bc952;
   proc registry {subcmd root key args} {
     global installdir;
     global default_font;
     if {[info commands regdbconn] == "regdbconn"} {
         #do nothing
     } elseif { [file exists "$installdir/registry.db"]} {
         sqlite3 regdbconn "$installdir/registry.db";
     } else {
         sqlite3 regdbconn "$installdir/registry.db";
         regdbconn eval {create table keyvals (key text, val text)};
     }
     if {$subcmd == "set"} {
        if {[regdbconn eval "select count(*) from keyvals where key='$key'"] == 0} {
            regdbconn eval "insert into keyvals values('$key','$args')";
        } else {
            regdbconn eval "update keyvals set val='$args' where key='$key'";
        }
     } elseif {$subcmd == "get"} {
             if {$key == "spectral_installdir"} {
               return $installdir;
             } elseif {$key == "default_font"} {
                  return $default_font;
             } else {
                  return [lindex [lindex [regdbconn eval "select val from keyvals where key='$key'"] 0] 0];
             }
     } 
     return "";
  }
}

proc isWindowsExecutable {} {
    global isWindowsExecutable;
    return $isWindowsExecutable;
} 
set installdir  [registry get $regroot spectral_installdir]
set splashimagefile $installdir/wbin/splashimage.png;
set current_keywords {};
set spectral_subfolder ".spectral"

proc set_spectral_subfolder {name} {
    global spectral_subfolder;
    set spectral_subfolder $name;
}
if {[info commands "console"] == "console"} {

rename console b8b0ed12-2b01-4901-b033-61a4cf671b5a;
}

rename update 4571077a-e0ea-11e6-bf01-fe55135034f3;

proc update {args} {
  global update_frozen;
  if {$update_frozen}  {
    
  } else {
     4571077a-e0ea-11e6-bf01-fe55135034f3 {*}$args; 
  }
}

set qcInterp [interp create];

catch { destroy .splash errorswindow }
set splash [ toplevel .splash ]
wm  withdraw  .
wm  title  $::splash  "spectral"
wm  overrideredirect  $::splash  1
wm  geometry  $::splash  "+200+200"
set splashImage [image create photo -file $splashimagefile]
set ::splashMessage "Spectral Editor"
label $::splash.image -image $splashImage  -fg #000000 -bg white 
label $::splash.text -text "All Rights Reserved" -font "Calibri 12" -fg #000000 -bg white 
bind $::splash <Escape> {
    catch { destroy .splash errorswindow }
}
pack $::splash.image -side top -fill x
pack $::splash.text -side top -fill x


#wm attributes $::splash -topmost 1;

update;
update;


set tmpdir $installdir;
catch {package require Thread}
set cursor_pos "1.0";
set view_top "1.0";
set tab_inserts "    ";
set current_file "";
set file_lastmod "";
set saving 0;
set highlight_colors {};
set autosyn_mode 0;
set cmd_to_editor 1;
set default_highlight "";
set modified 0;
set default_background white;
set default_foreground black;
catch { set default_font [registry get $regroot default_font]};
#catch { set default_background [registry get $regroot default_background]};
#catch { set default_foreground [registry get $regroot default_foreground]};

rename exit jaao;
proc exit {} {
   confirmAndExit
}
proc really_exit {} {
    jaao;
}
proc confirmAndExit {} {
    global modified;
    focus .
    set msg "";
    global current_file;
    if {$modified} {
        set msg "Content Modified! ";
    }
    append msg "Do you really want to quit?";
    append msg "\nFile:";
    append msg $current_file;
    

    set result [tk_messageBox -title "Confirm exit" -message $msg -icon question -type yesno];
    if {$result == yes} {
        if { [catch doSaveWhileExiting exception_msg ]  } {
          tk_messageBox -message $exception_msg;
          jaao;
      }
    }
      
 }
 
 proc doSaveWhileExiting {} {
        global modified;
        global regroot;
        global default_font;
        global default_background;
        global default_foreground;
        global new_loggedcommands;
        global new_recentfiles;
        global recentfonts;
        global new_recentfonts;
     
        registry set $regroot search1   [.searchFrame.search1 get];
        registry set $regroot search2   [.searchFrame.search2 get];
        registry set $regroot search3   [.searchFrame.search3 get];
        registry set $regroot search4   [.searchFrame.search4 get];
        registry set $regroot search5   [.searchFrame.search5 get]; 
        registry set $regroot search6   [.searchFrame.search6 get]; 
        registry set $regroot default_font  [set default_font]; 
        registry set $regroot default_background  [set default_background]; 
        registry set $regroot default_foreground  [set default_foreground];         
        registry set $regroot replace   [.bottomFrame.replace get]
        registry set $regroot with      [.bottomFrame.with get]
        registry set $regroot init      [.bottomFrame.init get]
        registry set $regroot incr      [.bottomFrame.incr get]
        registry set $regroot subst     [.bottomFrame.subst get]
        registry set $regroot expr      [.bottomFrame.expr get]
        registry set $regroot enforceLC   [.bottomFrame.enforceLC get]
        registry set $regroot enforceRC   [.bottomFrame.enforceRC get]
        registry set $regroot pwd   [pwd]
        if {$modified} {
            checkForSave;
        }

        catch {
             global tmpdir;
             global regroot;
             set dbname "";
            
             catch { set dbname [registry get $regroot dbname]};
             if {$dbname == ""} { set dbname "history.db"; }
             if { [file exists "$tmpdir/$dbname"]} {
               sqlite3 dbcon "$tmpdir/$dbname";
             }
        }

        catch {
            foreach lc $new_loggedcommands {
              dbcon eval "insert into commands values('$lc')";
            }
        } 

        catch {
            foreach rf $new_recentfiles {
              dbcon eval "insert into recentfiles values('$rf')";
            }
        }
        catch { 
         foreach rf $new_recentfonts {
           dbcon eval "insert into recentfonts values('$rf')";
          }
        }
        
        
        catch {
            dbcon close;
        }

        jaao;
      
 }

set clipboard_to_file_script {
 package require Tk
 package require twapi
 wm withdraw .
 # Copy the contents of the Windows clipboard into a photo image.
 # Return the photo image identifier.
 proc Clipboard2Img {outfile} {
     twapi::open_clipboard

     # Assume clipboard content is in format 8 (CF_DIB)
     set retVal [catch {twapi::read_clipboard 8} clipData]
     if { $retVal != 0 } {
         error "Invalid or no content in clipboard"
     }

     # First parse the bitmap data to collect header information
     binary scan $clipData "iiissiiiiii" \
            size width height planes bitcount compression sizeimage \
            xpelspermeter ypelspermeter clrused clrimportant

     # We only handle BITMAPINFOHEADER right now (size must be 40)
     if {$size != 40} {
         error "Unsupported bitmap format. Header size=$size"
     }

     # We need to figure out the offset to the actual bitmap data
     # from the start of the file header. For this we need to know the
     # size of the color table which directly follows the BITMAPINFOHEADER
     if {$bitcount == 0} {
         error "Unsupported format: implicit JPEG or PNG"
     } elseif {$bitcount == 1} {
         set color_table_size 2
     } elseif {$bitcount == 4} {
         # TBD - Not sure if this is the size or the max size
         set color_table_size 16
     } elseif {$bitcount == 8} {
         # TBD - Not sure if this is the size or the max size
         set color_table_size 256
     } elseif {$bitcount == 16 || $bitcount == 32} {
         if {$compression == 0} {
             # BI_RGB
             set color_table_size $clrused
         } elseif {$compression == 3} {
             # BI_BITFIELDS
             set color_table_size 3
         } else {
             error "Unsupported compression type '$compression' for bitcount value $bitcount"
         }
     } elseif {$bitcount == 24} {
         set color_table_size $clrused
     } else {
         error "Unsupported value '$bitcount' in bitmap bitcount field"
     }
     

     set phImg [image create photo]
     set filehdr_size 14                 ; # sizeof(BITMAPFILEHEADER)
     set bitmap_file_offset [expr {$filehdr_size+$size+($color_table_size*4)}]
     set filehdr [binary format "a2 i x2 x2 i" \
                  "BM" [expr {$filehdr_size + [string length $clipData]}] \
                  $bitmap_file_offset]

     append filehdr $clipData;

     # $phImg put $filehdr -format bmp
     
     set bmpfile [open $outfile w];
      fconfigure $bmpfile -translation binary
     puts -nonewline $bmpfile $filehdr
     close $bmpfile
     twapi::close_clipboard
     return $phImg
 }


catch {
 Clipboard2Img [lindex $argv 0];
 }

exit;
}
set recorder_script {
package require Tk
package require twapi
wm withdraw .

set dir [lindex $argv 0];
cd $dir;
wm iconbitmap . -default $dir/bm0.ico
wm  overrideredirect  .  1
wm attributes . -topmost 1;
    set x [winfo pointerx .];
     set y [winfo pointery .];
     set x [expr max(100, $x-100)];
     set y [expr max(100, $y-100)];
    wm geometry . "+$x+$y";



set fname [lindex $argv 1];
set cmd "|./sox.exe -t waveaudio -d $fname";
set fp [open $cmd "r"];
set apid [pid $fp];

set waited_enough 0;
after 5000 {
    set waited_enough 1;
}
while {![file exists $fname]} {
    if {$waited_enough} {
        break;
    }
}

button .b -text "Stop Recording" -command {
    catch {
       twapi::end_process $apid -force;
    }
    
    exit;

} -background "#5cb85c" -font {Consolas 14 bold} -foreground white


bind .b <Enter> {%W configure -bg "#449d44"}
bind .b <Leave> {%W configure -bg "#5cb85c"} 

bind . <Escape> { 
    catch {
       twapi::end_process $apid -force;
    }
    
    exit;
}


pack .b -side top -fill x;
wm deiconify .
focus .b;
update;
update;
}
if {$isWindowsExecutable} { set licfile [info nameofexecutable] } else { set licfile [info script];}
regsub -all {\\} $licfile {/} licfile;
regsub -all {/[^/]*$} $licfile {/license.txt} licfile;
if {![file exists $licfile]} {
   wm withdraw . 
   set yesno [tk_messageBox -message "License not found. Continue evaluation?" -icon question -type yesno -title "Spectral Editor"];
       if {$yesno == yes} {
       } else {
           jaao;
       }
   
}
set username "nobody";
if {[catch {
set fplic [open $licfile r];
set liccont [read $fplic];
close $fplic;
set liccont [split $liccont "\n"];
set username [string trim [lindex $liccont 0]];
set lic_username $username;
append lic_username $license_version;
set key [string trim [lindex $liccont 1]];
if {![verify_license $lic_username $key]} {
     error "License invalid";
}

}]} {
    if {![verify_license nobody evaluation]}  {
      wm withdraw . 
      tk_messageBox -message "Evaluation has expired. Sorry." -title "Spectral Editor";
      jaao;
  }
}

::$splash.text configure -text "This product is licensed to $username"  -font "Calibri 12" -fg #000000 -bg white ;
update;

# The following block is used in freewrap mode of execution
catch {
    set tmpdir [pwd]
    if {[file exists "/tmp"]} {set tmpdir "/tmp"}
    catch {set tmpdir $::env(TRASH_FOLDER)} ;# very old Macintosh. Mac OS X doesn't have this.
    catch {set tmpdir $::env(TMP)}
    catch {set tmpdir $::env(TEMP)}
    #puts stderr "TEMP folder is $tmpdir";
    append env(PATH) ";" "$installdir\\wbin"
    regsub -all {\\} $tmpdir {/} tmpdir
    
} msg;
#puts stderr $msg;
::$splash.text configure -text "This product is licensed to $username"  -font "Calibri 12" -fg #000000 -bg white ;
update;
update
catch {
  source "$installdir/config.cfg"
} msg;

#puts stderr $msg;
set iwidgets_loaded 0;


array set last_search {}

# The following catch block is for script mode
catch {
    package require Iwidgets ;
    set iwidgets_loaded 1;   
} msg;
#puts stderr $msg;

if {!$iwidgets_loaded} {
    catch {
        lappend auto_path "$installdir/incrTcl/iwidgets4.1/";
        lappend auto_path "$installdir/incrTcl/iwidgets4.1/scripts"
    }
}

catch { package require Iwidgets; }
if {[catch {package require Iwidgets}]} {
    set ::spectral_has_real_iwidgets 0
    namespace eval itcl {}
    proc itcl::body {args} { return }
    namespace eval iwidgets {
        variable kind
        variable cmd
        variable bg
        variable base
        array set kind {}
        array set cmd {}
        array set bg {}
        array set base {}
    }

    proc iwidgets::_subwidget {w which} {
        switch -- $which {
            entry { set suffix ".e" }
            label { set suffix ".l" }
            list { return "${w}.__popup.lb" }
            text { set suffix ".t" }
            vscroll { set suffix ".v" }
            hscroll { set suffix ".h" }
            default { set suffix ".${which}" }
        }
        foreach c [info commands ${w}*] {
            if {[string match "*${suffix}" $c]} {
                return $c
            }
        }
        return "${w}${suffix}"
    }

    proc iwidgets::_entryfield_layout {w labelpos} {
        set lbl [iwidgets::_subwidget $w label]
        set ent [iwidgets::_subwidget $w entry]
        if {$labelpos eq "n"} {
            pack $lbl -side top -anchor w
            pack $ent -side top -fill x -expand 1
        } else {
            pack $lbl -side left -anchor w
            pack $ent -side left -fill x -expand 1
        }
    }
    proc iwidgets::_ensure_entryfield_list {w} {
        set pop ${w}.__popup
        set lb ${w}.__popup.lb
        if {![winfo exists $pop]} {
            toplevel $pop
            wm withdraw $pop
            wm overrideredirect $pop 1
            listbox $lb -height 8 -exportselection 0
            pack $lb -fill both -expand 1
        }
        return $lb
    }
    proc iwidgets::_entryfield_cmd {w args} {
        variable base
        if {[llength $args] == 0} { return }
        set sub [lindex $args 0]
        set rest [lrange $args 1 end]
        set ent [iwidgets::_subwidget $w entry]
        set lbl [iwidgets::_subwidget $w label]
        switch -- $sub {
            component {
                set c [lindex $rest 0]
                if {$c eq "entry"} {
                    set cw $ent
                } elseif {$c eq "label"} {
                    set cw $lbl
                } elseif {$c eq "list"} {
                    set cw [iwidgets::_ensure_entryfield_list $w]
                } else {
                    set cw [iwidgets::_subwidget $w $c]
                }
                if {[llength $rest] > 1} {
                    return [$cw {*}[lrange $rest 1 end]]
                }
                return $cw
            }
            clear { $ent delete 0 end; return }
            get { return [$ent get] }
            insert { return [$ent insert {*}$rest] }
            delete { return [$ent delete {*}$rest] }
            configure {
                if {[llength $rest] == 0} { return [$ent configure] }
                catch { $ent configure {*}$rest }
                catch { $lbl configure {*}$rest }
                catch { [set base($w)] configure {*}$rest }
                return
            }
            cget {
                if {[llength $rest] == 0} { return "" }
                set opt [lindex $rest 0]
                if {[catch {$ent cget $opt} v]} { return [[set base($w)] cget $opt] }
                return $v
            }
            default { return [$ent $sub {*}$rest] }
        }
    }
    proc iwidgets::entryfield {w args} {
        variable base
        array set o {-labeltext "" -labelpos w -command "" -width 20 -foreground "" -insertbackground "" -background "" -textbackground "" -labelfont ""}
        array set o $args
        frame $w
        label $w.l -text $o(-labeltext)
        entry $w.e -width $o(-width)
        if {$o(-foreground) ne ""} { $w.e configure -foreground $o(-foreground) }
        if {$o(-insertbackground) ne ""} { $w.e configure -insertbackground $o(-insertbackground) }
        if {$o(-textbackground) ne ""} { $w.e configure -background $o(-textbackground) }
        if {$o(-background) ne ""} {
            catch { $w configure -background $o(-background) }
            catch { $w.l configure -background $o(-background) }
            catch { $w.e configure -background $o(-background) }
        }
        if {$o(-labelfont) ne ""} { catch {$w.l configure -font $o(-labelfont)} }
        iwidgets::_entryfield_layout $w $o(-labelpos)
        if {$o(-command) ne ""} { bind [iwidgets::_subwidget $w entry] <Return> $o(-command) }
        set base($w) ${w}.__base
        rename $w [set base($w)]
        interp alias {} $w {} iwidgets::_entryfield_cmd $w
        return $w
    }

    proc iwidgets::_combobox_cmd {w args} {
        variable cmd
        variable base
        if {[llength $args] == 0} { return }
        set sub [lindex $args 0]
        set rest [lrange $args 1 end]
        set ent [iwidgets::_subwidget $w entry]
        set lbl [iwidgets::_subwidget $w label]
        set lbx [iwidgets::_subwidget $w list]
        switch -- $sub {
            component {
                set c [lindex $rest 0]
                if {$c eq "entry"} { set cw $ent } elseif {$c eq "label"} { set cw $lbl } elseif {$c eq "list"} { set cw $lbx } else { set cw "" }
                if {$cw eq ""} { return "" }
                if {[llength $rest] > 1} {
                    return [$cw {*}[lrange $rest 1 end]]
                }
                return $cw
            }
            getcurselection {
                set sel [$lbx curselection]
                if {[llength $sel] == 0} { return [$ent get] }
                return [$lbx get [lindex $sel 0]]
            }
            insert { return [$lbx insert {*}$rest] }
            delete { return [$lbx delete {*}$rest] }
            clear {
                catch {$lbx delete 0 end}
                catch {$ent delete 0 end}
                return
            }
            configure {
                catch {[set base($w)] configure {*}$rest}
                catch {$lbl configure {*}$rest}
                catch {$ent configure {*}$rest}
                return
            }
            cget {
                if {[catch {$ent cget [lindex $rest 0]} v]} { return [[set base($w)] cget [lindex $rest 0]] }
                return $v
            }
            default { return [$ent $sub {*}$rest] }
        }
    }
    proc iwidgets::combobox {w args} {
        variable cmd
        variable base
        array set o {-labeltext "" -labelpos w -width 20 -foreground "" -insertbackground "" -background "" -selectioncommand ""}
        array set o $args
        frame $w
        label $w.l -text $o(-labeltext)
        entry $w.e -width $o(-width)
        button $w.b -text "v" -width 2 -padx 0 -pady 0 -relief flat -highlightthickness 0 -command [list iwidgets::_toggle_combo_popup $w]
        toplevel ${w}.__popup
        wm withdraw ${w}.__popup
        wm overrideredirect ${w}.__popup 1
        listbox ${w}.__popup.lb -height 8 -exportselection 0
        pack ${w}.__popup.lb -fill both -expand 1
        catch {$w.b configure -font [$w.e cget -font]}
        if {$o(-foreground) ne ""} { $w.e configure -foreground $o(-foreground) }
        if {$o(-insertbackground) ne ""} { $w.e configure -insertbackground $o(-insertbackground) }
        if {$o(-background) ne ""} {
            catch { $w configure -background $o(-background) }
            catch { $w.l configure -background $o(-background) }
            catch { $w.e configure -background $o(-background) }
        }
        frame $w.ea
        if {$o(-labelpos) eq "n"} {
            pack $w.l -side top -anchor w
            pack $w.ea -side top -fill x -expand 1
        } else {
            pack $w.l -side left -anchor w
            pack $w.ea -side left -fill x -expand 1
        }
        pack $w.e -in $w.ea -side left -fill x -expand 1
        pack $w.b -in $w.ea -side right
        set cmd($w) $o(-selectioncommand)
        bind ${w}.__popup.lb <<ListboxSelect>> [list iwidgets::_invoke_combo_selection $w]
        bind ${w}.__popup.lb <Escape> [list wm withdraw ${w}.__popup]
        bind ${w}.__popup <FocusOut> [list wm withdraw ${w}.__popup]
        bind $w.e <Return> [list iwidgets::_invoke_combo_selection $w]
        set base($w) ${w}.__base
        rename $w [set base($w)]
        interp alias {} $w {} iwidgets::_combobox_cmd $w
        return $w
    }
    proc iwidgets::_invoke_combo_selection {w} {
        variable cmd
        set lbx [iwidgets::_subwidget $w list]
        set ent [iwidgets::_subwidget $w entry]
        if {[winfo exists $lbx]} {
            set sel [$lbx curselection]
            if {[llength $sel] > 0} {
                set val [$lbx get [lindex $sel 0]]
                catch {$ent delete 0 end}
                catch {$ent insert end $val}
            }
        }
        if {[info exists cmd($w)] && $cmd($w) ne ""} { uplevel #0 $cmd($w) }
        catch {wm withdraw ${w}.__popup}
    }
    proc iwidgets::_toggle_combo_popup {w} {
        set pop ${w}.__popup
        set lb ${w}.__popup.lb
        set ent [iwidgets::_subwidget $w entry]
        if {![winfo exists $pop]} { return }
        if {[winfo viewable $pop]} {
            wm withdraw $pop
            return
        }
        set x [winfo rootx $ent]
        set y [expr {[winfo rooty $ent] + [winfo height $ent]}]
        set width [$ent cget -width]
        if {$width < 10} { set width 20 }
        $lb configure -width $width
        wm geometry $pop "+$x+$y"
        wm deiconify $pop
        focus $lb
    }

    proc iwidgets::_scrolledtext_cmd {w args} {
        variable base
        if {[llength $args] == 0} { return }
        set sub [lindex $args 0]
        set rest [lrange $args 1 end]
        set txt [iwidgets::_subwidget $w text]
        set lbl [iwidgets::_subwidget $w label]
        switch -- $sub {
            import {
                if {[llength $rest] == 0} { return }
                if {[lindex $rest 0] eq "-link"} {
                    set rest [lrange $rest 1 end]
                }
                set fname [lindex $rest 0]
                if {$fname eq ""} { return }
                if {![file exists $fname]} { return }
                set fp [open $fname r]
                set data [read $fp]
                close $fp
                regsub -all {<[^>]*>} $data "" data
                regsub -all {&nbsp;} $data " " data
                regsub -all {&lt;} $data "<" data
                regsub -all {&gt;} $data ">" data
                regsub -all {&amp;} $data "&" data
                $txt delete 1.0 end
                $txt insert end $data
                return
            }
            component {
                set c [lindex $rest 0]
                if {$c eq "label"} { set cw $lbl } elseif {$c eq "text"} { set cw $txt } else { set cw "" }
                if {$cw eq ""} { return "" }
                if {[llength $rest] > 1} {
                    return [$cw {*}[lrange $rest 1 end]]
                }
                return $cw
            }
            configure {
                if {[llength $rest] == 0} { return [$txt configure] }
                catch {$txt configure {*}$rest}
                catch {$lbl configure {*}$rest}
                catch {[set base($w)] configure {*}$rest}
                return
            }
            cget {
                if {[catch {$txt cget [lindex $rest 0]} v]} { return [[set base($w)] cget [lindex $rest 0]] }
                return $v
            }
            default { return [$txt $sub {*}$rest] }
        }
    }
    proc iwidgets::scrolledtext {w args} {
        variable base
        array set o {-labeltext "" -labelpos n -wrap word -width 80 -height 24 -textbackground "" -background ""}
        array set o $args
        set tw $o(-width)
        set th $o(-height)
        if {![string is integer -strict $tw]} { set tw 80 }
        if {![string is integer -strict $th]} { set th 24 }
        # Legacy iwidgets code often passes pixel-like sizes (e.g. 400x400).
        # Convert those to sensible text rows/cols for plain Tk text widgets.
        if {$tw > 200} {
            set tw [expr {int($tw / 8)}]
        }
        if {$th > 100} {
            set th [expr {int($th / 16)}]
        }
        if {$tw < 20} { set tw 20 }
        if {$th < 6} { set th 6 }
        frame $w
        label $w.l -text $o(-labeltext)
        text $w.t -wrap $o(-wrap) -width $tw -height $th
        scrollbar $w.v -orient vertical -command [list $w.t yview]
        scrollbar $w.h -orient horizontal -command [list $w.t xview]
        $w.t configure -yscrollcommand [list $w.v set] -xscrollcommand [list $w.h set]
        if {$o(-textbackground) ne ""} { catch {$w.t configure -background $o(-textbackground)} }
        if {$o(-background) ne ""} {
            catch {$w configure -background $o(-background)}
            catch {$w.l configure -background $o(-background)}
        }
        if {$o(-labelpos) eq "n"} {
            pack $w.l -side top -fill x
        } else {
            pack $w.l -side left
        }
        pack $w.v -side right -fill y
        pack $w.h -side bottom -fill x
        pack $w.t -side left -fill both -expand 1
        set base($w) ${w}.__base
        rename $w [set base($w)]
        interp alias {} $w {} iwidgets::_scrolledtext_cmd $w
        return $w
    }
    proc iwidgets::scrolledhtml {w args} {
        array set o {-fontname "" -linkcommand ""}
        set passthru {}
        foreach {k v} $args {
            if {$k eq "-fontname"} {
                set o(-fontname) $v
            } elseif {$k eq "-linkcommand"} {
                set o(-linkcommand) $v
            } else {
                lappend passthru $k $v
            }
        }
        set w [iwidgets::scrolledtext $w {*}$passthru]
        if {$o(-fontname) ne ""} { catch {[$w component text] configure -font $o(-fontname)} }
        return $w
    }

    package provide Iwidgets 4.1
}

if {[catch {package require ctext}]} {
    set ::spectral_has_real_ctext 0
    namespace eval ctext {}
    namespace eval ctext {
        variable classes
        array set classes {}
    }
    proc ctext::_yscroll_proxy {w orig first last} {
        if {$orig ne ""} {
            uplevel #0 [linsert $orig end $first $last]
        }
        catch {$w.l yview moveto $first}
        catch {ctext::linemapUpdate $w}
    }
    proc ctext::_bind_linemap_updates {w} {
        set t $w.t
        bind $w.l <KeyPress> {break}
        bind $w.l <ButtonPress-1> {break}
        bind $t <KeyRelease> [list catch {ctext::update $w}]
        bind $t <ButtonRelease-1> [list catch {ctext::update $w}]
        bind $t <MouseWheel> [list catch {ctext::linemapUpdate $w}]
        bind $t <Configure> [list catch {ctext::linemapUpdate $w}]
    }
    proc ctext {w args} {
        frame $w
        text $w.t {*}$args
        text $w.l -width 6 -state normal -wrap none -background #eeeeee -foreground #444444 -takefocus 0 -cursor arrow
        interp alias {} $w._t {} $w.t
        set orig_ys [$w.t cget -yscrollcommand]
        $w.t configure -yscrollcommand [list ctext::_yscroll_proxy $w $orig_ys]
        pack $w.l -side left -fill y
        pack $w.t -side left -fill both -expand 1
        set tags [bindtags $w.t]
        if {[lsearch -exact $tags $w] < 0} {
            bindtags $w.t [linsert $tags 1 $w]
        }
        ctext::_bind_linemap_updates $w
        after 1 [list catch {ctext::update $w}]
        rename $w ${w}.__base
        interp alias {} $w {} ctext::_cmd $w
        return $w
    }
    proc ctext::_escape_regex_list {lst} {
        set out {}
        foreach w $lst {
            set w [regsub -all {([][(){}.^$*+?|\\])} $w {\\\1}]
            lappend out $w
        }
        return $out
    }
    proc ctext::_apply_highlights {w} {
        variable classes
        if {![info exists classes($w)]} { return }
        set t $w.t
        set txt [$t get 1.0 end-1c]
        foreach classrec $classes($w) {
            lassign $classrec tag color regex
            catch {$t tag remove $tag 1.0 end}
            if {$regex eq ""} { continue }
            set idxs {}
            if {[catch {regexp -all -indices -- $regex $txt idxs}]} { continue }
            foreach pair $idxs {
                if {[llength $pair] != 2} { continue }
                lassign $pair s e
                set start [expr {$s}]
                set end [expr {$e + 1}]
                $t tag add $tag "1.0 + $start chars" "1.0 + $end chars"
            }
        }
    }
    proc ctext::_cmd {w args} {
        if {[llength $args] == 0} { return }
        set sub [lindex $args 0]
        if {$sub eq "fastinsert"} {
            set res [$w.t insert {*}[lrange $args 1 end]]
            catch {ctext::linemapUpdate $w}
            catch {ctext::_apply_highlights $w}
            return $res
        }
        if {$sub eq "fastdelete"} {
            set res [$w.t delete {*}[lrange $args 1 end]]
            catch {ctext::linemapUpdate $w}
            catch {ctext::_apply_highlights $w}
            return $res
        }
        return [uplevel 1 [list $w.t {*}$args]]
    }
    proc ctext::addHighlightClassForRegexp {w tag color regex} {
        variable classes
        lappend classes($w) [list $tag $color $regex]
        catch {$w.t tag configure $tag -foreground $color}
        catch {ctext::_apply_highlights $w}
    }
    proc ctext::addHighlightClass {w tag color keywords} {
        set esc [ctext::_escape_regex_list $keywords]
        if {[llength $esc] == 0} { return }
        set regex "\\m(?:[join $esc {|}])\\M"
        ctext::addHighlightClassForRegexp $w $tag $color $regex
    }
    proc ctext::addHighlightClassForSpecialChars {w tag color chars} {
        ctext::addHighlightClassForRegexp $w $tag $color $chars
    }
    proc ctext::enableComments {args} { return }
    proc ctext::comments {args} { return }
    proc ctext::getAr {args} { upvar [lindex $args end] ar; array set ar {}; return }
    proc ctext::update {w} {
        catch {ctext::linemapUpdate $w}
        catch {ctext::_apply_highlights $w}
    }
    proc ctext::linemapUpdate {w} {
        if {![winfo exists $w.l]} { return }
        set t $w.t
        set first [$t index @0,0]
        set last [$t index @0,[winfo height $t]]
        set firstLine [lindex [split $first .] 0]
        set lastLine [lindex [split $last .] 0]
        if {$lastLine < $firstLine} { set lastLine $firstLine }
        set maxLine [lindex [split [$t index end-1c] .] 0]
        set digits [string length $maxLine]
        if {$digits < 3} { set digits 3 }
        catch {$w.l configure -width [expr {$digits + 1}]}
        $w.l configure -state normal
        $w.l delete 1.0 end
        for {set i $firstLine} {$i <= $lastLine} {incr i} {
            $w.l insert end [format "%*d\n" $digits $i]
        }
        $w.l configure -state disabled
    }
    proc ctext::linemapUpdateOffset {w} { ctext::linemapUpdate $w }
    package provide ctext 1.0
}

set text_editor {notepad.exe};


 proc K { x y } { set x }
 proc lremove { listvar string } {
         upvar $listvar in
         foreach item [K $in [set in [list]]] {
                 if {[string equal $item $string]} { continue }
                 lappend in $item
         }
 }

 proc lremove_regex { listvar string } {
         upvar $listvar in
         foreach item [K $in [set in [list]]] {
                 if {[regexp $string $item ]} { continue }
                 lappend in $item
         }
 }

set textheight 40
# Globals controlled by checkboxes
set case_sensitive 0;
set multiword_mode 0;
set hyphenated_word_mode 0;
set remove_previous 0;
set use_regex 1;
set sel_only 0;
set eval_expr 0;

proc setCTextPropertiesMainWindow {widget keywords} {
    $widget tag configure attention -background #5555ce
    ::ctext::enableComments $widget
    ctext::addHighlightClassForRegexp $widget numbers #3aa905  {[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?}
    ctext::addHighlightClass $widget keyword red $keywords 
    ctext::addHighlightClassForSpecialChars $widget brackets #2b7d35 {[]{}()<>=+-*;^%$!}
    ctext::addHighlightClassForRegexp $widget strings blue {"([^"\\]*(\\.[^"\\]*)*)"|\'([^\'\\]*(\\.[^\'\\]*)*)\'}; 
    ctext::addHighlightClassForRegexp $widget singleLineComment #44616a {//.*$};
    ctext::addHighlightClassForRegexp $widget preproc #44616a {^[:blank]*#.*((\\\n.*)?)*}
    ::ctext::comments $widget 
    $widget tag configure _cComment -foreground #44616a
}

set regroot {HKEY_CURRENT_USER\Software\tcltktools}
proc search_source {file_name} {
    global env;
    if {[info exists env(path)]}  {
    
        set exec_path [set env(path)];
        regsub -all ";" $exec_path " " exec_path;
        regsub -all "\\\\" $exec_path {/} exec_path;
            foreach apath $exec_path {
            if { [file exists "$apath/$file_name"] } {
                catch {uplevel #0 "source \"$apath/$file_name\""};
                return;
            }
        }    
    }
    #puts stderr "$file_name was not found in path";
}


frame .topFrame  -background white
frame .bottomFrame -background white
frame .searchFrame -background white

. configure -background white;


iwidgets::entryfield .bottomFrame.position -labeltext "pos:" -labelpos w -command  {catch {
    set currentValue [[.bottomFrame.position component entry] get]
    set lineNum [lindex [split $currentValue .] 0];
    sel $lineNum $lineNum;
    change_yview [expr $currentValue -2];
    };
    } -width 8   -foreground #101010 -insertbackground blue
iwidgets::entryfield .bottomFrame.replace -labeltext "replace:" -labelpos w -command  {} -width 20   -foreground #101010 -insertbackground blue
iwidgets::entryfield .bottomFrame.with -labeltext "with:" -labelpos w -command  {doReplacement} -width 35   -foreground #101010 -insertbackground blue
iwidgets::entryfield .bottomFrame.init -labeltext "init:" -labelpos w -command  {doReplacement} -width 10   -foreground #101010 -insertbackground blue
iwidgets::entryfield .bottomFrame.incr -labeltext "incr:" -labelpos w -command  {doReplacement} -width 10   -foreground #101010 -insertbackground blue
iwidgets::entryfield .bottomFrame.subst -labeltext "rewrite:" -labelpos w -command  {doReplacement} -width 10   -foreground #101010 -insertbackground blue
iwidgets::entryfield .bottomFrame.expr -labeltext "as:" -labelpos w -command  {doReplacement} -width 10   -foreground #101010 -insertbackground blue;
iwidgets::entryfield .bottomFrame.enforceLC -labeltext "left:" -labelpos w -command  {doReplacement} -width 20   -foreground #101010 -insertbackground blue;
iwidgets::entryfield .bottomFrame.enforceRC -labeltext "right:" -labelpos w -command  {doReplacement} -width 20   -foreground #101010 -insertbackground blue;
label .bottomFrame.toppos -text "";

pack .bottomFrame.replace -side left
pack .bottomFrame.with -side left
pack .bottomFrame.init -side left
pack .bottomFrame.incr -side left
pack .bottomFrame.subst -side left
pack .bottomFrame.expr -side left
pack .bottomFrame.enforceLC -side left
pack .bottomFrame.enforceRC -side left

pack .bottomFrame.toppos -side right;
pack .bottomFrame.position -side right;

proc checkForSave {} {
   global modified;
   global current_file;

   if {$modified} {
       focus .
       set msg "Save Modifications?"
       if {$current_file != ""} {
           append msg "\nFile:" $current_file;
       }
       set result [tk_messageBox -title "Save Modifications?" -message $msg -icon question -type yesno];
       if {$result == yes} { 
         saveFile .t 
         set modified 0;
         updateModifiedStatus;
       }
   } 
}


set menu [menu .menu]
. configure -menu $menu    
$menu add cascade -label "File" -menu [menu $menu.file  -tearoff 0]
$menu.file add command -label "Open" -command "openFile .t"
$menu.file add command -label "Close (Ctrl+l)" -command "edit:close"
$menu.file add command -label "Save (Ctrl+s)" -command "saveFile .t"
$menu.file add command -label "Save As" -command "saveFileAs .t"
$menu.file add command -label "Export Html" -command "saveToHtmlFileWithoutMediaIndex .t"
$menu.file add command -label "Export Html with Media Index" -command "saveToHtmlFileWithMediaIndex .t"
$menu.file add command -label "Export Walkthrough Html" -command "saveWalkthrough .t"
$menu.file add command -label "Export Embeddable Walkthrough Html" -command "saveWalkthroughEmbeddable .t"
$menu.file add command -label "Export Walkthrough Zip" -command "saveWalkthroughZip"
$menu.file add command -label "Export Commentable Html" -command "saveToCommentableHtmlFile .t"
$menu.file add command -label "Export Embeddable Html" -command "saveToEmbeddableHtmlFile .t"
$menu.file add command -label "Export Zip" -command "saveSelfContainedZip .t"
$menu.file add command -label "Print" -command "printEditorContents .t"

#$menu.file add command -label "Load STXT File" -command "loadFromFile .t"
#$menu.file add command -label "Save STXT File" -command "saveToFile .t"
$menu.file add command -label "Load HLT File" -command "loadFromHltFile .t"
$menu.file add command -label "Save HLT File" -command "saveToHltFile .t"
$menu.file add command -label "Merge Text" -command "mergeWithFile"
$menu.file add command -label "Exit" -command "exit"

$menu add cascade -label "Edit" -menu [menu $menu.edit -tearoff 0]  
$menu.edit add command -label "Select All (Ctrl+a)" -command ".t tag add sel 1.0 end"
$menu.edit add command -label "Copy (Ctrl+c)" -command "copySelection .t"
$menu.edit add command -label "Cut (Ctrl+x)" -command "copySelection .t cut"
$menu.edit add command -label "Paste (Ctrl+v)" -command "multi_paste;"
$menu.edit add command -label "Trim" -command "trimSelection"
$menu.edit add command -label "Trim Left" -command "trimSelectionLeft"
$menu.edit add command -label "Trim Right" -command "trimSelectionRight"
$menu.edit add command -label "Format As Table" -command "formatAsTable .t"
$menu.edit add command -label "Copy To Html Clipboard" -command "copyToHtmlClipboard .t"
$menu.edit add command -label "Copy To Spectral" -command "copyToSpectral"
$menu.edit add command -label "Paste From Spectral" -command "pasteFromSpectral"
$menu.edit add command -label "Clear Selected Highlighting" -command "clearHighlights 1"
$menu.edit add command -label "Clear All Highlighting" -command "clearHighlights 0"
$menu.edit add command -label "Undo (Ctrl+z)" -command ".t edit undo; incr sepdepth -1;"
$menu.edit add command -label "Redo (Ctrl+y)" -command ".t edit redo; incr sepdepth;"
$menu.edit add command -label "Delete Selected Lines" -command "dellines"
$menu.edit add command -label "Delete Except Selected Lines" -command "keeplines"
$menu.edit add command -label "Delete Hyperlinks" -command "remove_hyperlinks"
$menu.edit add command -label "Delete Targets" -command "remove_targets"
$menu.edit add command -label "Second Order Search" -command "sos_show_dialog .sos"
$menu.edit add command -label "Replace by analogy" -command "processMultipleStringInputs Replace-by-analogy \{target replacement\} replace_substring_by_analogy"
$menu.edit add command -label "Replace by analogy (Whole Words)" -command "processMultipleStringInputs Replace-by-analogy \{target replacement\} replace_by_analogy"

$menu add cascade -label "Insert" -menu [menu $menu.insert -tearoff 0]
$menu.insert add command -label "Insert Image" -command "insertPhoto .t"
$menu.insert add command -label "Insert Media File (Audio/Video)" -command "insertMedia .t"
$menu.insert add command -label "Insert Audio Recording" -command "insertAudioRecording .t"
$menu.insert add command -label "Insert Audio Recording (ffmpeg)" -command "insertAudioRecordingUsingFfmpeg .t"
$menu.insert add command -label "Insert File Reference" -command "insertFileReference .t"
$menu.insert add command -label "Insert Watermark" -command "applyWatermark"
$menu.insert add command -label "Insert Note" -command "insertNoteFile .t"
$menu.insert add command -label "Insert Hyperlink" -command "setLastSelectionAsHyperlinkTarget"
$menu.insert add command -label "Insert Hyperlink to Selected Grep Lines" -command hyperlink_selected_grep_lines

$menu add cascade -label "Navigation" -menu [menu $menu.nav -tearoff 0]
$menu.nav add command -label "List of Images" -command listOfImages;
$menu.nav add command -label "List of Notes" -command listOfNotes;
$menu.nav add command -label "Search in Notes" -command searchInNotes;
$menu.nav add command -label "List of Media Files" -command listOfMultimedia;
$menu.nav add command -label "Close Navigation Windows" -command delete_result_windows;

$menu add cascade -label "Syntax" -menu [menu $menu.syntax -tearoff 0]

$menu add cascade -label "Options" -menu [menu $menu.options -tearoff 0]  
$menu.options add checkbutton -label "Automatic Syntax Highlight" -variable "autosyn_mode";
$menu.options add checkbutton -label "Use regex" -variable "use_regex";
set doExportButtonsToHtml 1;
$menu.options add checkbutton -label "Export buttons to html" -variable "doExportButtonsToHtml";

$menu.options add checkbutton -label "Replace Existing Hyperlinks" -variable "replace_existing_hyperlinks";
$menu.options add checkbutton -label "Disable Hyperlinks" -variable "disable_follow_target";
$menu.options add checkbutton -label "Case Sensitive Search" -variable "case_sensitive";
$menu.options add checkbutton -label "Doubleclick highlights multiple words" -variable "multiword_mode";
$menu.options add checkbutton -label "Doubleclick highlights hyphenated words" -variable "hyphenated_word_mode";
$menu.options add checkbutton -label "Arithmetic in Quick Command" -variable "eval_expr";
$menu.options add separator;
$menu.options add radiobutton -label "Open Dragged-and-Dropped File" -variable action_on_dnd -value edit
$menu.options add radiobutton -label "Puts Dragged-and-Dropped File Path" -variable action_on_dnd -value puts 
$menu.options add radiobutton -label "Add Ref to Dragged-and-Dropped File Path" -variable action_on_dnd -value addref
$menu.options add radiobutton -label "Insert Dragged-and-Dropped Image" -variable action_on_dnd -value add_image
$menu.options add radiobutton -label "Add Ref to Dragged-and-Dropped Image" -variable action_on_dnd -value add_media

$menu.options add separator;
$menu.options add checkbutton -label "Send Command Results to Editor" -variable "cmd_to_editor";
$menu.options add checkbutton -label "Paste Tags Only" -variable "global_tagsonly";
$menu.options add separator;
set dbl_click_behavior "default";
$menu.options add radiobutton -label "Bind double-click to default behavior" -variable "dbl_click_behavior" -value "default";
$menu.options add radiobutton -label "Bind double-click to open trace location" -variable "dbl_click_behavior" -value "open_trace_loc";
$menu.options add radiobutton -label "Bind double-click to show trace location" -variable "dbl_click_behavior" -value "show_trace_loc";
$menu.options add radiobutton -label "Bind double-click to open listed location" -variable "dbl_click_behavior" -value "open_listed_loc";
$menu.options add radiobutton -label "Bind double-click to show listed location" -variable "dbl_click_behavior" -value "show_listed_loc";
$menu.options add radiobutton -label "Bind double-click to find prev occurrence" -variable "dbl_click_behavior" -value "find_prev_occurrence";
$menu.options add radiobutton -label "Bind double-click to find next occurrence" -variable "dbl_click_behavior" -value "find_next_occurrence";
$menu.options add radiobutton -label "Bind double-click to read numbers aloud" -variable "dbl_click_behavior" -value "read_number_aloud";


proc add_double_click_handler {cmd menutxt} {
   global menu;
   $menu.options add separator;
   $menu.options add radiobutton -label $menutxt -variable "dbl_click_behavior" -value "custom$cmd"; 
}



add_double_click_handler load_one_line_before "Bind double-click to load one line before the grep line under cursor"
add_double_click_handler load_one_line_after "Bind double-click to load one line after the grep line under cursor"

proc load_one_line_after {args} {
    load_more_lines 0 1;
}

proc load_one_line_before {args} {
    load_more_lines 1 0;
}
$menu.options add separator;
$menu.options add command -label "Default Font" -command "setDefaultFont";
$menu.options add command -label "Default Background" -command "setDefaultBackground";
$menu.options add command -label "Invert Colors" -command "negateAll 1";
$menu.options add checkbutton -label "Wrap Lines" \
    -variable wrapLines -command toggleWrap


set wrapLines 1
proc toggleWrap {} {
    global wrapLines
    if {$wrapLines} {
        [editor] configure -wrap word
    } else {
        [editor] configure -wrap none
    }
}
$menu add cascade -label "Recipes" -menu [menu $menu.recipes -tearoff 0]  
$menu.recipes add command -label "Instrument Braces (C++)" -command "instrumentBraces";
$menu.recipes add command -label "Instrument Braces (Java)" -command "instrumentBracesJava";
$menu.recipes add command -label "Instrument Braces (Rust)" -command "instrumentBracesRust";
$menu.recipes add command -label "Remove Instrumentation" -command "removeInstrumentation";
$menu.recipes add command -label "Instrument Python" -command "instrumentPython";
$menu.recipes add command -label "Increment Numbers" -command "incrementNumbers";
$menu.recipes add command -label "Check Comment Checksums" -command checkAllCommentChecksums;
$menu.recipes add command -label "Run All Generators" -command "run_generators .";
$menu.recipes add command -label "Run All Verifiers" -command "run_verifiers .";

$menu.recipes add command -label "Add Line Prefix" -command "addLinePrefix";
$menu.recipes add command -label "Add Line Suffix" -command "addLineSuffix";
$menu.recipes add command -label "Execute Script" -command { eval [.t get 1.0 end]; };
$menu.recipes add command -label "Run web API tests" -command "run_test_suite curltest";
$menu.recipes add command -label "Run general tests" -command "run_test_suite generaltest";
$menu.recipes add command -label "Abort test run" -command abort_tests;
$menu.recipes add command -label "Set current test result as golden" -command rebaseline_tests;


$menu add cascade -label "Recent Files" -menu [menu $menu.recent -tearoff 0]; 
$menu.recent add command -label "Send List to Editor" -command sendRecentFileListToEditor;
$menu.recent add separator;

$menu add cascade -label "Help" -menu [menu $menu.help -tearoff 0]  
#$menu.help add command -label "User Guide" -command "userGuide";
$menu.help add command -label "About Spectral" -command "aboutSpectral";
$menu.help add command -label "Barebones Self Test" -command "barebones_selftest";


proc getmenu {} {
   global menu;
   return $menu;
}

proc show_diag_window {title text} {
    set w .diag_[randString]
    toplevel $w
    wm title $w $title
    text $w.t -wrap none -width 100 -height 25
    scrollbar $w.v -orient vertical -command "$w.t yview"
    $w.t configure -yscrollcommand "$w.v set"
    pack $w.v -side right -fill y
    pack $w.t -side left -fill both -expand 1
    $w.t insert end $text
    $w.t configure -state disabled
    return $w
}

proc barebones_selftest {} {
    set log ""
    append log "Barebones Self Test\n"
    append log "-------------------\n"
    append log "tcl_version: $::tcl_version\n"
    append log "tcl_patchLevel: $::tcl_patchLevel\n"
    if {[catch {package require Tk} tkver]} {
        append log "tk: NOT AVAILABLE ($tkver)\n"
    } else {
        append log "tk_version: $::tk_version\n"
        append log "tk_patchLevel: $::tk_patchLevel\n"
    }
    append log "ctext_real: $::spectral_has_real_ctext\n"
    append log "iwidgets_real: $::spectral_has_real_iwidgets\n"
    append log "\n"

    set original [.t get 1.0 end]
    set selranges [.t tag ranges sel]
    set insertpos [.t index insert]
    set testtext "alpha beta gamma\nbeta alpha\n"
    set ok 1

    .t fastdelete 1.0 end
    .t fastinsert 1.0 $testtext

    set length -1
    set found [.t search -regexp -count length {alpha} 1.0 end]
    append log "search_count_var_set: "
    if {$length > 0 && $found ne ""} {
        append log "OK (found=$found length=$length)\n"
    } else {
        append log "FAIL (found=$found length=$length)\n"
        set ok 0
    }

    .t tag add diag_tag 1.0 1.5
    set ranges [.t tag ranges diag_tag]
    append log "tag_ranges: "
    if {[llength $ranges] == 2} {
        append log "OK ([lindex $ranges 0] -> [lindex $ranges 1])\n"
    } else {
        append log "FAIL (ranges=$ranges)\n"
        set ok 0
    }

    # restore editor content
    .t fastdelete 1.0 end
    .t fastinsert 1.0 $original
    .t tag remove sel 1.0 end
    if {[llength $selranges] > 0} {
        foreach {s e} $selranges { .t tag add sel $s $e }
    }
    .t mark set insert $insertpos
    ctext::linemapUpdate .t

    append log "\nresult: "
    append log [expr {$ok ? "PASS" : "FAIL"}]
    append log "\n"

    show_diag_window "Barebones Self Test" $log
    puts stderr $log
}

proc clock_decode {seconds} {
   return [clock format $seconds -format "%Y-%m-%d %H:%M:%S"];
}

array set coverage_contexts {}
array set coverage_hits {}
array set coverage_tests {}
array set coverage_testlist {}

proc clear_coverage_hits {} {
    global coverage_hits;
    global coverage_contexts;
    global coverage_tests;
    global coverage_testlist;
    array set coverage_contexts {}
    array set coverage_hits {}
    array set coverage_tests {}
    array set coverage_testlist {}
}
proc load_coverage_hits {{fname ""}} {
    if {$fname == ""} {
        set fname [tk_getOpenFile];
    }
    if {$fname == ""} {
        return;
    }
    global coverage_hits;
    global coverage_contexts;
    global coverage_tests;
    global coverage_testlist;
    set fp [open $fname r];
    set line1 [gets $fp];
    set ncontexts [lindex $line1 1];
    for {set i 0} {$i < $ncontexts} {incr i} {
      set context_line [gets $fp];
      set num [lindex $context_line 0];
      set name [lindex $context_line 1];
      set coverage_contexts($num) $name;
    }
    set line1 [gets $fp];
    set nhits [lindex $line1 1];

    for {set i 0} {$i < $nhits} {incr i} {
      set hit_line [gets $fp];
      set context [lindex $hit_line 0];
      set loc     [lindex $hit_line 1];
      set count   [lindex $hit_line 2];
      if {[info exists coverage_hits($loc)]} {
          incr coverage_hits($loc) $count;
      } else {
          set coverage_hits($loc) $count;
      }
      if {[info exists coverage_testlist($context,$loc)]} {
          incr coverage_testlist($context,$loc) $count;
      } else {
       set coverage_testlist($context,$loc) $count;
      }
      if {[info exists coverage_tests($loc)]} {
          incr coverage_tests($loc) 1;
      } else {
          set coverage_tests($loc) 1;
      }
     
    }
    
}


proc load_coverage_hits_multifile {{fnames ""}} {
    if {$fnames == ""} {
        set fnames [tk_getOpenFile -multiple 1];
    }
    if {$fnames == ""} {
        return;
    }
    global coverage_hits;
    global coverage_contexts;
    global coverage_tests;
    global coverage_testlist;
    
    array set coverage_hits {};
    array set coverage_contexts {};
    array set coverage_tests {};
    array set coverage_testlist {};

    set max_remapped_context_id 0;
    array set context_name_to_id {};
    foreach fname $fnames {
            set fp [open $fname r];
            array set context_id_remap {};
            set line1 [gets $fp];
            set ncontexts [lindex $line1 1];
            for {set i 0} {$i < $ncontexts} {incr i} {
              set context_line [gets $fp];
              set num [lindex $context_line 0];
              set name [lindex $context_line 1];
              
              set remapped_num $num;
              if {![info exists context_name_to_id($name)]} {
                  incr max_remapped_context_id;
                  set remapped_num $max_remapped_context_id;
                  set context_name_to_id($name) $max_remapped_context_id;
                  set context_id_remap($num) $remapped_num;
              } else {
                  set remapped_num [set context_name_to_id($name)];
                  set context_id_remap($num) $remapped_num;
              }
              
              set coverage_contexts($remapped_num) $name;
              
            }
            if {![info exists context_id_remap(0)]} {
                incr max_remapped_context_id;
                set remapped_num $max_remapped_context_id;
                set context_name_to_id("untitled") $max_remapped_context_id;
                set context_id_remap(0) $remapped_num;
                set coverage_contexts($remapped_num) "untitled";
            }
            set line1 [gets $fp];
            set nhits [lindex $line1 1];
        
            for {set i 0} {$i < $nhits} {incr i} {
              set hit_line [gets $fp];
              set pre_remap_context [lindex $hit_line 0];
              set context 1;
              catch {
                  set context [set context_id_remap($pre_remap_context)];
              }
              set loc     [lindex $hit_line 1];
              set count   [lindex $hit_line 2];
              if {[info exists coverage_hits($loc)]} {
                  set coverage_hits($loc) [expr max($count,$coverage_hits($loc))];
              } else {
                  set coverage_hits($loc) $count;
              }
              if {[info exists coverage_testlist($context,$loc)]} {
                  set coverage_testlist($context,$loc)  [expr $count + $coverage_testlist($context,$loc)];  #[expr max($count,$coverage_testlist($context,$loc))]; not sure what I was thinking about when I used max
              } else {
                  set coverage_testlist($context,$loc) $count;
              }
              if {[info exists coverage_tests($loc)]} {
                  incr coverage_tests($loc) 1;
              } else {
                  set coverage_tests($loc) 1;
              }
           }
        }
    
}


proc annotate_coverage {{instr_regex {mprewriter..?scope_START!?\((\d+)\)}}} {
      global coverage_hits;
      global coverage_contexts;
      global coverage_tests;
      global case_sensitive;
      set selranges [.t tag ranges sel];
      if {[llength $selranges] == 0} {
           set selranges {1.0 end};
       }

       .t tag remove  sel 1.0 end;
       set resultsWindow [createResultsWindow "Coverage information"]
       update; 
       foreach {end start} [lreverse $selranges] {
           set last_cur "";
           set cur $start;
           while 1 {
               set cur [.t search -regexp -count length $instr_regex $cur $end];
               if {$cur == "" || $cur == $last_cur} {
                  break
               }
               set match [.t get  $cur "$cur + $length char"];
               set loc [regsub -all $instr_regex $match {\1}];
               set linenumber [expr int($cur)];
               applyHighlight "" $linenumber.0 $linenumber.end #fd9f9f;
               set hits 0;
               set tests 0;
               catch {
                 set hits [set coverage_hits($loc)];
               }
               catch {
                   set tests [set coverage_tests($loc)];
               }
               
               if {$hits == 0} {
                  set cur [.t index "$cur + $length char"];
                  update;
                  continue;
               } 
               applyHighlight "" $linenumber.0 $linenumber.end #aafba2;
               
               set last_cur $cur;
               change_yview $cur;
               
               if {$length == 0} {
                   incr length;
               }
               set curParts [split $cur "."];
               set theLine [lindex  $curParts 0];
               set theCol [lindex  $curParts 1];
               set theText [.t get "$theLine.0" "$theLine.end"]
               $resultsWindow.results insert end "($theLine):($theCol): $hits HITS IN $tests CONTEXTS\n" resultHyperlink;
               update;

               set cur [.t index "$cur + $length char"]
           }   
    }

    update; 
    return $resultsWindow;
}

proc annotate_coverage_inline {before_str after_str {instr_regex {mprewriter..?scope_START!?\((\d+)\)}}} {
      global coverage_hits;
      global coverage_contexts;
      global coverage_tests;
      global case_sensitive;
      set selranges [.t tag ranges sel];
      if {[llength $selranges] == 0} {
           set selranges {1.0 end};
       }
       .t tag remove  sel 1.0 end;
       update; 
       foreach {end start} [lreverse $selranges] {
           set last_cur "";
           set cur $start;
           while 1 {
               set cur [.t search -regexp -count length $instr_regex $cur $end];
               if {$cur == "" || $cur == $last_cur} {
                  break
               }
               set match [.t get  $cur "$cur + $length char"];
               set loc [regsub -all $instr_regex $match {\1}];
               set linenumber [expr int($cur)];
               applyHighlight "" $linenumber.0 $linenumber.end #fd9f9f;
               set hits 0;
               set tests 0;
               catch {
                 set hits [set coverage_hits($loc)];
               }
               catch {
                   set tests [set coverage_tests($loc)];
               }
               
               if {$hits == 0} {
                  set cur [.t index "$cur + $length char"];
                  update;
                  continue;
               }
               set inserted $before_str;
               append inserted $hits;
               append inserted $after_str;
               set inserted_length [string length $inserted];
               .t insert [.t index "$cur + $length char"] $inserted;
               set cur [.t index "$cur + [expr $length + $inserted_length] char"];
               
               applyHighlight "" $linenumber.0 $linenumber.end #aafba2;
               
           }   
    }

    update; 
}

proc annotate_contexts {{instr_regex {mprewriter..?scope_START!?\((\d+)\)}}} {

      global coverage_hits;
      global coverage_contexts;
      global coverage_tests;
      global case_sensitive;
      global coverage_testlist;
      set selranges [.t tag ranges sel];
      if {[llength $selranges] == 0} {
           set selranges {1.0 end};
       }

       .t tag remove  sel 1.0 end;
       set resultsWindow [createResultsWindow "Coverage information"]
       update;
       
       set context_ids [array names coverage_contexts];
       foreach {end start} [lreverse $selranges] {
           set last_cur "";
           set cur $start;
           while 1 {
               set cur [.t search -regexp -count length $instr_regex $cur $end];
               if {$cur == "" || $cur == $last_cur} {
                  break;
               }
               set match [.t get  $cur "$cur + $length char"];
               
               set linenumber [expr int($cur)];
               applyHighlight "" $linenumber.0 $linenumber.end #fd9f9f;
               
               set loc [regsub -all $instr_regex $match {\1}];
               set hits 0;
               set tests 0;
               
               catch {
                 set hits [set coverage_hits($loc)];
               }
               catch {
                   set tests [set coverage_tests($loc)];
               }
               if {$hits == 0} {
                  set cur [.t index "$cur + $length char"];
                  update;
                  continue;
               } 

               applyHighlight "" $linenumber.0 $linenumber.end #aafba2;
               
               set test_list {} 
               foreach context_id $context_ids {
                   set testname [set coverage_contexts($context_id)];
                   set testhit "";
                   catch {
                       set testhit [set coverage_testlist($context_id,$loc)];
                   }
                   if {[string trim $testhit] != ""} {
                              append test_list $testname " " $testhit "\n"
                   }
               }

               set last_cur $cur;
               change_yview $cur;
               
               if {$length == 0} {
                   incr length;
               }
               set curParts [split $cur "."];
               set theLine [lindex  $curParts 0];
               set theCol [lindex  $curParts 1];
               
               $resultsWindow.results insert end "($theLine):($theCol): $hits HITS IN $tests CONTEXTS\n" resultHyperlink;
               $resultsWindow.results insert end "\n";
               $resultsWindow.results insert end $test_list
               $resultsWindow.results insert end "\n";
               update;

               set cur [.t index "$cur + $length char"]
           }   
    }

    update;
   return $resultsWindow; 
}

proc userproc {name params body} {
  global qcInterp;
  global all_commands;
  append all_commands " " $name;
  set cmd "proc ";
  lappend cmd $name;
  lappend cmd $params;
  lappend cmd $body;
  eval $cmd;
  interp alias $qcInterp $name {} $name;
}


proc setAutoComplete {keywords} {
   global current_keywords;
   set current_keywords $keywords
}

proc is_noncritical_package_error {msg} {
    if {[regexp {can't find package (json|tdom)} $msg]} {
        return 1
    }
    return 0
}

proc load_plugin {pattern} {
   global installdir;
   global qcInterp;
   set msg "";
   set files {};
   catch {
     set files [glob "${installdir}/${pattern}"];
   }
   foreach file $files {
     if {[file isdirectory $file]} continue;

     set plugin_name $file;
     if {[ catch {
        set fp_plugin [open $plugin_name "r"];
        set cont [read $fp_plugin];
        close $fp_plugin;
        $qcInterp eval $cont;
      } msg ]} {
       set outmsg "Error in plugin ";
       append outmsg $plugin_name;
       append outmsg " : ";
       append outmsg $msg;
       if {[is_noncritical_package_error $msg]} {
           addToStatus $outmsg
       } else {
           tk_messageBox -message $msg;
       }
      }
   }
}

proc userGuide {} {
   global installdir;
   #tk_messageBox -message "install dir=$installdir"
   createHtmlWindow "User Guide" "${installdir}/help/index.html"
}
proc aboutSpectral {} {
    global splashimagefile;
    global spectral_version;
    global datestamp;
    global username;
   catch { destroy .splash errorswindow }
    set splash [ toplevel .splash ]
    wm  title  $splash  "spectral"
    wm  overrideredirect  $splash  1
    wm  geometry  $splash  "+200+200"
    set splashImage [image create photo -file $splashimagefile]
    label  $splash.image -image $splashImage  -fg #000000 -bg white 
    label  $splash.text -text "Spectral build $datestamp\nThis program is licensed to $username" -font "Calibri 12" -fg #000000 -bg white
    frame  $splash.buttonFrame -background white;
    button $splash.buttonFrame.close -text "Close" -command  {
        catch { destroy .splash  errorswindow}
    } -background white
    
    bind $splash <Escape> {
        catch { destroy .splash  errorswindow}
    }
    pack $splash.image -side top -fill x
    pack $splash.text -side top -fill x
    pack $splash.buttonFrame -side bottom -fill x
    pack $splash.buttonFrame.close -side right -fill y

}

proc instrumentPython {}  {
   .bottomFrame.replace delete 0 end;
   .bottomFrame.with delete 0 end;
   .bottomFrame.init delete 0 end;
   .bottomFrame.incr delete 0 end;
   .bottomFrame.subst delete 0 end;
   .bottomFrame.expr delete 0 end;
   .bottomFrame.enforceLC delete 0 end;
   .bottomFrame.enforceRC delete 0 end;

   .bottomFrame.replace insert 0 {([\t ]*((\mfor)|(\me?l?if)|(\mwhile)|(\mdef)|(\melse)|(\mexcept)).*:)(\s*)}
   .bottomFrame.with insert 0 {\1\9mprewriter.scope_START(index)\9};
   .bottomFrame.init insert 0 "set i 10000";
   .bottomFrame.incr insert 0  "incr i";
   .bottomFrame.subst insert 0  "index";
   .bottomFrame.expr insert 0 "set i";
}

proc incrementNumbers {} {
   .bottomFrame.replace delete 0 end;
   .bottomFrame.with delete 0 end;
   .bottomFrame.init delete 0 end;
   .bottomFrame.incr delete 0 end;
   .bottomFrame.subst delete 0 end;
   .bottomFrame.expr delete 0 end;
   .bottomFrame.enforceLC delete 0 end;
   .bottomFrame.enforceRC delete 0 end;

   .bottomFrame.replace insert 0 {\d+}
   .bottomFrame.with insert 0 substitution;
   .bottomFrame.subst insert 0  substitution;
   .bottomFrame.expr insert 0 "expr 100+\$match";
}

proc instrumentBraces {} {

   .bottomFrame.replace delete 0 end;
   .bottomFrame.with delete 0 end;
   .bottomFrame.init delete 0 end;
   .bottomFrame.incr delete 0 end;
   .bottomFrame.subst delete 0 end;
   .bottomFrame.expr delete 0 end;
   .bottomFrame.enforceLC delete 0 end;
   .bottomFrame.enforceRC delete 0 end;

   .bottomFrame.replace insert 0 {((const)|(=>)|(else)|[)]|:)\s*(//.*)?\s*\{}
   .bottomFrame.with insert 0 "&mprewriter_scope_START(index);";
   .bottomFrame.init insert 0 "set i 10000";
   .bottomFrame.incr insert 0  "incr i";
   .bottomFrame.subst insert 0  "index";
   .bottomFrame.expr insert 0 "set i";
   .bottomFrame.enforceLC insert 0 "-((\\mswitch\\M))\[^\{\]*\\\{"
   .bottomFrame.enforceRC insert 0 {-[0-9"m]p?r?e?w?r?i?}

}

proc instrumentBracesJava {} {

   .bottomFrame.replace delete 0 end;
   .bottomFrame.with delete 0 end;
   .bottomFrame.init delete 0 end;
   .bottomFrame.incr delete 0 end;
   .bottomFrame.subst delete 0 end;
   .bottomFrame.expr delete 0 end;
   .bottomFrame.enforceLC delete 0 end;
   .bottomFrame.enforceRC delete 0 end;

   .bottomFrame.replace insert 0 {(\mdefault\s*:)|(\mcase\M\s+[^:]+:)|(((try)|(->)|(throws [^;]*Exception)|(else)|[)]|:)\s*(//.*)?\s*\{)}
   .bottomFrame.with insert 0 "&mprewriter.scope_START(index);";
   .bottomFrame.init insert 0 "set i 10000";
   .bottomFrame.incr insert 0  "incr i";
   .bottomFrame.subst insert 0  "index";
   .bottomFrame.expr insert 0 "set i";
   .bottomFrame.enforceRC insert 0 {-(([0-9"\}])|(mprewriter)|(\s*super\()|(\s*this\())}
   .bottomFrame.enforceLC insert 0 "-((\\mswitch\\M)|(\\minterface\\M)|(new \[A-Za-z_0-9<>\]+\[(\]\[^)\]*\[)\])|(\\class\\M)|(\\menum\\M))\[^\{;\]*\\\{"

}

proc instrumentBracesRust {} {

   .bottomFrame.replace delete 0 end;
   .bottomFrame.with delete 0 end;
   .bottomFrame.init delete 0 end;
   .bottomFrame.incr delete 0 end;
   .bottomFrame.subst delete 0 end;
   .bottomFrame.expr delete 0 end;
   .bottomFrame.enforceLC delete 0 end;
   .bottomFrame.enforceRC delete 0 end;

   .bottomFrame.replace insert 0 {(\mdefault\s*:)|(\mcase\M\s+[^:]+:)|(((try)|(>)|(Exception)|(else)|(\mif\M[^\{]*.*)|(\mfn\M[^\{]*.*)|(\mfor\M[^\{]*.*)|(\mwhile\M[^\{]*.*)|(\mloop\M[^\{]*.*)|[)]|:)\s*(//.*)?\s*\{)}
   .bottomFrame.with insert 0 "&mprewriter_scope_START!(index);";
   .bottomFrame.init insert 0 "set i 10000";
   .bottomFrame.incr insert 0  "incr i";
   .bottomFrame.subst insert 0  "index";
   .bottomFrame.expr insert 0 "set i";
   .bottomFrame.enforceRC insert 0 {-(([0-9"\}])|(mprewriter)|(\s*super\()|([^"]*")|(\s*this\())}
   .bottomFrame.enforceLC insert 0 "-((\\mswitch\\M)|(\\mmatch\\M)|(\\muse\\M)|(\\minterface\\M)|(new \[A-Za-z_0-9\]+\[(\]\[^)\]*\[)\])|(\\class\\M)|(\\menum\\M))\[^\{;\]*\\\{"

}
proc removeInstrumentation {} {

   .bottomFrame.replace delete 0 end;
   .bottomFrame.with delete 0 end;
   .bottomFrame.init delete 0 end;
   .bottomFrame.incr delete 0 end;
   .bottomFrame.subst delete 0 end;
   .bottomFrame.expr delete 0 end;
   .bottomFrame.enforceLC delete 0 end;
   .bottomFrame.enforceRC delete 0 end;

   .bottomFrame.replace insert 0 {mprewriter..?scope_START!?\(\d+\);}
   .bottomFrame.with insert 0 "";
   .bottomFrame.init insert 0 "";
   .bottomFrame.incr insert 0  "";
   .bottomFrame.subst insert 0  "";
   .bottomFrame.expr insert 0 "";
   .bottomFrame.enforceLC insert 0 "";
   .bottomFrame.enforceRC insert 0 "";

}
proc addLinePrefix {} {

   .bottomFrame.replace delete 0 end;
   .bottomFrame.with delete 0 end;
   .bottomFrame.init delete 0 end;
   .bottomFrame.incr delete 0 end;
   .bottomFrame.subst delete 0 end;
   .bottomFrame.expr delete 0 end;
   .bottomFrame.enforceLC delete 0 end;
   .bottomFrame.enforceRC delete 0 end;

   .bottomFrame.replace insert 0 {^}
   .bottomFrame.with insert 0 "//";
    
}

proc addLineSuffix {} {

   .bottomFrame.replace delete 0 end;
   .bottomFrame.with delete 0 end;
   .bottomFrame.init delete 0 end;
   .bottomFrame.incr delete 0 end;
   .bottomFrame.subst delete 0 end;
   .bottomFrame.expr delete 0 end;
   .bottomFrame.enforceLC delete 0 end;
   .bottomFrame.enforceRC delete 0 end;

   .bottomFrame.replace insert 0 {$}
   .bottomFrame.with insert 0 "//";
    
}

proc setDefaultBackground {} {
   global default_background;
   set newcolor [tk_chooseColor -initialcolor $default_background ];
   if {$newcolor != ""} {
       set default_background $newcolor;
       .t configure -bg $newcolor;
       
       [.textFrame.overview component text] configure -bg $newcolor;
       [.textFrame.overview component text] configure -foreground [negateColor $newcolor];
       .t  configure -foreground [negateColor $newcolor];
   }
}



proc enlarge_font {num} {
    set current_font [.t cget -font]
    set fontsize $current_font;
    regsub -all {[^0-9]} $fontsize {} fontsize;
    set newsize [expr $fontsize+($num)];
    regsub -all $fontsize $current_font $newsize newfont;
    .t configure -font $newfont;
}

proc setDefaultFont {} {
   global default_font;
   set newfont [ChooseFont::ChooseFont $default_font];
   if {$newfont != ""} {
       set default_font $newfont;
       .t configure -font $newfont;
   }
}

set fixed_boxes { 
1 #f0f583
2 #fd9f9f
3 #aafba2
4 #a5f8f8
5 #f997f9
}


set currentColor "#ccd3f7";

proc searchButtonMenu {id} {
   catch {destroy .menu3}
    set x [winfo pointerx .]
    set y [winfo pointery .]
    menu .menu3 -tearoff 0;
    .menu3 add command -label "Toggle As Current Highlighter" -command "setDefaultHighlight $id";
    .menu3 add command -label "Remove This Highlight" -command "removeThisHighlight $id";
    .menu3 add command -label "Select Occurrences" -command "selectTagOccurrences $id"
    .menu3 add command -label "Select Occurrences in Selection" -command "selectTagOccurrencesInSelection $id"
    .menu3 add command -label "List Occurrences" -command "showTagOccurrences $id"
    .menu3 add command -label "Highlight Multiple Patterns" -command "matchMultiple $id"
    .menu3 add command -label "Hyperlink to Selection" -command "setSelectedRegionAsTargetsForHighlights $id"
    tk_popup .menu3 $x $y
}


proc removeThisHighlight {id} {

    global default_highlight;
    global fixed_boxes;
    global currentColor;
    array set preset_colors $fixed_boxes;
    set col "";
    if {$id == 6} {
        set col $currentColor;
    } else {
        set col [set preset_colors($id)];
    }

    if {[hasSelection]} {
       set selranges [.t tag ranges sel];
       foreach {start end} $selranges {
            .t tag remove $col $start $end;
       }
    } else {
        .t tag remove $col 1.0 end;
    }
    update;
}

proc gentablelogger {id} {
    set selranges [.t tag ranges sel];
    set retval "";
    global default_highlight;
    global fixed_boxes;
    global currentColor;
    array set preset_colors $fixed_boxes;
    set col "";
    if {$id == 6} {
        set col $currentColor;
    } else {
        set col [set preset_colors($id)];
    }
    puts "color=$col"

    .t tag remove sel 1.0 end
    if { $selranges == "" }  {
        set ranges [.t tag ranges $col];
        puts "ranges=<$ranges>";
        foreach {start end} $ranges {
            if {$retval == ""} {
                append retval [.t get $start $end];
            } else {
                append retval "," [.t get $start $end] ;
            }
        }
    } else {
         set ranges [.t tag ranges $col];
         puts "ranges=<$ranges>";
        foreach {start end} $ranges {
            foreach {selstart selend} $selranges {
                if {[textranges_overlap $start $end $selstart $selend]} {
                    if {$retval == ""} {
                        append retval [.t get $start $end];
                    } else {
                        append retval "," [.t get $start $end] ;
                    }
                }
            }
            
        }
    }
    clipboard clear;
    clipboard append "logtable!(1234,$retval)";
    return "Appended to clipboard"
}

proc selectTagOccurrencesInSelection {id} {
    set selranges [.t tag ranges sel];
    global default_highlight;
    global fixed_boxes;
    global currentColor;
    array set preset_colors $fixed_boxes;
    set col "";
    if {$id == 6} {
        set col $currentColor;
    } else {
        set col [set preset_colors($id)];
    }


    .t tag remove sel 1.0 end
    set ranges [.t tag ranges $col];
    foreach {start end} $ranges {
        foreach {selstart selend} $selranges {
            if {[textranges_overlap $start $end $selstart $selend]} {
                .t tag add sel $start $end;
            }
        }
        
    }
    .t tag raise sel;
    update;
}
proc selectTagOccurrences {id} {
 
    global default_highlight;
    global fixed_boxes;
    global currentColor;
    array set preset_colors $fixed_boxes;
    set col "";
    if {$id == 6} {
        set col $currentColor;
    } else {
        set col [set preset_colors($id)];
    }

    set ranges [.t tag ranges $col];
    foreach {start end} $ranges {
        .t tag add sel $start $end;
    }
    .t tag raise sel;
    update;
}

proc showTagOccurrences {id} {

    global default_highlight;
    global fixed_boxes;
    global currentColor;
    array set preset_colors $fixed_boxes;
    set col "";
    if {$id == 6} {
        set col $currentColor;
    } else {
        set col [set preset_colors($id)];
    }


    global allResultWindows;
   
    set resultsWindow [createResultsWindow "Highlight Occurrences"];
    update;

    set ranges [.t tag ranges $col];
    foreach {start end} $ranges {
        .t tag add sel $start $end;
        set curParts [split $start "."];
        set theLine [lindex  $curParts 0];
        set theCol [lindex  $curParts 1];
        $resultsWindow.results insert end "($theLine):($theCol):" resultHyperlink;
        $resultsWindow.results insert end "\n";
    }
    lappend allResultWindows $resultsWindow;
    .t tag raise sel;
    update;
}

proc negateColor {mycolor} {
    foreach {redcolor greencolor bluecolor} [winfo rgb . $mycolor] break
    set colormax [lindex [winfo rgb . white] 0]
    set myresult [format "#%02x%02x%02x" [expr int(255*($colormax-$redcolor))/$colormax]  [expr int(255*($colormax-$greencolor))/$colormax] [expr int(255*($colormax-$bluecolor))/$colormax]]
    return $myresult;
 }

 proc colorCode {mycolor} {
   foreach {redcolor greencolor bluecolor} [winfo rgb . $mycolor] break
   set colormax [lindex [winfo rgb . white] 0]
   set myresult [format "#%02x%02x%02x" [expr int(255*($redcolor))/$colormax]  [expr int(255*($greencolor))/$colormax] [expr int(255*($bluecolor))/$colormax]]
   return $myresult;
 }


proc negateWindow {w invert_tags} {

   if {$invert_tags} {
     $w configure -background [negateColor [$w cget  -background]];
     $w configure -foreground [negateColor [$w cget  -foreground]];
     set tags [$w tag names];
     foreach tag $tags {
       catch {$w tag configure $tag  -background [negateColor [$w tag cget $tag -background]];}
       catch {$w tag configure $tag -foreground [negateColor [$w tag cget  $tag -foreground]];}
     }
   }
}


proc negateAll {invert_tags} {
    negateWindow .t $invert_tags;
    set w [.textFrame.overview component text];
    $w configure -state normal;
    negateWindow $w $invert_tags;
    $w configure -state disabled;

    global default_foreground;
    global default_background;
    global cmd_bg;
    set default_foreground [negateColor $default_foreground];
    set default_background [negateColor $default_background];
    set cmd_bg [negateColor $cmd_bg];
    global fixed_boxes;
    global currentColor;
    array set colors {};
    foreach {id col} $fixed_boxes {
        set colors($id) [negateColor $col];
    }


    set fgcolor [ [.searchFrame.foreground component entry] get];
    if {[llength $fgcolor]} {
        [.searchFrame.foreground component entry] delete 0 end;
        [.searchFrame.foreground component entry] insert 0 [negateColor $fgcolor];
        [.searchFrame.foreground component entry] configure -foreground [negateColor $fgcolor];
    }
    set currentColor [negateColor $currentColor];
    set colors(6) $currentColor;

    set fixed_boxes {};
    foreach i {1 2 3 4 5 6} {
        append fixed_boxes $i " ";
        append fixed_boxes [set colors($i)] " ";
    }

    foreach {id col} [array get colors] {
       set bg [.searchFrame.search$id cget -background];
       if {$bg == [negateColor $col]} {
          .searchFrame.search$id configure -background $col;

       } else {
          .searchFrame.search$id configure -background $default_background;
       }
       [.searchFrame.search$id component label] configure -foreground $default_foreground
       [.searchFrame.search$id component label] configure -background $col
       [.searchFrame.search$id component label] configure -relief flat
       bind [.searchFrame.search$id component label] <ButtonPress-1> "highlightSelectedString 1 $id $col"
       bind [.searchFrame.search$id component label] <ButtonPress-3> "searchButtonMenu $id;break;";
       bind [.searchFrame.search$id component label] <ButtonPress-2> "searchButtonMenu $id;break;";
       bind [.searchFrame.search$id component entry] <Up> "searchString -1 $id $col"
       bind [.searchFrame.search$id component entry] <Down> "searchString 1 $id $col"
       bind [.searchFrame.search$id component entry] <Control-Up> "searchString -2 $id $col; break;"
       bind [.searchFrame.search$id component entry] <Control-Down> "searchString 2 $id $col; break;"
    }
    global default_highlight;
    if {$default_highlight != ""} {
       set default_highlight [negateColor $default_highlight]
    }

    .searchFrame configure -background [negateColor [.searchFrame cget -background]];
    .searchFrame.color configure -background [negateColor [.searchFrame.color cget -background]];
    .searchFrame.color configure -foreground [negateColor [.searchFrame.color cget -foreground]];
    .t.l configure -background [negateColor [.t.l cget -background]];
    .t.l configure -foreground [negateColor [.t.l cget -foreground]];

    .searchFrame.font configure -background [negateColor [.searchFrame.font cget -background]];
    #.searchFrame.font configure -foreground [negateColor [.searchFrame.font cget -foreground]];
    [.searchFrame.font component label] configure -background [negateColor [[.searchFrame.font component label] cget -background]];
    [.searchFrame.font component label] configure -foreground [negateColor [[.searchFrame.font component label] cget -foreground]];
    
    .searchFrame.codeMode configure -foreground [negateColor [.searchFrame.codeMode cget -foreground]];
    .searchFrame.codeMode configure -background [negateColor [.searchFrame.codeMode cget -background]];
    
    
    .searchFrame.foreground configure -background [negateColor [.searchFrame.foreground cget -background]];
    #.searchFrame.foreground configure -foreground [negateColor [.searchFrame.foreground cget -foreground]];
    [.searchFrame.foreground component label] configure -background [negateColor [[.searchFrame.foreground component label] cget -background]];
     [.searchFrame.foreground component label] configure -foreground [negateColor [[.searchFrame.foreground component label] cget -foreground]];

    .textFrame.overview configure -background [negateColor [.textFrame.overview cget -background]];
    .textFrame.overview configure -foreground [negateColor [.textFrame.overview cget -foreground]];
    [.textFrame.overview component label] configure -background [negateColor [[.textFrame.overview component label] cget -background]];

    . configure -background [negateColor [. cget -background]];
    global quickCommand;
    $quickCommand configure -background [negateColor [$quickCommand cget -background]];
    [$quickCommand component label] configure -background [negateColor [[$quickCommand component label] cget -background]];
    [$quickCommand component label] configure -foreground [negateColor [[$quickCommand component label] cget -foreground]];

}


proc show_text_input {base data title inputfn width height other_checkboxes clientdata}  {
   
    global default_font;
    set w ".${base}"
    toplevel $w;
     set x [winfo pointerx ${w}];
     set y [winfo pointery ${w}];
     set x [expr max(100, $x-100)];
     set y [expr max(100, $y-100)];
    wm geometry $w "+$x+$y";
    wm title $w $title
    iwidgets::scrolledtext $w.input  -labeltext $title -wrap word -labelpos n \
    -vscrollmode dynamic -hscrollmode dynamic \
    -width $width -height $height;
    $w.input insert 1.0 $data;

    [$w.input component label] configure -font $default_font;

    button $w.ok -text OK -command "if \{\[$inputfn $w $clientdata\] != 0\} \{destroy $w;\}" -font $default_font
    button $w.cancel -text Cancel -command "destroy $w" -font $default_font

    foreach {ocbname ocbtext} $other_checkboxes {
        checkbutton $w.${ocbname} -text $ocbtext -variable [randString] -font $default_font;
        pack $w.${ocbname} -side top -anchor w  ;
    }
    
    pack $w.input -side top -fill both -expand yes;
    pack $w.ok -side bottom -fill x
    pack $w.cancel -side bottom -fill x
    
    set txtwidget [$w.input component text];  
  
    bind $txtwidget  <Control-m> "
     matchBracket $txtwidget;
     break;
    ";
    
    bind $txtwidget  <Control-c> "
     copySelection $txtwidget;
     break;
    ";

    bind $txtwidget  <Control-x> "
     copySelection $txtwidget cut;
     break;
    " 
  
    bind $txtwidget <Double-ButtonPress-1> "
       set pos \[$txtwidget index {@%x,%y}\];
       highlightCurrent $txtwidget  \$pos; break;
  
    "
   
    grab $w
    wm transient $w .
    raise $w
    tkwait window $w
    
}

proc show_choice {base data colname coltext selectfn width clientdata}  {
    
    set w ".${base}"
    toplevel $w;
    wm title $w "Choose from $coltext"
    ttk::frame $w.container
    ttk::treeview $w.tree -columns $colname -show headings  -selectmode browse \
        -yscroll "$w.vsb set" -xscroll "$w.hsb set"

    if {[tk windowingsystem] ne "aqua"} {
        ttk::scrollbar $w.vsb -orient vertical -command "$w.tree yview"
        ttk::scrollbar $w.hsb -orient horizontal -command "$w.tree xview"
    } else {
        scrollbar $w.vsb -orient vertical -command "$w.tree yview"
        scrollbar $w.hsb -orient horizontal -command "$w.tree xview"
    }

    pack $w.container -fill both -expand 1
    grid $w.tree $w.vsb -in $w.container -sticky nsew
    grid $w.hsb -in $w.container -sticky nsew
    grid column $w.container 0 -weight 1
    grid row    $w.container 0 -weight 1

    foreach col $colname name $coltext {
        $w.tree heading $col -text $name
        $w.tree column $col -width $width 
    }

    foreach item $data {
        $w.tree insert {} end -values [list $item]
    }
    
    button $w.select -text Select -command "if \{\[$selectfn $w $clientdata\] != 0\} \{destroy $w;\}"
    button $w.cancel -text Cancel -command "destroy $w"

    pack $w.select -side bottom -fill x
    pack $w.cancel -side bottom -fill x

    grab $w
    wm transient $w .
    raise $w
    tkwait window $w
    
}

proc process_input_example {w args} {
   set txt [$w.input get 1.0 end];
   tk_messageBox -message $txt;
   return 1;
}

proc process_choice_example {w args} {
   set idx [$w.tree selection];
   if {[llength $idx] == 0} {
       return 0;
   }
   array set item [$w.tree item $idx];
   tk_messageBox -message [set item(-values)];
   return 1;
}

#show_choice choices {a b c d} {rfolders} {{Choose Option}} process_choice_example 100 {};
#show_text_input imagescale "-resize 100%" "Resize Scale" process_input_example 200 200 {}  {};
proc clearDefaultHighlight {} {
    global default_highlight;
    global default_background;
    global fixed_boxes;
    global currentColor;
     
    # Reset all the labels;
    foreach {idx colx} $fixed_boxes {
       .searchFrame.search$idx configure -background  $default_background; 
       [.searchFrame.search$idx component label] configure -background $colx;
    }

    .searchFrame.search6 configure -background  $default_background; 
    [.searchFrame.search6 component label] configure -background $currentColor;

    set default_highlight "";

}
proc setDefaultHighlight {id} {
    #puts stderr "setDefaultHighlight $id";
    global default_highlight;
    global default_background;
    global fixed_boxes;
    global currentColor;
    array set preset_colors $fixed_boxes;
    if {$id == 6} {
        set col $currentColor;
    } else {
        set col [set preset_colors($id)];
    }
    
    # Reset all the labels;
    foreach {idx colx} $fixed_boxes {
       .searchFrame.search$idx configure -background  $default_background; 
       [.searchFrame.search$idx component label] configure -background $colx;
       [.searchFrame.search$idx component label] configure -relief flat;
    }

    .searchFrame.search6 configure -background  $default_background; 
    [.searchFrame.search6 component label] configure -background $currentColor;
    [.searchFrame.search6 component label] configure -relief flat;
    

    if {$col == $default_highlight} {
        .searchFrame.search$id configure -background $default_background;
       [.searchFrame.search$id component label] configure -background $col;
       [.searchFrame.search$id component label] configure -relief flat;
       set default_highlight "";
    } else {
         .searchFrame.search$id configure -background $col;
       [.searchFrame.search$id component label] configure -background $col;
       [.searchFrame.search$id component label] configure -relief sunken;
       set default_highlight $col;
    }
}


foreach {id col} $fixed_boxes {
  iwidgets::entryfield .searchFrame.search$id -labeltext "Highlighter $id" -labelpos n -command  "searchString 1 $id $col" -width 25   -foreground #101010 -insertbackground blue -labelfont {Consolas 10} -background $default_background;
  [.searchFrame.search$id component label] configure -background $col
  [.searchFrame.search$id component label] configure -relief flat
  bind [.searchFrame.search$id component label] <ButtonPress-1> "highlightSelectedString 1 $id $col"
  bind [.searchFrame.search$id component label] <ButtonPress-3> "searchButtonMenu $id";
  bind [.searchFrame.search$id component label] <ButtonPress-2> "searchButtonMenu $id";

  bind [.searchFrame.search$id component entry] <Up> "searchString -1 $id $col"
  bind [.searchFrame.search$id component entry] <Down> "searchString 1 $id $col"
  bind [.searchFrame.search$id component entry] <Control-Up> "searchString -2 $id $col; break;"
  bind [.searchFrame.search$id component entry] <Control-Down> "searchString 2 $id $col; break;"
}

itcl::body iwidgets::Combobox::_stateSelect {} {
    switch --  $itk_option(-state) {
    normal {
        uplevel 1 $this _selectCmd
        # [itcl::code $this _selectCmd]
    }
    }
}


iwidgets::entryfield .searchFrame.search6 -labeltext "Highlighter 6 Palette =>" -labelpos n -command  {searchString 1 6 currentColor} -width 25   -foreground #101010 -insertbackground blue -background $default_background;
button .searchFrame.color -text "Palette:$currentColor" -command "chooseColor" -background $currentColor;

iwidgets::entryfield .searchFrame.font -labeltext "  Choose Font  " -labelpos n  -width 24   -foreground #101010 -insertbackground blue -textbackground white -background white;

[.searchFrame.font component label] configure -background white;
iwidgets::entryfield .searchFrame.foreground -labeltext "  Choose Foreground  " -labelpos n  -width 20   -foreground #101010 -insertbackground blue -textbackground white -background white;
[.searchFrame.foreground component label] configure -background white;

bind .searchFrame.color <ButtonPress-3> "pickColor";
bind .searchFrame.color <ButtonPress-2> "pickColor";

bind [.searchFrame.search6 component label] <ButtonPress-3> "searchButtonMenu 6";
bind [.searchFrame.search6 component label] <ButtonPress-2> "searchButtonMenu 6";

[.searchFrame.font component label] configure -relief raised
[.searchFrame.foreground component label] configure -relief raised

[.searchFrame.search6 component label] configure -background $currentColor
[.searchFrame.search6 component label] configure -relief flat
proc chooseColor {{title {}}} {
  global currentColor;
  set newColor [tk_chooseColor -initialcolor $currentColor -title $title];
  if  {$newColor != ""} {
  set currentColor $newColor;
  .searchFrame.color configure -background $currentColor;
  .searchFrame.color configure -text "Palette:$currentColor";
  [.searchFrame.search6 component label] configure -background $currentColor;
   setDefaultHighlight 6;
  }
  update;
}
proc set_hl_font {font} {
    [.searchFrame.font component entry] delete 0 end;
    [.searchFrame.font component entry] insert end $font;
}
proc set_hl_fg {newColor} {
   [.searchFrame.foreground component entry] delete 0 end;
   [.searchFrame.foreground component entry] insert end $newColor;
}
proc set_hl_bg {newColor} {
  global currentColor;

  if  {$newColor != ""} {
  set currentColor $newColor;
  .searchFrame.color configure -background $currentColor;
  .searchFrame.color configure -text "Palette:$currentColor";
  [.searchFrame.search6 component label] configure -background $currentColor;
   setDefaultHighlight 6;
  } else {
    setDefaultHighlight 6;
  }
  update;
}

proc pickColor {} {
    global currentColor;
    set tags [lreverse [.t tag names [.t index insert]]];
    foreach atag $tags {
        if { [regexp -nocase {^#[0-9A-F]{6}} $atag ] }  {
             regsub -all {^(#[(0-9)A-Fa-f]{6}).*$} $atag {\1} atag;
             set currentColor $atag;
             .searchFrame.color configure -background $currentColor;
             .searchFrame.color configure -text "Palette:$currentColor";
             [.searchFrame.search6 component label] configure -background $currentColor;
             setDefaultHighlight 6;
             #highlightCurrent .t [.t index insert];
             focus .t.t;
             update;
             return;
        }
    }
    foreach atag $tags {
        set newColor [.t tag cget $atag -background];
        if {$newColor != ""} {
          set currentColor $newColor;
          .searchFrame.color configure -background $currentColor;
          .searchFrame.color configure -text "Palette:$currentColor";
          [.searchFrame.search6 component label] configure -background $currentColor;
          setDefaultHighlight 6
          #highlightCurrent .t [.t index insert];
          focus .t.t;
          update;
          return;
        } 
    }
}

proc alltags {} {
    set tags [lreverse [.t tag names [.t index insert]]];
    return $tags;
}

proc seltag {} {
    set tags [lreverse [.t tag names [.t index insert]]];
    foreach atag $tags {
        if {$atag != "sel"} {
            set ranges [.t tag ranges $atag];
            foreach {start end} $ranges {
                .t tag add sel $start $end;
            }
        }   
    }  
    .t tag raise sel;

}

proc seltags {tagregex} {
    set tags [lreverse [.t tag names]];
    foreach atag $tags {
        if {![regexp $tagregex $atag] } continue;
        if {$atag != "sel"} {
            set ranges [.t tag ranges $atag];
            foreach {start end} $ranges {
                .t tag add sel $start $end;
            }
        }   
    }  
    .t tag raise sel;

}
bind [.searchFrame.search6 component label] <ButtonPress-1> {highlightSelectedString 1 6 [uplevel #0 "set currentColor"]}

bind [.searchFrame.search6 component entry] <Up> {searchString -1 6 [uplevel #0 "set currentColor"]}
bind [.searchFrame.search6 component entry] <Down> {searchString 1 6 [uplevel #0 "set currentColor"]}

bind [.searchFrame.search6 component entry] <Control-Up> {searchString -2 6 [uplevel #0 "set currentColor"]}
bind [.searchFrame.search6 component entry] <Control-Down> {searchString 2 6 [uplevel #0 "set currentColor"]}

proc startNote {id} {
    global currentColor;
    global fixed_boxes;
   
    set selranges [.t tag ranges sel];
    if {[llength $selranges] == 2} {
        set cont [.t get [lindex $selranges 0] [lindex $selranges 1]];
        [.searchFrame.search$id component entry] delete 0 end;
        [.searchFrame.search$id component entry] insert end $cont;
        .t tag remove sel 1.0 end;
        focus [.searchFrame.search$id component entry];
        return;
    }
    set col $currentColor;
    if {$id < 6} {
       set col [lindex $fixed_boxes [expr 2*$id - 1]];
    }
    set insert_pos [.t index insert];
    set boundingBox [.t bbox $insert_pos];
    if {[llength $boundingBox]} {
        .t tag configure $col -background $col;
        .t insert $insert_pos "  " $col;
        .t mark set insert "$insert_pos + 1 char";
    }

    setDefaultHighlight $id;
}

proc saveToFile {w} {
     set types {
        {{Spectral Text Files} {.stxt}}
     }

    set fname [tk_getSaveFile -filetypes $types];
    if {$fname == ""} {
        return;
    }
    if {![regexp -nocase "\\.stxt" $fname]} {
        append fname ".stxt";
    }

    set cont [text:save $w];
    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts $fp $cont;
    close $fp;
}
proc read_file_contents {fname}  {
    set fp [open $fname rb];
    fconfigure $fp -translation binary;
    set data  [read $fp];
    close $fp;
    return $data;
}

proc read_ascii_file_contents {fname}  {
    set fp [open $fname rb];
    fconfigure $fp -translation binary;
    set data  [read $fp];
    set data [string map {"\r\n" "\n"} $data]
    close $fp;
    return $data;
}

proc write_to_file {fname  data}  {
    set fp [open $fname w];
    fconfigure $fp -translation binary;
    puts -nonewline $fp $data;
    close $fp;
}


proc saveToHltFile {w args} {
    set fname "";
    if {[llength $args]} {
        set fname [lindex $args 0];
    } else {
       set types {
          {{Highlighted Text Files} {.hlt}}
       }
       set fname [tk_getSaveFile -filetypes $types];
    }
     if {$fname == ""} {
           return;
        }
    if {![regexp -nocase "\\.hlt" $fname]} {
        append fname ".hlt";
    }

    set cont [hlt:save $w savingToFile];
    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts $fp $cont;
    close $fp;
}

proc saveToTextFile {w fname} {
  set cont [$w get 0.0 end];
  if {[file exists $fname]} {
    set fpr [open $fname r];
    fconfigure $fpr -encoding utf-8
    set oldcont [read $fpr];
    close $fpr;
    if {$cont != $oldcont} {
      set fp [open $fname w];
      fconfigure $fp -encoding utf-8
      puts -nonewline $fp $cont;
      close $fp;
    }
   } else {
      set fp [open $fname w];
      fconfigure $fp -encoding utf-8
      puts -nonewline $fp $cont;
      close $fp;
   }
}

proc sendRecentFileListToEditor {} {
    global recentfiles;
    global new_recentfiles;
    foreach recentfile $recentfiles {
       .t insert [.t index insert] $recentfile;
       .t insert [.t index insert] ":1:\n";
    }   
    foreach recentfile $new_recentfiles {
       .t insert [.t index insert] $recentfile;
       .t insert [.t index insert] ":1:\n";
    }   
}

proc get_current_filename {} {
    global current_file;
    return $current_file;
}
proc full_path_name {filename} {
     set savewd [pwd]
     set realFile [file join $savewd $filename]
     # Hmm.  This (unusually) looks like a job for do...while!
     cd [file dirname $realFile]
     set dir [pwd] ;# Always gives a canonical directory name
     set filename [file tail $realFile]
     while {![catch {file readlink $filename} realFile]} {
         cd [file dirname $realFile]
         set dir [pwd]
         set filename [file tail $realFile]
     }
     cd $savewd
     return [file join $dir $filename]
 }

proc openFile {w args} {
   
   global current_file;
   global cmd_to_editor;
   set types {
       {{All Files}      {.*}       }
    }
    set fname "";
    if {[llength $args]} {
        set fname [lindex $args 0];
    } else {
       set fname [tk_getOpenFile -filetypes $types];
    }


    if {$fname == ""} {
        return;
    }

    set cmd_to_editor 0;
    
    ## We are already loading a file so pass 0 to edit:close
    edit:close 0;
    set current_file $fname;
    set msg "";
    if {[ catch {
           if {[file exists "$fname.hlt"]} {
              loadFromHltFile $w "$fname.hlt";
              mergeWithFile $fname;
           } else {
              loadFromTextFile $w $fname;
           }
       } msg ]} {
           tk_messageBox -message $msg; 
    }
    
    set fname [full_path_name $fname];

    global title_prefix;
    wm title . "$title_prefix-$fname";

    set current_file $fname;
    
    
    global recentfiles;
    global new_recentfiles;
    global menu;
    if {([lsearch $recentfiles $fname] == -1) && ([lsearch $new_recentfiles $fname] == -1)} {
        set new_recentfiles [linsert   $new_recentfiles 0 $fname];
        $menu.recent add separator;
        $menu.recent add command -label $fname -command "openFile .t  \"$fname\"";
  
    }

    global file_lastmod;
    set file_lastmod [file mtime $current_file];


    loadOverview;
    ctext::linemapUpdate $w;
    global modified;
    set modified 0;
    .t edit reset;
    .t edit modified 0;
    updateModifiedStatus;
}

proc loadOverview {} {
    set w [.textFrame.overview component text];
     $w configure -undo 0;
    $w configure -state normal;
    $w delete 1.0 end;
    set cont [hlt:save .t];
    hlt:restore $w $cont overview;
    $w configure -state disabled;
    $w tag configure tiny -font "courier 2 normal";
    $w tag raise tiny;
    $w tag add tiny 1.0 end;
    $w yview [.t index 1.0];
    update;
    
}
proc saveFile {w} {
     global current_file;
     global saving;
     set saving 1;
     global cmd_to_editor;
     
     if {$current_file == ""} {
       saveFileAs $w;
       return;
     }

     set cmd_to_editor 0;
     saveAll $w $current_file;
    
    global modified;
    set modified 0;
    updateModifiedStatus;
    
    global file_lastmod;
    set file_lastmod [file mtime $current_file];
    set saving 0;
}
proc saveFileAs {w} {
    global current_file;
    global saving;
    set saving 1;
     global cmd_to_editor;
     set cmd_to_editor 0;
    
    set types {
        {{All Files} {.*}}
    }

    set fname [tk_getSaveFile -filetypes $types];
    if {$fname == ""} {
        return;
    }

    global modified;
    set modified 0;
    updateModifiedStatus;

    set current_file $fname;
    global title_prefix;

    
    wm title . "$title_prefix-$fname";
    saveAll $w $fname;

    global file_lastmod;
    set file_lastmod [file mtime $current_file];
    
    global recentfiles;
    global new_recentfiles;
    global menu;
    if {([lsearch $recentfiles $fname] == -1) && ([lsearch $new_recentfiles $fname] == -1)} {
        set new_recentfiles [linsert   $new_recentfiles 0 $fname];
        $menu.recent add separator;
        $menu.recent add command -label $fname -command "openFile .t  \"$fname\"";
  
    }


    set saving 0;

}

proc saveAll {w fname} {
     saveToTextFile $w $fname;
     saveToHltFile $w "$fname.hlt";
 
    global modified;
    set modified 0;
    
}

proc loadFromTextFile {w fname} {
    global last_search;
    global rotate;
    global cmd_to_editor;
    set cmd_to_editor 0;
    
    set fp [open $fname r];
    fconfigure $fp -encoding utf-8
    set cont [read $fp];
    close $fp;
    .t fastdelete 0.0 end
    $w insert end $cont;
    array unset last_search;
    array unset rotate;
}

proc printEditorContents {w} {

        global tmpdir;
        set uid [guid]
        set fname "$tmpdir/$uid.html"
        set cont [text:toHtml [text:save $w] $tmpdir "$uid.html" 0];
        set fp [open $fname w];
        fconfigure $fp -encoding utf-8
        puts $fp $cont;
        close $fp;

        global current_file;

        set pageroot {HKEY_CURRENT_USER\Software\Microsoft\Internet Explorer\PageSetup};
        catch {
        set old_header [registry get $pageroot header];
        set old_footer [registry get $pageroot footer];
        set old_font [registry get $pageroot font];
        set old_Print_Background [registry get $pageroot Print_Background];
        set old_Shrink_To_Fit [registry get $pageroot Shrink_To_Fit];
        } msg;
        #puts $msg;
        catch {

        registry set $pageroot header $current_file;
        registry set $pageroot footer "Page &p of &P";
        registry set $pageroot Print_Background yes;
        registry set $pageroot Shrink_To_Fit yes;
        } msg;
        #puts $msg;
        catch {
     
        set batname "$tmpdir/print_${uid}.bat";
        set bfp [open $batname w];
        puts $bfp "rundll32.exe MSHTML.DLL,PrintHTML \"file://$fname\"";
        close $bfp;

        # print
        exec $batname;
       
        file delete -force $batname;
        file delete -force $fname;
       } msg;
       #puts $msg;
               
       catch {
        registry set $pageroot header $old_header;
        registry set $pageroot footer $old_footer;
        registry set $pageroot Print_Background $old_Print_Background;
        registry set $pageroot Shrink_To_Fit $old_Shrink_To_Fit; 
       } msg;
       #puts $msg;
}

proc saveColocatedHtml {} {
   global current_file;
   if {$current_file == ""} {
       return;
   }
   set fname $current_file;
   append fname ".html";
   set cont [text:toHtml [text:save .t] {}  $fname 0];
   set fp [open $fname w];
   fconfigure $fp -encoding utf-8
   puts $fp $cont;
   close $fp; 

}

proc saveColocatedEHtml {} {
   global current_file;
   if {$current_file == ""} {
       return;
   }
   set fname $current_file;
   append fname ".ehtml";
   set cont [text:toHtmlGeneral [text:save .t] {}  $fname 0 0 0 1 0];
   set fp [open $fname w];
   fconfigure $fp -encoding utf-8
   puts $fp $cont;
   close $fp; 

}



proc saveToCommentableHtmlFile {w} {
    set types {
    {{Web Pages}      {.html}       }
    {{Web Pages}      {.htm}        }
     }

    set fname [tk_getSaveFile -filetypes $types];
    if {$fname == ""} {
        return;
    }

     if {![regexp  -nocase "\\.html?$" $fname]} {
        append fname ".html";
    }

    set cont [text:toHtmlGeneral [text:save $w] {}  $fname 0 1 0 0 0];
    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts $fp $cont;
    close $fp;    
}

proc saveToEmbeddableHtmlFile {w} {
    set types {
    {{Embeddable Web Content}      {.ehtml}       }
    {{Embeddable Web Content}      {.ehtm}        }
     }

    set fname [tk_getSaveFile -filetypes $types];
    if {$fname == ""} {
        return;
    }

     if {![regexp  -nocase "\\.ehtml?$" $fname]} {
        append fname ".ehtml";
    }

    set cont [text:toHtmlGeneral [text:save $w] {}  $fname 0 0 0 1 0];
    clipboard clear;
    clipboard append $cont;
    
    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts $fp $cont;
    close $fp;    
}

proc saveToHtmlFileWithMediaIndex {w} {
    set types {
    {{Web Pages}      {.html}       }
    {{Web Pages}      {.htm}        }
     }

    set fname [tk_getSaveFile -filetypes $types];
    if {$fname == ""} {
        return;
    }

     if {![regexp  -nocase "\\.html?$" $fname]} {
        append fname ".html";
    }

    set cont [text:toHtmlWithMediaIndex [text:save $w] {}  $fname 0];
    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts $fp $cont;
    close $fp;    
}

proc saveToHtmlFileWithoutMediaIndex {w} {
    set types {
    {{Web Pages}      {.html}       }
    {{Web Pages}      {.htm}        }
     }

    set fname [tk_getSaveFile -filetypes $types];
    if {$fname == ""} {
        return;
    }

     if {![regexp  -nocase "\\.html?$" $fname]} {
        append fname ".html";
    }

    set cont [text:toHtml [text:save $w] {}  $fname 0];
    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts $fp $cont;
    close $fp;    
}

proc saveWalkthrough {w} {
    set types {
    {{Web Pages}      {.html}       }
    {{Web Pages}      {.htm}        }
     }

    set fname [tk_getSaveFile -filetypes $types];
    if {$fname == ""} {
        return;
    }

     if {![regexp  -nocase "\\.html?$" $fname]} {
        append fname ".html";
    }

    set cont [text:toHtmlWalkthrough [text:save $w] {}  $fname 0];
    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts $fp $cont;
    close $fp;    
}

proc saveWalkthroughEmbeddable {w} {
    set types {
    {{Embeddable Web Pages}      {.ehtml}       }
    {{Embeddable Web Pages}      {.ehtm}        }
     }

    set fname [tk_getSaveFile -filetypes $types];
    if {$fname == ""} {
        return;
    }

     if {![regexp  -nocase "\\.ehtml?$" $fname]} {
        append fname ".ehtml";
    }

    set cont [text:toEmbeddableHtmlWalkthrough [text:save $w] {}  $fname 0];
    clipboard clear;
    clipboard append $cont;
    
    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts $fp $cont;
    close $fp;    
}

proc saveHtmlFile {fname w} {

    set cont [text:toHtml [text:save $w] {}  $fname 0];
    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts $fp $cont;
    close $fp;    
}

proc hasMultiSelection {} {
   set selranges [.t tag ranges sel];
   if {[llength $selranges] > 2} {
       return 1;
   }
   return 0;
}

proc hasSelection {} {
   set selranges [.t tag ranges sel];
   foreach {start end} $selranges {
       return 1;
   }
   return 0;
}
proc copyToHtmlClipboard {w} {
    global tmpdir;
    global installdir;
    set selranges [.t tag ranges sel];
    .t tag remove sel 1.0 end;
    foreach {start end} $selranges {

        set cont [text:toHtml [text:save $w $start  $end] $tmpdir "clipboard.html"  1];
        set fp [open "$tmpdir/clipboard.html" w];
        fconfigure $fp -encoding utf-8
        puts $fp $cont;
        close $fp;
        clipboard clear;
        exec "$installdir/wbin/HtmlClipboard.exe" "$tmpdir/clipboard.html"
        break;
    }

    foreach {start end} $selranges {
       .t tag add sel $start $end;
    }
}

proc loadFromFile {w} {
    global rotate;
    global last_search;

    set types {
    {{Spectral Text Files}      {.stxt}       }
     }

    set fname [tk_getOpenFile -filetypes $types];
    if {$fname == ""} {
        return;
    }
    set fp [open $fname r];
    fconfigure $fp -encoding utf-8
    set cont [read $fp];
    close $fp;
    text:restore $w $cont
    
    array unset last_search;
    array unset rotate;

}

proc loadFromHltFile {w args} {
    global rotate;
    global cmd_to_editor;
    global last_search;
    global current_file;
    
    
    set fname "";
    if {[llength $args]} {
        set fname [lindex $args 0];
    } else {
       set types {
          {{Highlighted Text Files}      {.hlt}       }
       }
       set fname [tk_getOpenFile -filetypes $types];
    }
    if {$fname == ""} {
        return;
    }
    set cmd_to_editor 0;
    
    set current_file $fname;
    global title_prefix;
    if {$title_prefix == ""} {
        wm title . "Spectral Editor";
    } else {
        wm title . "$title_prefix-Spectral Editor"
    }
    
    set fp [open $fname r];
    fconfigure $fp -encoding utf-8
    set cont [read $fp];
    close $fp;
    set cont [trimMergeConflict $cont];
    $w configure -undo 0;
    hlt:restore $w $cont loadingFromFile;
    $w configure -undo 1;
   
    
    global file_lastmod;
    set file_lastmod [file mtime $current_file];

    array unset last_search;
    array unset rotate;

}

set finalLine "";
proc trimMergeConflict {cont} {
  set result "";
  global finalLine;
  set lines [split $cont "\n"];
  set num [llength $lines];
  set startsWithConflict 0;
  for {set i 0} {$i < $num} {incr i} {
      set line [lindex $lines $i];
      if {[string range $line 0 4] == "<<<<<"} {
          if {$i == 0} {
             append result  " T {" $line "\n} ";
             set startsWithConflict 1;
          } else {
             append result $line "\n";
          }
       } elseif {$startsWithConflict && [string range $line 0 4] == "=====" } {
            # {
            append result  "} T {" $line "\n} ";
           set startsWithConflict 0;

       } elseif {[string range $line 0 4] == "=====" } {
           set line2 "";
           set lastOne 1;
           for {set j $i} {$j < $num} {incr j} {
              set line2 [lindex $lines $j];
              if {$line2 == ""} continue;
              set finalLine $line2;
              if {[string range $line2 0 4] == "<<<<<"} {
                 set lastOne 0;
              } 
           }
          if {$lastOne && [string range $finalLine 0 4] == ">>>>>"} {
                  append  result  " T {\n" $line "\n";
                  # }
          } else {
                  append result $line "\n";
          }
           
       }  elseif {$i >= [expr $num - 2] && [string range $line 0 4] == ">>>>>"} {
          append result  " T {\n" $line "} ";
      } else {
          append result $line "\n"; 
      }
  }
  
  return $result;
}

proc filepath {} {
    global current_file;
    return $current_file;
}



proc edit:close {{load_old_text 1}} {
    checkForSave;
    edit:closeNoAsk $load_old_text;
}

proc edit:closeNoAsk {{load_old_text 1}} {
    

    #Reset the viewpoints list
    global viewpoints;
    global _viewpointPosition;
    set viewpoints {};
    set _viewpointPosition 0;

    global current_file;
    global old_dump;
    global old_dump_pos;
    global dbl_click_behavior;
    global old_mode;
    global file_lastmod;
    .textFrame.overview delete 1.0 end;
    global cmd_to_editor;
    set current_file "";
    set file_lastmod "";
    set cmd_to_editor 1;
    .t fastdelete 1.0 end;
    .t edit reset;
    
    reset_metadata;
    
   
    global title_prefix;
    wm title . "$title_prefix-Spectral Text";
    
    foreach tag [.t tag names] {
          .t tag remove $tag 1.0 end;
    }

    .t edit reset;

    global target;
    set target .t;
    .t edit reset;

    if {$load_old_text && [string length  $old_dump]} {
        hlt:restore .t $old_dump
        catch {
            set dbl_click_behavior $old_mode;
            .t see $old_dump_pos;
            .t mark set insert  $old_dump_pos;
            .t tag add sel [.t index "$old_dump_pos linestart"] [.t index "$old_dump_pos lineend"];
            
            
        }
    }

    global modified;
    set modified 0;
    update;
    return "";
}

proc text:save {w args} \
{ 
    set start 1.0;
    set end end;
    if {[llength $args] == 2} {
         set start [lindex $args 0];
         set end [lindex $args 1];
     }
    
    set tags {};
    # the resulting string
    set save {}
    # get the state of the widget
    set dump [$w dump -mark $start $end]
    append dump " "
    append dump [$w dump -all $start $end]
    # add more details
    foreach {key value index} $dump \
    {
        switch $key \
        {
            
            mark    \
            {
                # add attributes of a mark
                lappend save $key $value $index
                set exec "\$w mark gravity $value [$w mark gravity $value]"
                lappend save exec $exec {}
            }
            tagoff  \
            {
                if {[lsearch $tags $value] == -1} {
                lappend tags $value;
                # add attributes of a tag
                set exec "\$w tag configure $value"
                set keys {}
                lappend keys -background -bgstipple -borderwidth -elide -fgstipple
                lappend keys -font -foreground -justify -lmargin1 -lmargin2 -offset
                lappend keys -overstrike -relief -rmargin -spacing1 -spacing2
                lappend keys -spacing3 -tabs -underline -wrap
                foreach k $keys \
                { 
                    set v [$w tag cget $value $k]
                    if {$v != ""} { append exec " $k \{$v\}" }
                }

                lappend save exec $exec {}
                }
                lappend save $key $value $index
            }
            window  \
            {
                # add attributes of a window
                lappend save $key $value $index
                set exec "\$w window configure $index"
                foreach k {-align -create -padx -pady -stretch} \
                { 
                    set v [$w window cget $index $k]
                    if {$v != ""} { append exec " $k \{$v\}" }
                }
                lappend save exec $exec {}
            }
            default \
            {
                lappend save $key $value $index
            }
        }
    }
    # return the serialized widget
    return $save
}

proc load_html {args} {
  if {[llength $args] == 0} {
     set fname [tk_getOpenFile];
  } else {
     set fname [lindex $args 0];
  }

  createHtmlWindow "HTML Viewer" $fname;
}
proc load_binary {args} {
 if {[llength $args] == 0} {
     set fname [tk_getOpenFile];
 } else {
     set fname [lindex $args 0];
 }
 if {$fname == ""} {
     tk_messageBox -message "File not specified";
     return;
 }
 set fp [open $fname r];
 fconfigure $fp -translation binary;
 set inBinData [read $fp];
 close $fp
 binary scan $inBinData B* val
 set len [string length $val];
 set txt ""; 
 for {set i 0} {$i < $len} {incr i} {   
    append txt [string index $val $i];
    if {[expr $i % 80] == 79} {
        append txt "\n";
    } elseif {[expr $i % 8] == 7} {
        append txt " "
    }
 }
 .t insert end $txt;
 
}



proc load_line_fields {field_nums separator outsep {fname {}} } {
    if {$fname == ""} {
        set fname [tk_getOpenFile];
    } 
    if {$fname == ""} {
        tk_messageBox -message "File not specified";
        return;
    }
    set fp [open $fname r];
    set lnum 0;
    while {![eof $fp]} {
        set line [gets $fp];
        set parts [split $line $separator];
        foreach field_num $field_nums {
            .t insert end [lindex $parts $field_num];
            .t insert end $outsep;
        }
        .t insert end "\n";
    }
    close $fp; 
}

proc load_line_stringrange {start end {fname {}} } {
    if {$fname == ""} {
        set fname [tk_getOpenFile];
    } 
    if {$fname == ""} {
        tk_messageBox -message "File not specified";
        return;
    }
    set fp [open $fname r];
    set lnum 0;
    while {![eof $fp]} {
        set line [gets $fp];
        set substr [string range $line $start $end];
        .t insert end $substr;
        .t insert end "\n"
    }
    close $fp; 
}
proc hex2dec {args} {
    set largeHex "";
    if {[llength $args]} {
      foreach arg $args {
         append largeHex $arg;
      }
    } else {
     set selranges [.t tag ranges sel];
     foreach {start end} $selranges {
       append largeHex [.t get $start $end];
     }
    }
    regsub -all {\s*} $largeHex {} largeHex;
    set res 0
    foreach hexDigit [split $largeHex {}] {
        set new 0x$hexDigit
        set res [expr {16*$res + $new}]
    }
    return $res;
}

proc double2bin {args} {
    set input "";
    if {[llength $args]} {
      foreach arg $args {
         append input $arg;
      }
    } else {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
         append input [.t get $start $end];
      }
    }
    regsub -all {\s*} $input {} input;
    binary scan [binary format d $input] b* n;
    return [string reverse $n];
}

proc bin2double {args} {
    set input "";
    if {[llength $args]} {
      foreach arg $args {
         append input $arg;
      }
    } else {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
         append input [.t get $start $end];
      }
    }
    regsub -all {\s*} $input {} input;
    binary scan [binary format b* [string reverse $input]] d n;
    return $n;
}

proc float2bin {args} {
    set input "";
    if {[llength $args]} {
      foreach arg $args {
         append input $arg;
      }
    } else {
    set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
       append input [.t get $start $end];
      }
    }
    regsub -all {\s*} $input {} input;
    binary scan [binary format f $input] b* n;
    return [string reverse $n];
}

proc bin2float {args} {
    set input "";
    if {[llength $args]} {
      foreach arg $args {
         append input $arg;
      }
    } else {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
       append input [.t get $start $end];
      }
    }
    regsub -all {\s*} $input {} input;
     binary scan [binary format b* [string reverse $input]] f n;
    return $n;
}

proc int2bin {nbits args} {
    
    set input "";
    if {[llength $args]} {
      foreach arg $args {
         append input $arg;
      }
    } else {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
         append input [.t get $start $end];
      }
    }
    regsub -all {\s*} $input {} input;
    binary scan [binary format i $input] "b${nbits}" n;
    return [string reverse $n];
}

proc hex2bin {args} {
    
    set input "";
    if {[llength $args]} {
      foreach arg $args {
         append input $arg;
      }
    } else {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
         append input [.t get $start $end];
      }
    }
    regsub -all {\s*} $input {} input;
    regsub -all {0x} $input {} input;
    regsub -all {,} $input {} input;
    set input [split $input {}];
    set output "";
    set cnt 0;
    foreach {x} $input {
        binary scan [binary format h "${x}"] "b4" n;
        append output [string reverse $n]

        if {[expr $cnt % 20] == 19} {
           append output "\n";
        } elseif {[expr $cnt % 2] == 1} {
           append output " "
        }
        incr cnt;
    }
    return $output ;
}

# needs to be full bytes in order to interpret as 2's compliment negs
proc bin2int {args} {
    set input "";
    if {[llength $args]} {
      foreach arg $args {
         append input $arg;
      }
    } else {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
         append input [.t get $start $end];
      }
    }
    regsub -all {\s*} $input {} input;
    binary scan [binary format b* [string reverse $input]] i* n;
    return  $n;
}

proc bin2hex {args} {
    set input "";
    if {[llength $args]} {
      foreach arg $args {
         append input $arg;
      }
    } else {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
         append input [.t get $start $end];
      }
    }
    regsub -all {\s*} $input {} input;
    set input [split $input {}];
    set output "";
    set i 0;
    foreach {a b c d e f g h} $input {
        binary scan [binary format b8 "$h$g$f$e$d$c$b$a"] H2 n;
        append output $n " ";
        if {[expr $i % 40] == 39} {
          append output "\n";
        }
        incr i;

    }
    return  $output;
}


proc bin2chex {args} {
    set input "";
    if {[llength $args]} {
      foreach arg $args {
         append input $arg;
      }
    } else {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
         append input [.t get $start $end];
      }
    }
    regsub -all {\s*} $input {} input;
    set input [split $input {}];
    set output "";
    set i 0;
    foreach {a b c d e f g h} $input {
        binary scan [binary format b8 "$h$g$f$e$d$c$b$a"] H2 n;
        append output "0x$n, ";
        if {[expr $i % 40] == 39} {
          append output "\n";
        }
        incr i;

    }
    return  $output;
}

proc bin2dec {args} {
    set largeBin "";
    if {[llength $args]} {
      foreach arg $args {
         append largeBin $arg;
      }
    } else {
     set selranges [.t tag ranges sel];
     foreach {start end} $selranges {
       append largeBin [.t get $start $end];
     }
    }
    regsub -all {\s*} $largeBin {} largeBin;
    set res 0
    foreach binDigit [split $largeBin {}] {
        set new $binDigit
        set res [expr {2*$res + $new}]
    }
    return $res
}

proc save_binary {} {
     set input "";
    set selranges [.t tag ranges sel];
    foreach {start end} $selranges {
       append input [.t get $start $end];
    }
    regsub -all {\s*} $input {} input;
    set bin [binary format B* $input];
    set fname [tk_getSaveFile];
    set fp [open $fname w];
    fconfigure $fp -translation binary;
    puts -nonewline $fp $bin;
    close $fp;

}

proc save_hex {} {
     set input "";
    set selranges [.t tag ranges sel];
    foreach {start end} $selranges {
       append input [.t get $start $end];
    }
    regsub -all {\s*} $input {} input;
    set bin [binary format H* $input];
    set fname [tk_getSaveFile];
    set fp [open $fname w];
    fconfigure $fp -translation binary;
    puts -nonewline $fp $bin;
    close $fp;

}

proc load_hex {args} {
 if {[llength $args] == 0} {
     set fname [tk_getOpenFile];
 } else {
     set fname [lindex $args 0];
 }
 if {$fname == ""} {
     tk_messageBox -message "File not specified";
 }
 set fp [open $fname r];
 fconfigure $fp -translation binary;
 set inBinData [read $fp];
 close $fp
 binary scan $inBinData H* val
 set len [string length $val];
 set txt ""; 
 for {set i 0} {$i < $len} {incr i} {   
    append txt [string index $val $i];
    if {[expr $i % 80] == 79} {
        append txt "\n";
    } elseif {[expr $i % 2] == 1} {
        append txt " "
    }
 }
 .t insert end $txt;
 
}

proc strdiff_files {granularity file1 file2} {
  set cont1 [read_file_contents $file1];
  set cont2 [read_file_contents $file2];
  if { $cont1 == $cont2 } {
     tk_messageBox -message "Files are identical";
     return;
  }
  strdiff $granularity $cont1 $cont2;
}

package require struct::set
proc diffdiff { { ignore_re {} } } {
    set selranges [.t tag ranges sel];
    set lhs {};
    set rhs {};
    foreach {start end} $selranges {
        set txt [.t get $start $end];
        set lines [split $txt "\n"];
        foreach line $lines {
            if {[string range $line 0 0] == ">" } {
                set line [string range $line 1 end];
                if {$ignore_re != "" } { regsub -all $ignore_re $line {} line };
                lappend lhs $line;
            } elseif {[string range $line 0 0] == "<" } {
                set line [string range $line 1 end];
                if {$ignore_re != "" } { regsub -all $ignore_re $line {} line };
                lappend rhs $line
            }
        }
    }
    set diff1 [::struct::set difference $lhs $rhs];
    puts "In > but not in <"
    foreach diff $diff1 {
        puts $diff;
    }
    set diff2 [::struct::set difference $rhs $lhs];
    puts "In < but not in >"
    foreach diff $diff2 {
        puts $diff;
    }
}

proc strdiff {granularity {string1 {} } {string2 {} } {wnd {}} } {
 
  set selranges [.t tag ranges sel];
  # text strings to "difference":
  if {$string1 == ""} {
    if {[llength $selranges] != 4} {
         tk_messageBox -message "Two selected regions are needed for comparison";
         return;
    }
    set string1  [.t get [lindex $selranges 0] [lindex $selranges 1]]
    set string2  [.t get [lindex $selranges 2] [lindex $selranges 3]]
  } elseif {$string2 == ""} {
    if {[llength $selranges] != 2} {
         tk_messageBox -message "Need a single selection for comparison";
         return;
    }
    set string2  [.t get [lindex $selranges 0] [lindex $selranges 1]]
  }
  set wordorchar [string range $granularity 0 3];  
  if {$wordorchar == "char" } {
    set list1 [ split $string1 "" ]
    set list2 [ split $string2 "" ]
  } elseif {$wordorchar == "word"} {
    set list1 [ regexp -all -inline {\S+|\s+} $string1 ]
    set list2 [ regexp -all -inline {\S+|\s+} $string2 ]
  }  elseif {$wordorchar == "line"} {
      set list1x [ split $string1 "\n"]
      set list1 {}
      foreach x $list1x {
        lappend list1 [append x "\n"]
      }
      set list2x [ split $string2 "\n"]
      set list2 {}
      foreach x $list2x {
        lappend list2 [append x "\n"]
      }
  }

  if {$granularity == "word_ignorespace" || $granularity == "line_ignorespace" } {
     lremove_regex list1 {^[\t\n\r ]+$} 
     lremove_regex list2 {^[\t\n\r ]+$} 
  }
  if {$granularity == "char_ignorespace"} {
     lremove_regex list1 {[\t\n\r ]} 
     lremove_regex list2 {[\t\n\r ]} 
  }
  
  # these next two lines perform the "diff" operation

  set lcsdata  [ struct::list longestCommonSubsequence $list1 $list2 ]

  set diffdata [ struct::list lcsInvertMerge $lcsdata \
                                             [ llength $list1 ] \
                                             [ llength $list2 ] ]

  # format the result into the text widget:
  if {$wnd == ""} {
     set resultsWindow [createResultsWindow "strdiff results"];
     set wnd $resultsWindow.results;
  }
  
  $wnd tag configure inserted -underline true -background #aafba2;
  $wnd tag configure deleted  -overstrike true -background  #fd9f9f;
  foreach item $diffdata {
    lassign $item kind idx1 idx2
    switch -exact $kind {
      added     { $wnd insert end [ join [ lrange $list2 {*}$idx2 ] "" ] inserted;
       }
      deleted   { $wnd insert end [ join [ lrange $list1 {*}$idx1 ] "" ] deleted;
       }
      changed   { $wnd insert end [ join [ lrange $list1 {*}$idx1 ] "" ] deleted;
                  $wnd insert end [ join [ lrange $list2 {*}$idx2 ] "" ] inserted ;
              }
      unchanged { $wnd insert end [ join [ lrange $list1 {*}$idx1 ] "" ] {};
          }
      }
      
    }
}

proc strdiff++ {granularity ignore_regex {string1 {} } {string2 {} } {wnd {} } } {
 
  set selranges [.t tag ranges sel];
  # text strings to "difference":
  if {$string1 == ""} {
    if {[llength $selranges] != 4} {
         tk_messageBox -message "Two selected regions are needed for comparison";
         return;
    }
    set string1  [.t get [lindex $selranges 0] [lindex $selranges 1]]
    set string2  [.t get [lindex $selranges 2] [lindex $selranges 3]]
  } elseif {$string2 == ""} {
    if {[llength $selranges] != 2} {
         tk_messageBox -message "Need a single selection for comparison";
         return;
    }
    set string2  [.t get [lindex $selranges 0] [lindex $selranges 1]]
  }
  set wordorchar [string range $granularity 0 3];  
  if {$wordorchar == "char" } {
    set list1 [ split $string1 "" ]
    set list2 [ split $string2 "" ]
  } elseif {$wordorchar == "word"} {
    set list1 [ regexp -all -inline {\S+|\s+} $string1 ]
    set list2 [ regexp -all -inline {\S+|\s+} $string2 ]
  }

  if {$granularity == "word_ignorespace" } {
     lremove_regex list1 {^[\t\n\r ]+$} 
     lremove_regex list2 {^[\t\n\r ]+$} 
  }
  if {$granularity == "char_ignorespace"} {
     lremove_regex list1 {[\t\n\r ]} 
     lremove_regex list2 {[\t\n\r ]} 
  }

  lremove_regex list1 $ignore_regex;
  lremove_regex list2 $ignore_regex;
  
  # these next two lines perform the "diff" operation

  set lcsdata  [ struct::list longestCommonSubsequence $list1 $list2 ]

  set diffdata [ struct::list lcsInvertMerge $lcsdata \
                                             [ llength $list1 ] \
                                             [ llength $list2 ] ]

  # format the result into the text widget:
   # format the result into the text widget:
  if {$wnd == ""} {
     set resultsWindow [createResultsWindow "strdiff results"];
     set wnd $resultsWindow.results;
  }
  
  $wnd tag configure inserted -underline true -background #aafba2;
  $wnd tag configure deleted  -overstrike true -background  #fd9f9f;
  foreach item $diffdata {
    lassign $item kind idx1 idx2
    switch -exact $kind {
      added     { $wnd insert end [ join [ lrange $list2 {*}$idx2 ] "" ] inserted }
      deleted   { $wnd insert end [ join [ lrange $list1 {*}$idx1 ] "" ] deleted  }
      changed   { $wnd insert end [ join [ lrange $list1 {*}$idx1 ] "" ] deleted;
                  $wnd insert end [ join [ lrange $list2 {*}$idx2 ] "" ] inserted }
      unchanged { $wnd insert end [ join [ lrange $list1 {*}$idx1 ] "" ] {} }
      }
    }
}


proc text:restore {w save} \
{   
    if {[catch {
    set slave [::safe::interpCreate];
    interp alias $slave .t {} .t
    interp alias $slave $w {} $w
    $slave eval [list set w $w];
    # empty the text widget
    .t fastdelete 1.0 end
    # create items, restoring their attributes
    foreach {key value index} $save \
    {
        switch $key \
        {
            exec    { 
                regsub -all {[;\"\\\[\]]} $value {} value;
                    if {[regexp  {(^\$w tag configure)|(^\$w mark)|(^\$w window configure)|(^\$w image)} $value ]} {
                    $slave eval $value;
                }
            }
            image   { $w image create $index -name $value }
            text    { $w insert $index $value }
            mark    \
            { 
                if {$value == "current"} { set current $index }
                $w mark set $value $index 
            }
            tagon   { set tag($value) $index }
            tagoff  { $w tag add $value $tag($value) $index }
            window  { $w window create $index -window $value }
        }
    }
    # restore the "current" index
    $w mark set current $current 
    ::safe::interpDelete $slave;
    } msg]} {
       
        addToStatus "$msg : malicious/corrupt content detected" ;
        error "$msg : malicious/corrupt content detected";

    };

}
proc setAlternatingColor {w col1 col2 alt start end} {
     set col "";
     if {$alt} {
         set col $col1;
     } else {
         set col $col2;
     }
     if {$col != ""} {
         $w tag configure $col -background $col;
         $w tag add $col $start $end;
     }
}

proc formatAsTable {w} {
   set col1 [tk_chooseColor -title "Select color of the odd rows"];
   set col2 [tk_chooseColor -title "Select color of the even rows"];
   
   if {[hasMultiSelection]} {
     set alt 0;
     set selranges [.t tag ranges sel];
     foreach {start end} $selranges {
         set alt [expr 1 - $alt];
         setAlternatingColor $w $col1 $col2 $alt $start $end;
     }

   } else {
     set selranges [.t tag ranges sel];
     foreach {start end} $selranges {
       set start [expr int($start)];
       set end   [expr int($end)];
       set alt 0;
       for {set line $start} {$line <= $end} {incr line} {
            set alt [expr 1 - $alt];
            setAlternatingColor $w $col1 $col2 $alt "$line.0" "$line.end + 1c"
       }
     }
   }
}
############################################################
proc hlt:save {w args} \
{
    global image_filenames;
    global general_filenames;
    global sound_filenames;
    global external_hyperrefs;
    global comment_tags;
    global comment_checksums;
    global global_all_verifiers;
    global global_all_generators;
    global global_verifier_tags;
    global global_generator_tags;
    global global_verifier_names;
    global global_generator_names;
    
    set start 1.0;
    set end end;
    
    if {[llength $args] >= 2} {
         set start [lindex $args 0];
         set end [lindex $args 1];
    }

    set savingToFile 0;
    if {[lsearch $args "savingToFile"] != -1} {
        set savingToFile 1;
    }
    set tillEnd 0;
    if {[$w index $end] == [$w index end]} {
        set end [$w index "$end - 1 char"];
        set tillEnd 1;
    }
    set fromStart 0;
    if {[$w index $start] == [$w index 1.0]} {
        set fromStart 1;
    }

    set tags {};
    # the resulting string
    set save {}
    # get the state of the widget
    set dump "";
    append dump [$w dump -all $start $end]
    

    if {$fromStart && $tillEnd} {
         lappend save BG [$w cget -background];
         lappend save DF [$w cget -font];
    }

    # add more details
    foreach {key value index} $dump \
    {
        switch $key \
        {
            tagoff  \
            {
                if {[lsearch $tags $value] == -1} {
                   lappend tags $value;
                   # add attributes of a tag
                   set exec " $value"
                   set keys {}
                   lappend keys -background -bgstipple -borderwidth -elide -fgstipple
                   lappend keys -font -foreground -justify -lmargin1 -lmargin2 -offset
                   lappend keys -overstrike -relief -rmargin -spacing1 -spacing2
                   lappend keys -spacing3 -tabs -underline -wrap
                   foreach k $keys \
                   { 
                       set v [$w tag cget $value $k]
                       if {$v != ""} { append exec " $k \{$v\}" }
                   }
                
                   lappend save P $exec 
                }
                lappend save /S $value 
            }
            tagon  \
            {
                if {[string first target_ $value] == 0 } {
                    set tag [string range $value 7 end];
                    if {[info exists external_hyperrefs($tag)]} {
                        set fname [set external_hyperrefs($tag)];
                        set info {};
                        lappend info $fname;
                        lappend info $tag;
                        lappend save EXT $info;
                    }
                } elseif {[string first hyperref_ $value] == 0 } {
                    set tag [string range $value 9 end];
                    if {[info exists external_hyperrefs($tag)]} {
                        set fname [set external_hyperrefs($tag)];
                        set info {};
                        lappend info $fname;
                        lappend info $tag;
                        lappend save EXT $info;
                    }
                }
                lappend save S $value 
            }
           text \
            {
                
                set parts [split $value "\n"]
                set first_one 1;
                foreach part $parts {
                    if {$first_one} { 
                        set first_one 0;
                    } else {
                        lappend save T "\n"
                    }
                    if {[string length $part]} {
                        lappend  save T $part
                    }

               }

                
            }
            image \
            {
                # If we are sending to clipboard, use 
                # absolute paths, but while
                # writing to file, use relative paths
                # where applicable.
                   
                set fname [set image_filenames($value)];
                if {$savingToFile} {
                    set fname [relativizeFileName $fname];
                }
                global do_embed_images;
                global embedded_content_on_single_line;

                if  {$do_embed_images} {
                    set embedded_image [base64::encode [$value data -format png]];
                    if {$embedded_content_on_single_line} {
                        set embedded_image [regsub -all "\n" $embedded_image " "];
                    }
                    lappend save EI
                    lappend save $embedded_image;
                } else {
                    lappend save I 
                    lappend save $fname;
                }
            }
            window \
            { 
                global do_embed_images;
                global embedded_content_on_single_line;
                if {[info exists sound_filenames($value)]} {
                    set fname [set sound_filenames($value)];
                    if {$savingToFile} {
                        set fname [relativizeFileName $fname];
                     }
                     if  {$do_embed_images} {
                         set embedded_text [base64::encode [read_file_contents $fname]];
                         if {$embedded_content_on_single_line} {
                             set embedded_text [regsub -all "\n" $embedded_text " "];
                         }
                         lappend save EM;
                         set ext [regsub -all {^.*\.([^.]*)$} $fname {\1}];
                         lappend save [list M $ext $embedded_text];
                     } else {
                         lappend save M;
                         lappend save $fname;
                     }
                } elseif {[info exists general_filenames($value)]} {
                    set fname [set general_filenames($value)];
                    if {$savingToFile} {
                        set fname [relativizeFileName $fname];
                     }
                     global comment_tags;
                     global comment_checksums;
                    
                    set ftype [$value cget -text];
                    if {$ftype == "N" || $ftype == "C" || $ftype == "V" || $ftype == "G" } {
                       if  {$do_embed_images} {
                         set embedded_text [base64::encode [read_file_contents $fname]];
                         if {$embedded_content_on_single_line} {
                             set embedded_text [regsub -all "\n" $embedded_text " "];
                         }
                         if {$ftype == "C"} { #saving comment embedded
                              set cmttag [set comment_tags($value)];
                              set cmtchecksum [set comment_checksums($value)];
                            lappend save EC;
                            lappend save [list $cmttag $cmtchecksum $embedded_text];
                         } elseif {$ftype == "V"} { #saving verifier embedded                         
                             lappend save EV; 
                             set veriftag [set global_verifier_tags($value)];
                             set verifname [set global_verifier_names($value)];
                             #add extra information on verifier
                             lappend save [list $verifname $veriftag $embedded_text];    
                         } elseif {$ftype == "G" } { #saving generator embedded
                             lappend save EG; 
                             set genertag [set global_generator_tags($value)];
                             set genername [set global_generator_names($value)];
                             #add extra information on generator
                             lappend save [list $genername $genertag $embedded_text];    
                         } else {
                            lappend save EN;
                            lappend save $embedded_text;
                         }
                      } else {
                          if {$ftype == "C"} { #saving comment
                              set cmttag [set comment_tags($value)];
                              set cmtchecksum [set comment_checksums($value)];
                            lappend save C;
                            lappend save [list $cmttag $cmtchecksum $fname];
                         } elseif {$ftype == "V"} {   #saving verifier                    
                             lappend save V; 
                             set veriftag [set global_verifier_tags($value)];
                             set verifname [set global_verifier_names($value)];
                             #add extra information on verifier
                             lappend save [list $verifname $veriftag $fname];   
                         } elseif {$ftype == "G" } { #saving generator
                             lappend save G; 
                             set genertag [set global_generator_tags($value)];
                             set genername [set global_generator_names($value)];
                             #add extra information on generator
                             lappend save [list $genername $genertag $fname];    
                         } else {
                           lappend save N ;
                           lappend save $fname;
                         }
                      }
                    } else {
                       if  {$do_embed_images} {
                         set embedded_text [base64::encode [read_file_contents $fname]];
                         if {$embedded_content_on_single_line} {
                             set embedded_text [regsub -all "\n" $embedded_text " "];
                         }
                         lappend save EF;
                         set ext [regsub -all {^.*\.([^.]*)$} $fname {\1}];
                         lappend save [list $ftype $ext $embedded_text];
                      } else {
                         lappend save $ftype;
                         lappend save $fname;
                      }
                  }
            }
        }

            default \
            {
                
            }
        }
    
   }
    # return the serialized widget
    return $save
}


proc randomRangeString {length {chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"}} {
    set range [expr {[string length $chars]-1}]

    set txt ""
    for {set i 0} {$i < $length} {incr i} {
       set pos [expr {int(rand()*$range)}]
       append txt [string range $chars $pos $pos]
    }
    return $txt
}


proc randString {} { 
  set chars "abcdefghijklmnopqrstuvwxyz";
  set range [expr {[string length $chars]-1}]
  set pos [expr {int(rand()*$range)}]
  set init [string range $chars $pos $pos]
  set len [expr {10 + int(rand()*5)}]
  set x [randomRangeString $len];
  regsub -all {[\-]} $x "" x
  return "${init}$x";
}

proc get_current_folder {} {
    global current_file;
    global tmpdir;
    if {$current_file == ""} {
        return $tmpdir;
    } elseif {[string first "/" $current_file] == -1} {
        return [pwd];
    } else {
        set result "";
        regsub -all {/[^/]*$} $current_file {} result;
        if {$result  ==  "."} {
            return [pwd];
        }
        return $result;
    }

}
array set sound_filenames {}
array set image_filenames {};
array set image_shrunk {};
array set comment_tags {}
array set comment_checksums {}
proc insertAudioRecording {w} {
      global tmpdir;
      global installdir;
      global play_image;
      global spectral_subfolder;
      global recorder_script;

      set rsname "$tmpdir/[guid].tcl"
      set fps [open $rsname w];
      puts $fps $recorder_script;
      close $fps;
     
      catch {file mkdir "[get_current_folder]/${spectral_subfolder}"}
      set fname "[get_current_folder]/${spectral_subfolder}/[randString].wav";
      global sound_filenames;

      exec $installdir/wbin/tclkit-gui-8_6_4-twapi-4_1_27-x86-max.exe  $rsname $installdir/wbin/ $fname;
      
      if {[file exists $fname]} {
            set pos [$w index insert];
            set btn $w.[randString];
            $w window create $pos -create " button $btn  -image $play_image -relief flat -command \"playMedia $fname\" -background #ccd3f7 -activebackground #a78737";
           after 1000 "setTooltip $btn $fname";
           after 2000 "bind $btn <ButtonPress-3> \{showMediaMenu $btn \"$fname\"\}";
           after 2000 "bind $btn <ButtonPress-2> \{showMediaMenu $btn \"$fname\"\}";
           set sound_filenames($btn) $fname;
      }

      file delete -force $rsname; 
      after 5000  "open \"| $installdir/wbin/lame.exe -V2 $fname $fname.mp3\" r";
      after 10000  "if \[file exists \"$fname.mp3\"\]  \{file delete -force $fname\}";
      after 2000 "bind $btn <ButtonPress-3> \{showMediaMenu $btn \"$fname.mp3\"\}";
      after 2000 "bind $btn <ButtonPress-2> \{showMediaMenu $btn \"$fname.mp3\"\}";
      
      
}
set selected_device "";

proc selected_device {} {
    global selected_device;
    return "audio=\"$selected_device\"";
}
proc isWindowsExecutable {} {
    global isWindowsExecutable;
    return $isWindowsExecutable;
}

proc insertAudioRecordingUsingFfmpeg {w} {
      global tmpdir;
      global installdir;
      global play_image;
      global spectral_subfolder;
      global recorder_script;
      global selected_device;
      
      set toolspath "";
      set driver avfoundation;
      if {[isWindowsExecutable]} {
          set driver dshow;
          set toolspath "$installdir/wbin/"
      }
      ##############
      # Create a new toplevel window
      toplevel .record

      # Set the window title
      wm title .record "Audio Recorder"

      # Set the window size
      wm geometry .record 300x400

      # Create a label widget
      label .record.lbl -text "Select audio device:"

      # Pack the label widget
      pack .record.lbl -side top -pady 10

      # Get a list of audio devices
      
     
      append ffmpegcmd $toolspath ffmpeg;
      catch {set audio_devices [exec $ffmpegcmd -list_devices true -f $driver -i dummy] } audio_devices_msg;
      
      addToStatus "Audio devices msg : <<$audio_devices_msg>>";
      if {![info exists audio_devices]} {
          set audio_devices $audio_devices_msg;
      }
      set audio_devices_lines [split $audio_devices "\n"]
      addToStatus "audio devices : $audio_devices_lines";
      set audio_devices_list {};
      
      foreach audio_device $audio_devices_lines {
          
          if {![regexp {(Microphone)|(Audio)|(Blackwire)} $audio_device]} continue;
          regsub -all {.*"([^"]*)".*} $audio_device {\1} audio_device;
          regsub -all {^.*\]\s*} $audio_device {} audio_device
          
          lappend audio_devices_list $audio_device;
          
      }

      # Create a variable to store the selected audio device
      set selected_device [lindex $audio_devices_list 0]
      set num 0;
      foreach audio_device $audio_devices_list {
          incr num;
          radiobutton .record.device$num -text $audio_device -variable selected_device -value $audio_device
          pack .record.device$num -side top -anchor w
          
      }

      catch { file mkdir "[get_current_folder]/${spectral_subfolder}" }
      set fname "[get_current_folder]/${spectral_subfolder}/[randString].mp3";
      global sound_filenames;

      # Create a button to start recording
      set startcmd "
          # Start recording
          .record.start configure -state disabled;
          exec $ffmpegcmd -f $driver -i \[selected_device\] $fname &
      ";
      set stopcmd "
          # Stop recording
          add_media_file_at \[$w index insert\] $fname;
          update;
          destroy .record;
          after 10000 \"
          catch {
              if {[isWindowsExecutable]} {
                  exec taskkill /IM ffmpeg.exe /F 
              } else {
                  exec killall ffmpeg;
              }
          }

          \" 
      "
      addToStatus "startcmd is $startcmd";
      addToStatus "stopcmd is $stopcmd";
      button .record.start -text "Start Recording" -command $startcmd
      # Pack the buttons
      pack .record.start -side top -fill x -padx 50 -pady 20

      # Create a button to stop recording
      button .record.stop -text "Stop Recording" -command $stopcmd


      pack .record.stop -side top -fill x -padx 50 -pady 20
      # Display the window
      focus .record
}
proc insertMedia {w} {
    set types {
       {{All Files}      {.*}   }
       {{WAV Files}      {.wav} }
       {{MP3 Files}      {.mp3} }
       {{MP4 Files}      {.mp4} }
       {{AVI Files}      {.avi} }
    }
    global sound_filenames;
    global play_image;

    set fname [tk_getOpenFile -filetypes $types];
    if {$fname == ""} {
        return;
    }
    set pos [$w index insert];
    set btn $w.[randString];
    $w window create $pos -create " button $btn  -image $play_image -command \"playMedia $fname\" -background #ccd3f7 -activebackground #a78737";
    after 1000 "setTooltip $btn $fname";
    set sound_filenames($btn) $fname;
    after 2000 "bind $btn <ButtonPress-3> \{showMediaMenu $btn \"$fname\"\}";
    after 2000 "bind $btn <ButtonPress-2> \{showMediaMenu $btn \"$fname\"\}";
}

array set general_filenames {};
proc insertFileReference {w} {
    set types {
       {{All Files}      {.*}   }
    }
    global general_filenames;

    set fname [tk_getOpenFile -filetypes $types];
    if {$fname == ""} {
        return;
    }
    set pos [$w index insert];
    set btn $w.[randString];
    $w window create $pos -create " button $btn  -text F -relief flat -command \{showFile \"$fname\"\} -background #ccd3f7 -activebackground #a78737 -padx 0 -pady 0  -font {Consolas 10}";
    after 1000 "setTooltip $btn \{$fname\}";
    after 2000 "bind $btn <ButtonPress-3> \{showNoteMenu $btn \"$fname\"\}" 
    after 2000 "bind $btn <ButtonPress-2> \{showNoteMenu $btn \"$fname\"\}" 
    set general_filenames($btn) $fname;
}

proc add_file_at {pos fname} {
    global general_filenames;
    set btn .t.[randString];
    .t window create $pos -create " button $btn  -text F -relief flat -command \{showFile \"$fname\"\} -background #ccd3f7 -activebackground #a78737 -padx 0 -pady 0  -font {Consolas 10}";
    after 1000 "catch \"setTooltip $btn \\\{$fname\\\}\"";
    after 2000 "catch \"bind $btn <ButtonPress-3> \\\{showNoteMenu $btn \\\"$fname\\\"\\\}\"" 
    after 2000 "catch \"bind $btn <ButtonPress-2> \\\{showNoteMenu $btn \\\"$fname\\\"\\\}\"" 
    set general_filenames($btn) $fname;
}

proc add_media_file_at {pos fname} {
    insertMediaFile .t $pos $fname;
}

proc actually_add_note {w args} {
   
  set fname $args;

   set txt [$w.input get 1.0 end];
   set fp [open $fname w];
   fconfigure $fp -encoding utf-8
   puts -nonewline $fp $txt;
   close $fp;
   global modified;
   set modified 1;

    global general_filenames;
    set pos [.t index insert];
    set btn .t.[randString];

    .t window create $pos -create " button $btn  -text N -relief flat -command \"showFile \\\"$fname\\\"\" -background #ccd3f7 -activebackground #a78737 -padx 0 -pady 0 -font {Consolas 10}" ;

    after 2000 "catch \"bind $btn <ButtonPress-3> \\\{showNoteMenu $btn \\\"$fname\\\"\\\}\"" 
    after 2000 "catch \"bind $btn <ButtonPress-2> \\\{showNoteMenu $btn \\\"$fname\\\"\\\}\"" 
    after 2000 "catch \"setTooltip $btn \\\"$fname\\\"\"";
    set general_filenames($btn) $fname;
    return 1;
}

proc create_note {pos txt} {
    global spectral_subfolder;
    global general_filenames;
    set rnd [randString];
    catch {file mkdir "[get_current_folder]/${spectral_subfolder}"}
    set fname "[get_current_folder]/${spectral_subfolder}/${rnd}.txt";

    set btn ".t.${rnd}";

    set fp [open $fname w];
    fconfigure $fp -encoding utf-8
    puts -nonewline $fp $txt;
    close $fp;
    global modified;
    set modified 1;

    .t window create $pos -create " button $btn  -text N -relief flat -command \"showFile \\\"$fname\\\"\" -background #ccd3f7 -activebackground #a78737 -padx 0 -pady 0 -font {Consolas 10} " ;


    after 2000 "catch \"bind $btn <ButtonPress-3> \\\{showNoteMenu $btn \\\"$fname\\\"\\\}\""
    after 2000 "catch \"bind $btn <ButtonPress-2> \\\{showNoteMenu $btn \\\"$fname\\\"\\\}\""
    after 2000 "catch \"setTooltip $btn \\\"$fname\\\"\"";
    set general_filenames($btn) $fname;
    return "";
}



proc insert_image {pos fname {tag ""} } {
    global image_filenames;
    set image [image create photo -file $fname];
    set image_filenames($image) $fname;
    .t image create $pos -image  $image;
    if {$tag != ""} {
        .t tag add $tag $pos "$pos + 1 char"
    }
    global image_shrunk;
    set shrunk_image [image create photo]
    $shrunk_image copy $image -subsample 3 3 
    set image_shrunk($fname) $shrunk_image;
}
proc exec_convert {args} {
    global isWindowsExecutable;global installdir;
    if {$isWindowsExecutable} { exec $installdir/wbin/convert.exe {*}$args; } else { exec convert {*}$args;}
}
proc load_slides {} {
   set types {
       {{PNG Files}      {.png}       }
       {{GIF Files}      {.gif}       }
       {{JPEG Files}     {.jpg .jpeg} }
       {{BMP Files}      {.bmp}       }
    }
    global image_filenames;
    global current_file;
    global installdir;
    global tmpdir;

    if {$current_file == ""} {
        tk_messageBox -message "Can't insert image into unnamed buffer.\nSave as a file first.";
        return;
    }

    set fnames [tk_getOpenFile -filetypes $types -multiple 1];
    catch {
      set fnames [lsort $fnames -command numbers_compare];
    }
    set nextimagetag "";
    set previmagetag "";
    
    set cnt [llength $fnames];
    set i 0;
    
    set toptag "[randString]";
    .t fastinsert end "\n";
    .t fastinsert end "TOP" "target_$toptag";
    .t fastinsert end "\n\n";
    .t tag bind "hyperref_${toptag}" <Control-ButtonRelease-1> "followTarget ${toptag}"
    .t tag configure  "hyperref_${toptag}" -underline 1;
    foreach fname $fnames {
    incr i;
    if {$fname == ""} {
        return;
    }
    if {![file exists $fname]} {
        tk_messageBox -message "Cant find image file $fname";
        return;
    }
    
    
    global spectral_subfolder;
    if {$nextimagetag == ""} {
      set imagetag [randString];
    } else {
        set imagetag $nextimagetag;
    }
    set nextimagetag [randString];
    catch {file mkdir "[get_current_folder]/${spectral_subfolder}"}
    set fnamepng "[get_current_folder]/${spectral_subfolder}/${imagetag}.png";
    catch {
        exec_convert $fname $fnamepng
    }

    if {$i > 1} {
    .t fastinsert end "\n";
    }
    .t fastinsert end "Slide $i" "target_$imagetag";
    .t fastinsert end "  ";
    if {$previmagetag != ""} {
       .t fastinsert end "prev" "hyperref_$previmagetag"
       .t tag bind "hyperref_${previmagetag}" <Control-ButtonRelease-1> "followTarget ${previmagetag}"
       .t tag configure  "hyperref_${previmagetag}" -underline 1;
    }
    .t fastinsert end " "
    if {$i != $cnt} {
       .t fastinsert end "next" "hyperref_$nextimagetag"
       .t tag bind "hyperref_${nextimagetag}" <Control-ButtonRelease-1> "followTarget ${nextimagetag}"
       .t tag configure  "hyperref_${nextimagetag}" -underline 1;
    }
    .t fastinsert end " "
    .t fastinsert end "top" "hyperref_$toptag"

    .t insert end "\n"
    if {[file exists $fnamepng]} {
       insert_image end $fnamepng;
    }
    set previmagetag $imagetag;
  }
}


proc make_slides_template {n} {

    set nextimagetag "";
    set previmagetag "";
    
    
    set toptag "[randString]";
    .t fastinsert end "\n";
    .t fastinsert end "TOP" "target_$toptag";
    .t fastinsert end "\n\n";
    .t tag bind "hyperref_${toptag}" <Control-ButtonRelease-1> "followTarget ${toptag}"
    .t tag configure  "hyperref_${toptag}" -underline 1;
    for {set i 1} {$i <= $n} {incr i} {
    
    if {$nextimagetag == ""} {
      set imagetag [randString];
    } else {
        set imagetag $nextimagetag;
    }

    set nextimagetag [randString];

    if {$i > 1} {
    .t fastinsert end "\n";
    }
    .t fastinsert end "Slide $i" "target_$imagetag";
    .t fastinsert end "  ";
    if {$previmagetag != ""} {
       .t fastinsert end "prev" "hyperref_$previmagetag"
       .t tag bind "hyperref_${previmagetag}" <Control-ButtonRelease-1> "followTarget ${previmagetag}"
       .t tag configure  "hyperref_${previmagetag}" -underline 1;
    }
    .t fastinsert end " "
    if {$i != $n} {
       .t fastinsert end "next" "hyperref_$nextimagetag"
       .t tag bind "hyperref_${nextimagetag}" <Control-ButtonRelease-1> "followTarget ${nextimagetag}"
       .t tag configure  "hyperref_${nextimagetag}" -underline 1;
    }
    .t fastinsert end " "
    .t fastinsert end "top" "hyperref_$toptag"

    .t insert end "\n"

    set previmagetag $imagetag;
    }
}


proc insert_text {pos txt {tag ""}} {
    if {$tag != ""} {
        
    set id [expr (($tag - 1) % 6) +1]
    global fixed_boxes;
    global all_tags;
    global currentColor;

    set color white;
    if {$id == 6} {
       set color $currentColor;
    } elseif {$id <= 5} {
       set color [lindex  $fixed_boxes [expr 2*$id-1]];
    }
    if { [ catch {
     
    set font [[.searchFrame.font component entry] get];
    if {[string first "." $font] == 0 && [winfo exists $font]} {
        catch { set font [$font get] }
    }
    set foreground [[.searchFrame.foreground component entry] get];
    if {[string first "." $foreground] == 0 && [winfo exists $foreground]} {
        catch { set foreground [$foreground get] }
    }

    set tagname $color;

    foreach x $font {
        foreach y $x {
            append tagname $y;
        }
    }
    if {[llength $foreground]} {
      append tagname "_" $foreground;
    }

    if {[llength $font]} {
        .t tag configure $tagname -font $font;
    }
    
    if {$color != "white" && $color != "#FFFFFF" && $color != "#ffffff"} {
        .t tag configure $tagname  -background $color ;
    }
    if {[llength $foreground]} {
        .t tag configure $tagname -foreground $foreground;
    }
    global all_tags;
    set new_tag 1;
    foreach tag $all_tags {
        if { $tag == $tagname } {
          set new_tag 0;
        }
    }
    if {$new_tag} {
        lappend all_tags $tagname;
    }
    .t tag raise $tagname;
     .t insert $pos $txt $tagname;
    }] } {
        .t insert $pos $txt $color;
    }

    
    } else {
        .t insert $pos $txt;
    }

}

proc actually_edit_note {w args} {
   
   set fname $args;
   set txt [$w.input get 1.0 end];
   set fp [open $fname w];
   fconfigure $fp -encoding utf-8
   puts -nonewline $fp $txt;
   close $fp;

}

proc editNoteFile {fname} {
  if {[file exists "${fname}.hlt"]} {
      tk_messageBox -message "This note has rich text content.\n Please use the \"Open Note on Spectral\" menu"
  } else {
    set fp [open $fname r];
    fconfigure $fp -encoding utf-8
    set cont [read $fp];
    close $fp;
    show_text_input addNote $cont "Edit Note" actually_edit_note 600 400 {} $fname; 
  } 
}

proc cmdhistory { {re {}} } {
    set result {};
    global loggedcommands;
    foreach cmd $loggedcommands {
        if { $re == "" || [regexp $re $cmd]} {
            append result ">" $cmd "\n";
        }
    }
    return $result;
}

proc actually_match_multiple {w args} {
    set txt [$w.input get 1.0 end];
    set id [lindex $args 0];
    upvar 1 [$w.nlsep cget -variable] nlsep;
    upvar 1 [$w.sortres cget -variable] sortres;
    upvar 1 [$w.seqmatsym cget -variable] seqmatsym;
    
    global loggedcommands;
    global new_loggedcommands;
    set cmd {}
    lappend cmd search_multiple;
    lappend cmd $id;
    lappend cmd $txt;
    lappend cmd $nlsep;
    lappend cmd $sortres;
    lappend cmd $seqmatsym;
    lappend loggedcommands $cmd;
    lappend new_loggedcommands $cmd;
    
    search_multiple $id $txt $nlsep $sortres $seqmatsym;
    
}

proc add_hypertarget {} {
    global external_hyperrefs;
    set tag [randString];
    set selranges [.t tag ranges sel];
    foreach {start end} $selranges {
        .t tag add  target_${tag} $start $end
    }
    set result {};
    set filename [get_current_filename];
 
    lappend result $filename;
    set external_hyperrefs($tag) $filename;
    lappend result ${tag};
    clipboard clear;
    clipboard append $result;
    return $result;
}


proc add_hypertargets_at_sel {} {
    global external_hyperrefs;
    set result {};
    set filename [get_current_filename];
    set selranges [.t tag ranges sel];
    foreach {start end} $selranges {
         set tag [randString];
         set external_hyperrefs($tag) $filename;
        .t tag add  target_${tag} $start $end
        set content [.t get $start $end];
        append result " EXT \{\{$filename\} ${tag}\} S hyperref_${tag}  P \{hyperref_${tag} -underline 1\} T " ;
        lappend result $content;
        append result " /S hyperref_${tag} T \{\n\} "
    }
    clipboard clear;
    clipboard append $result;
    tk_messageBox -message "Use \"Paste from spectral\" to paste" 
    return "";
}


proc get_hypertarget {} {
    
    set tags [tags_in_range];
    global external_hyperrefs;
    set count 0;
    foreach tag $tags {
        if {[string first "target_" $tag] == 0} {
            set target_tag $tag;
            incr count;
        }
    }
    if {$count != 1} {
        tk_messageBox "There needs to be exactly one target tag in range : found $tags";
    }
    set tag [string range $target_tag 7 end];
    
   
    set result {};
    set filename [get_current_filename];
    lappend result $filename;
    set external_hyperrefs($tag) $filename;
    lappend result ${tag};
    clipboard clear;
    clipboard append $result;
    return $result;
}


proc hyperref {} {
    global external_hyperrefs;
    set selranges [.t tag ranges sel];
    set info [clipboard get];
    set filename [lindex $info 0];
    set tag [lindex $info 1];
    set current_filename [get_current_filename];
    
    foreach {start end} $selranges {
        .t tag add  hyperref_${tag} $start $end; 
    }
    .t tag configure  "hyperref_${tag}" -underline 1;
     .t tag bind "hyperref_${tag}" <Control-ButtonRelease-1> "followTarget ${tag}"
     puts "filename=$filename current_filename=$current_filename"
    if {$filename == $current_filename} {
           
    } else {
        set external_hyperrefs($tag) [relativizeFileName $filename];    
    }
}

proc get_external_hyperrefs {} {
    global external_hyperrefs;
    return [array get external_hyperrefs];
 }
    
proc search_multiple  {id txt nlsep sortres seqmatsym} {
   set resultsWindow "";
   if {$nlsep} {
       set txt [split $txt "\n"];
       set resultsWindow [createResultsWindow "Multi-search: $txt"]
   } else {
       set title [split $txt  "\n"];
       set resultsWindow [createResultsWindow "Multi-search: $title"]
   }
   
   set symnum 97;
   array set symbols {};  
   foreach word $txt {
      if {$word == {}} {
          continue;
      }
      set word [string trim $word]
      if {$symnum > 122} {
        set symbols($word) "([expr $symnum - 122])"
      } else {
        set symbols($word) [format "%c" $symnum];
      }

      incr symnum;

      set entry [.searchFrame.search${id} component entry];
      $entry delete 0 end;
      $entry insert end $word;

      if {$id == 6} {
          chooseColor "Choose color for $word";
      }
      
      searchString 1 $id ""  $resultsWindow;
   }
    if {$seqmatsym} {
      set matches [sortresults $resultsWindow.results];
       $resultsWindow.results insert end "\nKEY: ";
       array set names_to_links {}
       set patnames [array names symbols]
       foreach name $patnames {
          $resultsWindow.results insert end "$name -> $symbols($name) ";
          set names_to_links($name) {};
       }
       $resultsWindow.results insert end "\n";
       foreach {lnum cnum pat} $matches {
            set tag [randString];
            $resultsWindow.results insert end "[set symbols($pat)]\n" hyperref_${tag};
            .t tag add  target_${tag} "$lnum.$cnum" "$lnum.$cnum + 1c";
            .t tag bind "hyperref_${tag}" <Control-ButtonRelease-1> "followTarget $tag";
            .t tag configure "hyperref_${tag}" -underline 1;
             $resultsWindow.results tag configure "hyperref_${tag}" -underline 1;
             $resultsWindow.results tag bind "hyperref_${tag}" <ButtonRelease-1> "followTarget $tag";
            
            lappend names_to_links($pat) hyperref_${tag};

       }
       $resultsWindow.results insert end "\n";
       foreach name $patnames {
           $resultsWindow.results insert end "\n";
           set links [set names_to_links($name)];
           $resultsWindow.results insert end "$name [llength $links] occurrences :";
           set counter 0;
           foreach link $links {
               incr counter;
               $resultsWindow.results insert end " ";
               $resultsWindow.results insert end $counter $link;
           }
       }
      
   } elseif {$sortres} {
      sortresults $resultsWindow.results;
   }
   
   focus $resultsWindow;

  
   return 1;
}

proc numbers_compare {a b} {
  set an [regsub -all {[^0-9]} $a ""];
  set bn [regsub -all {[^0-9]} $b ""];
  return [expr int($an-$bn)];
} 

proc results_compare {a b} {
    set al [lindex $a 0];
    set ac [lindex $a 1];
    set bl [lindex $b 0];
    set bc [lindex $b 1];
    if {$al > $bl} {
        return 1;
    } elseif {$al == $bl} {
        if {$ac > $bc} {
            return 1;
        } elseif {$ac == $bc} {
            return 0;
        } else {
            return -1;
        }
    } else {
        return -1;
    }
   }

proc sortresults {w} {
      set results {};
      set txt [$w get 1.0 end];
      set lines [split $txt "\n"];
      set lnum "";
      set cnum "";
      set rest "";
      set pat "";
      set tosort {};
      foreach line $lines {
         regsub -all {^\((\d+)\):.*} $line {\1} lnum;
         regsub -all {^\(\d+\):\((\d+)\).*} $line {\1} cnum;
         regsub -all {^\(\d+\):\(\d+\):([^\t:]+):\t.*$} $line {\1} pat;
         regsub -all {^\(\d+\):\(\d+\):(.*)$} $line {\1} rest;
         lappend tosort [list $lnum $cnum $pat $rest];
      }
      set tosort [lsort -command results_compare $tosort];
      $w delete 1.0 end;
      
      foreach result $tosort {
         set randword [randString];
         set tagname "hyperref_${randword}"
         set lnum [lindex $result 0];
         set cnum [lindex $result 1];
         set pat  [lindex $result 2];
         set rest [lindex $result 3];
         if {$lnum != ""} {
            $w insert end "($lnum):($cnum):" resultHyperlink;
            $w insert end "$rest" $tagname;
            $w insert end "\n";
            .t tag add "target_${randword}"  "$lnum.$cnum" "$lnum.$cnum + 1 char";
            .t tag bind $tagname <Control-ButtonRelease-1> "followTarget $randword";
            .t tag configure  $tagname -underline 1;
            lappend results  $lnum $cnum $pat;
         }
      }

      return $results;
}


proc num_glyphs {w args} {
   set start [lindex $args 0];
   if {[llength $args] ==1} {
       set end "$start + 1 char";
   } else {
       set end [lindex $args 1];
   }
   append dump [.t dump -all $start $end]
   set result 0;
   # add more details
   foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                incr result;
            }

            image \
            {
                incr result;
            }
        }
    }
    return $result;
}

proc num_glyphs_and_chars {w args} {
   set start [lindex $args 0];
   if {[llength $args] ==1} {
       set end "$start + 1 char";
   } else {
       set end [lindex $args 1];
   }
    
   append dump [.t dump -all $start $end]
   set ng 0;
   set nc 0;
   # add more details
   foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                incr ng;
            }

            image \
            {
                incr ng;
            }

            text \
            {    
                incr nc [string length $value];
            }
        }
    }
    return "$ng $nc";
}

proc actually_search_in_notes {w args} {
   set txt [$w.input get 1.0 end];
   set id [lindex $args 0];
   upvar 1 [$w.nlsep cget -variable] nlsep;
   upvar 1 [$w.match_all cget -variable] match_all;
   set resultsWindow "";
   if {$nlsep} {
       set txt [split $txt "\n"];
       set resultsWindow [createResultsWindow "Search in Notes: $txt"]
   } else {
       set title [split $txt  "\n"];
       set resultsWindow [createResultsWindow "Search in Notes: $title"]
   }

   #############################
   global general_filenames;
   global allResultWindows;
   append dump [.t dump -all 1.0 end]
   update;
   # add more details
   foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                if {[info exists general_filenames($value)]} {
                    set fname [set general_filenames($value)];
                     catch {
                    set fp1 [open $fname r];
                    fconfigure $fp1 -encoding utf-8
                    set cont  [read $fp1];
                    close $fp1;
                   

                    set all_match 1;
                    set some_match 0;
                    foreach word $txt {
                        
                        set word [string trim $word];
                        
                        if {$word == {}} {
                                continue;
                        }
                        if {[regexp $word $cont]} {
                            set some_match 1;
                        } else {
                            set all_match 0;
                        }
                    }
                    #addToStatus "match_all=$match_all some_match=$some_match all_match=$all_match";
                    set matches 0;
                    if {$match_all && $all_match} {
                        set matches 1;
                    } 
                    if {(!$match_all) && $some_match} {
                        set matches 1;
                    }
                    if {!$matches} {
                        continue;
                    }
      
                    set curParts [split $index "."];
                    set theLine [lindex  $curParts 0];
                    set theCol [lindex  $curParts 1];
                    $resultsWindow.results insert end "($theLine):($theCol):" resultHyperlink; 
                    if {[string length $cont] > 300} {
                       set truncated [string range $cont 0 300];
                        $resultsWindow.results insert end "${truncated} **TRUNCATED**\n";
            } else {
                $resultsWindow.results insert end "${cont}\n";
                 }
                 } msg;

                 addToStatus $msg;  
               }
            }
        }
    }

    focus .t;
    focus $resultsWindow;
   
   return 1;
}

proc get_notefiles {} {
     global general_filenames;
     array get general_filenames;
 }
 
proc notesgrep_postfilter {filters args} {
   global general_filenames;
   set grepcmd grep;
   if {[isWindowsExecutable]} { set grepcmd "[installdir]/wbin/grep.exe" }
   set resultsWindow [createResultsWindow "notesgrep_postfilter"]
   set dump [.t dump -all 1.0 end]
   # add more details
   foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                if {[info exists general_filenames($value)]} {
                    
                    set fname [set general_filenames($value)];
                    if {[catch {
                       exec $grepcmd {*}$args {*}$fname;
                    } msg]} {
                       update;
                   } else {
                       update;
                       if {$msg != ""} {
                          set pos [split $index "."];
                          set theLine [lindex $pos 0];
                          set theCol [lindex $pos 1];
                          set filterCriterionPass 1;
                          foreach filter $filters {
                              if {![regexp $filter $msg]} {
                                  set filterCriterionPass 0;
                              }
                          }
                          if {$filterCriterionPass} {
                            $resultsWindow.results insert end "($theLine):($theCol): \n" resultHyperlink;
                            $resultsWindow.results insert end $msg;
                            $resultsWindow.results insert end "\n"
                            puts "\n>In note @ $index";
                            puts  $msg;
                          }
                       }
                       update;
                   }
                }
            }
        }
    }
    focus $resultsWindow;
}

proc notesgrep {args} {
   global general_filenames;
   set grepcmd grep;
   if {[isWindowsExecutable]} { set grepcmd "[installdir]/wbin/grep.exe" }
   set resultsWindow [createResultsWindow "notesgrep"]
   
   set dump [.t dump -all 1.0 end]
   # add more details
   foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                if {[info exists general_filenames($value)]} {
                    
                    set fname [set general_filenames($value)];
                    if {[catch {
                       exec $grepcmd {*}$args {*}$fname;
                    } msg]} {
                       update;
                   } else {
                       update;
                       if {$msg != ""} {
                                 set pos [split $index "."];
                                 set theLine [lindex $pos 0];
                                 set theCol [lindex $pos 1];
                                 $resultsWindow.results insert end "($theLine):($theCol): \n" resultHyperlink;
                                 $resultsWindow.results insert end $msg;
                                 $resultsWindow.results insert end "\n"
                                 puts "\n>In note @ $index";
                                 puts  $msg;
                       }
                       update;
                   }
                }
            }
        }
    }
    focus $resultsWindow;
}


proc openNoteFile {fname} {
    set result [tk_messageBox -title "Open Note File"  -message "Really open note file $fname on Spectral?" -icon question -type yesno];
    if {$result == "no"} {
         return;
    }
    openFile .t $fname;
}

proc matchMultiple {id} {
   show_text_input searchMultiple "" "Search Multiple Patterns" actually_match_multiple 200 200 {nlsep {Patterns separated by newlines?} sortres {Sort Results} seqmatsym {Sequence Match Symbols}} $id; 
}

proc searchInNotes {} {
  show_text_input searchInNotes "" "Search in Notes" actually_search_in_notes 200 200 {nlsep {Patterns separated by newlines?} match_all {Match All?}} ""
}

proc copyContentToClipboard {fname} {
    set fp [open $fname r];
    set cont [read $fp];
    close $fp;
    clipboard clear;
    clipboard append $cont;
}

set fileToCompareAgainst "";

proc fileToCompareAgainst {} {
    global fileToCompareAgainst;
    return $fileToCompareAgainst;
}

package require md5;

proc getNoteType {btn} {
    
    global global_generator_names ;
    global global_verifier_names ;
    global comment_tags;
    global comment_checksums;
    global sound_filenames;
    global general_filenames;
    if {[info exists global_generator_names($btn)]} {
        return "generator [set global_generator_names($btn)]";
    } elseif {[info exists global_verifier_names($btn)]} {
        return "verifier [set global_verifier_names($btn)]";
    } elseif {[info exists comment_tags($btn)]} {
        return "comment [set comment_tags($btn)] [set comment_checksums($btn)]";
    } elseif {[info exists sound_filenames($btn)]} {
        return "media [set sound_filenames($btn)]";
    } else  {
        return "ordinary [set general_filenames($btn)]";
    }
}

proc convertToOrdinaryNote {btn} {
    
    set result [tk_messageBox -title "Really convert back to ordinary note?" -message "Really convert back to ordinary note?" -icon question -type yesno];
    if {$result != yes} {
      return;
    }
    global global_generator_names ;
    global global_verifier_names ;
    global global_generator_tags ;
    global global_verifier_tags ;
    global comment_tags;
    global comment_checksums;

    if {[info exists global_generator_names($btn)]} {
        $btn configure -text N;
        set tag [set global_generator_tags($btn)];
        .t tag remove $tag 1.0 end;
        catch { unset global_generator_tags($btn) }
        catch { unset global_generator_names($btn) }
        
    } elseif {[info exists global_verifier_names($btn)]} {
        $btn configure -text N;
        set tag [set global_verifier_tags($btn)];
        .t tag remove $tag 1.0 end;
        catch { unset global_verifier_tags($btn) }
        catch { unset global_verifier_names($btn) }
        
    } elseif {[info exists comment_tags($btn)]} {
        $btn configure -text N;
        set tag [set comment_tags($btn)];
        .t tag remove $tag 1.0 end;
        catch { unset comment_tags($btn) }
        catch { unset comment_checksums($btn) }
    } 
}

proc convertNoteToGenerator {generator btn} {
    global global_generator_names ;
    global global_generator_tags ;
    
    set thetag "generator_";
    append thetag [randString];
    $btn configure -text G;
   
    set global_generator_tags($btn) $thetag;
    set global_generator_names($btn) $generator;
}

proc convertNoteToVerifier {verifier btn} {
    global global_verifier_names ;
    global global_verifier_tags ;
    
    set thetag "verifier_";
    append thetag [randString];
    $btn configure -text V;
    set selranges [.t tag ranges sel];
    foreach {start end} $selranges {
        .t tag add $thetag $start $end;
    }
    
    set global_verifier_tags($btn) $thetag;
    set global_verifier_names($btn) $verifier;
    
}

proc showCommentExtent {btn} {
    global comment_checksums;
    global comment_tags;
    set cmttag $comment_tags($btn);
    set tagranges [.t tag ranges $cmttag];
    set content "";
    foreach {start end} $tagranges {
        .t tag add sel $start $end;
    }
}
    
proc debug_special_notes {} {
   global comment_checksums;
   global comment_tags;
   puts comments
   foreach {key value} [array get comment_checksums] {
       puts "btn=$key checksum=$value tag=[set comment_tags($key)]";
   } 
    global global_verifier_names ;
    global global_verifier_tags ;
    puts verifiers;
    foreach {key value} [array get global_verifier_names] {
       puts "btn=$key name=$value tag=[set global_verifier_tags($key)]";
   } 
   global global_generator_names ;
    global global_generator_tags ;
    puts generators;
    foreach {key value} [array get global_generator_names] {
       puts "btn=$key name=$value tag=[set global_generator_tags($key)]";
   } 
   global global_all_verifiers ;
   global global_all_generators;
   puts "verifier handlers"
   foreach {key value} [array get global_all_verifiers] {
       puts "name=$key handler=$value";
   }
   puts "generator handlers"
   foreach {key value} [array get global_all_generators] {
       puts "name=$key handler=$value";
   }
}


proc convertNoteToComment {btn} {
    global comment_checksums;
    global comment_tags;
    set cmttag "comment_";
    append cmttag [randString];
    $btn configure -text C;
    set selranges [.t tag ranges sel];
    set content "";
    foreach {start end} $selranges {
        append content [.t get $start $end];
        .t tag add $cmttag $start $end;
    }
    set checksum [md5::md5 -hex $content];
    set comment_checksums($btn) $checksum;
    set comment_tags($btn) $cmttag;
    
 }
    
proc checkSingleCommentChecksum {btn} {
    if {[checkSingleCommentChecksumAux $btn]} {
        tk_messageBox -message "Checksum OK";
    } else {
        tk_messageBox -message "Check Failed";
    }
  }
 
 proc checkSingleCommentChecksumAux {btn} {
    global comment_checksums;
    global comment_tags;
    set cmttag $comment_tags($btn);
    set tagranges [.t tag ranges $cmttag];
    set content "";
    foreach {start end} $tagranges {
        append content [.t get $start $end];
    }
    set checksum [md5::md5 -hex $content];
    if { $checksum == $comment_checksums($btn) } {
        return 1;
    } else {
        return 0;
    }
  }
    
proc updateCommentChecksum {btn} {
    global comment_checksums;
    global comment_tags;
    set cmttag $comment_tags($btn);
    set tagranges [.t tag ranges $cmttag];
    set content "";
    foreach {start end} $tagranges {
        append content [.t get $start $end];
    }
    set comment_checksums($btn) [md5::md5 -hex $content];
 }
 
    
proc run_generators {args} {
   global global_all_generators;
   global global_generator_tags;
   global global_generator_names;

   set resultsWindow [createResultsWindow "Generation Results"];
    
    set dump [lreverse [.t dump -all 1.0 end]]
   
    update;
    # add more details
    foreach {index value key} $dump \
    {
        switch $key \
        {
           window \
            {
                if {[info exists global_generator_names($value)]} {
                    set generator_name [set global_generator_names($value)];
                    set match 0;
                    foreach regex $args {
                        if [regexp $regex $generator_name] {
                            set match 1;
                            break;
                        }
                    }
                    if {! $match } {
                        continue;
                    }
                    set generator_tag [set global_generator_tags($value)];
                    set ranges [.t tag ranges $generator_tag];
                    foreach {start end} $ranges {.t delete $start $end};
                }
            }
        }
    }
    
    set dump [lreverse [.t dump -all 1.0 end]]
   
    update;
    # add more details
    foreach {index value key} $dump \
    {
        switch $key \
        {
           window \
            {
                set curParts [split $index "."];
                set theLine [lindex  $curParts 0];
                set theCol [lindex  $curParts 1];
                if {[info exists global_generator_names($value)]} {
                    set generator_name [set global_generator_names($value)];
                    set match 0;
                    foreach regex $args {
                        if [regexp $regex $generator_name] {
                            set match 1;
                            break;
                        }
                    }
                    if {! $match } {
                        continue;
                    }
                    set generator_tag [set global_generator_tags($value)];
                    if {[runSingleGenerator $index $generator_name $generator_tag $value]} {
                        
                        $resultsWindow.results insert end "($theLine):($theCol): OK" resultHyperlink;
                        $resultsWindow.results insert end "\n";
                        $value configure -bg "#c8fbe7"
                    } else {
                        $resultsWindow.results insert end "($theLine):($theCol): FAILED" resultHyperlink;
                        $resultsWindow.results insert end "\n";
                        $value configure -bg "#f7d9cc"
                    }
                }
            }
        }
    } 
}

proc run_verifiers {args} {
   global global_all_verifiers;
   global global_verifier_tags;
   global global_verifier_names;
   set dump [.t dump -all 1.0 end]
   
    update;
    # add more details
    foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                set curParts [split $index "."];
                set theLine [lindex  $curParts 0];
                set theCol [lindex  $curParts 1];
                
                if {[info exists global_verifier_names($value)]} {
                   set verifier_name [set global_verifier_names($value)];
                   set match 0;
                    
                   foreach regex $args {
                       if [regexp $regex $verifier_name] {
                           set match 1;
                           break;
                       }
                   }
                 
                   if {! $match } {
                       continue;
                   }
                   set verifier_tag [set global_verifier_tags($value)];
                   checkSingleVerifier $index $verifier_name $verifier_tag $value;                }
            }
        }
    }
    popupStatusContent
    return "";
}


proc checkSingleVerifier {index verifier_name verifier_tag btn} {

    global global_all_verifiers;
    set verifier_proc [set global_all_verifiers($verifier_name)];

    global general_filenames;
    set filename [absolutizeFileName [set general_filenames($btn)]];
    
    set exprToEval [list $verifier_proc $filename $index $verifier_tag];
    eval $exprToEval;
}

proc runSingleGenerator {index generator_name generator_tag btn} {
    global global_all_generators;
    set generator_proc [set global_all_generators($generator_name)];
    global general_filenames;
    set filename [absolutizeFileName [set general_filenames($btn)]];
    
    set result [eval [list $generator_proc $filename $index $generator_tag]];
    return $result;
}
          
proc checkAllCommentChecksums  {} {
    #loadOverview;
    global general_filenames;
    global allResultWindows;
    global comment_tags;
    global comment_checksums;
    
   
    set resultsWindow [createResultsWindow "Comment Check Results"];
    
    append dump [.t dump -all 1.0 end]
   
    update;
    # add more details
    foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                set curParts [split $index "."];
                set theLine [lindex  $curParts 0];
                set theCol [lindex  $curParts 1];
                if {[info exists comment_checksums($value)]} {
                    if {[checkSingleCommentChecksumAux $value]} {
                        
                        $resultsWindow.results insert end "($theLine):($theCol): OK" resultHyperlink;
                        $resultsWindow.results insert end "\n";
                        $value configure -bg "#c8fbe7"
                    } else {
                        $resultsWindow.results insert end "($theLine):($theCol): FAILED" resultHyperlink;
                        $resultsWindow.results insert end "\n";
                        $value configure -bg "#f7d9cc"
                    }
                }
            }
        
        }
    }
     
}

proc showNoteMenu {btn fname} {
    global fileToCompareAgainst;
    global comment_tags;
    global comment_checksums;
    
    catch {destroy .menu4}
    set x [winfo pointerx .]
    set y [winfo pointery .]
    menu .menu4 -tearoff 0;
    
    set btntxt [$btn cget -text];
    
   
    set pos [.t index "@$x,$y"];
    set pos2 [.t index "$pos+1c"];
    .menu4 add command -label "Edit Note" -command "editNoteFile \"$fname\"";
    .menu4 add command -label "Copy File Name" -command "clipboard clear; clipboard append \"$fname\"";
    .menu4 add command -label "Open Note on Spectral" -command "openNoteFile \"$fname\"";
    .menu4 add command -label "Show in Explorer" -command "showFileInExplorer \"$fname\"";
    .menu4 add command -label "Choose File to Compare Against" -command "set fileToCompareAgainst  \"$fname\"";
    .menu4 add command -label "Compare with file chosen for comparison" -command "eval \{strdiff_files_and_log line \"\$fileToCompareAgainst\" \"$fname\" \}";
    .menu4 add command -label "Copy content to Clipboard" -command "copyContentToClipboard \"$fname\"";
    
     set getNoteTypeCmd {tk_messageBox -message [getNoteType }; append getNoteTypeCmd $btn; append getNoteTypeCmd {]};
    .menu4 add command -label "Show Note Type" -command $getNoteTypeCmd;
    if {$btntxt == "C" || $btntxt == "V" || $btntxt == "G" } {
        .menu4 add command -label "Convert back to Ordinary Note" -command "convertToOrdinaryNote $btn";   
    }
    
    if {$btntxt == "C"} {
       .menu4 add command -label "Show comment Extent" -command "showCommentExtent $btn ";
       .menu4 add command -label "Redefine comment applicability" -command "convertNoteToComment $btn ";
       .menu4 add command -label "Check comment checksum" -command "checkSingleCommentChecksum $btn ";
       .menu4 add command -label "Update comment checksum" -command "updateCommentChecksum $btn "; 
       set cmttag [set comment_tags($btn)];
       set tagranges [.t tag ranges $cmttag];
       foreach {start end} $tagranges {
           .t tag add sel $start $end;
       }
    } elseif {$btntxt == "N" } {
        .menu4 add command -label "Convert note to comment" -command "convertNoteToComment $btn ";
        
        .menu4 add cascade -label "Convert to verifier" -menu [menu .menu4.verifier  -tearoff 0];
        .menu4 add cascade -label "Convert to generator" -menu [menu .menu4.generator  -tearoff 0];
        
        global global_all_verifiers;
        global global_all_generators;
        foreach verifier [array names global_all_verifiers] {
            .menu4.verifier add command -label $verifier -command "convertNoteToVerifier $verifier $btn ";
        }
        foreach generator [array names global_all_generators] {
            .menu4.generator add command -label $generator -command "convertNoteToGenerator $generator $btn ";
        }
    }
    tk_popup .menu4 $x $y
}


proc count_re {regex inputString} {
    return [llength [regexp -all -inline $regex $inputString]]
}



proc verify_note_asserts {filename index verifier_tag} {
    set ranges [.t tag ranges $verifier_tag];
    set text "";
    foreach {start end} $ranges {
        append text [.t get $start $end];
    }
    set script [read_ascii_file_contents $filename];
    addToStatus "*** Checking verifier at $index  ***"
    catch {eval $script} msg;
    addToStatus $msg;
}

add_generator macro_expand expand_note_macro;
add_verifier code_asserts verify_note_asserts;
 


proc strdiff_files_and_log {granularity file1 file2} {
    global loggedcommands;
    global new_loggedcommands;

        set cmd "strdiff_files"
        lappend cmd $granularity;
        lappend cmd $file1;
        lappend cmd $file2;
        lappend loggedcommands $cmd;
        lappend new_loggedcommands $cmd;

        strdiff_files $granularity $file1 $file2;
    
}

proc showMediaMenu {btn fname} {
    catch {destroy .menu5}
    set x [winfo pointerx .]
    set y [winfo pointery .]
    menu .menu5 -tearoff 0;
   
    set pos [.t index "@$x,$y"];
    set pos2 [.t index "$pos+1c"];
    .menu5 add command -label "Copy File Name" -command "clipboard clear; clipboard append \"$fname\"";
    .menu5 add command -label "Show in Explorer" -command "showFileInExplorer \"$fname\"";
    tk_popup .menu5 $x $y
}


proc insert_note_button {pos txt} {
   global spectral_subfolder;
   set fname "[get_current_folder]/${spectral_subfolder}/[randString].txt";;
   set fp [open $fname w];
   fconfigure $fp -encoding utf-8
   puts -nonewline $fp $txt;
   close $fp;
   global modified;
   set modified 1;

    global general_filenames;
    set btn .t.[randString];

    .t window create $pos -create " button $btn  -text N -relief flat -command \"showFile \\\"$fname\\\"\" -background #ccd3f7 -activebackground #a78737 -padx 0 -pady 0 -font {Consolas 10}" ;

    ####after 2000 "bind $btn <ButtonPress-3> \"showFileInExplorer \\\"$fname\\\"\"";
    
    after 2000 "bind $btn <ButtonPress-3> \{showNoteMenu $btn \"$fname\"\}"
    after 2000 "bind $btn <ButtonPress-2> \{showNoteMenu $btn \"$fname\"\}"
    after 2000 "catch \"setTooltip $btn \\\"$fname\\\"\"";
    set general_filenames($btn) $fname;
    update;
    return $fname;
}

proc appendToFile {fname txt} {
    catch {
    set fp [open $fname a+];
    puts $fp $txt;
    close $fp;
    }
}


proc insertNoteFile {w} {
    global spectral_subfolder;
    catch {file mkdir "[get_current_folder]/${spectral_subfolder}"}
    set fname "[get_current_folder]/${spectral_subfolder}/[randString].txt";
    show_text_input addNote "" "Add Note" actually_add_note 300 400 {} $fname
}

proc insertGeneralFile {w pos fname symb} {
    global general_filenames;
    global comment_tags;
    global comment_checksums;
    set btn $w.[randString];
    $w window create $pos -create " button $btn  -text $symb -relief flat -command \"showFile \\\"$fname\\\"\" -background #ccd3f7 -activebackground #a78737  -padx 0 -pady 0  -font {Consolas 10}";

    after 2000 "bind $btn <ButtonPress-3> \{showNoteMenu $btn \"$fname\"\}"
    after 2000 "bind $btn <ButtonPress-2> \{showNoteMenu $btn \"$fname\"\}"
    after 2000 "catch \"setTooltip $btn \\\"$fname\\\"\"";
    set general_filenames($btn) $fname;
    return $btn;
}
proc playMedia {fname} {
     global installdir;global tmpdir;global isWindowsExecutable;
     set ffplay ffplay;
     if {$isWindowsExecutable} {set ffplay "$installdir/wbin/ffplay.exe"}
     if {[file exists "$fname.mp3"]} {
        catch {exec $ffplay "$fname.mp3"};
     } elseif {[file exists $fname]} {
        catch {exec $ffplay $fname};
     } else {
        tk_messageBox -message "File $fname was not found";
     }
}

proc searchFileForNotes {fname searchPattern} {
    set fp [open "$fname.hlt" r];
    set save [read $fp];
    close $fp;
    set curline 1;
    update;

    foreach {key value } $save \
    {
        #puts stderr "$key :--> $value";
        switch $key \
        {
            T {
                 set numlines [expr [llength [split $value "\n"]] - 1];
                 incr curline $numlines;

            } 
            N {
                 set notename [absolutizeFileNameAux $fname $value];
                 set fpn [open $notename r];
                 set note [read $fpn];
                 close $fpn;
                 if {[regexp -nocase $searchPattern $note]} {
                      if {[string length $note] > 300} {
                         set truncated [string range $note 0 300];
                         puts "$fname\($curline\): ${truncated} **TRUNCATED**\n";
              } else {
             puts "$fname\($curline\): $note";
              }
                 }

           } 
           
            C {
                 
                 set notename [absolutizeFileNameAux $fname [lindex $value 2]];
                 set fpn [open $notename r];
                 set note [read $fpn];
                 close $fpn;
                 if {[regexp -nocase $searchPattern $note]} {
                      if {[string length $note] > 300} {
                         set truncated [string range $note 0 300];
                         puts "$fname\($curline\): ${truncated} **TRUNCATED**\n";
                 } else {
                    puts "$fname\($curline\): $note";
                 }
              }

           }        
        }
    }   
}



proc grepnotes {folders fileType searchPattern} {
    set queue $folders
    if {[llength $queue] == 0} {
        set queue .;
    }
    
    while {[llength $queue] > 0} {
      set current [lindex $queue 0]
      set queue [lreplace $queue 0 0]
    
      set files {}; 

      catch {
          set subs [glob "$current/*"];
          foreach sub $subs {
              lappend files $sub ;
          }
      }

      #puts "queue = $queue current = $current files = $files";
      foreach f $files {
            #puts "okay so f is $f";
            if {[file isdirectory $f]} {
                catch {
                    lappend queue $f;
                }
            } elseif {[regexp $fileType $f]} {
                if {[file exists "$f.hlt"] } {
                    catch {
                       searchFileForNotes $f  $searchPattern ;
                    }
                }
            }
        }
      }
    puts "END";
}


proc sortuniq {fname args} {
    global installdir;
    catch {exec "$installdir/wbin/sort.exe" $fname {*}$args |  "$installdir/wbin/uniq.exe" } msg;
    puts $msg;
}
proc insertMediaFile {w pos fname} {
    global sound_filenames;
    set btn $w.[randString];
    global play_image;
    $w window create $pos -create " button $btn -relief flat -image $play_image -command \"playMedia $fname\" "; 
    after 2000 "bind $btn <ButtonPress-3> \{showMediaMenu $btn \"$fname\"\}";
    after 2000 "bind $btn <ButtonPress-2> \{showMediaMenu $btn \"$fname\"\}";
    set sound_filenames($btn) $fname;
}
proc insertScreenshot {w} {
    global spectral_subfolder;
    catch {file mkdir "[get_current_folder]/${spectral_subfolder}"}
    set fnamepng "[get_current_folder]/${spectral_subfolder}/[randString].png";
    wm withdraw .
    catch {
      exec import -window root $fnamepng;
      if {[file exists $fnamepng]} {
       insertPhotoFile .t $fnamepng;
      }
    }
    wm deiconify .
    ctext::linemapUpdate .t
}
proc set_image_editor {editor} {
   global image_editor; 
   set image_editor $editor;
   }
proc insertPhoto {w} {
   set types {
       {{PNG Files}      {.png}       }
       {{GIF Files}      {.gif}       }
       {{JPEG Files}     {.jpg .jpeg} }
       {{BMP Files}      {.bmp}       }
    }
    global image_filenames;
    global current_file;
    global installdir;
    global tmpdir;

    set fname [tk_getOpenFile -filetypes $types];
    if {$fname == ""} {
        return;
    }
    if {![file exists $fname]} {
        tk_messageBox -message "Cant find image file $fname";
        return;
    }
    
    if {$current_file == ""} {
        tk_messageBox -message "Can't insert image into unnamed buffer.\nSave as a file first.";
        return;
    }
    
    global spectral_subfolder;
    catch {file mkdir "[get_current_folder]/${spectral_subfolder}"}
    set fnamepng "[get_current_folder]/${spectral_subfolder}/[randString].png";
    catch {
        exec_convert $fname $fnamepng
    }
   
    if {[file exists $fnamepng]} {
       set inserted [insertPhotoFile .t $fnamepng];
    } else {
       set inserted 0;
    }
    if {!$inserted} {
        if {[string match -nocase "*.png" $fname]} {
            catch {file copy -force $fname $fnamepng}
            if {[file exists $fnamepng]} {
                set inserted [insertPhotoFile .t $fnamepng];
            }
        }
    }
    if {!$inserted} {
        catch {set inserted [insertPhotoFile .t $fname]}
    }

    ctext::linemapUpdate .t
}



proc actually_apply_watermark {w args} {
    global tmpdir;
    set txt [$w.input get 1.0 end];
    regsub -all "\n" $txt { } txt;
    global installdir;
    set fname $args;
    set fnamepng "$tmpdir/[randString].png";
    catch {
        exec_convert {*}$txt  $fname $fnamepng
    }
    set pos [.t index insert];
    set xy [split $pos "."];
    set x0 [lindex $xy 1];
    set y0 [lindex $xy 0];
    if {[file exists $fnamepng]} {
       set img [image create photo -file $fnamepng];
       set width [image width $img];
       set height [image height $img];
       for {set y 0} {$y < $height} {incr y} {
            for {set x 0} {$x < $width} {incr x} {
                 set pix [$img get $x $y];
                 set rgb [format "#%02x%02x%02x" {*}$pix];
                 .t tag configure "w$rgb" -background $rgb;
                  set x1 [expr $x0 + $x];
                  set y1 [expr $y0 + $y];
                  set pos1 "$y1.$x1";
                  set pos1end [.t index "$pos1 lineend"];
                  if {$pos1 == $pos1end} {
                    for {set xx 0} {$xx <= $x0} {incr xx} {
                        .t insert  [.t index "$pos1 lineend"] " ";
                     }
                  }
                 
                  catch {
                        .t tag add "w$rgb" "$y1.$x1" "$y1.$x1 + 1c"
                  }
                  .t tag raise "w$rgb"
              }

           }
    }
}



proc convert_single_image {imagename txt} {
   global image_filenames;
   global installdir;
   
   set fname [set image_filenames($imagename)];
   set cmd "exec_convert ";
   append cmd "  \"$fname\" ";
   append cmd $txt " \"$fname\" ";
   eval $cmd;
   puts $cmd;
   set image [image create photo -file $fname]
   $imagename blank;
   $imagename copy $image -shrink;
   
   #Update the overview image
   global image_shrunk;
   set shrunk_image [set image_shrunk($fname)];
   $shrunk_image copy $image -subsample 3 3 -shrink;
   image delete $image;
    
   ctext::linemapUpdate .t
   return 1;
}

proc actually_resize_image {w args} {
   set txt [$w.input get 1.0 end];
   regsub -all "\n" $txt { } txt;
   global image_filenames;
   global installdir;
   #puts "image_filenames = [array get image_filenames]";
   set fname [set image_filenames($args)];
   set cmd "exec_convert ";
   append cmd "  \"$fname\" ";
   append cmd $txt " \"$fname\" ";
   eval $cmd;
   set image [image create photo -file $fname]
   $args blank;
   $args copy $image -shrink;
   
   #Update the overview image
   global image_shrunk;
   set shrunk_image [set image_shrunk($fname)];
   $shrunk_image copy $image -subsample 3 3 -shrink;
   image delete $image;
    
   ctext::linemapUpdate .t
   return 1;
}

proc resizeImage {imagename pos} {  
    show_text_input imagescale "-resize 100%" "Resize Scale" actually_resize_image 200 100 {} $imagename;
}
proc editImage {imagename pos} {
   global image_editor;
   global image_shrunk;
   global image_filenames;
   set fname [set image_filenames($imagename)];
   catch {
     regsub -all {/} $fname {\\\\} fname1
      exec $image_editor $fname1;
   }
   set image [image create photo -file $fname]
   $imagename blank;
   $imagename copy $image -shrink;
   #Update the overview image
   global image_shrunk;
   set shrunk_image [set image_shrunk($fname)];
   $shrunk_image copy $image -subsample 3 3 -shrink;
   image delete $image;
   ctext::linemapUpdate .t
   return 1;      
}

proc showInExplorer {imagename pos} {
    global image_filenames;
    set fname [set image_filenames($imagename)];
    regsub -all {/} $fname {\\\\} fname
    catch {
      set fp [open "| explorer.exe /select,$fname" r];
      close $fp;
    }
}


proc showFileInExplorer {fname} {
    regsub -all {/} $fname {\\\\} fname
    catch  {
      set fp [open "| explorer.exe /select,$fname" r];
      close $fp;
    }
}

proc insertPhotoFile {w fname} {

    global image_filenames;
    set pos [$w index insert];
    if {[catch {set image [image create photo -file $fname]} err]} {
        tk_messageBox -message "Unable to load image: $fname\n$err";
        return 0;
    }
    set image_filenames($image) $fname;
    $w image create $pos -image  $image;
    global image_shrunk;
    set shrunk_image [image create photo]
    $shrunk_image copy $image -subsample 3 3 
    set image_shrunk($fname) $shrunk_image;
    return 1;
}

proc find_in_folder_or_parents {folder find_file_name} {
    set fname "${folder}/${find_file_name}"
    if {[file exists $fname]} {
        return $fname;
    }
    regsub -all {/[^/]*$} $folder {} parent_folder;
    if {$folder != $parent_folder} {
        return [find_in_folder_or_parents $parent_folder $find_file_name];
    } else {
        return "";
    }
}

proc absolutizeFileNameAux {current_file fname} {
    #puts stderr "absolutizeFileName current_file=$current_file fname=$fname";
    set current_folder "";
    if {$current_file !=""} {
         regsub -all {/[^/]*$} $current_file {} current_folder;
         set full_name $current_folder;
         append full_name {/} $fname;
         #puts stderr "absolutize $full_name";
         if {[file exists $full_name]} {
               return $full_name;
         } elseif {[file exists "$full_name.mp3"]} {
               return "$full_name.mp3";
         }
     }
    return $fname;
}




proc absolutizeFileName {fname} {
    global current_file;
    return [absolutizeFileNameAux $current_file $fname];
}

proc relativizeFileName {fname} {
     #puts stderr relativizeFileName;
     global current_file;
     set current_folder "";
     if {$current_file !=""} {
         regsub -all {/[^/]*$} $current_file {} current_folder;
         set len [string length $current_folder];
         if {[string range $fname 0 [expr $len - 1]] == $current_folder} {
               set fname [string range $fname [expr $len + 1] end];
         }
     }
     return $fname;
}


proc hlt:restore {w save args} \
{   
    #puts $save;
    global all_tags;
    global update_frozen;
    global spectral_subfolder;
    global external_hyperrefs;

  global comment_tags;
  global comment_checksums;
  global global_all_verifiers;
  global global_all_generators;
  global global_verifier_tags;
  global global_generator_tags;
  global global_verifier_names;
  global global_generator_names;
  
    set update_frozen 1;
    set toupper 0;
    set tolower 0;
    set camelcase 0;
    set pascalcase 0;
    set snakecase 0;
    set kebabcase 0;
    set tagsonly 0;
    global global_tagsonly;
    if {[lsearch $args "toupper"] != -1} {
        set toupper 1;
    }
    if {[lsearch $args "tolower"] != -1} {
        set tolower 1;
    }
    if {[lsearch $args "camelcase"] != -1} {
        set camelcase 1;
    }
    
    if {[lsearch $args "pascalcase"] != -1} {
        set pascalcase 1;
    }
    if {[lsearch $args "kebabcase"] != -1} {
        set kebabcase 1;
    }
    if {[lsearch $args "snakecase"] != -1} {
        set snakecase 1;
    }

    if {[lsearch $args "tagsonly"] != -1} {       
        set tagsonly 1;
    }

    catch {file mkdir "[get_current_folder]/${spectral_subfolder}"}

    if {$global_tagsonly} {
        set tagsonly 1;
    }
    if {[catch {
    
    set slave [::safe::interpCreate];
    interp alias $slave .t {} .t
    interp alias $slave $w {} $w
    $slave eval [list set w $w];
    # empty the text widget
    if {[llength $args] == 0} {
        $w delete 1.0 end;
    }
    set loadingFromFile 0;
    set inOverview 0;

    if {[lsearch $args "overview"] != -1} {
       set inOverview 1;
    }
    if {[lsearch $args "loadingFromFile"] != -1} {
        set loadingFromFile 1;
    }
   
    set initial_pos [$w index insert]
    set in_tag {} ;# [$w tag names $initial_pos];
    set full_text "";
    set pic_offset 0;
    array set pic_offset_at_spanstart {};
    set image_offset 0;
    
    # create items, restoring their attributes
    foreach pass {1 2} {
     
     set this_pos $initial_pos;
     if {$pass == 2 && !$tagsonly} {
         if {$w == ".t" } {
            $w insert $this_pos "";
            $w fastinsert $this_pos $full_text;
        } else {
            $w insert $this_pos $full_text;
        }
     }
    foreach {key value} $save \
    {
       # puts stderr "$key :--> $value";
        switch $key \
        {
            E   { 
                if {$pass == 1} {
                    regsub -all {[;\"\\\[\]]} $value {} value;
                    set cmd "\$w tag configure ";
                    append cmd $value;
                    if [ catch { $slave eval $cmd; } msg ] {
                         addToStatus $msg;
                    }
                }
            }
            P   { 
                if {$pass == 1} {
                    regsub -all {[;\"\\\[\]]} $value {} value;
                    set cmd "\$w tag configure ";
                    append cmd $value;
                    if [ catch { $slave eval $cmd; } msg ] {
                         addToStatus $msg;
                    }

                }
            }
            T    {
                if {$pass == 1} {
                     if {$tolower} {
                        append full_text [string tolower $value];
                    } elseif {$toupper} {
                         append full_text [string toupper $value];
                    } elseif {$camelcase} {
                         append full_text [camel_case $value];
                    } elseif {$pascalcase} {
                         append full_text [pascal_case $value];
                    } elseif {$snakecase} {
                         append full_text [snake_case $value];
                    } elseif {$kebabcase} {
                         append full_text [kebab_case $value];
                    } else {
                         append full_text $value;
                    }
                } else  {
                    set this_pos [$w index "$this_pos + [string length $value] char"];
                }
            }
            BG {
                if {$pass == 2} {
                    set currentBackground [$w cget -background];
                    if {[negateColor $currentBackground] != [negateColor $value]} {
                        $w configure -background $value;
                        set fg [negateColor $value];
                   
                        $w configure -foreground $fg;
                        if {$fg == "#ffffff" || $fg == "#FFFFFF"} {
                            if {!$inOverview} {
                                negateAll 0;
                            }
                        }
                    }
                }
            }
            DF {
                if {$pass == 1} {
                    
                    $w configure -font $value;
                }

            }
            S   { 
                if {$pass == 2} {
                   if {[lsearch $all_tags $value] == -1} {
                       lappend all_tags $value;
                   }
                   set pic_offset_at_spanstart($value) $pic_offset;
                   set tag($value) $this_pos;
                   if {[lsearch $in_tag $value] == -1} {
                     lappend in_tag $value
                   }
                 }
             }
            /S  { 
                if {$pass == 2} {
                  set from $initial_pos;
                  set startoffset 0;
                  catch { set from $tag($value); }
                  catch { set startoffset $pic_offset_at_spanstart($value); }
                  $w tag add $value "$from + $startoffset char" "$this_pos + $pic_offset char";
                  #puts stderr "$w tag add $value $from $this_pos"
                  lremove in_tag $value;
                     if {[string first "hyperref_" $value] == 0} {
                           set word [string range $value 9 end];
                           .t tag bind "hyperref_${word}" <Control-ButtonRelease-1> "followTarget $word";
                           
                    }
                  
                    if {[string first "target_" $value] == 0} {
                           set word [string range $value 7 end];
                           .t tag bind "hyperref_${word}" <Control-ButtonRelease-1> "followTarget $word";
                           
                    }
                }
                
             }
           EI {

              if {$pass == 2} {
                  set fname "[randString].png";
                  set data [base64::decode $value];
                  if {!$inOverview} {     
                    set image [image create photo -data $data];
                    global image_filenames;
                    global image_shrunk;
                    global spectral_subfolder;
                    set shrunk_image [image create photo]
                    $shrunk_image copy $image -subsample 3 3 
                    catch {file mkdir "[get_current_folder]/${spectral_subfolder}"}
                    set fname "[get_current_folder]/${spectral_subfolder}/$fname";
                    set image_shrunk($fname) $shrunk_image;
                    set image_filenames($image) $fname
                    $w image create [$w index "$this_pos + [expr $pic_offset] char"] -image $image;
                    $image write $fname -format png;
                     
                   } else {
                       if {[file exists $fname]} {
                          global image_shrunk;
                          $w image create $this_pos -image [set image_shrunk($fname)]
                      }
                   }
                    if {[file exists $fname]} {  
                         incr pic_offset 1;
                    }
                 
               }


           }

           I {
               if {$pass == 2} {
                  set fname $value;
                  if {$loadingFromFile} {
                     set fname [absolutizeFileName $fname];
                  }
                  if {!$inOverview} {
                    if {[file exists $fname]} {  
                    set image [image create photo -file $fname];
                    global image_filenames;
                    global image_shrunk;
                    set shrunk_image [image create photo]
                    $shrunk_image copy $image -subsample 3 3 
                    set image_shrunk($fname) $shrunk_image;
                    set image_filenames($image) $fname
                    $w image create [$w index "$this_pos + [expr $pic_offset] char"] -image $image;
                     } else {
                         tk_messageBox -message "Referenced image $fname was not found!"
                     }
                   } else {
                       if {[file exists $fname]} {
                          global image_shrunk;
                          $w image create $this_pos -image [set image_shrunk($fname)]
                      }
                   }
                    if {[file exists $fname]} {  
                         incr pic_offset 1;
                    }
                 
               }
           }
           M {
               if {$pass == 2} {
                  
                  if {!$inOverview} {
                   
                      set fname $value;
                      if {$loadingFromFile} {
                          set fname [absolutizeFileName $fname];
                      }
                      if {[file exists $fname] || [file exists "$fname.mp3"]} {
                          insertMediaFile $w [$w index "$this_pos + $pic_offset char"]  $fname;
                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
               }
           }
           F {
               
               if {$pass == 2} {
                 if {!$inOverview} {
                  set fname $value;
                  if {$loadingFromFile} {
                       set fname [absolutizeFileName $fname];
                  }
                   if {[file exists $fname]} {
                         insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname F;

                         incr pic_offset 1;
                    } else {
                         tk_messageBox -message "Referenced file $fname was not found!"
                    }
                }
              }
           }
           
           EXT {
               
               if {$pass == 2} {
                  if {!$inOverview} {
                   set afname [lindex $value 0];
                   set atag [lindex $value 1];
                   set external_hyperrefs($atag) $afname;
                  }
              }
           }
           
            N {
               
               if {$pass == 2} {
                  if {!$inOverview} {
                   set fname $value;
                      if {$loadingFromFile} {
                           set fname [absolutizeFileName $fname];
                      }
                      if {[file exists $fname]} {
                          insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname N;

                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           }
            C { #restoring comment
               
               if {$pass == 2} {
                  if {!$inOverview} {
                   set fname [lindex $value 2];
                      if {$loadingFromFile} {
                           set fname [absolutizeFileName $fname];
                      }
                      if {[file exists $fname]} {
                          set btn [insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname C];
                          set comment_tags($btn) [lindex $value 0];
                          set comment_checksums($btn) [lindex $value 1];

                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           } 
            G { #Restoring generator
               
               if {$pass == 2} {
                  if {!$inOverview} {
                   set fname [lindex $value 2];
                      if {$loadingFromFile} {
                           set fname [absolutizeFileName $fname];
                      }
                      if {[file exists $fname]} {
                          set btn [insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname G];
                          set global_generator_names($btn) [lindex $value 0];
                          set global_generator_tags($btn) [lindex $value 1];
                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           } 
            V { #restoring verifier
               
               if {$pass == 2} {
                  if {!$inOverview} {
                   set fname [lindex $value 2];
                      if {$loadingFromFile} {
                           set fname [absolutizeFileName $fname];
                      }
                      if {[file exists $fname]} {
                          set btn [insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname V];
                          set global_verifier_names($btn) [lindex $value 0];
                          set global_verifier_tags($btn) [lindex $value 1];

                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           } 
           EN {
               global spectral_subfolder;
               if {$pass == 2} {
                  if {!$inOverview} {
                      set fname "[randString].txt";
                      set data [base64::decode $value];
                      set fname "[get_current_folder]/${spectral_subfolder}/$fname";
                      write_to_file $fname $data;
                      if {[file exists $fname]} {
                          insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname N;
                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           }
           EC {
               global spectral_subfolder;
               if {$pass == 2} {
                  if {!$inOverview} {
                      set fname "[randString].txt";
                      set data [base64::decode [lindex $value 2]];
                      set fname "[get_current_folder]/${spectral_subfolder}/$fname";
                      write_to_file $fname $data;
                      if {[file exists $fname]} {
                          
                          set btn [insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname C];
                          set comment_tags($btn) [lindex $value 0];
                          set comment_checksums($btn) [lindex $value 1];
                          
                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           }
           EV { #restoring embedded verifier
               global spectral_subfolder;
               if {$pass == 2} {
                  if {!$inOverview} {
                      set fname "[randString].txt";
                      set data [base64::decode [lindex $value 2]];
                      set fname "[get_current_folder]/${spectral_subfolder}/$fname";
                      write_to_file $fname $data;
                      if {[file exists $fname]} {
                          
                          set btn [insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname V];
                          set global_verifier_names($btn) [lindex $value 0];
                          set global_verifier_tags($btn) [lindex $value 1];                          
                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           }
           EG { #restoring embedded generator
               global spectral_subfolder;
               if {$pass == 2} {
                  if {!$inOverview} {
                      set fname "[randString].txt";
                      set data [base64::decode [lindex $value 2]];
                      set fname "[get_current_folder]/${spectral_subfolder}/$fname";
                      write_to_file $fname $data;
                      if {[file exists $fname]} {
                          
                          set btn [insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname C];
                          set global_generator_names($btn) [lindex $value 0];
                          set global_generator_tags($btn) [lindex $value 1];
                          
                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           }
           EM {
               global spectral_subfolder;
               if {$pass == 2} {
                  if {!$inOverview} {
                      set ext [lindex $value 1];
                      set fname "[randString].${ext}";
                      set data [base64::decode [lindex $value 2]];
                      set fname "[get_current_folder]/${spectral_subfolder}/$fname";
                      write_to_file $fname $data;
                      if {[file exists $fname]} {
                          insertMediaFile $w [$w index "$this_pos + $pic_offset char"]  $fname;
                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           }

           EF {
               global spectral_subfolder;
               if {$pass == 2} {
                  if {!$inOverview} {
                      set ext [lindex $value 1];
                      set fname "[randString].${ext}";
                      set data [base64::decode [lindex $value 2]];
                      set fname "[get_current_folder]/${spectral_subfolder}/$fname";
                      write_to_file $fname $data;
                      if {[file exists $fname]} {
                          insertGeneralFile $w [$w index "$this_pos + $pic_offset char"]  $fname [lindex $value 0];
                          incr pic_offset 1;
                      } else {
                          tk_messageBox -message "Referenced file $fname was not found!"
                      }
                  }
              }
           }
           
        }
      }
    if {$pass == 2} {
      foreach atag $in_tag {
          set from $initial_pos;
          catch { set from $tag($atag); }
          set startoffset 0;
          catch { set startoffset $pic_offset_at_spanstart($atag); }
          $w tag add $atag "$from + $startoffset char" "$this_pos + $pic_offset char";
          #puts stderr "$w tag add $value $from $this_pos"
        }
     }
    }
       ::safe::interpDelete $slave;
    } msg]} {
    
        addToStatus "$msg : malicious/corrupt content detected" ;
    };

    set update_frozen 0;
    update;

}


###########################################################

array set jmtags  {};
proc html_preproc {txt} {
    regsub -all {<} $txt {\&lt;} txt
    regsub -all {>} $txt {\&gt;} txt
    return $txt;
}

proc tagstack_preproc {tags} {

    lremove tags attention;
    lremove tags identifiers;
    lremove tags numbers;
    lremove tags keyword;
    lremove tags vars;
    lremove tags brackets;
    lremove tags strings;
    lremove tags singleLineComment;
    lremove  tags _cComment;
    return $tags;

}

set embedNotes 1;
proc embed_html_notes {val} {
    global embedNotes;
    set was $embedNotes;
    set embedNotes $val;
    return "was $was, now set to $val";
}


proc note {srcfile x y xPerCent yPerCent args} {
     set maxlines [.t index end];
     set lnum [expr int($maxlines*$yPerCent)];
     set linestart "$lnum.0";
     set xoffset [expr int(1.0*$x*$maxlines/$y)];
     set linepos [.t index "$linestart + $xoffset char"];
     create_note $linepos $args
}

proc text:toHtmlWalkthrough  {save folder file absolute_image_path } {
   text:toHtmlGeneral $save $folder $file $absolute_image_path 0 0 0 1
}


proc text:toHtml  {save folder file absolute_image_path } {
   text:toHtmlGeneral $save $folder $file $absolute_image_path 0 0 0 0
}

proc text:toEmbeddableHtml  {save folder file absolute_image_path } {
   text:toHtmlGeneral $save $folder $file $absolute_image_path 0 0 1 0
}

proc text:toEmbeddableHtmlWalkthrough  {save folder file absolute_image_path } {
   text:toHtmlGeneral $save $folder $file $absolute_image_path 0 0 1 1
}

proc text:toHtmlWithMediaIndex  {save folder file absolute_image_path } {
   text:toHtmlGeneral $save $folder $file $absolute_image_path 0 1 0 0
}


proc exportButtonsToHtml {do} {
    global doExportButtonsToHtml;
    set doExportButtonsToHtml $do;
}

proc saveWalkthroughZip {} {
    set zipname [tk_getSaveFile -filetypes {{{Zip Archive} {.zip}}}];
    if {$zipname == ""} {
        return;
    }
    set filename [get_current_filename]  
    if {$filename == ""} {
        tk_messageBox -message "Unnamed/unsaved buffer can not be saved";
        return;
    }
    saveHtmlFile "$filename.html" .t;
    
    set files [relativizeFileName "$filename.html"];
    
    global external_hyperrefs;
    foreach {tag fname} [array get external_hyperrefs] {
        if {[string first line_ $tag] == 0} {
            set external_filenames($fname) 1;
        } else {
            set external_filenames(${fname}.html) 1;
        }
    }
    set error 0;
    foreach fname [array names external_filenames] {
        if {![file exists ${fname}]} {
            addToStatus "ERROR :  The referenced file ${fname} does not exist"; 
            set error 1;
        }
    }
    if {$error} {
        tk_messageBox -message "Some hyperlinked files don't have htmls saved. See status bar for details"
        return "";
    }
    foreach fname [array names external_filenames] {
        lappend files ${fname};
    }
    addToStatus "Zipping files $files"
    catch {
      exec zip $zipname {*}[set files]
      update;
    } msg;
    if {$msg ne ""} {
        addToStatus "highlightCurrent warning: $msg"
    }
    addToStatus $msg;
}

proc text:toHtmlGeneral {save folder file absolute_image_path commentable withMediaIndex embeddable walkthrough} {
    global embedNotes;
    global default_font;
    global default_background;
    global default_foreground;
    global doExportButtonsToHtml;
    global external_hyperrefs;
    array set external_filenames {};
    set js_externalFiles "\nvar externalContent = {};\n"
    if {$walkthrough} {
        foreach {tag fname} [array get external_hyperrefs] {
	   if {[string first "line_" $tag] == 0 } {
               set external_filenames($fname) "";
	   } else {
	     set external_filenames($fname) ".html";
	   }
        }
        set error 0;
        foreach {fname extn} [array get external_filenames] {
                if {![file exists "${fname}${extn}"]} {
                    addToStatus "ERROR : ${fname}${extn} does not exist"; 
                    set error 1;
                } 
            
        }
        if {$error} {
            tk_messageBox -message "Some hyperlinked files don't have htmls saved. See status bar for details"
            return "";
        }
        foreach {fname extn} [array get external_filenames] {
                set extcontent [base64::encode [read_file_contents "${fname}${extn}"]];
                append js_externalFiles "externalContent\[\"$fname${extn}\"\] = `$extcontent`;\n";

        }
        append js_externalFiles "\n";
        
    }
  
    set imageloaders {};
    set out "";
    if {$folder == ""} {
        regsub -all {(^.*)/[^/]*$} $file {\1} folder;
        if {$file == $folder} {
             set folder ".";
        }
    }
  set filename $file;
  regsub -all {(^.*)/([^/]*)$} $filename {\2} filename;
  set script_preamble {
      <script type="text/javascript">
  }
  append script_preamble $js_externalFiles;
  append script_preamble {
        function execCmd(command, value = null) {
            document.execCommand(command, false, value);
        }
		function dumpPreElementHierarchy(preElementId) {
    const preElement = document.getElementById(preElementId);
    if (!preElement) {
        console.error("Element with the specified ID not found.");
        return;
    }

    let output = "";

    function traverse(node) {
        if (node.nodeType === Node.TEXT_NODE) {
            output += node.textContent;
        } else if (node.nodeType === Node.ELEMENT_NODE) {
            if (["SPAN", "B", "FONT"].includes(node.tagName)) {
                output += " S ";  // Start marker
            }

            // Recursively process child nodes
            node.childNodes.forEach(traverse);

            if (["SPAN", "B", "FONT"].includes(node.tagName)) {
                output += " /S ";  // End marker
            }
        }
    }
    traverse(preElement);
    console.log(output.trim());
   }
		function getHtmlAsHlt() {
		    var topPre = document.getElementById("vimCodeElement")
            var spans = topPre.querySelectorAll("span");
            spans.forEach(span => {
                const computedStyles = window.getComputedStyle(span);
                console.log("Styles for class" + span.className);
                console.log("Color:" + computedStyles.color );
                console.log("Font Size:" + computedStyles.fontSize );
                console.log("Background Color:" + computedStyles.backgroundColor);
                console.log('----------------------');
            });
        }

var Base64 = {

    // private property
    _keyStr : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",

    // public method for encoding
    encode : function (input) {
        var output = "";
        var chr1, chr2, chr3, enc1, enc2, enc3, enc4;
        var i = 0;

        input = Base64._utf8_encode(input);

        while (i < input.length) {

            chr1 = input.charCodeAt(i++);
            chr2 = input.charCodeAt(i++);
            chr3 = input.charCodeAt(i++);

            enc1 = chr1 >> 2;
            enc2 = ((chr1 & 3) << 4) | (chr2 >> 4);
            enc3 = ((chr2 & 15) << 2) | (chr3 >> 6);
            enc4 = chr3 & 63;

            if (isNaN(chr2)) {
                enc3 = enc4 = 64;
            } else if (isNaN(chr3)) {
                enc4 = 64;
            }

            output = output +
            this._keyStr.charAt(enc1) + this._keyStr.charAt(enc2) +
            this._keyStr.charAt(enc3) + this._keyStr.charAt(enc4);

        }

        return output;
    },

    // public method for decoding
    decode : function (input) {
        var output = "";
        var chr1, chr2, chr3;
        var enc1, enc2, enc3, enc4;
        var i = 0;

        input = input.replace(/[^A-Za-z0-9\+\/\=]/g, "");

        while (i < input.length) {

            enc1 = this._keyStr.indexOf(input.charAt(i++));
            enc2 = this._keyStr.indexOf(input.charAt(i++));
            enc3 = this._keyStr.indexOf(input.charAt(i++));
            enc4 = this._keyStr.indexOf(input.charAt(i++));

            chr1 = (enc1 << 2) | (enc2 >> 4);
            chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
            chr3 = ((enc3 & 3) << 6) | enc4;

            output = output + String.fromCharCode(chr1);

            if (enc3 != 64) {
                output = output + String.fromCharCode(chr2);
            }
            if (enc4 != 64) {
                output = output + String.fromCharCode(chr3);
            }

        }

        output = Base64._utf8_decode(output);

        return output;

    },

    // private method for UTF-8 encoding
    _utf8_encode : function (string) {
        string = string.replace(/\r\n/g,"\n");
        var utftext = "";

        for (var n = 0; n < string.length; n++) {

            var c = string.charCodeAt(n);

            if (c < 128) {
                utftext += String.fromCharCode(c);
            }
            else if((c > 127) && (c < 2048)) {
                utftext += String.fromCharCode((c >> 6) | 192);
                utftext += String.fromCharCode((c & 63) | 128);
            }
            else {
                utftext += String.fromCharCode((c >> 12) | 224);
                utftext += String.fromCharCode(((c >> 6) & 63) | 128);
                utftext += String.fromCharCode((c & 63) | 128);
            }

        }

        return utftext;
    },

    // private method for UTF-8 decoding
    _utf8_decode : function (utftext) {
        var string = "";
        var i = 0;
        var c = c1 = c2 = 0;

        while ( i < utftext.length ) {

            c = utftext.charCodeAt(i);

            if (c < 128) {
                string += String.fromCharCode(c);
                i++;
            }
            else if((c > 191) && (c < 224)) {
                c2 = utftext.charCodeAt(i+1);
                string += String.fromCharCode(((c & 31) << 6) | (c2 & 63));
                i += 2;
            }
            else {
                c2 = utftext.charCodeAt(i+1);
                c3 = utftext.charCodeAt(i+2);
                string += String.fromCharCode(((c & 15) << 12) | ((c2 & 63) << 6) | (c3 & 63));
                i += 3;
            }

        }

        return string;
    }

}
function loadComments() 
{
    var lines = window.document.getElementById("notes").value.split("\n");
    for(var i = 0; i < lines.length; ++i) {
        line = lines[i];
        
        var words = line.split(" ");
        if (words.length < 6) continue;
        var px = parseFloat(words[4]);
        var py = parseFloat(words[5]);
        var y = Math.round(py*window.document.getElementById("content").scrollHeight);
        //var x = Math.round(px*window.document.getElementById("content").scrollWidth);
        var x = Math.round(parseFloat(words[2]));
        var note = "";
        for (var j = 6; j < words.length; ++j) {
           note = note + words[j]+ " ";
        }
        
         var newDiv = document.createElement("div"); 
        var newContent = document.createTextNode(note); 
        newDiv.appendChild(newContent);
        newDiv.style.position='absolute';
        newDiv.style.top =  y+'px';
        newDiv.style.left = x+'px';
        newDiv.style.backgroundColor = '#ffff80';
        newDiv.style.fontFamily = "Courier New";
        newDiv.style.fontSize = "10pt";
        document.body.appendChild(newDiv);

        
    }
   
}
function popup(txt, popupid)
{
  var generator=window.open('',popupid,',resizable=false,height=800,width=1000,titlebar=0,toolbar=0');
  var doc = generator.document;
  doc.write("<html><head>");
  doc.write("<style type=\"text/css\">");
  doc.write("body { background-color: $default_background ;  color: $default_foreground; }"); 
  doc.write("\ntextarea {width: 100%;  height: 100%; }"); 
  doc.write("</style></head>");

  doc.write("<body><textarea id=myarea>");
  doc.write("</textarea></body></html>");
  generator.focus();
  doc.getElementById('myarea').value = txt;
  doc.close();
}
function escapeHtml(text) {
    var map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    };

    return text.replace(/[&<>"']/g, function (m) {
        return map[m];
    });
}

function popupWithLineNumber(txt, popupid,linenum)
{
    var generator=window.open('',popupid,',resizable=false,height=800,width=1200,titlebar=0,toolbar=0');
  var doc = generator.document;
  doc.write("<html><head><");
  doc.write("script>");
  doc.write("\nfunction selectText(containerid) {");
  doc.write("\n    if (document.selection) { // IE");
  doc.write("\n        var range = document.body.createTextRange();");
  doc.write("\n        element = document.getElementById(containerid);");
  doc.write("\n        if(element != null)");
  doc.write("\n        {");
  doc.write("\n            range.moveToElementText(element);");
  doc.write("\n            range.select();");
  doc.write("\n            element.scrollIntoView();");
  doc.write("\n            setTimeout(function() {");
  doc.write("\n                    element.scrollIntoView({ behavior: \"smooth\" });");
  doc.write("\n                }, 1000);");
  doc.write("\n        }");
  doc.write("\n    } else if (window.getSelection) {");
  doc.write("\n        var range = document.createRange();");
  doc.write("\n        element = document.getElementById(containerid);");
  doc.write("\n        if (element != null)");
  doc.write("\n        {");
  doc.write("\n            range.selectNode(element);");
  doc.write("\n            window.getSelection().removeAllRanges();");
  doc.write("\n            window.getSelection().addRange(range);");
  doc.write("\n            element.scrollIntoView();");
  doc.write("\n            setTimeout(function() {");
  doc.write("\n                    element.scrollIntoView({ behavior: \"smooth\" });");
  doc.write("\n                }, 1000);");
  doc.write("\n            ");
  doc.write("\n        }");
  doc.write("\n    }");
  doc.write("\n}");
  doc.write("\nsetTimeout(function() {selectText(\"line_"+linenum+"\")},1000);");
  doc.write("</");
  doc.write("script>\n");
  doc.write("<style type=\"text/css\">");
  doc.write("body { background-color: white ;  color: black; }"); 
  doc.write("\ntextarea {width: 100%;  height: 100%; }"); 
  doc.write("\npre {  font-family: monospace; font-size: 10pt;  display: inline; margin: 0;  white-space: pre-wrap;    white-space: -moz-pre-wrap;   white-space: -pre-wrap;       white-space: -o-pre-wrap;     word-wrap: break-word;       }");
  doc.write("\n</style></head>");
  doc.write("<body id=myarea>");
  doc.write("</body></html>");
  generator.focus();
  
  const lines = txt.split(/\n/); 
  // Iterate through the pieces (lines)
  bodyHtml="";
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (i > 0) bodyHtml+="</pre></span>";
    bodyHtml+="<span id=\"line_"+(i+1) +"\"><pre>"+escapeHtml(line)+"\n";
  }
  if(lines.length > 0) bodyHtml+="</pre>";
  doc.getElementById('myarea').innerHTML = bodyHtml;
  
  var s = doc.getElementsByTagName('script');
  generator.eval(s[0].text);
  
  doc.close();
}


function popupTsv(txt, popupid)
{
  var generator=window.open('',popupid,',resizable=false,height=800,width=1000,titlebar=0,toolbar=0');
  var doc = generator.document;
  doc.write("<html><head>");
  doc.write("<style type=\"text/css\">");
  doc.write("\nbody { background-color: white ;  color: black;  }"); 
  doc.write("\ntable,th,td {border: 1px solid white; border-collapse: collapse; font-family: 'Lucida Console', 'Courier New', monospace; font-size: 10}"); 
  doc.write("\nth, td {background-color: #96D4D4;}")
  doc.write("</style></head>");
  doc.write("<body id='body1'>");
  doc.write("</body></html>");
  generator.focus();
  

  var table = doc.createElement('TABLE');
  var tbody = doc.createElement('TBODY');
  table.appendChild(tbody);
  var lines=txt.split("\n");
  for(var i=0,l;l=lines[i];i++){
    var fields=l.split("\t");
    if(fields.length==0) return;
    var tr=doc.createElement('TR');
    for(var j=0,f;f=fields[j];j++){
      var td=doc.createElement('TD');
      if(f[0]=='"') {
         f = f.substr(1); 
      }
      if(f.substr(-1) == '\n' || f.substr(-1) == '\r') {
          f = f.substr(0,f.length-1);
      }
      if(f.substr(-1) == '\n' || f.substr(-1) == '\r') {
          f = f.substr(0,f.length-1);
      }
      if(f.substr(-1) == '"') {
          f = f.substr(0,f.length-1);
      }
      td.innerHTML = f;
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
  doc.getElementById('body1').appendChild(table);
  doc.close();
}

function popupHtml (txt, popupid)
{
  var generator=window.open('',popupid,',resizable=false,height=800,width=1200,titlebar=0,toolbar=0');
  var doc = generator.document;
  doc.write("<html><head>");
  doc.write("<style type=\"text/css\">");
  doc.write("body { background-color: white ;  color: black; }"); 
  doc.write("\ntextarea {width: 100%;  height: 100%; }"); 
  doc.write("</style></head>");
  doc.write("<body id=myarea>");
  doc.write("</body></html>");
  generator.focus();
  doc.getElementById('myarea').innerHTML = txt;
  
  var s = doc.getElementsByTagName('Script');
  generator.eval(s[0].text);
  generator.eval(s[1].text);
  
  doc.close();
}

function popupHtmlAndGotoTag (txt, popupid, tag)
{
  var generator=window.open('',popupid,',resizable=false,height=800,width=1200,titlebar=0,toolbar=0');
  var doc = generator.document;
  doc.write("<html><head>");
  doc.write("<style type=\"text/css\">");
  doc.write("body { background-color: white ;  color: black; }"); 
  doc.write("\ntextarea {width: 100%;  height: 100%; }"); 
  doc.write("</style></head>");
  doc.write("<body id=myarea>");
  
  doc.write("</html>");
  generator.focus();
  doc.getElementById('myarea').innerHTML = txt;
  
  var s = doc.getElementsByTagName('Script');
  
  generator.eval(s[0].text);
  generator.eval(s[1].text+";selectText(\""+tag +"\");");

  
  doc.close();
}

function showWalkthroughContent(tag, fname) 
{
    var content = Base64.decode(externalContent[fname]);
    popupHtmlAndGotoTag(content,fname,tag);
}

function showGrepLineWalkthroughContent(line, fname) 
{
    var content = Base64.decode(externalContent[fname]);
    popupWithLineNumber(content,fname,line);
}

function showText(str, popupid)
{
  dec = Base64.decode(str);
  popup(dec, popupid);
} 

function showTextHtml(str, popupid)  {
  dec = Base64.decode(str);
  popupHtml(dec, popupid);
  
} 

function showTextTsv(str, popupid)  {
  dec = Base64.decode(str);
  popupTsv(dec, popupid);
  
} 

function selectSpan(className) {
      const spans = document.querySelectorAll('span.'+className);
      if (spans.length === 0) return;

      const range = document.createRange();
      range.setStartBefore(spans[0]);
      range.setEndAfter(spans[spans.length - 1]);

      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
}
    
function selectText(containerid) {
    if (document.selection) { // IE
        var range = document.body.createTextRange();
        element = document.getElementById(containerid);
        if(element != null)
        {
            range.moveToElementText(element);
            range.select();
            element.scrollIntoView();
            setTimeout(function() {
                    element.scrollIntoView({ behavior: "smooth" });
                }, 1000);
        }
    } else if (window.getSelection) {
        var range = document.createRange();
        element = document.getElementById(containerid);
        if (element != null)
        {
            range.selectNode(element);
            window.getSelection().removeAllRanges();
            window.getSelection().addRange(range);
            element.scrollIntoView();
            setTimeout(function() {
                    element.scrollIntoView({ behavior: "smooth" });
                }, 1000);
            
        }
    }
}

function playVideo(txt,popupid)
{
var generator=window.open('',popupid,',resizable=false,height=400,width=500,titlebar=0,toolbar=0');
  var doc = generator.document;
  doc.write("<html><head>");
  doc.write("<style type=\"text/css\">");
  doc.write("body { background-color: white ;  color: black; }"); 
  doc.write("\nvideo {width: 100%;  height: 100%; }"); 
  doc.write("</style></head>");
  doc.write("<body><video controls id=myarea>");
  doc.write("</video></body></html>");
  generator.focus();
  doc.getElementById('myarea').src = txt;
  doc.close();
}

function playAudio(txt,popupid)
{
var generator=window.open('',popupid,',resizable=false,height=100,width=400,titlebar=0,toolbar=0');
  var doc = generator.document;
  doc.write("<html><head>");
  doc.write("<style type=\"text/css\">");
  doc.write("body { background-color: white ;  color: black; }"); 
  doc.write("\nvideo {width: 100%;  height: 100%; }"); 
  doc.write("</style></head>");
  doc.write("<body><audio controls id=myarea>");
  doc.write("</audio></body></html>");
  generator.focus();
  doc.getElementById('myarea').src = txt;
  doc.close();
  audio = new Audio(txt);
  audio.play();
}

function playSound(txt,popupid)
{
  audio = new Audio(txt);
  audio.play();
}


function playImage(txt,popupid)
{
  var generator=window.open('',popupid,',resizable=false,height=600,width=800,titlebar=0,toolbar=0');
  var doc = generator.document;
  doc.write("<html><head>");
  doc.write("<style type=\"text/css\">");
  doc.write("body { background-color: white ;  color: black; }"); 
  doc.write("\nvideo {width: 100%;  height: 100%; }"); 
  doc.write("</style></head>");
  doc.write("<body><img  id=myarea>");
  doc.write("</img></body></html>");
  generator.focus();
  doc.getElementById('myarea').src = txt;
  doc.close();
}

}
if {$commentable} {
       append script_preamble {

window.document.addEventListener(
    'contextmenu', 
    function(ev) { 
        ev.preventDefault(); 
     
        var comment = prompt("Please enter your comment", "");
        if (comment != null && comment != "") {
        var newDiv = document.createElement("div"); 
     
        var py = (1.0*ev.pageY)/window.document.getElementById("content").scrollHeight;
        var px = (1.0*ev.pageX)/window.document.getElementById("content").scrollWidth;
        
        var newContent = document.createTextNode(comment); 
        newDiv.appendChild(newContent);
        newDiv.style.position='absolute';
        newDiv.style.top =  ev.pageY+'px';
        newDiv.style.left = ev.pageX+'px';
        newDiv.style.backgroundColor = '#ffff80';
        newDiv.style.fontFamily = "Courier New";
          newDiv.style.fontSize = "10pt";
        document.body.appendChild(newDiv);
        window.document.getElementById("notes").value += "note "+window.location.href+" "+ev.pageX+" "+ev.pageY+" "+px+" "+py+" "+comment +'\n';
        }
        
        return false; 
        }, false);

       }
  }
  
  set media_data "";

  set script_preamble [subst  -nobackslashes -nocommands $script_preamble];
  
  append script_preamble "
    function onBodyLoad() \{
        var targetId = window.location.hash.substr(1)
        selectText(targetId);
  "
  if {$embeddable} {
      set preamble {};
  } else {
      set preamble "
        <!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">
<html>
<head>
<meta http-equiv=\"content-type\" content=\"text/html; charset=UTF-8\">
<title>$filename</title>
<meta name=\"Generator\" content=\"Spectral\">
<meta name=\"settings\" content=\"use_css,pre_wrap,no_foldcolumn,expand_tabs,prevent_copy=1\">"
  }

        set css_preamble "<style type=\"text/css\">" 
        append css_preamble "
a {
    font-family: monospace;
    font-size: 10pt;
    display: inline; 
}

.link-style {
  color: #007bff; /* Link color, you can change this to your desired color */
  text-decoration: underline; /* Underline the text */
  cursor: pointer; /* Change cursor to pointer on hover to indicate interactivity */
}

.link-style:hover {
  color: #0056b3; /* Change color on hover for visual feedback */
}        
        
";

      if {[llength $default_font] == 1} {
      append css_preamble "
img {
  display: inline-block;
  vertical-align:middle;
}
pre {
    display: inline;
    margin: 0;
    white-space: pre-wrap;       /* CSS 3 */
    white-space: -moz-pre-wrap;  /* Mozilla, since 1999 */
    white-space: -pre-wrap;      /* Opera 4-6 */
    white-space: -o-pre-wrap;    /* Opera 7 */
    word-wrap: break-word;       /* Internet Explorer 5.5+ */
font-family: [lindex $default_font 0]; font-size: 10pt ; background-color: $default_background; color: $default_foreground; }
body { font-family: [lindex $default_font 0]; background-color: $default_background ; font-size: 10pt; }
* { font-size: 10pt; color: $default_foreground; }
" } elseif {[llength $default_font] == 2} {
     append css_preamble "
img {
  display: inline-block;
  vertical-align:middle;
}


pre {  
    display: inline;
    margin: 0;
    white-space: pre-wrap;       /* CSS 3 */
    white-space: -moz-pre-wrap;  /* Mozilla, since 1999 */
    white-space: -pre-wrap;      /* Opera 4-6 */
    white-space: -o-pre-wrap;    /* Opera 7 */
    word-wrap: break-word;       /* Internet Explorer 5.5+ */
    font-family: [lindex $default_font 0]; font-size: [lindex $default_font 1]pt ;  background-color: $default_background;  color: $default_foreground; }
body { font-family: [lindex $default_font 0];  background-color: $default_background ; font-size: [lindex $default_font 1]pt;  color: $default_foreground; }
* { font-size: [lindex $default_font 1]pt; }
"
} else {
    append css_preamble "
img {
  display: inline-block;
  vertical-align:middle;
}
pre { 
    font-family: monospace;
    font-size: 10pt; 
    display: inline;
    margin: 0;
    //white-space: pre;
    white-space: pre-wrap;       // CSS 3 
    white-space: -moz-pre-wrap;  // Mozilla, since 1999 
    white-space: -pre-wrap;      // Opera 4-6 
    white-space: -o-pre-wrap;    // Opera 7 
    
    word-wrap: break-word;       // Internet Explorer 5.5+ 
  }
body { background-color: $default_background ;  color: $default_foreground; } 
  "
}
    set mid {
     
</style> 
}
   if {!$embeddable} {
   append mid {
</head>
<body>
   }
  }
  append mid {
<div id="content" contenteditable=true>}
set prestart {
<pre id='vimCodeElement'>
}
set end {
    </pre> </div>
}
if {$commentable} {
   append end {
    <br/>
       <textarea id="notes" rows="7" cols="80"></textarea>
       <br/>
       <a onclick="loadComments()"><button>Load Comments</button></a>
    <br/>
   }
}
append end {
    <script>onBodyLoad();</script>
}
if {!$embeddable} {
    append end {
</body>
</html>
    }
}
set current_filename [ get_current_filename ];
global external_hyperrefs;
append end {
<!-- vim: set foldmethod=manual : -->}
    global jmtags;
    array set jmtags  {};
    set css "";
    set pre "";
    set imagelist "";
    set audiolist "";
    set notelist "";
    set imagecount 0;
    set notecount 0;
    set audiocount 0;
    set in_string 0;
    set tag_stack {};
    foreach {key value index} $save \
    {
        switch $key \
        {   exec    { 
                      if {[lrange $value 1 2] == "tag configure"} {
                          set tname [lindex $value 3];
                          set jmtags($tname) [lrange $value 4 end]
                       }
                    }
            text    { 
                append pre [html_preproc $value]
            }
            tagon   {
                regsub -all {#} $value {c} value;
                foreach item $tag_stack {
                    append pre "</span>"
                }
                if {$value == "link"} {
                    append pre "</pre>"
                    append pre "<a href=\"";
                } elseif {[string first "target_" $value] == 0} {
                    set word [string range $value 7 end];
                    append pre "</pre>"
                    append pre "<span id=${word}><pre>";
                } elseif {[string first "hyperref_" $value] == 0} {
                    set word [string range $value 9 end];
                    append pre "</pre>"
                    if {[info exists external_hyperrefs($word)]} {
                        if {$walkthrough} {
                           set fname $external_hyperrefs($word);
                           if {$fname == $current_filename} {
                                append pre "<a href=#${word} onClick=\"javascript:selectText('${word}');\">";
                            } else {
                               if {[string first "line_" $word] == 0} {
                                   regsub -all {line_[^_]+_} $word {} greplinenum;
                                   append pre "<a class=\"link-style\" onclick=\"showGrepLineWalkthroughContent(${greplinenum},\'${fname}\')\" >";

                               } else {
                                   append pre "<a class=\"link-style\" onclick=\"showWalkthroughContent(\'${word}\',\'${fname}.html\')\" >";
                                }
                            }
                        } else {
                            set fname $external_hyperrefs($word);
                            if {$fname == $current_filename} {
                                append pre "<a href=#${word} onClick=\"javascript:selectText('${word}');\">";
                            } else {
                                if {[string first "line_" $word] == 0} {
                                    regsub -all {line_[^_]+_} $word {} greplinenum;
                                    append pre "<a href=${fname}#${greplinenum} >";
                                } else {
                                   append pre "<a href=${fname}.html#${word} >";
                                }
                            }
                        }
                    } else {
                        append pre "<a href=#${word} onClick=\"javascript:selectText('${word}');\">";
                    }
                } else {
                lappend tag_stack $value;
                }
                #append pre "tagon:(" $tag_stack ")"
                foreach item  $tag_stack {
                    append pre "<span class=\"$item\">"
                }
                

            }
            tagoff  {
                regsub -all {#} $value {c} value;

                if {$value == "link"} {
                    append pre "\">link</a>";
                    append pre "<pre><span></span>";
                } else {
                     foreach item $tag_stack {
                        append pre "</span>"
                    }
                    if {[string first "target_" $value] == 0} {
                        set word [string range $value 7 end];
                        append pre "</pre></span>"
                        append pre "<pre><span></span>";
                    } elseif {[string first "hyperref_" $value] == 0} {
                        set word [string range $value 9 end];
                       
                        append pre "</a>"
                        append pre "<pre><span></span>";
                    } else {
                       lremove tag_stack $value;
                    }
                }
                #append pre "tagoff:(" $tag_stack ")"
                foreach item $tag_stack {
                    append pre "<span class=\"$item\">"
                }
                
            }
            image {
                global image_filenames;
                set fname [set image_filenames($value)];

                 foreach item $tag_stack {
                    append pre "</span>"
                }
               
                append pre "</pre>";
                foreach item $tag_stack {
                        append pre "<span class=\"$item\">"
                }
                set uid [guid];
                incr imagecount;
                regsub -all {^.*/} $fname "" fname;
                
                append imagelist "\n<a href=#${uid}>image ${imagecount}</a><br/>"
                append pre "<a name=${uid}><img  id=\"" "img_${uid}" "\" /></a>"
                if {$absolute_image_path} {
                      set imgfile  "file:///$folder/${uid}_$fname" 
                } else {
                      set imgfile  "${uid}_$fname" 
                }


                ###########

                if {$embedNotes} {
                        set filecont [read_file_contents [set image_filenames($value)]];
                        set fileextension [get_file_extension  [set image_filenames($value)]];
                        set filebase64 [base64::encode $filecont]; 
                        append script_preamble "
var image_${uid} = document.getElementById(\"img_${uid}\");
image_${uid}.src = `data:image/${fileextension};base64,${filebase64}`; 
                "
                } else {
                        file copy -force [set image_filenames($value)] "$folder/${uid}_$fname";
                        append script_preamble "
var image_${uid} = document.getElementById(\"img_${uid}\");
image_${uid}.src = \"$imgfile\"; 
                "
                }
                ###########

                foreach item $tag_stack {
                    append pre "</span>"
                }

                
              append pre "<pre><span></span>";
              foreach item $tag_stack {
                    append pre "<span class=\"$item\">"
               }
            }
            window \
            {
                global doExportButtonsToHtml;
                global general_filenames;
                global sound_filenames;
                if {[info exists sound_filenames($value)]} {
                    set fname [set sound_filenames($value)];
                    foreach item $tag_stack {
                      append pre "</span>"
                    }
                 
                    append pre "</pre>";
                    foreach item $tag_stack {
                        append pre "<span class=\"$item\">"
                    }
                    set uid [guid];
                    incr audiocount;
                    regsub -all {^.*/} $fname "" fname;
                 
                    set soundfilename [set sound_filenames($value)];
                    if {[file exists "$soundfilename.mp3"]} {
                        set soundfilename "${soundfilename}.mp3";
                        set fname "$fname.mp3";
                    } 
                    set fname_len [string length $fname];
                    set fname_ext [string range $fname [expr $fname_len -3] $fname_len];
                    
                    
                    append audiolist "\n<a href=#${uid}>media ${audiocount}</a><br/>"
                    if {$fname_ext == "mp3" || $fname_ext == "wav"} {
                          append pre "<a name=${uid} onclick=\"playAudio(media_data_${uid}(),'${uid}');\"><button>\u25BA ${audiocount}</button></a>";
                    } elseif {$fname_ext == "mp4" || $fname_ext == "ogg"} {
                        append pre "<a name=${uid} onclick=\"playVideo(media_data_${uid}(),'${uid}');\"><button>\u25BA ${audiocount}</button></a>";
                    } elseif {$fname_ext == "png" || $fname_ext == "jpg" || $fname_ext == "gif" } {
                        append pre "<a name=${uid} onclick=\"playImage(media_data_${uid}(),'${uid}');\"><button>\u25BA ${audiocount}</button></a>";
                    }
                    foreach item $tag_stack {
                      append pre "</span>"
                    }

                    if {$embedNotes} {
                        set filecont [read_file_contents $soundfilename];
                        set fileextension [get_file_extension  $soundfilename];
                        set filebase64 [base64::encode $filecont]; 
                        append media_data "
                        function media_data_${uid} () \{
                            return `data:audio/${fileextension};base64,${filebase64}`; 
                        \} 
                        ";
                     } else {
                        file copy -force $soundfilename "$folder/${uid}_$fname";
                        append media_data "
                        function media_data_${uid} () \{
                            return `$folder/${uid}_$fname`; 
                        \} 
                        " 
                     }
                    append pre "<pre><span></span>"
                    foreach item $tag_stack {
                        append pre "<span class=\"$item\">"
                    }
                } elseif {[info exists general_filenames($value)] && $doExportButtonsToHtml } {
                    incr notecount;
                    global comment_tags;
                    global global_generator_tags;
                    global global_verifier_tags;
                    set cmttag "";
                    set selspan "";
                    set buttonsym "\u2020" 
                    if {[info exists comment_tags($value)]} {
                        set cmttag [set comment_tags($value)];
                        set selspan "selectSpan('$cmttag');";
                        set buttonsym "\u00a7"
                    } elseif {[info exists global_generator_tags($value)]} {
                        set gentag [set global_generator_tags($value)];
                        set selspan "selectSpan('$gentag');";
                        set buttonsym "\u2021"
                    } elseif {[info exists global_verifier_tags($value)]} {
                        set gentag [set global_verifier_tags($value)];
                        set selspan "selectSpan('$gentag');";
                        set buttonsym "\u2021"
                    }
                    set fname [set general_filenames($value)];
                    foreach item $tag_stack {
                      append pre "</span>"
                    }
                    append pre "</pre>";
                    foreach item $tag_stack {
                        append pre "<span class=\"$item\">"
                    }
                    set uid [guid];
                    regsub -all {^.*/} $fname "" fname;
                    set filecont [read_file_contents [set general_filenames($value)]];
                    set notecont [string range $filecont 10 end];
                    if {[string range $filecont 0 9] == "indexentry"} {
                        append notelist "\n<a href=#${uid}>note ${notecount}:$notecont</a><br/>"
                    } else {
                        append notelist "\n<a href=#${uid}>note ${notecount}</a><br/>"
                    }
                    if {$embedNotes} {
                        set encoded [base64::encode $filecont]; 
                        if {[regexp -nocase {html?$} $fname]} {
                            append pre "<a name=\"${uid}\"></a><button onclick=\"${selspan}showTextHtml(`${encoded}`,'${uid}')\">${buttonsym} ${notecount}</button>"
                        } elseif {[regexp -nocase {tsv$} $fname]} {
                            append pre "<a name=\"${uid}\"></a><button onclick=\"${selspan}showTextTsv(`${encoded}`,'${uid}')\">${buttonsym} ${notecount}</button>"
                        } else {
                            append pre "<a name=\"${uid}\"></a><button onclick=\"${selspan}showText(`${encoded}`,'${uid}')\">${buttonsym} ${notecount}</button>"
                        }
                        
                    } else {
                        file copy -force [set general_filenames($value)] "$folder/${uid}_$fname"; 
                        append pre "<a name=\"${uid}\" href=\"" "${uid}_$fname" "\"></a><button>${buttonsym} ${notecount}</button></a>"
                    }
                    foreach item $tag_stack {
                        append pre "</span>"
                    }
                    append pre "<pre><span></span>";
                    foreach item $tag_stack {
                        append pre "<span class=\"$item\">"
                    }

                }
            }
        }
    }

    set css [create_css];
    
   append script_preamble "
     \}
     ";
     append script_preamble $media_data;
    append script_preamble "
      </script>
   "
    
    if {$commentable} {
         append out $preamble $script_preamble $css_preamble $css $mid $prestart
    } else {
        if {$withMediaIndex} {
        append out $preamble $script_preamble $css_preamble $css  $mid $imagelist $notelist $audiolist $prestart; } else {
          append out $preamble $script_preamble $css_preamble $css  $mid $prestart;  
        }
    }
    # append out "\n" [array get jmtags] "\n";
    append out $pre;
    append out $end;
    return $out;
}

proc get_file_extension {fname} {
    set extn [file extension $fname]
    return [string range $extn 1 end];
}

proc transform_css {key val} {
    if {$key == "-font"} {
       set linethru "";
       set underline "";

      if { [lsearch $val underline] != -1 } {
            set linethru "text-decoration : underline;"
      }  
      if { [lsearch $val overstrike] != -1 } {
            set linethru "text-decoration : line-through;"
      }
      if {[llength $val] == 1} {
          return "font-family : \"$val\" ;  $linethru $underline";
      } elseif {[llength $val] == 2} {
          return "font-family : \"[lindex $val 0]\" ; font-size : [lindex $val 1]pt ; $linethru $underline"
      } else  {
          return "font-family : \"[lindex $val 0]\" ; font-size : [lindex $val 1]pt ; font-weight: [lindex $val 2]; $linethru $underline"
      }
    } elseif {$key == "-underline" && $val} {
        return "text-decoration : underline ;"
    } elseif {$key == "-overstrike" && $val} {
        return "text-decoration : line-through;"
    } else {
      array set lookup {
         -foreground color
         -background background-color
         -relief relief
         -borderwidth border-width
      }
      return "[set lookup($key)] : $val ;"
    } 
}

proc create_css {} {
    set out "";
    global jmtags;
    set names [array names jmtags];
    foreach name $names {
        set attribs [set jmtags($name)];

        set cssname $name;
        regsub -all  {#}  $cssname c cssname;
        append out "\n.${cssname} \{ "
        foreach {key val} $attribs  {
            append out "[transform_css $key $val] ";
        }
        append out " \}"
    }
    return $out;
}
proc show_current_view_on_overview {} {
     loadOverview;
     set w [.textFrame.overview component text];
     $w configure -state normal;
     $w configure -undo 0;

     set view_top [expr int(1.999999999 + [.t index end] * [lindex [.t yview] 0])];
     set view_bottom [expr int(1.999999999 + [.t index end] * [lindex [.t yview] 1])];

     $w tag remove viewmarker 1.0 end;
     $w tag remove viewbg 1.0 end;
     $w tag remove cursor 1.0 end;

     $w tag configure viewmarker -background red;
     if {[negateColor [$w cget -background]] == "#ffffff"} {
        $w tag configure viewbg -background #222222;
     } else {
        $w tag configure viewbg -background #dddddd;
     }
     $w tag configure cursor -background blue;



     $w tag add viewmarker "${view_top}.0" "${view_top}.end + 1 char";
     $w tag add viewmarker "${view_bottom}.0" "${view_bottom}.end + 1 char";
     $w tag add viewbg "${view_top}.0" "${view_bottom}.end";

     
     set insertPos [lindex [split [.t index insert] "."] 0];
     $w tag add cursor "${insertPos}.0"  "${insertPos}.end + 1 char"

     $w tag lower viewbg;
     $w tag raise viewmarker;
     $w tag raise cursor;


     $w yview "${view_top}.0";
     $w configure -state disabled;


}

proc change_xview {args} {
    eval ".t xview  $args";
}

proc change_yview {args} {
    global modified;
    set marker "";
    if {$modified} {
        set marker "(M)"
        .bottomFrame.toppos configure -background "orange";
            .bottomFrame.position configure -background "orange";
    } else {
            .bottomFrame.toppos configure -background "green";
            .bottomFrame.position configure -background "green";
    }
    if {[llength $args] == 0} {
        set args " moveto [lindex [.t yview] 0]" ;
    } 
    #puts stderr $args;
    global view_top;
    global cursor_pos;
    eval ".t yview  $args";
    set view_top [expr int(1.999999999 + [.t index end] * [lindex [.t yview] 0])];
   .bottomFrame.toppos configure -text "END: [.t index end] ${marker}";
    .bottomFrame.position clear;
    .bottomFrame.position insert 0 $cursor_pos; 
}
frame .textFrame
scrollbar .s -orient vertical -command {change_yview} -takefocus 1
scrollbar .shoriz -orient horizontal -command {change_xview} -takefocus 1

 ctext .t -yscrollcommand {.s set} -xscrollcommand {.shoriz set} -wrap word -width 100 -height $textheight \
    -font $default_font -setgrid 1 -highlightthickness 0 \
    -padx 4  -takefocus 0 -bg $default_background -fg $default_foreground -insertbackground blue -selectbackground #6bced6 -selectforeground black -selectborderwidth 2 -inactiveselectbackground #6bced6 -maxundo -1 -undo 1
   
iwidgets::scrolledtext .textFrame.overview  -labeltext "Refresh Overview" -wrap word -labelpos n \
    -vscrollmode static -hscrollmode dynamic \
    -width 16 -textbackground $default_background -background white ;
[.textFrame.overview component label] configure -relief raised
[.textFrame.overview component text] configure -undo 0
pack .textFrame.overview -side right -fill y
pack .s -in .textFrame -side right -fill y
pack .shoriz -in .textFrame -side bottom -fill x
[.textFrame.overview component label] configure -background white;
frame .statusFrame
scrollbar .status_s -orient vertical -command {.status yview} -takefocus 1
pack .status_s -in .statusFrame -side right -fill y
text .status -wrap word -width 100 -height 3 \
    -font {Courier 10} -setgrid 1 -highlightthickness 0 \
    -padx 4 -pady 2 -takefocus 0 -bg #ababc8 -fg #101010 -insertbackground blue
pack .status -in .statusFrame -expand y -fill both -padx 1
pack .statusFrame -side bottom -fill x;


bind [.textFrame.overview component label] <ButtonPress-1>  {loadOverview};
bind [.textFrame.overview component text] <Double-ButtonPress-1>  {change_yview [[.textFrame.overview component text] index {@%x,%y}]};
    
    #-padx 4 -pady 2 -takefocus 0 -bg white -fg #101010 -insertbackground blue -selectbackground #6bced6 -selectforeground black -selectborderwidth 2 -maxundo -1 -undo 1
.t tag configure highlight2 -background #6bced6
.t tag configure diffed -background #dbd6ce
.t tag configure highlight3 -background #f7fbac 
.t tag configure linenum -background #aaaaaa

checkbutton .searchFrame.codeMode -text "autsyn" -font {Consolas 8} -variable autosyn_mode -relief flat \
    -onvalue 1 \
    -offvalue 0 -anchor n -background white -foreground red;
    

grid .searchFrame.search1 .searchFrame.search2 .searchFrame.search3 \
.searchFrame.search4 .searchFrame.search5 .searchFrame.search6 .searchFrame.color .searchFrame.font .searchFrame.foreground  .searchFrame.codeMode \
-sticky snew;
grid columnconfigure . {0 1 2 3 4 5 6 7 8 9 10} -uniform allTheSame
pack .topFrame -side top -fill x 
pack .bottomFrame -side bottom -fill x 
pack .searchFrame -side top -fill x  -expand 0
pack .t -in .textFrame -expand yes -fill both -padx 1

pack .textFrame -expand yes -fill both

proc update_main_editor_linenumbers {} {
    if {![winfo exists .t.l] || ![winfo exists .t.t]} {
        return
    }
    set h [winfo height .t.t]
    if {$h <= 0} {
        return
    }
    set lines {}
    for {set y 0} {$y < $h} {incr y 14} {
        set idx [.t.t index @0,$y]
        set ln [lindex [split $idx .] 0]
        if {[llength $lines] == 0 || [lindex $lines end] ne $ln} {
            lappend lines $ln
        }
    }
    set new_text ""
    foreach ln $lines {
        append new_text "${ln}\n"
    }
    if {![info exists ::main_linenum_text] || $::main_linenum_text ne $new_text} {
        set ::main_linenum_text $new_text
        .t.l delete 1.0 end
        .t.l insert end $new_text
    }
    set endrow [lindex [split [.t.t index end-1c] .] 0]
    set new_w [expr {max(3,[string length $endrow])}]
    if {![info exists ::main_linenum_width] || $::main_linenum_width != $new_w} {
        set ::main_linenum_width $new_w
        .t.l configure -width $new_w
    }
}

proc schedule_main_editor_linenumbers {} {
    catch {update_main_editor_linenumbers}
    after 500 schedule_main_editor_linenumbers
}
after 500 schedule_main_editor_linenumbers

bind [.searchFrame.font component label] <ButtonPress-1> {
  set fnt [::ChooseFont::ChooseFont "courier 10 normal"];
    if {$fnt != ""} {
    [.searchFrame.font component entry] delete 0 end;
    [.searchFrame.font component list] insert end $fnt;
    [.searchFrame.font component entry] insert end $fnt;
    if {[lsearch $new_recentfonts $fnt] == -1} {
        set new_recentfonts [linsert   $new_recentfonts 0 $fnt];
    }

    
    }
  }

bind [.searchFrame.foreground component label] <ButtonPress-1> {
    set fgcolor [tk_chooseColor]; 
    if {$fgcolor != ""} {
      [.searchFrame.foreground component entry] delete 0 end;
      [.searchFrame.foreground component list] insert end $fgcolor;
      [.searchFrame.foreground component entry] insert end $fgcolor;
    }
}
#############################################
set loggedcommands {};
set recentfiles {};
set new_loggedcommands {};
set new_recentfiles {};
set recentcolors {};
set recentbgs {};
set recentfonts {};
set new_recentfonts {};


proc recent_commands {} {
   global loggedcommands;
   foreach cmd $loggedcommands {
       puts $cmd;
   } 
}

proc recent_files {} {
   global recentfiles;
   global new_recentfiles;
   foreach file $recentfiles  {
       puts $file;
   }
   foreach file $new_recentfiles  {
       puts $file;
   }
}

proc clear_command_history {} {
   global loggedcommands;
   global new_loggedcommands;
   set loggedcommands {};
   set new_loggedcommands {};
}

proc clear_file_history {} {
   global recentfiles;
   global new_recentfiles;
   set recentfiles {};
   set new_recentfiles {};
}

proc extendSelectionLeft {} {
   set selranges [.t tag ranges sel];
   foreach {start end} $selranges {
       .t tag add sel [.t index "$start - 1 c"] $start;
   }
}


proc extendSelectionRight {} {
   set selranges [.t tag ranges sel];
   foreach {start end} $selranges {
       .t tag add sel $end [.t index "$end + 1 c"];
   }
}

proc shrinkSelectionLeft {} {
   set selranges [.t tag ranges sel];
   foreach {start end} $selranges {
       .t tag remove sel $start [.t index "$start + 1 c"];
   }
}



proc moveSelectionUp {} {
    set selranges [.t tag ranges sel];
    foreach {start end} $selranges {
        set firstline [lindex [split [.t index "$start linestart"] "."] 0];
        set lastline  [lindex [split [.t index "$end linestart"] "."] 0];
        if {$firstline == 1} {
            continue;
        }
        set tomove_start "[expr $firstline - 1].0";
        set tomove_end $firstline.0;
       
          set cont [hlt:save .t $tomove_start $tomove_end]
          .t delete $tomove_start $tomove_end;
          .t mark set insert "$lastline.0"
          set final [.t index end];
          if {"$lastline.0" >= $final} {
              .t insert "$lastline.0" "\n"
          }
         hlt:restore .t $cont "$lastline.0";
        
    }
}


proc moveSelectionDown {} {
    set selranges [.t tag ranges sel];
    foreach {start end} $selranges {
        set firstline [lindex [split [.t index "$start linestart"] "."] 0];
        set lastline  [lindex [split [.t index "$end linestart"] "."] 0];
        set final [.t index end];
        if {"$lastline.0" >= $final} {
            continue;
        }
        set tomove_start "[expr $lastline + 1].0";
        set tomove_end [.t index "[expr $lastline + 2].0"];
        set cont [hlt:save .t $tomove_start $tomove_end]
        .t delete $tomove_start $tomove_end;
        .t mark set insert "$firstline.0"
         hlt:restore .t $cont "$firstline.0";
        
    }
}

proc shrinkSelectionRight {} {
   set selranges [.t tag ranges sel];
   foreach {start end} $selranges {
       .t tag remove sel  [.t index "$end - 1 c"] $end;
   }
}

bind .t <Control-q> "insertNoteFile .t; break;";

bind .t <Control-f> {focus [.searchFrame.search6  component entry]};

bind .t <Alt-Up> {
 moveSelectionUp;
 break;
}

bind .t <Alt-Down> {
 moveSelectionDown;
 break;
}

bind .t <Alt-Right> {
 extendSelectionRight;
 break;
}

bind .t <Alt-Left> {
 extendSelectionLeft;
 break;

}

bind .t <Alt-Shift-Right> {
 shrinkSelectionRight;
 break;
}
bind .t <Alt-Shift-Left> {
 shrinkSelectionLeft;
 break;

}
bind .t <Option-Up> {
 moveSelectionUp;
 break;
}
bind .t <Option-Down> {
 moveSelectionDown;
 break;
}
bind .t <Option-Right> {
 extendSelectionRight;
 break;
}
bind .t <Option-Left> {
 extendSelectionLeft;
 break;

}
bind .t <Option-Shift-Right> {
 shrinkSelectionRight;
 break;
}
bind .t <Option-Shift-Left> {
 shrinkSelectionLeft;
 break;

}

bind .t <Control-Left> {
    global viewpoints;
    global _viewpointPosition;
    if {$_viewpointPosition >= [llength $viewpoints] } {
        set _viewpointPosition [llength $viewpoints];
        incr _viewpointPosition -1;
    
    } else {
       incr _viewpointPosition;
       changeViewpointPosition;
    } 
    break;
}

bind .t <Control-Right> {
    if {$_viewpointPosition < 0} {
        set _viewpointPosition 0;
        
    } else {
    incr _viewpointPosition -1
    changeViewpointPosition;
    }
    break;
    
}
proc changeViewpointPosition {} {
    global _viewpointPosition;
    global   viewpoints;
    
    set numvpts [llength $viewpoints]
    set apos [expr "$numvpts - $_viewpointPosition"]
    if {$apos > 0 && $apos <= $numvpts} {
        incr apos -1    
        set newvpt [lindex $viewpoints $apos];
        dott see $newvpt;

    }
}

proc init_database {} {
     global tmpdir;
     global regroot;
     set dbname "";
     global loggedcommands;
     global new_recentfiles;
     global recentfiles;
     global recentbgs;
     global recentcolors;
     global recentfonts;
     
     global menu;

     catch { set dbname [registry get $regroot dbname]};
     if {$dbname == ""} { set dbname "history.db"; }
     if {[file exists "$tmpdir/$dbname"]} {
         sqlite3 dbcon "$tmpdir/$dbname";
     } else {
         set dbname "[randString].db";
         registry set $regroot dbname $dbname;
         sqlite3 dbcon "$tmpdir/$dbname";
         dbcon eval {create table commands (command text)};
         dbcon eval {create table recentfiles (recentfile text)};
         dbcon eval {create table recentcolors (recentcolor text)};
         dbcon eval {create table recentfonts (recentfont text)};
         dbcon eval {create table recentbgs (recentbg text)};
     }
     set msg "";
     if { [catch {
     set loggedcommands [dbcon eval {SELECT * FROM commands}];
     set recentfiles  [dbcon eval {SELECT * FROM recentfiles }];
     set recentbgs  [dbcon eval {SELECT * FROM recentbgs }];
     set recentfonts  [dbcon eval {SELECT * FROM recentfonts}];
     set recentcolors  [dbcon eval {SELECT * FROM recentcolors}];
     set cnt 0;
     foreach rc $recentfiles {
          incr cnt;
          $menu.recent add command -label $rc -command "openFile .t  \"$rc\"";
          if {$cnt > 100}  {
              break;
          }
     }
     
     foreach rf $recentfonts {
         [.searchFrame.font component list] insert end $rf
     }
     
     } msg ] } {
          tk_messageBox -message $msg;
          catch {dbcon eval {create table commands (command text)} };
          catch {dbcon eval {create table recentfiles (recentfile text)}};
          catch {dbcon eval {create table recentcolors (recentcolor text)} };
          catch {dbcon eval {create table recentfonts (recentfont text)}};
          catch {dbcon eval {create table recentbgs (recentbg text)}};
          set loggedcommands [dbcon eval {SELECT * FROM commands}];
          set recentfiles  [dbcon eval {SELECT * FROM recentfiles }];
          set cnt 0;
          foreach rc $recentfiles {
              incr cnt;
              $menu.recent add command -label $rc -command "openFile .t  \"$rc\"";
              if {$cnt > 100}  {
                  break;
              }
         }
          
     }
   catch {dbcon close;}
}

init_database;
set cmd_bg "#ffff00";
set bottompane .topFrame
interp alias $qcInterp .t {} .t
set quickCommand $bottompane.quickCommand ;
proc quickCommandExec {} {
    global quickCommand;
    global cmd_to_editor;
    global eval_expr;
    global qcInterp;
    global _historyPosition;
    global loggedcommands;
    global new_loggedcommands;
    global stay_in_quick_command;
    global cmd_bg;

    set thistext  [$quickCommand component entry get ];
    set thistext  [string trim $thistext];
    set firstchar [string index $thistext 0];
    if { $firstchar == "/" || $firstchar == ":"} {
        set rest [string range $thistext 1 end];
        set thistext "$firstchar ";
        append thistext $rest;
    } 
    
    if {[string length $thistext] > 0} { 
      lappend  loggedcommands $thistext;
      lappend  new_loggedcommands $thistext;
      $quickCommand clear
      set _historyPosition -1;
      set target .status;
      if {$cmd_to_editor} {set target .t};
      $target tag configure tag_cmd_bg -background $cmd_bg;
      $target insert end ">>>> $thistext" tag_cmd_bg;
      $target insert end "\n"
      update;
      set the_cmd "";
      if {$eval_expr } {
          append the_cmd "expr ";
      }
      append the_cmd $thistext;
      catch {$qcInterp eval $the_cmd} msg;
      $target insert end $msg;
      $target insert end "\n";
      
      #loadOverview;
      $target yview end;
      if {"$target" != ".t" && !$stay_in_quick_command} {
         [.topFrame.quickCommand component entry] configure -background white;
          focus .t.t;
      }
    }  
 }

iwidgets::entryfield $quickCommand -labeltext "Quick Command:" -labelpos w  \
    -command quickCommandExec \
      -textbackground white -background white 

[$quickCommand component label] configure -background white;
pack $quickCommand -side bottom -fill x
bind [$quickCommand component entry] <KeyPress-Up> {
    
    if {$_historyPosition >= [llength $loggedcommands]} {
        set _historyPosition [llength $loggedcommands];
        incr _historyPosition -1;
        tk_messageBox -title "Spectral" -message "Reached the first entry in command history"
    } else {
       incr _historyPosition;
       changeQuickCommandContent;
    } 
}
bind [$quickCommand component entry] <KeyPress-Down> {
    if {$_historyPosition < 0} {
        set _historyPosition 0;
        tk_messageBox -title "Spectral" -message "Reached the last entry in command history"
    }
    incr _historyPosition -1
    changeQuickCommandContent
    
}
proc changeQuickCommandContent {} {
    global _historyPosition;
    global   loggedcommands;
    global quickCommand;
    set numcmds [llength $loggedcommands]
    set apos [expr "$numcmds-$_historyPosition"]
    if {$apos > 0 && $apos <= $numcmds} {
            incr apos -1    
        set newcmd [lindex $loggedcommands $apos]
        $quickCommand clear
        $quickCommand component entry insert end $newcmd
    }
}

#############################################

wm title . "$title_prefix-Spectral Text-";

proc highlight_lines {lines widget} {
    foreach line $lines {
        if {$line != "end"} {
           $widget tag add attention "${line}.0" "[expr $line+1].0"
        }
    }
}

array set file_lookup {};

proc load_trace_lookup {args} {
    global file_lookup;
    set fp [open "c:/temp/trace_lookup.txt" r];
    set cont [read $fp];
    close $fp;
    set lines [split $cont "\n"];
    foreach input_line $lines {
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
        set loc_file [regsub -all {^[ \t]*(.:[^\(:]*)[\(:].*} $input_line {\1}];
        set loc_line [regsub -all {^[ \t]*.:[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        set tag [regsub -all {^.*mprewriter.*START\(?[ ]*([0-9]*)[ ]*\)?.*$} $input_line {\1}];
        regsub -all {\\} $loc_file {/} loc_file
        set file_lookup($tag) "$loc_file:$loc_line:";
    }
}

proc read_trace_lookup {fname symbol} {
    global file_lookup;
    set fp [open $fname r];
    set cont [read $fp];
    close $fp;
    set lines [split $cont "\n"];
    foreach input_line $lines {
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
        set loc_file [regsub -all {^[ \t]*(.:[^\(:]*)[\(:].*} $input_line {\1}];
        set loc_line [regsub -all {^[ \t]*.:[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        set reg {^.*};
        append reg $symbol;
        append reg {\(?[ ]*([0-9]*)[ ]*\)?.*$}
        set tag [regsub -all $reg $input_line {\1}];
        regsub -all {\\} $loc_file {/} loc_file
        set file_lookup($tag) "$loc_file:$loc_line:";
    }
}
 
proc my_regexp {pat str ignore_case} {
   set negate 0;
   if {[string index $pat 0] == "-"} {
       if {[string index $pat 1] != "-"} {
         set pat [string range $pat 1 end];
         set negate 1;
       } else {
     #two leading "-"s will be regarded as one leading "-"
     set pat_original [string range $pat 1 end];
     set pat "\\";
     append pat $pat_original;
       }
   }
   set val 0;
   if {$ignore_case} {
    set val [regexp -nocase $pat $str];
   } else {
    set val [regexp $pat $str];
   }
   if {$negate} {
        return [expr !$val];
    } else {
    return $val;
    }
}

proc setCTextProperties {widget} {
    $widget tag configure attention -background #5555ce
   ::ctext::enableComments $widget
    ctext::addHighlightClassForRegexp $widget identifiers orange  {[a-zA-Z0-9_]+}
    ctext::addHighlightClassForRegexp $widget numbers white  {[0-9\.]+}
    ctext::addHighlightClass $widget keyword red {do BOOL TRUE FALSE const NULL while for bool true false double float private public static void int char if return else template class struct case switch}

    ctext::addHighlightClass $widget keyword red {else int char if return else template}
    ctext::addHighlightClassForRegexp $widget vars cyan {[A-Za-z0-9_]*[Ss][Cc][mM][A-Za-z0-9_]*}
    ctext::addHighlightClassForSpecialChars $widget brackets green {[]{}()<>=+-*;^%$!}
    ctext::addHighlightClassForRegexp $widget strings lightblue {"([^"]|\\")*"}; #the unmatched quote confused vim " 
    ctext::addHighlightClassForRegexp $widget singleLineComment khaki {//.*$};
    ::ctext::comments $widget
}




proc showOutputFile {file_name type name highlight_lines} {
    
    
    set textheight 40;
    catch {destroy .popup_${type}}
    toplevel .popup_${type};
    wm title .popup_${type} "$name $highlight_lines";
    frame .popup_${type}.textFrame
    scrollbar .popup_${type}.s -orient vertical -command ".popup_${type}.t yview" -takefocus 1
    pack .popup_${type}.s -in .popup_${type}.textFrame -side right -fill y
    ctext .popup_${type}.t -yscrollcommand ".popup_${type}.s set" -wrap word -width 120 -height $textheight \
        -font {Courier 10} -setgrid 1 -highlightthickness 0 \
        -padx 4 -pady 2 -takefocus 0 -bg white -fg black -insertbackground blue ;
    .popup_${type}.t tag configure attention -background #ccd4f7
    pack .popup_${type}.t -in .popup_${type}.textFrame -expand y -fill both -padx 1
    pack .popup_${type}.textFrame -expand yes -fill both

    

    button .popup_${type}.copyAll -text "Copy To Clipboard" -command " 
        # tk_messageBox -message \"Copied content of the window \\\"$type\\\" to clipboard\"; 
        
        set alltext \[.popup_${type}.t get 0.0 end\];
        clipboard clear;
        clipboard append \$alltext;
    
    "

    
   set txtwidget ".popup_${type}.t";
    
   bind $txtwidget  <Control-c> "
     copySelection $txtwidget;
     break;
  "

  bind $txtwidget  <Control-x> "
     copySelection $txtwidget cut;
     break;
  " 
  
  bind $txtwidget  <Control-m> "
     matchBracket $txtwidget;
     break;
  " 
  
  bind $txtwidget <Double-ButtonPress-1> "
       set pos \[$txtwidget index {@%x,%y}\];
       highlightCurrent $txtwidget  \$pos; break;
   "
                   
    pack .popup_${type}.copyAll -side bottom -fill x -expand yes
    wm geometry .popup_${type} "+20+20";
    
    if {[file exists ${file_name}.hlt]} {
        loadFromHltFile $txtwidget ${file_name}.hlt
    } else {
        set cont [read_file_contents ${file_name}];
        $txtwidget insert 1.0 $cont;
    }
    
    highlight_lines $highlight_lines  $txtwidget
    
    catch {
        foreach highline $highlight_lines {
            if {$highline == "end"} {
            .popup_${type}.t yview end;
                
           } else {
            .popup_${type}.t yview [expr $highline -4];
           }
        }
    }
     
}

proc popupStatusContent {} {
   showOutput [.status get 1.0 end] status status end;
}
proc showOutput {txt type name highlight_lines} {
    set textheight 40;
    catch {destroy .popup_${type}}
    toplevel .popup_${type};
    wm title .popup_${type} "$name $highlight_lines";
    frame .popup_${type}.textFrame
    scrollbar .popup_${type}.s -orient vertical -command ".popup_${type}.t yview" -takefocus 1
    pack .popup_${type}.s -in .popup_${type}.textFrame -side right -fill y
    ctext .popup_${type}.t -yscrollcommand ".popup_${type}.s set" -wrap word -width 120 -height $textheight \
        -font {Courier 10} -setgrid 1 -highlightthickness 0 \
        -padx 4 -pady 2 -takefocus 0 -bg white -fg black -insertbackground blue ;
    .popup_${type}.t tag configure attention -background #ccd4f7
    pack .popup_${type}.t -in .popup_${type}.textFrame -expand y -fill both -padx 1
    pack .popup_${type}.textFrame -expand yes -fill both
    .popup_${type}.t insert end $txt;
    highlight_lines $highlight_lines  .popup_${type}.t
    button .popup_${type}.copyAll -text "Copy To Clipboard" -command " 
        # tk_messageBox -message \"Copied content of the window \\\"$type\\\" to clipboard\"; 
        
        set alltext \[.popup_${type}.t get 0.0 end\];
        clipboard clear;
        clipboard append \$alltext;
    
    "
    catch {
        
        foreach highline $highlight_lines {
            if {$highline == "end"} {
              .popup_${type}.t yview end;
           } else {
              .popup_${type}.t yview [expr $highline -4];               
           }
        }
    }
    
   set txtwidget ".popup_${type}.t";
    
   bind $txtwidget  <Control-c> "
     copySelection $txtwidget;
     break;
  "

  bind $txtwidget  <Control-x> "
     copySelection $txtwidget cut;
     break;
  " 
  
  bind $txtwidget <Double-ButtonPress-1> "
       set pos \[$txtwidget index {@%x,%y}\];
       highlightCurrent $txtwidget  \$pos; break;
   "
               
    
    pack .popup_${type}.copyAll -side bottom -fill x -expand yes
    wm geometry .popup_${type} "+20+20";
    
    
}
proc multi_regexp {pats text} {
    foreach pat $pats {
       if {![my_regexp $pat $text 0]} {
       return 0;
       }
   }
   return 1;
}


proc showListedFileInExplorer {pos} {
   set lnum [lindex [split $pos "." ] 0];
   set file_loc [.t get $lnum.0 $lnum.end];
   set file_name "";
   set sel_ranges [.t tag ranges sel];
   if {[llength  $sel_ranges]} {
      foreach {start end} $sel_ranges {
          set file_name [.t get $start $end];
          break;
      }
    } else {
      set file_name [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $file_loc {\1}]
   } 
   showFileInExplorer $file_name;
}

proc showFileAtCursor {pos} {
   set lnum [lindex [split $pos "." ] 0];
   set file_loc [.t get $lnum.0 $lnum.end];
   set file_loc [regsub -all {\\} $file_loc {/}];
   set file_name [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $file_loc {\1}];
   set file_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $file_loc {\1}];
   if {![string is integer $file_line]}  {
       set file_line 1;
   }
   
   showOutputFile $file_name cpp $file_name $file_line;
}


proc editFileAtCursor {pos} {
   set lnum [lindex [split $pos "." ] 0];
   set file_loc [.t get $lnum.0 $lnum.end];
   set file_loc [regsub -all {\\} $file_loc {/}];
   set file_name [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $file_loc {\1}];
   set file_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $file_loc {\1}];
    if {![string is integer $file_line]}  {
       set file_line 1;
   }
    
    if {[string first "/" $file_name] == -1} {
        set file_name "[pwd]/$file_name";
    } else {
        set folder "";
        regsub -all {/.*$} $file_name {} folder;
        
        if {$folder  ==  "."} {
            regsub -all {^[.]} $file_name [pwd] file_name;
        }

    }
   
   
   global current_file;
   global old_dump;
   global old_dump_pos;
   global old_mode;
   global dbl_click_behavior;
   global modified;
   set new_dump "";
   if {$current_file == "" || $dbl_click_behavior == "open_listed_loc"} {
       addToStatus "${file_name}:${file_line}: - attempting to open";
       set old_dump_pos [.t index insert];
       set new_dump  [hlt:save .t 1.0 end];
       .t fastdelete 1.0 end;
       set modified 0;
   }
   catch {
    openFile .t $file_name;
   .t see $file_line.0;
   .t tag add sel $file_line.0 "$file_line.end + 1 char";
   } msg;
   addToStatus $msg;
   if {$new_dump != ""} {
       set old_dump $new_dump;
   }
   set old_mode $dbl_click_behavior;
   set dbl_click_behavior default;
   
}


bind .t <ButtonPress-3> {createPopupMenu %x %y;break;};
bind .t <ButtonPress-2> {createPopupMenu %x %y;break;};
bind .status <ButtonPress-3> {createBottomPanelPopupMenu %x %y;break;};
bind .status <ButtonPress-2> {createBottomPanelPopupMenu %x %y;break;};

proc handle_editor_double_click {widget x y} {
    global dbl_click_behavior
    set tw $widget
    if {$tw eq ".t" && [winfo exists .t.t]} {
        set tw .t.t
    }
    if {[catch {set pos [$tw index "@$x,$y"]}]} {
        return
    }
    addToStatus "double click behavior =  $dbl_click_behavior"
    if {$dbl_click_behavior == "default"} {
        highlightCurrentBarebones $tw $pos
        return
    } elseif {$dbl_click_behavior == "show_trace_loc"} {
        load_tag .t $pos load_tag
        return
    } elseif {$dbl_click_behavior == "open_trace_loc"} {
        load_tag_for_edit $pos load_tag_for_edit
        return
    } elseif {$dbl_click_behavior == "open_listed_loc"} {
        editFileAtCursor $pos
        return
    } elseif {$dbl_click_behavior == "show_listed_loc"} {
        showFileAtCursor $pos
        return
    } elseif {$dbl_click_behavior == "find_prev_occurrence"} {
        highlightPreviousOccurrance $tw $pos
        return
    } elseif {$dbl_click_behavior == "find_next_occurrence"} {
        highlightNextOccurrance $tw $pos
        return
    } elseif {[string range $dbl_click_behavior 0 5] == "custom"} {
        set acmd [string range $dbl_click_behavior 6 end]
        eval "$acmd $pos"
        return
    } elseif {$dbl_click_behavior == "read_number_aloud"} {
        readNumberAloud $tw $pos
        return
    }
}

bind .t <Double-ButtonPress-1> {handle_editor_double_click %W %x %y; break}
bind .t.t <Double-ButtonPress-1> {handle_editor_double_click %W %x %y; break}
bind .t <Double-1> {handle_editor_double_click %W %x %y; break}
bind .t.t <Double-1> {handle_editor_double_click %W %x %y; break}
set editor "gvim"; 
proc load_tag {w pos mode} {
    global file_lookup;
    if {[catch { 
        #puts stderr $pos;
        set current_word [$w get "$pos wordstart" "$pos wordend"];
        regsub -all {[<>T/]} $current_word {} current_word;

        set file_loc [set file_lookup($current_word)];
        set file_name [regsub -all {^[ \t]*(.:[^\(:]*)[\(:].*} $file_loc {\1}];
        set file_line [regsub -all {^[ \t]*.:[^\(:]*[\(:]([0-9]*)[:\)].*} $file_loc {\1}];
        showOutputFile $file_name cpp $file_name $file_line;
 
    } msg]} {
       addToStatus $msg;
    }
}

proc load_tag_for_edit {pos mode} {
    global file_lookup;
    if {[catch { 
        #puts stderr $pos;
        set current_word [.t get "$pos wordstart" "$pos wordend"];
        regsub -all {[<>T/]} $current_word {} current_word;

        set file_loc [set file_lookup($current_word)];
        set file_name [regsub -all {^[ \t]*(.:[^\(:]*)[\(:].*} $file_loc {\1}];
        set file_line [regsub -all {^[ \t]*.:[^\(:]*[\(:]([0-9]*)[:\)].*} $file_loc {\1}];
       
       global current_file;
       global old_dump;
       global old_mode;
       global dbl_click_behavior;
       global old_dump_pos;
       global modified;
       set new_dump "";
       
       if {$current_file == "" || $dbl_click_behavior == "open_trace_loc" } {
           addToStatus "${file_name}:${file_line}: - attempting to open";
           set old_dump_pos [.t index insert];
           set new_dump  [hlt:save .t 1.0 end];
           .t fastdelete 1.0 end;
           set modified 0;
       }
       catch {
        openFile .t $file_name;
       .t see $file_line.0;
       .t tag add sel $file_line.0 "$file_line.end + 1 char";
       } msg;
       addToStatus $msg;
       if {$new_dump != ""} {
           set old_dump $new_dump;
       }
       set old_mode $dbl_click_behavior;
       set dbl_click_behavior default;
 
    } msg]} {
       # puts stderr $msg;
    }
}

proc showFile {file_name} {
        showOutputFile $file_name ref $file_name {};
}
set all_tags "#f0f583 #fd9f9f #aafba2 #a5f8f8 #f997f9 #faf496 $currentColor"; 
foreach tag $all_tags {
    .t tag configure $tag  -background $tag
    .t tag raise sel $tag;
}


array set last_search {}

proc textpos_in_range {start end test} {
    set split_start [split $start "."];
    set start_line [lindex $split_start 0]
    set start_col [lindex $split_start 1]
    
    set split_end [split $end "."];
    set end_line [lindex $split_end 0]
    set end_col [lindex $split_end 1]
    
    set split_test [split $test "."];
    set test_line [lindex $split_test 0]
    set test_col [lindex $split_test 1]
    return [textpos_in_range_helper $start_line $start_col $end_line $end_col $test_line $test_col]
    
}

proc textpos_in_range_helper {start_line start_col end_line end_col test_line test_col} {
    if {$test_line >= $start_line && $test_line <= $end_line} {
        if {$test_line == $start_line && $test_col < $start_col} {
            return 0
        }
        if {$test_line == $end_line && $test_col > $end_col} {
            return 0
        }
        return 1
    }
    return 0
}


proc textranges_overlap {start1 end1 start2 end2} {
    set split_start1 [split $start1 "."];
    set start1_line [lindex $split_start1 0]
    set start1_col [lindex $split_start1 1]
    
    set split_end1 [split $end1 "."];
    set end1_line [lindex $split_end1 0]
    set end1_col [lindex $split_end1 1]
    
    set split_start2 [split $start2 "."];
    set start2_line [lindex $split_start2 0]
    set start2_col [lindex $split_start2 1]
    
    set split_end2 [split $end2 "."];
    set end2_line [lindex $split_end2 0]
    set end2_col [lindex $split_end2 1]

    if {$end1_line < $start2_line || ($end1_line == $start2_line && $end1_col < $start2_col)} {
        return 0
    }
    
    if {$end2_line < $start1_line || ($end2_line == $start1_line && $end2_col < $start1_col)} {
        return 0
    }

    return 1
}

proc tags_in_range {{regex {}}} {
    return [tags_in_given_ranges $regex [.t tag ranges sel]]
}

proc tags_overlapping_selection {{regex {}}} {
    set selranges [.t tag ranges sel]
    if {[llength $selranges] == 0} {
        return {}
    }
    return [tags_overlapping_given_ranges $selranges $regex]
}

proc tags_overlapping_given_ranges {given_ranges {regex {}}} {
    set overlapping_tags {}
    foreach tag [.t tag names] {
        if {$tag == "sel"} continue
        if {$regex != "" && ![regexp $regex $tag]} continue
        set ranges [.t tag ranges $tag]
        set found 0
        foreach {sel_start sel_end} $given_ranges {
            foreach {tag_start tag_end} $ranges {
                if {[textranges_overlap $tag_start $tag_end $sel_start $sel_end]} {
                    lappend overlapping_tags $tag
                    set found 1
                    break
                }
            }
            if {$found} break
        }
    }
    return $overlapping_tags
}

proc tags_contained_in_selection {{regex {}}} {
    set selranges [.t tag ranges sel]
    if {[llength $selranges] == 0} {
        return {}
    }
    return [tags_contained_in_given_ranges $selranges $regex]
}

proc tags_contained_in_given_ranges {given_ranges {regex {}}} {
    set contained_tags {}
    foreach tag [.t tag names] {
        if {$tag == "sel"} continue
        if {$regex != "" && ![regexp $regex $tag]} continue
        set ranges [.t tag ranges $tag]
        set found 0
        foreach {tag_start tag_end} $ranges {
            foreach {sel_start sel_end} $given_ranges {
                if {[.t compare $tag_start >= $sel_start] && [.t compare $tag_end <= $sel_end]} {
                    lappend contained_tags $tag
                    set found 1
                    break
                }
            }
            if {$found} break
        }
    }
    return $contained_tags
}

proc tags_in_given_ranges {given_ranges {regex {}}} {
    set overlapping_tags {}
    # Get all the tags applied to the text widget
    set all_tags [.t tag names]
    foreach tag $all_tags {
        if {$tag == "sel"} continue;
        set ranges [.t tag ranges $tag]
        set tag_was_added 0;
        foreach {start_pos end_pos} $given_ranges {
            if {$tag == "sel"} continue;
            if {$regex == "" || [regexp $regex $tag ]} {
            
              # Loop through each range and check for overlap
              foreach {range_start range_end} $ranges {
                   if {[textranges_overlap $range_start $range_end $start_pos $end_pos]} {
                
                    lappend overlapping_tags $tag
                    set tag_was_added 1;
                    break;
                }
              }
            }
        }
        set curpos [.t index insert];
        if {!$tag_was_added} {
            foreach {range_start range_end} $ranges {
                    if {[textpos_in_range $range_start $range_end $curpos]} {
                    
                        lappend overlapping_tags $tag
                        break;
                    }
            } 
       }
    }

    # Return the list of overlapping tags
    return $overlapping_tags
}


proc add_tags_to_sel {tags} {
    set selranges [.t tag ranges "sel"];
    foreach {start_pos end_pos} $selranges {
        foreach tag $tags {
            .t tag add $tag $start_pos $end_pos;
        }
    }
    .t tag configure link -underline 1 -foreground blue
}

proc clearHighlights {sel_only} {
 if {!$sel_only} {
     set result1 [tk_messageBox -title "Really remove all highlights?"  -message "Really remove all highlights?" -icon question -type yesno];            
     if {$result1 != "yes"} {
         return;
     }
 }
 if {$sel_only || [hasSelection] } {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
          foreach tag [.t tag names] {
              if {[string first {hyperref_} $tag] == 0} continue;
              if {[string first {target_} $tag] == 0} continue;
              .t tag remove $tag $start $end;
         }
      }  
  } else {
      foreach tag [.t tag names] {
          
           if {[string first {hyperref_} $tag] == 0} continue;
           if {[string first {target_} $tag] == 0} continue;
          .t tag remove $tag 0.0 end;
        }
  }
  .t tag remove highlight2 0.0 end;
  .t tag remove highlight3 0.0 end;
  .t tag remove diffed 0.0 end;
}


proc clearHighlightsInRange {start end} {
  foreach tag [.t tag names] {
     if {[string first {hyperref_} $tag] == 0} continue;
     if {[string first {target_} $tag] == 0} continue;
    .t tag remove $tag $start $end;
  }
    
}


proc show_hyperlinks {} {
  foreach tag [.t tag names] {
       if {[string first {hyperref_} $tag] == 0} {
          set ranges [.t tag ranges $tag];
          foreach {start end} $ranges {
              .t tag add sel $start $end;
          }
      }
  }
}

proc show_hyperlink_targets {} {
  foreach tag [.t tag names] {
       if {[string first {target_} $tag] == 0} {
          set ranges [.t tag ranges $tag];
          foreach {start end} $ranges {
              .t tag add sel $start $end;
          }
      }
  }
}

proc clear_hyperlinks {{sel_only 1}} {

 if {!$sel_only} {
     set result1 [tk_messageBox -title "Really remove all hyperlinks?"  -message "Really remove all hyperlinks?" -icon question -type yesno];            
     if {$result1 != "yes"} {
         return;
     }
 }
 if {$sel_only || [hasSelection] } {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
          foreach tag [.t tag names] {
              if {[string first {hyperref_} $tag] == 0}  {
                  .t tag remove $tag $start $end;
              }
         }
      }  
  } else {
      foreach tag [.t tag names] {
          
           if {[string first {hyperref_} $tag] == 0} {
              .t tag remove $tag 0.0 end;
          }
      }
  }
}

proc clear_hyperlink_targets {{sel_only 1}} {

 if {!$sel_only} {
     set result1 [tk_messageBox -title "Really remove all hyperlink targets?"  -message "Really remove all hyperlink targets?" -icon question -type yesno];            
     if {$result1 != "yes"} {
         return;
     }
 }
 if {$sel_only || [hasSelection] } {
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
          foreach tag [.t tag names] {
              if {[string first {target_} $tag] == 0}  {
                  .t tag remove $tag $start $end;
              }
         }
      }  
  } else {
      foreach tag [.t tag names] {
          
           if {[string first {target_} $tag] == 0} {
              .t tag remove $tag 0.0 end;
          }
      }
  }
}

proc copyToSpectral {} {
     clipboard clear;
     catch {
         set selranges [.t tag ranges sel];
         set first_time 1;
         foreach {start end} $selranges {
            .t tag remove sel $start $end;
            if {$first_time} {
               set first_time 0; 
            } else {
              clipboard append " T {\n} " 
            }

            embed_images 1;
            clipboard append [hlt:save .t $start $end];
            embed_images 0;
            .t tag add sel $start $end;
         }
     } msg;
     #puts stderr $msg;
}

proc pasteFromSpectral {} {
     catch {
        set cont [clipboard get];
        if {$cont != ""} {
           if {[catch { hlt:restore .t $cont [.t index insert]}]} {
               set cont1 "T {";
               append cont1 $cont;
               append cont1 "}"
               hlt:restore .t $cont1 [.t index insert]
           }
        }
        set selranges [.t tag ranges sel];
        foreach {start end} $selranges {
           .t fastdelete $start $end
        }
     } msg;
     #puts stderr $msg;
}

proc syntaxBegin {widget} {
    
}
proc syntaxEnd {widget} {
    ::ctext::enableComments $widget
    $widget tag configure _cComment -foreground #44616a
    ::ctext::comments $widget 
    $widget highlight 1.0 end;
    update;
}

proc editor {} {
    return ".t";
}

proc  syntaxColorForRegex {widget specs} {
    foreach {name col expr}  $specs {
        ctext::addHighlightClassForRegexp $widget $name $col $expr;
    }
}



#if 0 { foreach word $words {
#        set expr "\\m";
#        append expr $word "\\M";
#        addToStatus $expr;
#       ctext::addHighlightClassForRegexp $widget $name $col $expr;
#    } }
proc  syntaxColorForWords {widget name col words} {
    
    ctext::addHighlightClass $widget $name $col $words
}

proc  syntaxColorForChars {widget name col chars} {
    ctext::addHighlightClassForSpecialChars $widget $name $col $chars
}

proc quotesel {} {
    clipboard clear;
    foreach {start end} [.t tag ranges sel] {
       set txt [.t get $start $end];
       regsub -all {[{}\[\]$"\\]} $txt "\\\\&" txt;
       clipboard append $txt;
    }
    tk_messageBox -message "Copied to clipboard";
}

proc selrange_compare {a b} {
    set a0 [lindex $a 0]
    set b0 [lindex $b 0]
    if {[position_gt $a0  $b0]} {
        return 1
    } elseif {[position_gt $b0  $a0]} {
        return -1
    }
    return 0;
}


proc sortRanges {ranges} {
    set pairs {};
    foreach {x y}  $ranges { 
        lappend pairs [list $x $y];
    }
    set result {};
    set pairs [lsort -command selrange_compare $pairs];
    foreach x $pairs {
       lappend result [lindex $x 0] [lindex $x 1];  
    }
    
    return $result;
}

proc deleteSelection {w} {
    set selranges [lreverse [$w tag ranges sel]];
    foreach {end start} $selranges {
       .t delete $start $end;
    }
}
proc copySelection {w {docut ""} } {
    clipboard clear;
    catch {
        if {[hasMultiSelection]} {
            set items {M};
            set first_time 1;
            set selranges [$w tag ranges sel];
            set selranges [sortRanges $selranges];
            foreach {start end} $selranges {
               if {$first_time} {
                   set first_time 0;
               } else {
                  clipboard append -type STRING "\n";
               }
               $w tag remove sel $start $end;
               lappend items [hlt:save $w $start $end]
               clipboard append -type STRING [$w get $start $end];

               $w tag add sel $start $end;
               if {$docut == "cut"} {
                   .t fastdelete $start $end;
                }
            
             }
             clipboard append -type HLT $items;
        } else {
          set selranges [$w tag ranges sel];
          foreach {start end} $selranges {
           $w tag remove sel $start $end;
           
           clipboard append -type HLT [hlt:save $w $start $end];
           clipboard append -type STRING [$w get $start $end];
           $w tag add sel $start $end;
           if {$docut == "cut"} {
               .t fastdelete $start $end;
             }
            break;
          }
       }
    } msg;
    #puts stderr $msg;
}
bind .t <Control-c> {
     copySelection .t ;
     break;
}

bind .t <Control-l> {
     edit:close; 
     break;
}


bind .t <Control-x> {
     copySelection .t cut;
     break;
}



bind .t <Control-C> {
     copySelection .t ;
     break;
}

bind .t <Control-L> {
     edit:close; 
     break;
}


bind .t <Control-X> {
     copySelection .t cut;
     break;
}

bind .t <Control-plus> {
     enlarge_font 2;
     break;
}

bind .t <Control-minus> {
     enlarge_font -2;
     break;
}

proc trimLine {line} {
   set linecont [.t get "$line.0" "$line.end"];
   set trimmed [string length [string trim $linecont]];
   set len [string length $linecont];
   for {set i 0} {$i < $len} {incr i} {
        set ch [.t get "$line.0" "$line.1"];
        if {$ch == " "} {
            .t fastdelete "$line.0" "$line.1";
            incr len -1;
        } else {
            break;
        }
   }
   set diff [expr $len - $trimmed];
   if {$diff > 0} {
      .t fastdelete "$line.[expr $len - $diff]" "$line.end";
   }
   
}

bind .t <Control-t> {
     .t insert [.t index insert] "\t";
     break;
}

bind .t <Control-T> {
     set ins [expr int([.t index insert])];
     trimLine $ins;
     break;
}


bind .t <Option-Control-t> {add_hypertarget;break;}
bind .t <Alt-Control-t>    {add_hypertarget;break;}
bind .t <Option-Control-l> {hyperref;break;}
bind .t <Alt-Control-l>    {hyperref;break;}



set readaloud_script {
package require Tk;
package require twapi;


set dir [lindex $argv 0];
cd $dir;
wm iconbitmap . $dir/bm0.ico
wm  overrideredirect  .  1
wm attributes . -topmost 1;

     set x [winfo pointerx .];
     set y [winfo pointery .];
     set x [expr max(100, $x-100)];
     set y [expr max(100, $y-100)];
    wm geometry . "+$x+$y";


set fname [lindex $argv 1];
set fp [open $fname r];
fconfigure $fp -encoding utf-8
set textToRead [read $fp];
close $fp;

set voice [twapi::comobj Sapi.SpVoice]
$voice Speak $textToRead 1

button .b -text "Close Reader" -command {
    catch {
    $voice -destroy;
    }
    exit;

} -background "#f0ad4e" -foreground white -font {Consolas 14 bold};

bind .b <Enter> {%W configure -bg "#ec971f"}
bind .b <Leave> {%W configure -bg "#f0ad4e"} 
bind . <Escape> {
    catch {
      $voice -destroy;
    }
    exit;
} 

pack .b -side top -fill x;
update;
focus .b;
update;
}


proc tempfilename {ext} {
  global tmpdir;
  set fname "$tmpdir/[randString].${ext}";
  return $fname;
}

proc readAloud {} {
    set txt {}
    set selranges [.t tag ranges sel];
    foreach {selStart selEnd} $selranges {
      append  txt [.t get $selStart $selEnd];
    }
    readTextAloud $txt;
}

set shouldstopevery 0;
proc stopevery {{val 1}} {
    global shouldstopevery;
    set shouldstopevery $val;
}

proc every {time args} {
    global shouldstopevery;
    if {! $shouldstopevery} {
      after $time "every $time $args";
      eval $args;
    }
}


proc readTextAloud {args} {
 global tmpdir;
 global readaloud_script;
 set fname "$tmpdir/[randString].txt";
 set fp [open $fname w];
  foreach arg $args {
   puts $fp $arg;
  }
 close $fp;

 set rsname "$tmpdir/[guid].tcl"
 set fps [open $rsname w];
 puts $fps $readaloud_script ;
 close $fps;
 
 global installdir;
  exec $installdir/wbin/tclkit-gui-8_6_4-twapi-4_1_27-x86-max.exe  $rsname $installdir/wbin/ $fname;

  file delete -force $rsname;
   
 file delete $fname;
}


proc enumerate {{count 0}} {
   set selranges [.t tag ranges sel];
   if {[llength $selranges] > 0} {
    array set starts {};
    set multiple_inserts_in_a_line 0;
       foreach {start end} $selranges {
        set startline [lindex [split $start "."] 0];
        if {[info exists starts($startline)]} {
            set multiple_inserts_in_a_line 1;
            break;
        }
        set starts($startline) 1;

      }
      set numsel [expr [llength $selranges] / 2];
      if {$multiple_inserts_in_a_line} {
          for {set i 0} {$i < $numsel} {incr i} {
         
            set selranges [.t tag ranges sel];
            set start [lindex $selranges [expr 2*$i]];
            .t insert $start " $count ";
            incr count;
         }
        
     } else {
          foreach {start end} $selranges {
            .t insert $start " $count ";
             incr count;
          }
     }

  }

}


proc multi_paste {} {

   set selranges [.t tag ranges sel];
   if {[llength $selranges] > 0} {
    set result [tk_messageBox -title "Selections detected"  -message "Paste at selections?" -icon question -type yesno];
    if {$result == "no"} {
         pasteSingleSelection;
         return;
    }
    global update_frozen;
    set update_frozen 1;
    array set starts {};
    set multiple_inserts_in_a_line 0;
       foreach {start end} $selranges {
        set startline [lindex [split $start "."] 0];
        if {[info exists starts($startline)]} {
            set multiple_inserts_in_a_line 1;
            break;
        }
        set starts($startline) 1;
      }
      if {[clipboardIsMultiLine]} {
          set multiple_inserts_in_a_line 1;
      }

      set numsel [expr [llength $selranges] / 2];
      if {$multiple_inserts_in_a_line} {
          for {set i 0} {$i < $numsel} {incr i} {
         
            set selranges [.t tag ranges sel];
            set start [lindex $selranges [expr 2*$i]];
            set end [lindex $selranges [expr 2*$i+1]];
            .t mark set insert $start;
            pasteSingleSelection;
         }
        
     } else {
          foreach {start end} $selranges {
            .t mark set insert $start;
            pasteSingleSelection;
          }
     }

  } else {
       pasteSingleSelection;
  }
  set update_frozen 0;
  update;

}

proc contentIsMultiline {cont} {

   # add more details
   foreach {key value} $cont \
    {
        
        switch $key \
        {
          
            T \
            {   
                if {[regexp "\n" $value]} {
                    return 1;
                }
            }
        }
    }
    return 0;
}

proc clipboardIsMultiLine {} {
  set result 0;
  if { [ catch {
   set cont [clipboard get -type HLT];
   set firstchar [string range $cont 0 0]
   if {$firstchar == "M"} {
      set result 1; 
   } else {
       set result [contentIsMultiline $cont];
   }
   } ] } {
      if { [ catch {
        set cont [clipboard get -type STRING];
         set result [regexp "\n" $cont];
       } ] } {
          return 0;
       }
   }

   return $result;
    
}

proc signedRegexp {regex line} {
    if {[string range $regex 0 0] == "-"} {
        return [expr ![regexp [string range $regex  1 end] $line]];
    } else {
        return [regexp $regex $line];
    }
}

proc find_files {regex {handler puts} args } {
    set queue "$args"
    if {[llength $queue] == 0} {
        set queue [tk_chooseDirectory];
    }
    
    if {[llength $queue] == 0} {
        set queue .;
    }
    
    
    while {[llength $queue] > 0} {
    
      set current [lindex $queue 0]
      set queue [lreplace $queue 0 0]
    
      set files {}; 
      if {[file isfile $current]} {
          lappend files $current
      } else {
	  catch {
              set files [lsort [glob "$current/*"]];
          }
      }
      foreach f $files {
            if {[file isdirectory $f]} {
                    lappend queue $f
            } else {
                 if {[signedRegexp $regex $f]} {
                         eval "$handler \{$f\}";
                 }
               }
            }
    
      }
}

proc pasteMultiselClipAtEnd {} {
     global spectral_subfolder;
     set has_hlt 0;
     if {[catch {
        set cont [clipboard get -type HLT];
        set firstchar [string range $cont 0 0]
        if {$firstchar == "M"} {
           set cont [string range $cont 2 end];
           set pos  [.t index insert];
           set possplit [split $pos "."];
           set lnum [lindex $possplit 0];
           foreach item $cont {
               hlt:restore .t $item ${lnum}.end;
               incr lnum;
               .t mark set insert ${lnum}.end
               set has_hlt 1;
           }
        } else {
           if {$cont != ""} {
            hlt:restore .t $cont [.t index insert];
            set has_hlt 1;
           }
        }
        
     } msg]} {
        #puts stderr $msg;
     }
}

proc pasteMultiLine {} {
    set cont [clipboard get];
    set lines [split $cont "\n"];
    set pos [.t index insert];
    set possplit [split $pos "."]; set row [lindex $possplit 0]; set col [lindex $possplit 1];
    foreach line $lines {
        .t insert "$row.$col" $line sel;    
        incr row;
    }
}

proc pasteMultiLineEnd {} {
    set cont [clipboard get];
    set lines [split $cont "\n"];
    set pos [.t index insert];
    set possplit [split $pos "."]; set row [lindex $possplit 0]; set col [lindex $possplit 1];
    foreach line $lines {
        .t insert "$row.end" $line sel;    
        incr row;
    }
}
proc pasteSingleSelection {} {
     global spectral_subfolder;
     set has_hlt 0;
     if {[catch {
        set cont [clipboard get -type HLT];
        set firstchar [string range $cont 0 0]
        if {$firstchar == "M"} {
           set cont [string range $cont 2 end];
           set pos [.t index insert];
           foreach item $cont {
               hlt:restore .t $item $pos;
               set lnum [expr int($pos) + 1];
               set colnum [regsub -all {^\d+\.} $pos {}]
               set pos ${lnum}.${colnum}
               set line [.t get ${lnum}.0 ${lnum}.end];
               set len  [string length $line];
               if {$len < $colnum} {
                 set padding "";
                 for {set k $len} {$k < $colnum} {incr k} {
                   append padding  " ";
                 }
                 .t insert ${lnum}.${len}  $padding
               }
               .t mark set insert ${lnum}.${colnum}
               set has_hlt 1;
           }
        } else {
           if {$cont != ""} {
            hlt:restore .t $cont [.t index insert];
            set has_hlt 1;
           }
        }
        
     } msg]} {
        #puts stderr $msg;
     }
     set has_text 0;
     catch {
     if {!$has_hlt} {
           set cont [clipboard get -type STRING];
           if {$cont != ""} {
               set has_text 1;
              .t insert [.t index insert] $cont;
           }
     }
     }
     if {!$has_text && !$has_hlt} {
        global tmpdir;
        global installdir;
        global clipboard_to_file_script
        set fname "$tmpdir/[guid].bmp";

        set rsname "$tmpdir/[guid].tcl"
        set fps [open $rsname w];
        puts $fps $clipboard_to_file_script;
        close $fps;

        catch {file mkdir "[get_current_folder]/${spectral_subfolder}"}
        set fnamepng "[get_current_folder]/${spectral_subfolder}/[randString].png";
        exec $installdir/wbin/tclkit-gui-8_6_4-twapi-4_1_27-x86-max.exe $rsname $fname;
        if {[file exists $fname]} {
            catch {
              exec_convert $fname $fnamepng
            }
            if {[file exists $fnamepng]} {
              insertPhotoFile .t $fnamepng;
           }
          file delete $fname;
        }
        file delete -force $rsname; 
     }

     ctext::linemapUpdate .t;
}
bind .t <Control-v> {
    multi_paste;
    break;
}

bind .t <Control-V> {
    multi_paste;
    break;
}

bind .t <Control-Key-8> {
    enumerate 0;
    break;
}

bind .t <Control-Key-7> {
    enumerate 1;
    break;
}


bind .t <Control-r> {
    readAloud;
    break;
}

bind .t <Control-R> {
    readAloud;
    break;
}
proc f1 {} {
  global highlight_colors
  global rotate;
  global last_search;
  .t tag remove highlight2 1.0 end;
  .t tag remove highlight3 1.0 end;
  .t tag remove diffed 1.0 end;
  foreach hc $highlight_colors {
      .t tag remove $hc 1.0 end;
  }
  set highlight_colors {}
  array unset rotate;
  array unset last_search;
  clearDefaultHighlight;
};
bind . <F1> f1;
bind . <F10> f1;



proc delete_line_numbers {} {
   
   set selranges [.t tag ranges linenum];
   .t configure -autoseparators 0;
   .t edit separator;
   foreach {start end} $selranges {
       .t fastdelete $start $end;
   }
   .t edit separator;
   .t configure -autoseparators 1;
}
proc insert_line_numbers {} {
    set line 0;
   set selranges [.t tag ranges sel];
   if {$selranges == ""} {
     set pos [.t index end];
     set pos [.t index "$pos - 1 char"];
     set selranges "1.0  $pos"
   }
   set count 0;
    foreach {start end} $selranges {
       set start [expr int($start)];
       set end   [expr int($end)];
       incr count [expr $end - $start + 1];
       
    }
   .t configure -autoseparators 0;
   .t edit separator;

    set len [string length $count]
    foreach {start end} $selranges {
       set start [expr int($start)];
       set end   [expr int($end)];
       for {set i $start} {$i <= $end} {incr i} {
           incr line;
           .t insert "$i.0" [format "%${len}d: " $line] linenum;
       }
       
    }
     .t edit separator;
   .t configure -autoseparators 1;
}
proc updateModifiedStatus {} {
    global modified;
    if {$modified} {
            
            .bottomFrame.toppos configure -background "orange";
            .bottomFrame.position configure -background "orange";
        } else {
             .bottomFrame.toppos configure -background "green";
             .bottomFrame.position configure -background "green";
        }
        update;
    }
foreach acol {snow gainsboro linen bisque moccasin cornsilk ivory seashell honeydew azure lavender white black gray navy blue turquoise cyan aquamarine olive green chartreuse khaki goldenrod yellow gold goldenrod sienna peru burlywood beige wheat tan chocolate firebrick brown salmon orange coral tomato red pink violet maroon violet magenta violet plum orchid purple thistle} {
   .t tag configure "bg_$acol" -background $acol;
   .t tag configure "fg_$acol" -foreground $acol;
}

bind .t <ButtonPress-1> {
    .t tag raise sel;
    after idle {
        set marker "";
        if {$modified} {
            set marker "(M)"
            .bottomFrame.toppos configure -background "orange";
            .bottomFrame.position configure -background "orange";
        } else {
             .bottomFrame.toppos configure -background "green";
             .bottomFrame.position configure -background "green";
        }
         set cursor_pos [.t index insert];
        .bottomFrame.toppos configure -text "END: [.t index end] ${marker}";
        .bottomFrame.position clear;
        .bottomFrame.position insert 0 $cursor_pos;
    };
    
}




array set rotate {};



proc maximizeWindow toplevel {
            
         if {[string equal $::tcl_platform(platform) windows]} {
             wm state $toplevel normal
             return
         }
         pack propagate $toplevel 0
         update idletasks
         wm geometry $toplevel 900x600+-1+-1
         
         
}

proc listOfImages {} {
  append dump [.t dump -all 1.0 end]
  global image_filenames;
  global image_shrunk;
  global allResultWindows;
   
  set resultsWindow [toplevel ".[randString]"];
  lappend allResultWindows $resultsWindow;
  
  wm title $resultsWindow "List of Images";
  iwidgets::scrolledtext $resultsWindow.results -width 400 -height 400;
  pack $resultsWindow.results -side top -fill both -expand yes
  $resultsWindow.results tag configure resultHyperlink  -foreground blue
  $resultsWindow.results tag configure visited  -foreground purple
  $resultsWindow.results tag bind resultHyperlink <ButtonRelease-1> {
         set aline [%W index {@%x,%y linestart}];
         %W tag add visited "$aline" "$aline lineend";
         set linecont [%W get  "$aline" "$aline lineend"];
         set linenum $linecont;
         regsub -all {\((\d+)\):.*} $linenum {\1} linenum;
         sel $linenum $linenum;
         set yv [expr max($linenum-2,1)]
         change_yview "$yv.0";
         focus .t;
         focus %W;
       }
   $resultsWindow.results tag bind resultHyperlink <ButtonRelease-3> {
         set aline [%W index {@%x,%y linestart}];
         %W tag remove visited "$aline" "$aline lineend";
       }
       update;
    # add more details
    foreach {key value index} $dump \
    {
        switch $key \
        {
           
            image \
            {
                # If we are sending to clipboard, use 
                # absolute paths, but while
                # writing to file, use relative paths
                # where applicable.
                set fname [set image_filenames($value)];
                set shrunk_image [set image_shrunk($fname)];
                
                set curParts [split $index "."];
                set theLine [lindex  $curParts 0];
                set theCol [lindex  $curParts 1];
                
                $resultsWindow.results insert end "($theLine):($theCol):" resultHyperlink;
                $resultsWindow.results image create end -image $shrunk_image;
                $resultsWindow.results insert end "\n" resultHyperlink;
                update;
            }
           
            default \
            {
                
            }
        }
    }
  
}

proc listOfMultimedia {} {
    #loadOverview;
    global sound_filenames;
    global allResultWindows;
    
    append dump [.t dump -all 1.0 end]

    set resultsWindow [toplevel ".[randString]"];
    lappend allResultWindows $resultsWindow;
    
    wm title $resultsWindow "Multimedia Files";
    iwidgets::scrolledtext $resultsWindow.results -width 400 -height 400;
    pack $resultsWindow.results -side top -fill both -expand yes
    $resultsWindow.results tag configure resultHyperlink  -foreground blue
    $resultsWindow.results tag configure visited  -foreground purple
    $resultsWindow.results tag bind resultHyperlink <ButtonRelease-1> {
          set aline [%W index {@%x,%y linestart}];
          %W tag add visited "$aline" "$aline lineend";
          set linecont [%W get  "$aline" "$aline lineend"];
          set linenum $linecont;
          regsub -all {\((\d+)\):.*} $linenum {\1} linenum;
          sel $linenum $linenum;
          set yv [expr max($linenum-2,1)]
          change_yview "$yv.0";
          focus .t;
          focus %W;
       }
    $resultsWindow.results tag bind resultHyperlink <ButtonRelease-3> {
       set aline [%W index {@%x,%y linestart}];
       %W tag remove visited "$aline" "$aline lineend";
    }
    update;
    # add more details
    foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                if {[info exists  sound_filenames($value)]} {
                    set fname [set sound_filenames($value)];
                    catch {
                       set curParts [split $index "."];
                       set theLine [lindex  $curParts 0];
                       set theCol [lindex  $curParts 1];
                       $resultsWindow.results insert end "($theLine):($theCol):" resultHyperlink; 
                       $resultsWindow.results insert end "$fname\n";
                    } 
                }
            }
        
        }
    }
}
#[getmenu].file add command -label "Save Self Contained Zip" -command "saveSelfContainedZip [editor]";
proc saveSelfContainedZip {widget} {
    set zipname [tk_getSaveFile -filetypes {{{Zip Archive} {.zip}}}];
    if {$zipname == ""} {
        return;
    }
    set filecontent [hlt:save $widget];
    set files {};
    set filename   [get_current_filename]
    set curdir [pwd];
    
    set folder $filename
    regsub -all {/[^/]+$} $folder {} folder;
    if {$folder == $filename} {
        set folder "."
    } elseif {$folder == ""} {
        set folder "/";
    }
    
    regsub -all ".*/" $filename "" filename

    lappend files $filename;
    lappend files "${filename}.hlt";
    if {$files == ""} {
        tk_messageBox -message "Unnamed/unsaved buffer can not be saved";
        return;
    }


    foreach {key value} $filecontent \
    {
        switch $key \
        {
           I - M - F - N  
           {
               set fname [relativizeFileName $value];
               if {[file exists "$value.mp3"]} {
                  lappend files "$fname.mp3";
               } else {
                  lappend files $fname;
              }
           }
        }
    }

    catch {
      cd $folder
      exec zip $zipname {*}[set files]
      update;
    }
    cd $curdir;
}

proc regex_matched_line {regex index} {
    set linenum [lindex [split $index "."] 0];
    set line [.t get $linenum.0 $linenum.end];
    if {[string range $regex 0 0] == "-"} {
        return [expr ![regexp [string range $regex  1 end] $line]];
    } else {
        return [regexp $regex $line];
    }
}

proc delete_selected_notes {{regex {}}} {
    set selranges [.t tag ranges sel];
    global general_filenames;
    global allResultWindows;
    foreach {start end} $selranges {
        append dump [.t dump -all $start $end];
        update;
    # add more details
    set indexes {};
    foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
               if {$regex == {} || [regex_matched_line $regex $index]} {
               lappend indexes $index;
               catch {
                if {[info exists general_filenames($value)]} {
                    set fname [set general_filenames($value)];
                    file delete $fname; 
                 }
               }
            }
          }
        }   
    }
    foreach index [lreverse $indexes] {
        set pos [split $index "."];
        set line [lindex $pos 0];
        set col [lindex $pos 1];
        .t fastdelete $index "$line.[expr $col + 1]";    
    }
  }
}

proc delete_notes {{regex {}}} {
    global general_filenames;
    global allResultWindows;
    append dump [.t dump -all 1.0 end]
    update;
    # add more details
    set indexes {};
    foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                if {$regex == {} || [regex_matched_line $regex $index]} {
           lappend indexes $index;
        catch {
            set ftype [$value cget -text];
            if {$ftype == "N"} {
                  if {[info exists general_filenames($value)]} {
                    
                    set fname [set general_filenames($value)];
                    file delete $fname; 
                 }
               }
              }
            }
          }
        }   
    }
    foreach index [lreverse $indexes] {
        set pos [split $index "."];
        set line [lindex $pos 0];
        set col [lindex $pos 1];
        .t fastdelete $index "$line.[expr $col + 1]";    
    }
}

proc delete_images {{regex {}}} {
    global image_filenames;
    global allResultWindows;
    append dump [.t dump -all 1.0 end]
    update;
    # add more details
    set indexes {};
    foreach {key value index} $dump \
    {
        switch $key \
        {
           image \
            {
                if {$regex == {} || [regex_matched_line $regex $index]} {
           lappend indexes $index;
        catch {
                 if {[info exists image_filenames($value)]} {
                    set fname [set image_filenames($value)];
                    file delete $fname; 
                 }
              }
            }
          }
        }   
    }
    foreach index [lreverse $indexes] {
        set pos [split $index "."];
        set line [lindex $pos 0];
        set col [lindex $pos 1];
        .t fastdelete $index "$line.[expr $col + 1]";    
    }
}

proc convert_images {subcmd {regex {}}} {
    global image_filenames;
    global allResultWindows;
    append dump [.t dump -all 1.0 end]
    update;
    # add more details
    set indexes {};
    foreach {key value index} $dump \
    {
        switch $key \
        {
           image \
            {
                if {$regex == {} || [regex_matched_line $regex $index]} {
           lappend indexes $index;
        catch {
                 if {[info exists image_filenames($value)]} {
                    convert_single_image $value $subcmd;
                 }
              }
            }
          }
        }   
    }
}

proc delete_notes_by_content { {content_regex} {line_regex {} } }  {
    global general_filenames;
    global allResultWindows;
    append dump [.t dump -all 1.0 end]
    update;
    # add more details
    set indexes {};
    foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                if { ($line_regex == {} || [regex_matched_line $line_regex $index]) &&
                    [info exists general_filenames($value)] &&
                    [file exists [set general_filenames($value)]] &&
                    [regexp $content_regex [read_file_contents $general_filenames($value)]]
                  } {
           lappend indexes $index;
        catch {
          set ftype [$value cget -text];
          if {$ftype == "N"} {     
                if {[info exists general_filenames($value)]} {
                    set fname [set general_filenames($value)];
                    file delete $fname; 
                 }
               }
             }
            }
          }
        }   
    }
    foreach index [lreverse $indexes] {
        set pos [split $index "."];
        set line [lindex $pos 0];
        set col [lindex $pos 1];
        .t fastdelete $index "$line.[expr $col + 1]";    
    }
}

proc tesseract_ocr {} {
    global image_filenames;
    append dump [.t dump -all 1.0 end]
    update;
    set outfile c:/temp/tesseract.out
    # add more details
    set indexes {};
    clipboard clear;
    foreach {key value index} $dump \
    {
        switch $key \
        {
           image \
            {
              set fname [set image_filenames($value)];
              catch {
              exec tesseract.exe $fname $outfile --dpi 150;
              } msg;
              puts $msg;
              set cont [read_file_contents "${outfile}.txt"];
              clipboard append $cont;
              clipboard append "\n";
            }
        }   
    }
    tk_messageBox -message "Copied OCR result to clipboard";
    
}

proc numberToWords {number} {
    set ones {"" one two three four five six seven eight nine}
    set teens {ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen}
    set tens {zero ten twenty thirty forty fifty sixty seventy eighty ninety}
    set bigs {"" thousand million billion}

    if {$number < 0 || $number >= 100000000000} {
        return "Invalid number"
    }
    if {$number == 0} {
        return "zero";
    }

    if {$number < 10} {
        return [lindex $ones $number]
    } elseif {$number < 20} {
        return [lindex $teens [expr {$number - 10}]]
    } elseif {$number < 100} {
        set tens_digit [lindex $tens [expr {$number / 10}]]
        set ones_digit [lindex $ones [expr {$number % 10}]]
        return "${tens_digit} ${ones_digit}"
    } elseif {$number < 1000} {
        set hundreds_digit [lindex $ones [expr {$number / 100}]]
        set remaining [expr {$number % 100}]
        set remaining_words [numberToWords $remaining]
        return "${hundreds_digit} hundred $remaining_words"
    } else {
        set level 0
        set words ""
        while {$number > 0} {
            set chunk [expr {$number % 1000}]
            set chunk_words [numberToWords $chunk]
            if {$chunk != 0} {
                set words "${chunk_words} [lindex $bigs $level] $words"
            }
            incr level
            set number [expr {$number / 1000}]
        }
        return $words
    }
}

proc addNotesForNumbers {} {
    visit_re_quiet {[1-9][0-9,]+} wordNotesForNumbers;
}

proc wordNotesForNumbers {regex cur end} {
    set numb [.t get $cur $end];
    regsub -all {,} $numb "" numb;
    set prevchar [.t get "$cur - 1 char" "$cur - 1 char"];
    if {$prevchar != "."} {
        set words [numberToWords $numb];
        create_note $end $words;
    } 
    update;
}

proc addNoteForCurrentWord {pos} {
    visit_re_quiet {[1-9][0-9,]+} wordNotesForNumbers;
}
   

proc dyslexiaOfNumbers {} {
    addNotesForNumbers;
    addAudioReadoutsOfNotes;
}
proc addAudioReadoutsOfNotes {} {

    #loadOverview;
    global general_filenames;
     global sound_filenames;
    global play_image;
    global tcl_platform;

    append dump [.t dump -all 1.0 end]
   
    update;
    # add more details
    set count 0;
    foreach {key value index} $dump \
    {   update;
        switch $key \
        {
            
           text \
            {    
                if {[string first "\n" $value] != -1} {set count 0;}
            }
             
           window \
            { 
                incr count;
                puts "(key value index) = $key $value $index";
                if {[info exists general_filenames($value)]} {
                    set fname [set general_filenames($value)];

                   catch {
                       catch {
                         if {[string first "Windows" $tcl_platform(os)] == 0 } { 
                            set cmd "";
                            append cmd  "exec" " " "[installdir]/wbin/balcon.exe" " "  -n " "  "Microsoft Hazel Desktop" " "  "-f" " "  $fname  " " -o " "  --raw " "  | " "  "[installdir]/wbin/lame.exe" " "  -r " "  -s " "  14.05 " "  -m " "  m " "  -h " "  - " "  "${fname}.mp3"
                            puts $cmd;
                            exec "[installdir]/wbin/balcon.exe" -n "Microsoft Hazel Desktop" "-f" $fname -o --raw | "[installdir]/wbin/lame.exe" -r -s 14.05 -m m -h - "${fname}.mp3"
                         } else {
                             exec say -f $fname -o $fname.aiff;
                             exec lame -m m $fname.aiff $fname.mp3;
                             file delete --force $fname.aiff;
                         }
                     } msg1;
                     puts $msg1;
                    set pos $index
                    #puts "pos=$pos";
                    set btn .t.[randString];
                   .t window create "$pos + $count char" -create " button $btn  -image $play_image -command \"playMedia $fname\" -background #ccd3f7 -activebackground #a78737";
                    after 1000 "setTooltip $btn $fname";
                    after 2000 "bind $btn <ButtonPress-3> \{showMediaMenu $btn \"$fname\"\}";
                    after 2000 "bind $btn <ButtonPress-2> \{showMediaMenu $btn \"$fname\"\}";
                    set sound_filenames($btn) $fname;

                   } msg;
                   puts $msg;
                   
                }
            }
        
        }
    }
     

}

proc listOfNotes {} {
    #loadOverview;
    global general_filenames;
    global allResultWindows;
   
    set resultsWindow [createResultsWindow "List of Notes"];
    
    append dump [.t dump -all 1.0 end]
   
    update;
    # add more details
    foreach {key value index} $dump \
    {
        switch $key \
        {
           window \
            {
                if {[info exists general_filenames($value)]} {
                    set fname [set general_filenames($value)];
                     catch {
                    set fp1 [open $fname r];
                    fconfigure $fp1 -encoding utf-8
                    set cont [string  range [read $fp1] 0 200];
                    close $fp1;

                    set curParts [split $index "."];
                    set theLine [lindex  $curParts 0];
                    set theCol [lindex  $curParts 1];
                    $resultsWindow.results insert end "($theLine):($theCol):" resultHyperlink; 
                    $resultsWindow.results insert end "$cont\n";
                 }
                   
                }
            }
        
        }
    }
     
}
set undo_stack {};
set redo_stack {};
array set last_positions {}


proc highlightSelectedString {dir id color} {
    global fixed_boxes;
    global currentColor;

    set color white;
    if {$id == 6} {
       set color $currentColor;
    } elseif {$id <= 5} {
       set color [lindex  $fixed_boxes [expr 2*$id-1]];
    }
    catch {
     
    set font [[.searchFrame.font component entry] get];
    set foreground [[.searchFrame.foreground component entry] get];

    set tagname $color;

    foreach x $font {
        foreach y $x {
            append tagname $y;
        }
    }
    if {[llength $foreground]} {
      append tagname "_" $foreground;
    }

    if {[llength $font]} {
        .t tag configure $tagname -font $font;
    }
    
    if {$color != "white" && $color != "#FFFFFF" && $color != "#ffffff"} {
        .t tag configure $tagname  -background $color ;
    }
    if {[llength $foreground]} {
        .t tag configure $tagname -foreground $foreground;
    }
    global all_tags;
    set new_tag 1;
    foreach tag $all_tags {
        if { $tag == $tagname } {
          set new_tag 0;
        }
    }
    if {$new_tag} {
        lappend all_tags $tagname;
    }
    .t tag raise $tagname;
    global modified;
    global undo_stack;
    global redo_stack;
    global sel_only;
    global use_regex;
    global case_sensitive;
    global last_search;
    global last_positions ;
    global rotate;
    global remove_previous;
    global allResultWindows;
    set string [.searchFrame.search${id} component entry get];

    
   set selranges [.t tag ranges sel];
   resetOverpaintedStuff;
   saveSelectionForUndo .t;

   set got_sels 0;
   foreach {start end} $selranges {
       foreach tag $all_tags {
            if {![regexp {(^target_)|(^hyperref_)} $tag]} {
               .t tag remove $tag  $start $end;
            }
       }  
       .t tag add $tagname $start $end
       set got_sels 1;
   }
   .t tag raise sel;
   if {!$got_sels} {
       #-startNote $tagname; # Shikha did not like this
       return;
   }
   #loadOverview;
  }
}


proc insertResultsAsNotes {w} {
     set end [$w.results index end];
     set lastline [expr int($end)];
     set notefile "";
     set filter [$w.filter get];
     set lastlinenum "";
     set offset 0;
     for {set i 1} {$i <= $lastline} {incr i} {
         set linecont [$w.results get  "$i.0" "$i.end"];
         set origcont $linecont;
         set linenum $linecont;
         set col $linecont;
     if {$filter != ""} {
          catch {
                  regsub -all {^\((\d+)\):.*} $linenum {\1} linenum;
                  regsub -all {^\(\d+\):\((\d+)\):.*} $col {\1} col;
                  regsub -all {^\(\d+\):\(\d+\):(.*)} $linecont {\1} linecont;
                  set notetext $filter
              if {[string index $filter end] == "+"} {
                      set notetext [string range $notetext 0 end-1];
                      append notetext ": $linecont"
              }
              if {$linenum == $lastlinenum} {
                  incr offset
              } else {
                  set offset 0;
              }
              
              create_note  [.t index "$linenum.$col + $offset char"] $notetext;
          }
       } else {
             if {[catch {
             regsub -all {^\((\d+)\):.*} $linenum {\1} linenum;
             regsub -all {^\(\d+\):\((\d+)\):.*} $col {\1} col;
                    regsub -all {^\(\d+\):\(\d+\):(.*)} $linecont {\1} linecont;
                  if {$linenum == $lastlinenum} {
                    incr offset
                  } else {
                    set offset 0;
                  }   
                 set notefile [insert_note_button [.t index "$linenum.$col + $offset char"] $linecont];
               }]} {
             appendToFile $notefile $origcont;
           } 
        }
        set lastlinenum $linenum;
    }     
 }
 
proc selectResultsLines {w} {
    set end [$w.results index end];
    set lastline [expr int($end)];
    set notefile "";
    set filter [$w.filter get];
    for {set i 1} {$i <= $lastline} {incr i} {
        set linecont [$w.results get  "$i.0" "$i.end"];
        set origcont $linecont;
        set linenum $linecont;
        catch {
                 regsub -all {^\((\d+)\):.*} $linenum {\1} linenum;
                 .t tag add sel "${linenum}.0" "${linenum}.end";
             }
     }     
}

proc selectResultsLocations {w} {
  set end [$w.results index end];
  set lastline [expr int($end)];
  set notefile "";
  set filter [$w.filter get];
  for {set i 1} {$i <= $lastline} {incr i} {
    set linecont [$w.results get  "$i.0" "$i.end"];
    set origcont $linecont;
    catch {
     regsub -all {^\((\d+)\):.*} $linecont {\1} linenum;
     regsub -all {^\(\d+\):\((\d+)\).*} $linecont {\1} colnum;
     .t tag add sel "${linenum}.${colnum}" [.t index "${linenum}.${colnum} + 2 char"];
    }
  }     
}
 
proc filterResult {w} {
    set string [$w.filter get];
    if {$string == ""} {
        return;
    }
    
    set resultsWindow [createResultsWindow "Filtered Results for $string"];
    set last_cur "";
    set cur 1.0;
    while 1 {
        set cur [$w.results search -regexp -count length $string $cur end];
        if {$cur == "" || $cur == $last_cur} {
              break
           }
        set matchline [$w.results get "$cur linestart" "$cur lineend"];
        $resultsWindow.results insert end $matchline resultHyperlink;
        $resultsWindow.results insert end "\n";
        set last_cur $cur;
        set cur [$w.results index "$cur lineend"];
    }
    
    update;
}

proc createResultsWindow {title} {
   global allResultWindows;
   global default_font;
   set resultsWindow [toplevel ".[randString]"];
   lappend allResultWindows $resultsWindow;
  
    set x [winfo pointerx ${resultsWindow}];
     set y [winfo pointery ${resultsWindow}];
     set x [expr max(100, $x-100)];
     set y [expr max(100, $y-100)];
    wm geometry $resultsWindow "+$x+$y";

   wm title $resultsWindow $title;
   iwidgets::scrolledtext $resultsWindow.results -width 400 -height 400;
   [$resultsWindow.results component text] configure -undo 0
   pack $resultsWindow.results -side top -fill both -expand yes
   entry $resultsWindow.filter;
   bind $resultsWindow.filter <Return>  "filterResult $resultsWindow";
   button $resultsWindow.selectLines -text "Select Lines!" -command "selectResultsLines $resultsWindow";
   button $resultsWindow.selectLocations -text "Select Locations!" -command "selectResultsLocations $resultsWindow";
   button $resultsWindow.insertNotes -text "Insert as Notes!" -command "insertResultsAsNotes $resultsWindow";
   pack $resultsWindow.filter -side bottom -fill x -expand yes;
   pack $resultsWindow.selectLines -side left;
   pack $resultsWindow.selectLocations -side left;
   pack $resultsWindow.insertNotes -side right;
   $resultsWindow.results tag configure resultHyperlink  -foreground blue
   $resultsWindow.results tag configure visited  -foreground purple
   $resultsWindow.results tag bind resultHyperlink <ButtonRelease-1> {
     set aline [%W index {@%x,%y linestart}];
     %W tag add visited "$aline" "$aline lineend";
     set linecont [%W get  "$aline" "$aline lineend"];
     set linenum $linecont;
     regsub -all {\((\d+)\):.*} $linenum {\1} linenum;
     sel $linenum $linenum;
     set yv [expr max($linenum-2,1)]
     change_yview "$yv.0";
     focus .t;
     focus %W;
   }
   
   $resultsWindow.results tag bind resultHyperlink <ButtonRelease-3> {
     set aline [%W index {@%x,%y linestart}];
     %W tag remove visited "$aline" "$aline lineend";
   }
   
   set txtwidget [$resultsWindow.results component text];  
  
  
    bind $txtwidget  <Control-c> "
     copySelection $txtwidget;
     break;
    "

    bind $txtwidget  <Control-x> "
     copySelection $txtwidget cut;
     break;
    " 
  
    bind $txtwidget <Double-ButtonPress-1> "
       set pos \[$txtwidget index {@%x,%y}\];
       highlightCurrent $txtwidget  \$pos; break;
  
    "
   
   return $resultsWindow;
}


proc createHtmlWindow {title htmlfile} {
   global allResultWindows;
   global default_font;
   set resultsWindow [toplevel ".[randString]"];
   lappend allResultWindows $resultsWindow;
  
    set x [winfo pointerx ${resultsWindow}];
     set y [winfo pointery ${resultsWindow}];
     set x [expr max(100, $x-100)];
     set y [expr max(100, $y-100)];
    wm geometry $resultsWindow "+$x+$y";

   iwidgets::scrolledhtml  $resultsWindow.results  -fontname helvetica -linkcommand "$resultsWindow.results import -link"

   pack  $resultsWindow.results -padx 10 -pady 10 -fill both -expand yes

   $resultsWindow.results import $htmlfile


   bind $resultsWindow  <Control-c> "
     copySelection [$resultsWindow.results component text];
     break;
    "

    bind $resultsWindow  <Control-x> "
     copySelection [$resultsWindow.results component text] cut;
     break;
   "   
   return $resultsWindow;
}


proc collect_snippet_as_note {file_name file_line extent pos} {
    set cont [read_file_contents $file_name];
    set lines [split $cont "\n"];
    set lnum 0;
    set txt "${file_name}:${file_line}:@@@@@@@@@@@@@@@@@@@@@\n";
    foreach line $lines {
        incr lnum;
        if {$lnum >= ($file_line - $extent) && 
            $lnum <= ($file_line + $extent)} {
            if {$lnum == $file_line} {
                append  txt "$lnum: @@@@@@@@@@@@@@@@@@@@@@@  $line"
            } else {
                append  txt "$lnum: $line"
            }   
        }
    }
    create_note $pos $txt;
}

proc visitorTraceSnippet {regex cur end resultsWindow args} {
    global file_lookup;
    set extent [lindex $args 0];
    set txt [.t get $cur $end];
     
    set tagnum "";
    regsub -all {</?T(\d+)>}  $txt {\1} tagnum;
    if {[info exists file_lookup($tagnum)]} {
      set file_loc [set file_lookup($tagnum)];
      set file_name [regsub -all {^[ \t]*(.:[^\(:]*)[\(:].*} $file_loc {\1}];
      set file_line [regsub -all {^[ \t]*.:[^\(:]*[\(:]([0-9]*)[:\)].*} $file_loc {\1}];
      $resultsWindow.results insert end "$file_name:${file_line}:$txt";
      $resultsWindow.results insert end "\n";
      collect_snippet_as_note $file_name $file_line $extent $end;
    } else {
      $resultsWindow.results insert end "not_found\(0\):$txt";
      $resultsWindow.results insert end "\n"; 
    } 
    update;
}

proc collect_trace_snippets {extent} {
    visit_re "</?T\\d+>" visitorTraceSnippet $extent;
}

proc selre {regex} {
    visit_re $regex visitorSelreMarkWord;
}

proc hlre {re col} {
    visit_re_quiet $re applyHighlight $col
}

proc applyHighlight {regex cur end col} {
     clearHighlightsInRange $cur $end; 
    .t tag configure $col -background $col;
    .t tag add $col $cur  $end;
    .t tag raise $col;
    update;
}



proc visit_re_quiet {regex visitor_fn args}  {
  
    global sel_only;
    global use_regex;
    global case_sensitive;

       set contexts [getLRContexts];

       if {$regex == ""} {
         return
       }
       
       set selranges [.t tag ranges sel];
       if {[llength $selranges] == 0} {
           set selranges {1.0 end};
       }
       
       set got_sel 0;
       set num_found 0;
       update;
       set contexts [getLRContexts];
       .t tag remove  sel 1.0 end;
       
       foreach {start end} $selranges {
           set last_cur "";
           set cur $start;
       
           while 1 {
               if {$use_regex} {
                   if {$case_sensitive} {
                         set cur [.t search -regexp -count length $regex $cur $end]
                    } else {
                         set cur [.t search -regexp -nocase -count length $regex $cur $end]
                    }
                   } else {
                   if {$case_sensitive} {
                         set cur [.t search -exact -count length $regex $cur $end]
                    } else {
                         set cur [.t search -exact -nocase -count length $regex $cur $end]
                    }
               }
           
               if {$cur == "" || $cur == $last_cur} {
                  break
               }
               
               if {![satisfiesContext $cur $length $contexts]} {
                   if {$length == 0} {
                    incr length;
                    }
                    set endpos [.t index "$cur + $length char"];
                    set cur $endpos;
                   continue;
               }
               set last_cur $cur;
               incr num_found;
               set endpos [.t index "$cur + $length char"];
               $visitor_fn $regex $cur $endpos {*}$args;

               set cur $endpos;
           } 
           
           
    }
    set statusMessage "Found $num_found occurrences of ";
           append statusMessage $regex;
           addToStatus $statusMessage;

    .t tag raise sel;
    update;
}

proc visit_re {regex visitor_fn args}  {
  
    global sel_only;
    global use_regex;
    global case_sensitive;

       set contexts [getLRContexts];

       if {$regex == ""} {
         return
       }
       
       set selranges [.t tag ranges sel];
       if {[llength $selranges] == 0} {
           set selranges {1.0 end};
       }
       
       set got_sel 0;
       set num_found 0;
       set resultsWindow [createResultsWindow "Search Results for $regex"]
       update;
       set contexts [getLRContexts];
       .t tag remove  sel 1.0 end;
       
       
       foreach {start end} $selranges {
           set last_cur "";
           set cur $start;
       
           while 1 {
               if {$use_regex} {
                   if {$case_sensitive} {
                         set cur [.t search -regexp -count length $regex $cur $end]
                    } else {
                         set cur [.t search -regexp -nocase -count length $regex $cur $end]
                    }
                   } else {
                   if {$case_sensitive} {
                         set cur [.t search -exact -count length $regex $cur $end]
                    } else {
                         set cur [.t search -exact -nocase -count length $regex $cur $end]
                    }
               }
           
               if {$cur == "" || $cur == $last_cur} {
                  break
               }
               
               if {![satisfiesContext $cur $length $contexts]} {
                   if {$length == 0} {
                    incr length;
                    }
                    set endpos [.t index "$cur + $length char"];
                    set cur $endpos;
                   continue;
               }
               set last_cur $cur;
               incr num_found;
               set endpos [.t index "$cur + $length char"];
               $visitor_fn $regex $cur $endpos $resultsWindow {*}$args;

               set cur $endpos;
           } 
           
           
    }
    set statusMessage "Found $num_found occurrences of ";
           append statusMessage $regex;
           addToStatus $statusMessage;

    .t tag raise sel;
    update;
}

proc visitorSelreMarkWord {regex cur end resultsWindow args} {
    change_yview $cur;
    .t tag add sel $cur $end;

    set curParts [split $cur "."];
    set theLine [lindex  $curParts 0];
    set theCol [lindex  $curParts 1];
    set theText [.t get "$theLine.0" "$theLine.end"]
    $resultsWindow.results insert end "($theLine):($theCol):${regex}:\t$theText\n" resultHyperlink;
    update;
}

proc invsel {} {
    set selranges [.t tag ranges sel];
    .t tag add sel 1.0 end;
    foreach {start end} $selranges {
        .t tag remove sel $start $end;
    }
}

proc selfrac {{frac 0.5} {min 0}} {
    set selranges [.t tag ranges sel];
    .t tag remove sel 1.0 end;
    foreach {start end} $selranges {
        set txt [.t get $start $end];
        set len [string length $txt];
        set newlen [expr max($min,int($len*$frac))];
        if {$newlen > 0} {
          .t tag add sel $start "$start + $newlen char";
      }
    }
}


proc adhd {{frac 0.5} {font {{Courier New} 12 bold}}} {
    selre {\m\w\w\w+\M};
    global all_tags;
    
    set afont [[.searchFrame.font component entry] get];
    
    selfrac 0.5 1;
    set selranges [.t tag ranges sel];

    if { $afont != "" } {
       .t tag configure adhd_wordstart -font $afont; 
    } else {
      .t tag configure adhd_wordstart -font $font;
    }
    if {[lsearch $all_tags adhd_wordstart] == -1} {
        lappend all_tags adhd_wordstart;
    }
    foreach {start end} $selranges {
        .t tag add adhd_wordstart $start $end;
    }
    set aforeground [[.searchFrame.foreground component entry] get];  
    if { $aforeground != "" } {
      set aforeground "#808080";
    }
    invsel;
    set selranges [.t tag ranges sel];
    .t tag configure adhd_wordend -foreground $aforeground; 
    if {[lsearch $all_tags adhd_wordend] == -1} {
        lappend all_tags adhd_wordend;
    }
    foreach {start end} $selranges {
        .t tag add adhd_wordend $start $end;
    }
    .t tag remove sel 1.0 end;
}

 proc unselre {string}  {
  
      global sel_only;
    global use_regex;
    global case_sensitive;

       set contexts [getLRContexts];

       if {$string == ""} {
         return
       }
       
       set selranges [.t tag ranges sel];
       if {[llength $selranges] == 0} {
           set selranges {1.0 end};
       }
       
       set got_sel 0;
       set did_change 0;
       set num_found 0;
       set resultsWindow [createResultsWindow "Search Results for $string"]
       update;
       set contexts [getLRContexts];
       
       foreach {start end} $selranges {
           set last_cur "";
           set cur $start;
       
           while 1 {
               if {$use_regex} {
                   if {$case_sensitive} {
                         set cur [.t search -regexp -count length $string $cur $end]
                    } else {
                         set cur [.t search -regexp -nocase -count length $string $cur $end]
                    }
                   } else {
                   if {$case_sensitive} {
                         set cur [.t search -exact -count length $string $cur $end]
                    } else {
                         set cur [.t search -exact -nocase -count length $string $cur $end]
                    }
               }
           
               if {$cur == "" || $cur == $last_cur} {
                  break
               }
               if {![satisfiesContext $cur $length $contexts]} {
                   if {$length == 0} {
                    incr length;
                    }
                    set cur [.t index "$cur + $length char"]
                   continue;
               }
               set last_cur $cur;
               change_yview $cur;
               .t tag remove sel $cur "$cur + $length char";
               incr num_found;
               set did_change 1;
            
               if {$length == 0} {
                   incr length;
               }
               set curParts [split $cur "."];
               set theLine [lindex  $curParts 0];
               set theCol [lindex  $curParts 1];
               set theText [.t get "$theLine.0" "$theLine.end"]
               $resultsWindow.results insert end "($theLine):($theCol):${string}:\t$theText\n" resultHyperlink;
               update;

               set cur [.t index "$cur + $length char"]
           } 
           
           
    }
    set statusMessage "Found $num_found occurrences of ";
           append statusMessage $string;
           addToStatus $statusMessage;

    .t tag raise sel;
    update;
}


proc annot_search {search_string txt} {
    [.searchFrame.search6 component entry] delete 0 end;
   [.searchFrame.search6 component entry] insert end $search_string;
   focus [.searchFrame.search6 component entry]; 
   annot_search_aux 1 6 currentColor $txt 
}

proc annot_search_aux {dir id color txt} {
    global fixed_boxes;
    global currentColor;

    set color white;
    if {$id == 6} {
       set color $currentColor;
    } elseif {$id <= 5} {
       set color [lindex  $fixed_boxes [expr 2*$id-1]];
    }
    catch {
     
    set font [[.searchFrame.font component entry] get];
    set foreground [[.searchFrame.foreground component entry] get];

    set tagname $color;

    foreach x $font {
        foreach y $x {
            append tagname $y;
        }
    }
    if {[llength $foreground]} {
      append tagname "_" $foreground;
    }

    if {[llength $font]} {
        .t tag configure $tagname -font $font;
    }
    
    if {$color != "white" && $color != "#FFFFFF" && $color != "#ffffff"} {
        .t tag configure $tagname  -background $color ;
    }
    if {[llength $foreground]} {
        .t tag configure $tagname -foreground $foreground;
    }
    global all_tags;
    set new_tag 1;
    foreach tag $all_tags {
        if { $tag == $tagname } {
          set new_tag 0;
        }
    }
    if {$new_tag} {
        lappend all_tags $tagname;
    }
    .t tag raise $tagname;
    global modified;
    global undo_stack;
    global redo_stack;
    global sel_only;
    global use_regex;
    global case_sensitive;
    global last_search;
    global last_positions ;
    global rotate;
    global remove_previous;
    
    set string [.searchFrame.search${id} component entry get];
     
    
    set last_string "";
    if {[info exists last_search($id)]} {
        set last_string [set last_search($id)];
    }
    
    set num_finds 0;
    if {[info exists last_positions($id)]} {
        set num_finds [llength $last_positions($id)];
    }
    set has_sel_now [hasSelection];
    addToStatus "search$id flags dir=$dir last_eq=[expr {$last_string eq $string}] sel_only=$sel_only has_sel=$has_sel_now num_finds=$num_finds";
    if {$last_string  != $string || $sel_only  || $has_sel_now || !$num_finds || $dir == 1 } {
       addToStatus "search$id branch=full";
       set contexts [getLRContexts];
       set last_search($id) $string
       set last_positions($id) {}
       if {$remove_previous} {
           .t tag remove $tagname 1.0 end;
       }
       if {$string == ""} {
         return
       }
       set cur 1.0;
       set last_cur "";
       set got_sel 0;
       if {$sel_only || $has_sel_now} {
         catch {
          set cur [lindex [lindex [.t tag ranges sel] 0] 0];
         }
       }
       set final_sel_pos $cur ;
       set did_change 0;
       set num_found 0;  
       
       update;

       while 1 {
           if {$use_regex} {
               if {$case_sensitive} {
                     set cur [.t search -regexp -count length $string $cur end]
                } else {
                     set cur [.t search -regexp -nocase -count length $string $cur end]
                }
               } else {
               if {$case_sensitive} {
                     set cur [.t search -exact -count length $string $cur end]
                } else {
                     set cur [.t search -exact -nocase -count length $string $cur end]
                }
           }
           #puts "cur=$cur";
           if {$cur == "" || $cur == $last_cur} {
              break
           }
           if {![satisfiesContext $cur $length $contexts]} {
               if {$length == 0} {
                incr length;
                }
                set cur [.t index "$cur + $length char"]
               continue;
           }
           set last_cur $cur;
           lappend last_positions($id) $cur
           change_yview $cur;
            if {$sel_only || $has_sel_now} {
                set curtag [.t tag names $cur];
                if {[lsearch $curtag "sel"] != -1} {
                    set got_sel 1;
                    set final_sel_pos $cur;
                    foreach tag $all_tags {
                      if {![regexp {(^target_)|(^hyperref_)} $tag]} {
                        .t tag remove $tag  $cur "$cur + $length char";
                      }
                     }
             if {$txt == ""}  {
                          create_note $cur [.t get $cur  "$cur + $length char"]
                 } else {
                  create_note $cur $txt;
                 }   
                    .t tag add $tagname $cur "$cur + $length char"
                    incr num_found;
                    set did_change 1;
                } else {
                     if {$got_sel && ![hasMultiSelection]} {
                         break;
                     }
                }
            } else {
                foreach tag $all_tags { 
                   if {![regexp {(^target_)|(^hyperref_)} $tag]} {
                      .t tag remove $tag  $cur "$cur + $length char";
                     }
                 }
               if {$txt == ""}  {
                   create_note $cur [.t get $cur  "$cur + $length char"]
           } else {
           create_note $cur $txt;
           } 
               .t tag add $tagname $cur "$cur + $length char"
               incr num_found;
               set did_change 1;
            }
            if {$length == 0} {
                incr length;
            }
            set curParts [split $cur "."];
            set theLine [lindex  $curParts 0];
            set theCol [lindex  $curParts 1];
            set theText [.t get "$theLine.0" "$theLine.end"]
            update;

            set cur [.t index "$cur + $length char"]
           } 
           # while 1
           if { $did_change } {
              .t edit separator;
           }
           set statusMessage "Found $num_found occurrences of ";
           append statusMessage $string;
           addToStatus $statusMessage;
          
           if {$sel_only || $has_sel_now} {
                change_yview $final_sel_pos; 
                .t tag remove highlight2 1.0 end;
                .t tag add highlight2 $final_sel_pos "$final_sel_pos + 1 char";
               
           }
    } elseif {$num_finds} {
       addToStatus "search$id branch=navigate";
       set curpos [.t index insert];
       if {$dir == 2} {
           for {set rotate($id) 0} {$rotate($id) < $num_finds} {incr rotate($id)} {
              if { [lindex [set last_positions($id)] [set rotate($id)]] > $curpos } {
                  set dir 0; 
                  break;
               }
            }
        }
        if {$dir == -2} {
           for {set rotate($id) [expr $num_finds - 1 ]} {$rotate($id) >= 0} {incr rotate($id) -1} {
              if { [lindex [set last_positions($id)] [set rotate($id)]] < $curpos } {
                   set dir 0;
                   break;
               }
            }
        }
        if {![info exists rotate($id)]} {
            set rotate($id) 0;
        } else {
            set rotate($id) [expr ([set rotate($id)] + ($dir)) % [llength [set last_positions($id)]]];
        }
        set newpos [lindex [set last_positions($id)] [set rotate($id)]];
        change_yview $newpos
        .t tag remove highlight2 1.0 end;
        .t tag add highlight2 $newpos "$newpos + 1 char";

    }

    .t tag raise $tagname;
    .t tag raise sel;
    .t tag raise highlight2;
    } msg;
    if {$msg ne ""} {
        addToStatus "search error: $msg";
    }
    #loadOverview;
    update;
}


proc get_search_match_length {w pos pattern use_regex case_sensitive} {
    if {!$use_regex} {
        set n [string length $pattern]
        if {$n <= 0} { set n 1 }
        return $n
    }
    set txt [$w get $pos "$pos lineend"]
    if {$case_sensitive} {
        if {[regexp -indices -- "^($pattern)" $txt m]} {
            return [expr {[lindex $m 1] - [lindex $m 0] + 1}]
        }
    } else {
        if {[regexp -nocase -indices -- "^($pattern)" $txt m]} {
            return [expr {[lindex $m 1] - [lindex $m 0] + 1}]
        }
    }
    set n [string length $pattern]
    if {$n <= 0} { set n 1 }
    return $n
}

proc searchString {dir id color args} {
    global fixed_boxes;
    global currentColor;
    
    set string [.searchFrame.search${id} component entry get];
    if {[string first "." $string] == 0 && [winfo exists $string]} {
        catch { set string [$string get] }
    }
    
    global loggedcommands;
    global new_loggedcommands;


    set color white;
    if {$id == 6} {
       set color $currentColor;
    } elseif {$id <= 5} {
       set color [lindex  $fixed_boxes [expr 2*$id-1]];
    }
    catch {
     
    set font [[.searchFrame.font component entry] get];
    if {[string first "." $font] == 0 && [winfo exists $font]} {
        catch { set font [$font get] }
    }
    set foreground [[.searchFrame.foreground component entry] get];
    if {[string first "." $foreground] == 0 && [winfo exists $foreground]} {
        catch { set foreground [$foreground get] }
    }
    

    set tagname $color;

    foreach x $font {
        foreach y $x {
            append tagname $y;
        }
    }
    if {[llength $foreground]} {
      append tagname "_" $foreground;
    }

    if {[llength $font]} {
        .t tag configure $tagname -font $font;
    }
    
    if {$color != "white" && $color != "#FFFFFF" && $color != "#ffffff"} {
        .t tag configure $tagname  -background $color ;
    }
    if {[llength $foreground]} {
        .t tag configure $tagname -foreground $foreground;
    }
    global all_tags;
    set new_tag 1;
    foreach tag $all_tags {
        if { $tag == $tagname } {
          set new_tag 0;
        }
    }
    if {$new_tag} {
        lappend all_tags $tagname;
    }
    .t tag raise $tagname;
    global modified;
    global undo_stack;
    global redo_stack;
    global sel_only;
    global use_regex;
    global case_sensitive;
    global last_search;
    global last_positions ;
    global rotate;
    global remove_previous;
    
    set last_string "";
    if {[info exists last_search($id)]} {
        set last_string [set last_search($id)];
    }
    
    set num_finds 0;
    if {[info exists last_positions($id)]} {
        set num_finds [llength $last_positions($id)];
    }
    if {$last_string  != $string } {
        set cmd "selre"
        lappend cmd $string;
        lappend loggedcommands $cmd;
        lappend new_loggedcommands $cmd;
    }
    if {$last_string  != $string || $sel_only  || [hasSelection] || !$num_finds || $dir == 1 } {
       set contexts [getLRContexts];
       set last_search($id) $string
       set last_positions($id) {}
       if {$remove_previous} {
           .t tag remove $tagname 1.0 end;
       }
       if {$string == ""} {
         return
       }
       set cur 1.0;
       set last_cur "";
       set got_sel 0;
       if {$sel_only || [hasSelection]} {
         catch {
          set cur [lindex [lindex [.t tag ranges sel] 0] 0];
         }
       }
       set final_sel_pos $cur ;
       set did_change 0;
       set num_found 0;
       set resultsWindow "";
       if {[string length $args]}  {
          # Check if a results window was passed
          set resultsWindow [lindex $args 0];
       } else {
           set resultsWindow [createResultsWindow "Search Results for $string"]
       }
       
       
       update;

       while 1 {
           if {$use_regex} {
               if {$case_sensitive} {
                     set cur [.t search -regexp -count length $string $cur end]
                } else {
                     set cur [.t search -regexp -nocase -count length $string $cur end]
                }
               } else {
               if {$case_sensitive} {
                     set cur [.t search -exact -count length $string $cur end]
                } else {
                     set cur [.t search -exact -nocase -count length $string $cur end]
                }
           }
           #puts "cur=$cur";
           if {$cur == "" || $cur == $last_cur} {
              break
           }
            set match_len [get_search_match_length .t $cur $string $use_regex $case_sensitive]
            if {![satisfiesContext $cur $match_len $contexts]} {
                 set cur [.t index "$cur + $match_len char"]
                continue;
            }
           set last_cur $cur;
           lappend last_positions($id) $cur
           change_yview $cur;
            if {$sel_only || [hasSelection]} {
                set curtag [.t tag names $cur];
                if {[lsearch $curtag "sel"] != -1} {
                    set got_sel 1;
                    set final_sel_pos $cur;
                    foreach tag $all_tags {
                      if {![regexp {(^target_)|(^hyperref_)} $tag]} {
                        .t tag remove $tag  $cur "$cur + $match_len char";
                      }
                    }  
                    .t tag add $tagname $cur "$cur + $match_len char"
                    incr num_found;
                    set did_change 1;
                } else {
                     if {$got_sel && ![hasMultiSelection]} {
                         break;
                     }
                }
            } else {
                foreach tag $all_tags { 
                   if {![regexp {(^target_)|(^hyperref_)} $tag]} {
                      .t tag remove $tag  $cur "$cur + $match_len char";
                     }
                 }
                   
               .t tag add $tagname $cur "$cur + $match_len char"
               incr num_found;
               set did_change 1;
            }
            set curParts [split $cur "."];
            set theLine [lindex  $curParts 0];
            set theCol [lindex  $curParts 1];
            set theText [.t get "$theLine.0" "$theLine.end"]
            $resultsWindow.results insert end "($theLine):($theCol):${string}:\t$theText\n" resultHyperlink;
            update;

            set cur [.t index "$cur + $match_len char"]
           } 
           # while 1
           if { $did_change } {
              .t edit separator;
           }
           set statusMessage "Found $num_found occurrences of ";
           append statusMessage $string;
           addToStatus $statusMessage;
          
           if {$sel_only || [hasSelection]} {
                change_yview $final_sel_pos; 
                .t tag remove highlight2 1.0 end;
                .t tag add highlight2 $final_sel_pos "$final_sel_pos + 1 char";
               
           }
    } elseif {$num_finds} {
       set curpos [.t index insert];
       if {$dir == 2} {
           for {set rotate($id) 0} {$rotate($id) < $num_finds} {incr rotate($id)} {
              if { [lindex [set last_positions($id)] [set rotate($id)]] > $curpos } {
                  set dir 0; 
                  break;
               }
            }
        }
        if {$dir == -2} {
           for {set rotate($id) [expr $num_finds - 1 ]} {$rotate($id) >= 0} {incr rotate($id) -1} {
              if { [lindex [set last_positions($id)] [set rotate($id)]] < $curpos } {
                   set dir 0;
                   break;
               }
            }
        }
        if {![info exists rotate($id)]} {
            set rotate($id) 0;
        } else {
            set rotate($id) [expr ([set rotate($id)] + ($dir)) % [llength [set last_positions($id)]]];
        }
        set newpos [lindex [set last_positions($id)] [set rotate($id)]];
        change_yview $newpos
        .t tag remove highlight2 1.0 end;
        .t tag add highlight2 $newpos "$newpos + 1 char";

    }

    .t tag raise $tagname;
    .t tag raise sel;
    .t tag raise highlight2;
    } msg;
    if {$msg ne ""} {
        addToStatus "search error: $msg";
    }
    #loadOverview;
    update;
}

proc applyWatermark {} {
    set types {
       {{PNG Files}      {.png}       }
       {{GIF Files}      {.gif}       }
       {{JPEG Files}     {.jpg .jpeg} }
       {{BMP Files}      {.bmp}       }
    }
    global installdir;
    global tmpdir;

    set fname [tk_getOpenFile -filetypes $types];
    if {$fname == ""} {
        return;
    }
    if {![file exists $fname]} {
        tk_messageBox -message "Cant find image file $fname";
        return;
    }

    show_text_input imagescale "-resize 50x40! -modulate 200,90" "Resize Scale" actually_apply_watermark 200 100 {} $fname;
    

}

proc trimSelection {} {

    if {[hasMultiSelection]} {
       set ranges [.t tag ranges sel];
       foreach {start end} $ranges {
           set linetext [.t get $start $end];
           .t fastdelete $start $end;
           .t insert $start [string trim $linetext];
       }
    } else {
       
       set ranges [.t tag ranges sel];
       foreach {start end} $ranges {
         set start [expr int($start)];
         set end   [expr int($end)];
         for {set line $start} {$line <= $end} {incr line} {
           set linetext [.t get $line.0 $line.end];
           .t fastdelete $line.0 $line.end;
           .t insert $line.0 [string trim $linetext];
         }
       }
    }
}

proc trimSelectionLeft {} {

    if {[hasMultiSelection]} {
       set ranges [.t tag ranges sel];
       foreach {start end} $ranges {
           set linetext [.t get $start $end];
           .t fastdelete $start $end;
           .t insert $start [string trimleft $linetext];
       }
    } else {
       
       set ranges [.t tag ranges sel];
       foreach {start end} $ranges {
         set start [expr int($start)];
         set end   [expr int($end)];
         for {set line $start} {$line <= $end} {incr line} {
           set linetext [.t get $line.0 $line.end];
           .t fastdelete $line.0 $line.end;
           .t insert $line.0 [string trimleft $linetext];
         }
       }
    }
}

proc delete_result_windows {} {
    global allResultWindows;
    foreach wnd $allResultWindows {
        catch {
            destroy $wnd;
        }
    }
     set allResultWindows {} 
}

proc trimSelectionRight {} {
    
    if {[hasMultiSelection]} {
       set ranges [.t tag ranges sel];
       foreach {start end} $ranges {
           set linetext [.t get $start $end];
           .t fastdelete $start $end;
           .t insert $start [string trimright $linetext];
       }
    } else {
       
       set ranges [.t tag ranges sel];
       foreach {start end} $ranges {
         set start [expr int($start)];
         set end   [expr int($end)];
         for {set line $start} {$line <= $end} {incr line} {
           set linetext [.t get $line.0 $line.end];
           .t fastdelete $line.0 $line.end;
           .t insert $line.0 [string trimright $linetext];
         }
       }
    }
}
proc applySyntax {type word start end tag} {
       set cur $start;
       set last_cur "";
       set exp $word;
       if {$type == "exact"} {
         set exp "\\m";
         append exp $word;
         append exp "\\M";
       }
       while 1 {
           set length 1;
           if {$type == "singlechar"} {
               set cur [.t search -exact -count length $exp $cur $end]
           } else {
               set cur [.t search -regexp -count length $exp $cur $end]
           }
           if {$cur == "" || $cur == $last_cur || $cur > $end } {
               break;
           }
           .t tag add $tag $cur "$cur + $length char";
           if {$length == 0} {
                incr length;
            }
            set cur "$cur + $length char";
           set last_cur $cur;
           
       }
}
#  (?s)^\s*(enum|class|struct)\s*[^\{]+\s*
#  (?s)^\s*(enum|class|struct|switch)\s*[^\{]+\s*   
proc satisfiesLeftContext {pos len negate lc} {
     set startline [expr int($pos) - 5];
     if {$startline < 1} {
         set startline 1;
     }

     set txt [.t get ${startline}.0  [.t index "$pos + $len char"] ];
     #puts stderr "<<<<$txt>>>>";
     set lc1 "(?s).*"
     append lc1 $lc;
     append lc1 "\$";
     if {[regexp $lc1 $txt]} {
         if {$negate} {
             return 0;
         } else {
             return 1;
         }
     } else {
         if {$negate} {
             return 1;
         } else {
             return 0;
         }

     }
}


proc getLRContexts {} {
   set result {};

   set lc [.bottomFrame.enforceLC get];
   if {[string length $lc] == 0} {
      lappend result {} ;
      lappend result {} ;
   } else {
   set negate 0;
   if {[string index $lc 0] == "-"} {
       if {[string index $lc 1] != "-"} {
         set lc [string range $lc 1 end];
         set negate 1;
       } else {
         #two leading "-"s will be regarded as one leading "-"
         set lc_original [string range $lc 1 end];
         set lc "\\";
         append lc $lc_original;
       }
   }
   lappend result $negate;
   lappend result $lc;
   }

   set rc   [.bottomFrame.enforceRC get];
   if {[string length $rc] == 0} {
      lappend result {} ;
      lappend result {} ;
   } else {
   set negate 0;
   if {[string index $rc 0] == "-"} {
       if {[string index $rc 1] != "-"} {
         set rc [string range $rc 1 end];
         set negate 1;
       } else {
         #two leading "-"s will be regarded as one leading "-"
         set rc_original [string range $rc 1 end];
         set rc "\\";
         append rc $rc_original;
       }

   }
   lappend result $negate;
   lappend result $rc;
   }

   return $result
}
proc satisfiesRightContext {pos len negate rc} {
   #puts -nonewline stderr "."
  
   set start [.t index "$pos + $len  char"];
   #puts stderr "start $start"
   set found [.t search -regexp -count length $rc $start end];
   #puts stderr "found $found";
   if {$found ==  $start } {
        if {$negate} {
            return 0;
        } else {
            return 1;
        }
    } else {
       if {$negate} {
            return 1;
        } else {
            return 0;
        } 
    }

}

proc satisfiesContext {pos len contexts}  {

    set negatelc [lindex $contexts 0];
    set lc [lindex $contexts 1];
    set negaterc [lindex $contexts 2];
    set rc [lindex $contexts 3];
    set result 1;
    if {$negatelc != ""} {
        set result [expr $result && [satisfiesLeftContext $pos $len $negatelc $lc]];
    }
    if  {$negaterc != ""} {
        set result [expr $result && [satisfiesRightContext $pos $len $negaterc $rc]];
    }
    return $result;
}


proc simpleReplace {replace with {quiet 0}} {
   if {$replace == ""} {
       return;
   }
   
   set slave "";

   set init  "";
   set incr  "";
   set subst "";
   set expr  ""; 

   global sel_only;
   set do_sel_only $sel_only;
   if {[hasSelection]} {
       set do_sel_only 1;
   }
   set contexts [getLRContexts];
   
   .t tag raise highlight2;
   set cur 1.0;
   
   set num 0;
   .t configure -autoseparators 0;
   .t edit separator;

   if {$do_sel_only} {
       set selranges [.t tag ranges sel];
       foreach {start end} $selranges {
           incr num [doSingleReplacement $start $end $replace $with $init $incr $subst $expr $contexts $slave $do_sel_only]
       }
   } else {
       incr num [doSingleReplacement $cur end $replace $with $init $incr $subst $expr $contexts $slave $do_sel_only];
   }
   if {!$quiet} {
      tk_messageBox -message "$num replacements were made";
   }
   .t edit separator;
   .t configure -autoseparators 1;

}


proc simpleReplaceLineRange {startline endline replace with} {
   set slave [::safe::interpCreate];

   if {$replace == ""} {
       return;
   }
   

   set init  "";
   set incr  "";
   set subst "";
   set expr  ""; 

   interp alias $slave guid {} guid

   .t tag remove sel 1.0 end;
   .t tag add sel "$startline.0" "$endline.end";

   global sel_only;
   set do_sel_only $sel_only;
   if {[hasSelection]} {
       set do_sel_only 1;
   }
   set contexts [getLRContexts];
   
   .t tag raise highlight2;
   set cur 1.0;
   
   set num 0;
   .t configure -autoseparators 0;
   .t edit separator;


   if {$do_sel_only} {
       set selranges [.t tag ranges sel];
       foreach {start end} $selranges {
           incr num [doSingleReplacement $start $end $replace $with $init $incr $subst $expr $contexts $slave $do_sel_only]
       }
   } else {
       incr num [doSingleReplacement $cur end $replace $with $init $incr $subst $expr $contexts $slave $do_sel_only];
   }
   
   tk_messageBox -message "$num replacements were made";
   .t edit separator;
   .t configure -autoseparators 1;
   ::safe::interpDelete $slave;
}

proc shuffle {data} {
    set length [llength $data]
    for {} {$length > 1} {incr length -1} {
        set idx_1 [expr {$length - 1}]
        set idx_2 [expr {int($length * rand())}]
        set temp [lindex $data $idx_1]
        lset data $idx_1 [lindex $data $idx_2]
        lset data $idx_2 $temp
    }
    return $data
}

proc doReplacement {} {

   global loggedcommands;
   global new_loggedcommands;
   set replace [.bottomFrame.replace get];
   set with    [.bottomFrame.with get];
   set init    [.bottomFrame.init get];
   set incr    [.bottomFrame.incr get];
   set subst   [.bottomFrame.subst get];
   set expr    [.bottomFrame.expr get];

   if {[catch {substitute $replace $with $init $incr $subst $expr} err]} {
       tk_messageBox -message "Computed replace failed:\n$err";
       return;
   }

   set cmd substitute;
   lappend cmd $replace $with $init $incr $subst $expr;
   lappend loggedcommands $cmd;
   lappend new_loggedcommands $cmd;

}

proc get_all_filenames {} {
   set input [.t get 0.0 end];
    set input_lines [split $input "\n"];
    set editorline 0;
    array set files_done {};
    #tk_messageBox -message "About to start processing $time1 $time2";
    set all_files {};
    foreach input_line $input_lines {
        update;
        incr editorline;
        set input_line [regsub -all {\\} $input_line {/}];
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
         set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        if {[info exists files_done($loc_file)]} {
            continue;
        }
    
        set files_done($loc_file) 1;
        if {[file exists $loc_file] && ![file isdirectory $loc_file]} {
            lappend all_files $loc_file;
        }
     }
     return $all_files;
}

proc puts_list {lst} {
    foreach item $lst {
        puts $item;
    }
}
proc sort_selected {args} {
    set selranges [.t tag ranges sel];
    set list {};
    foreach { start end }  $selranges {
        set txt [.t get $start $end];
        lappend list $txt;
    }
    return [lsort {*}$args $list];
}


proc add_sel_as_notes {} {
    set selranges [lreverse  [.t tag ranges sel]];
    foreach { end start }  $selranges {
        set txt [.t get $start $end];
        create_note $end $txt;
    }
}


proc sort_lines {{start 1.0} {end end}} {
    sort_lines_aux $start $end;
}
proc sort_lines_aux {sortstart sortend} {
   set input [.t get $sortstart $sortend];
    set input_lines [split $input "\n"];
    set editorline 0;
    array set files_done {};
    #tk_messageBox -message "About to start processing $time1 $time2";
    foreach input_line $input_lines {
        update;
        incr editorline;
        catch {
        set input_line [regsub -all {\\} $input_line {/}];
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
        set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        if {[info exists files_done($loc_file)]} {
            append files_done($loc_file) " " $loc_line ;
          } else {
            set files_done($loc_file) $loc_line ;
          } 
        }
     }

     set names [array names files_done];
     foreach name $names {
          set lines [set files_done($name)];
          catch {
            set lines_ordered [lsort -integer $lines];
            foreach line $lines_ordered {
              puts "${name}:${line}:"
            }
          }
     }

     return "";
}


proc save_html_files {} {
  set input [.t get 0.0 end];
  set all_files [get_all_filenames];
  foreach file $all_files {
       edit $file;
       saveColocatedHtml;
       edit:close;
  }
   tk_messageBox -message "Done : Saved html files";
  .t fastdelete 1.0 end;
   .t insert 1.0 $input;
   return "";  
}



proc delete_notes_in_files {} {
  set input [.t get 0.0 end];
  set all_files [get_all_filenames];
  foreach file $all_files {
       edit $file;
       delete_notes;
       save;
       edit:close;
  }
   tk_messageBox -message "Done : Deleted notes in files";
  .t fastdelete 1.0 end;
   .t insert 1.0 $input;
   return "";  
}

proc save_context_annotated_html {{save_or_nosave {}} {instr_regex {mprewriter..?scope_START!?\((\d+)\)}}} {
  set input [.t get 0.0 end];
  set all_files [get_all_filenames];
  foreach file $all_files {
       edit $file;
       set resultsWindow [annotate_contexts $instr_regex];
       set resultsTxt [string trim [$resultsWindow.results get 1.0 end]];
       if {$resultsTxt != ""} {
           addToStatus "\n$file:1: ANNOTATED"
       }
       insertResultsAsNotes $resultsWindow
       saveColocatedHtml;
       if {${save_or_nosave} == "save"} {
           saveFile .t;
           edit:close;
       } elseif {${save_or_nosave} == "nosave"} {
           edit:closeNoAsk;
       } else {
           edit:close;
       }
       
       catch "destroy  $resultsWindow";
  }
  tk_messageBox -message "Done : Saved context annotated html files";
  .t fastdelete 1.0 end;
   .t insert 1.0 $input;
   return "";
}

proc save_context_annotated_ehtml {{save_or_nosave {}} {instr_regex {mprewriter..?scope_START!?\((\d+)\)}}} {
  set input [.t get 0.0 end];
  set all_files [get_all_filenames];
  foreach file $all_files {
       edit $file;
       set resultsWindow [annotate_contexts $instr_regex];
       set resultsTxt [string trim [$resultsWindow.results get 1.0 end]];
       if {$resultsTxt != ""} {
           addToStatus "\n$file:1: ANNOTATED"
       }
       insertResultsAsNotes $resultsWindow
       saveColocatedEHtml;
       if {${save_or_nosave} == "save"} {
           saveFile .t;
           edit:close;
       } elseif {${save_or_nosave} == "nosave"} {
           edit:closeNoAsk;
       } else {
           edit:close;
       }
       
       catch "destroy  $resultsWindow";
  }
  tk_messageBox -message "Done : Saved context annotated html files";
  .t fastdelete 1.0 end;
   .t insert 1.0 $input;
   return "";
}


proc save_coverage_annotated_html {{save_or_nosave {}} {instr_regex {mprewriter..?scope_START!?\((\d+)\)}}} {
  set input [.t get 0.0 end];
  set all_files [get_all_filenames];
  foreach file $all_files {
       edit $file;
       set resultsWindow [annotate_coverage $instr_regex];
       
       set resultsTxt [string trim [$resultsWindow.results get 1.0 end]];
       if {$resultsTxt != ""} {
           addToStatus "\n$file:1: ANNOTATED";
           
       }
       
       insertResultsAsNotes $resultsWindow
       saveColocatedHtml;
       
       if {${save_or_nosave} == "save"} {
           saveFile .t;
           edit:close;
       } elseif {${save_or_nosave} == "nosave"} {
           edit:closeNoAsk;
       } else {
           edit:close;
       }
       
       catch "destroy  $resultsWindow";
  }
  tk_messageBox -message "Done : Saved coverage annotated html files";
  .t fastdelete 1.0 end;
  .t insert 1.0 $input;
   return "";
}


proc complete_filenames {root_path} {
    set input [.t get 0.0 end];
    
    set input_lines [split $input "\n"];
    set editorline 0;
    array set files_done {};
    #tk_messageBox -message "About to start processing $time1 $time2";
    set all_files {};
    foreach input_line $input_lines {
        update;
        incr editorline;
        set input_line [regsub -all {\\} $input_line {/}];
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
         set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        set  loc_remaining [regsub -all {^[ \t]*.:?[^\(:]*[\(:][0-9]*[:\)](.*)} $input_line {\1}];
        if {[regexp {[<>]} $loc_file]} {
            continue;
        }

        set find_results "";
        catch {
           set find_results [exec "[installdir]/wbin/find.exe" $root_path -name $loc_file -print];
        } msg;
        if {$msg != ""} {
            addToStatus $msg;
        }
        set find_results [split $find_results "\n"];
        set full_names {};
        foreach find_result $find_results {
            set find_result [regsub -all {\\} $find_result {/}];
            if {[file exists $find_result]} {
                lappend full_names $find_result;
            }
        }
        if {[llength $full_names] > 1} {
            addToStatus "multiple matches found for line $editorline";
        }
        if {[llength $full_names] > 0} {
            .t delete $editorline.0 $editorline.end;
        }
        set repcount 0;
        foreach full_name $full_names {
            incr repcount;
            if {$repcount > 1} {
              incr editorline;
              .t insert $editorline.0 "$full_name:$loc_line:$loc_remaining\n" "#fd9f9f";
               
            } else {
              .t insert $editorline.0 "$full_name:$loc_line:$loc_remaining";   
            }
        }

     }
     tk_messageBox -message "Done";
}



proc substitute_in_files {} {
   set slave [::safe::interpCreate];
   set replace [.bottomFrame.replace get];
   set with    [.bottomFrame.with get];
   set init    [.bottomFrame.init get];
   set incr    [.bottomFrame.incr get];
   set subst   [.bottomFrame.subst get];
   set expr    [.bottomFrame.expr get];

   if {$replace == ""} {
       return;
   }

   set input [.t get 0.0 end];
   
   interp alias $slave guid {} guid
   catch {
       $slave eval $init;
   }
   .t tag raise highlight2;
   
   set num 0;
   .t configure -autoseparators 0;
   .t edit separator;
   set num_substs 0;
   ##### Go through the list of files #####
    set all_files [get_all_filenames];
    foreach file $all_files {
       edit $file;
       incr num_substs [substitute_in_file $file $slave $replace $with $init $incr $subst $expr];
       save;
       edit:close;
    }
   ########################################
   .t edit separator;
   .t configure -autoseparators 1;
   ::safe::interpDelete $slave;
   tk_messageBox -message "Number of substitutions: $num_substs";
   .t fastdelete 1.0 end;
   .t insert 1.0 $input;
   return "";
}

proc substitute_in_file {filename slave replace with init incr subst expr} {
   set contexts [getLRContexts];
   global update_frozen;
   set update_frozen 1;
   
   set num [doSingleReplacement 1.0 end $replace $with $init $incr $subst $expr $contexts $slave 0];
   
   set update_frozen 0;
   update; 

   return $num;
}

proc execute_on_files {cmd} {
   set slave [::safe::interpCreate];
   set replace [.bottomFrame.replace get];
   set with    [.bottomFrame.with get];
   set init    [.bottomFrame.init get];
   set incr    [.bottomFrame.incr get];
   set subst   [.bottomFrame.subst get];
   set expr    [.bottomFrame.expr get];

   if {$replace == ""} {
       return;
   }

   set input [.t get 0.0 end];
   
   interp alias $slave guid {} guid
   catch {
       $slave eval $init;
   }
   .t tag raise highlight2;
   
   set num 0;
   .t configure -autoseparators 0;
   .t edit separator;
   set num_substs 0;
   ##### Go through the list of files #####
    set all_files [get_all_filenames];
    foreach file $all_files {
       edit $file;
       eval "$cmd $file";
       save;
       edit:close;
    }
   ########################################
   .t edit separator;
   .t configure -autoseparators 1;
   ::safe::interpDelete $slave;
   tk_messageBox -message "Finished!";
   .t fastdelete 1.0 end;
   .t insert 1.0 $input;
   return "";
}



proc substitute {replace with init incr subst expr} {
   set slave [::safe::interpCreate];

  

   if {$replace == ""} {
       return;
   }
   
   interp alias $slave guid {} guid
   catch {
       $slave eval $init;
   }
   global sel_only;
   set do_sel_only $sel_only;
   if {[hasSelection]} {
       set do_sel_only 1;
   }
   set contexts [getLRContexts];
   
   .t tag raise highlight2;
   set cur 1.0;
   
   set num 0;
   .t configure -autoseparators 0;
   .t edit separator;
   global update_frozen;
   set update_frozen 1;
   if {$do_sel_only} {
       set selranges [.t tag ranges sel];
       set numsels [expr [llength $selranges] / 2];
       for {set ii 0} {$ii < $numsels} {incr ii} {
           set selranges [.t tag ranges sel];
           set start [lindex $selranges [expr 2*$ii]];
           set end   [lindex $selranges [expr 2*$ii+1]];
           incr num  [doSingleReplacement $start $end $replace $with $init $incr $subst $expr $contexts $slave $do_sel_only];
      } 
   } else {
       incr num [doSingleReplacement $cur end $replace $with $init $incr $subst $expr $contexts $slave $do_sel_only];
   }
   set update_frozen 0;
   update; 
   tk_messageBox -message "$num replacements were made";
   .t edit separator;
   .t configure -autoseparators 1;
   ::safe::interpDelete $slave;
}

array set jmcoverage {};
proc jmtrace {n} {
    global jmcoverage;
    if {![info exists jmcoverage($n)]} {
       set jmcoverage($n) 1;
    } else {
        incr jmcoverage($n);
    }

}
proc jmdebug {str} {
    puts stderr $str;
}

proc position_gt {p1 p2} {
   set p1x [split $p1 "."];
   set p2x [split $p2 "."];
   if {[lindex $p1x 0] > [lindex $p2x 0]} {
      return 1;
   } elseif {[lindex $p1x 0] == [lindex $p2x 0]} {
      return [expr [lindex $p1x 1] > [lindex $p2x 1]];
   }
   return 0;
}


proc doSingleReplacement {cur end replace with init incr subst expr contexts slave do_sel_only} {
   #jmtrace doSingleReplacement;
   #jmdebug "searching $cur -> $end"
   set num 0;
   set match_ending 0;
   if { [string index $replace end] == {$} } {
       set match_ending 1;
   }
   
   set lastcur "";
   set lastlen 1e20;
   set tmp 0;

   while 1 { 
       #jmtrace while_1;
       incr tmp;
       if {$tmp > 1000000} break;
       set cur [.t search -regexp -count length $replace $cur $end];
       if {$cur == ""} {
           break;
       }
       
       set len [string length [.t get $cur end]];

       if {$end != "end" && [position_gt $cur $end]} {
           break;
       }
       

       if {$cur == $lastcur && $len >= $lastlen} {
           set cur [.t index "$cur + 1 char"];
           if {$cur == $lastcur} {
               break;
           }
       }
       if {$len > $lastlen} {
           break;
       }
       set lastlen $len;
       set lastcur $cur;
       set newoffset $length;
       set done_modification 0;
       if { (!$do_sel_only) || ($do_sel_only && ([lsearch [.t tag names $cur] sel] != -1))} {
           if {[satisfiesContext $cur $length $contexts]} {
               set match [.t get $cur "$cur + $length char"];
               set new_with $with;
               catch {
                   if {$slave != ""} {
                   catch {
                     $slave eval "set match \"$match\"";
                   }

                   $slave eval $incr;
                   
                   set val [$slave eval $expr];
                   regsub -all $subst $with $val new_with
                 }
               }
               if {$match == ""} {
                   set match $new_with;
               } else {
                   regsub -all $replace $match $new_with match;
               }
               set newoffset [string length $match];
               .t fastdelete $cur "$cur + $length char";
               .t fastinsert $cur $match; 
               .t tag add highlight2 $cur "$cur + $newoffset char";
               if {$newoffset == 0  && $length == 0} {
                   set newoffset 1; 
               }
                incr num;
                set done_modification 1;
            }
       }
       if {!$done_modification && $newoffset == 0} {set newoffset 1;};
       if {$match_ending} {incr newoffset}; 
       if {$done_modification && ([string index $replace 0] == "^")}  {
           set thisline [lindex [split $cur "."] 0];
           set cur [.t index "$thisline.end"];
       }  else {
           set cur [.t index "$cur + $newoffset char"];
       }
 
   }
   return $num;
}

proc guid {} {
    return [randString];
  #return [uuid::uuid generate];
}




proc load_more_lines_at_sel {before after} {
    set ranges [.t tag ranges sel];
    foreach {end1 start1} [lreverse $ranges] {
       set start [expr int($start1)];
       set end   [expr int($end1)];
       for {set line $end} {$line >= $start} {incr line -1} {
            catch {
               load_more_lines_aux $before $after ${line}.0 ${line}.end;
            }
       }
    }
}

proc load_more_lines {before after} {
    set inspos [.t index insert];
    set linestart [.t index "$inspos linestart"];
    set lineend  [.t index "$inspos lineend"];
    load_more_lines_aux $before $after $linestart $lineend;
    
}
proc load_more_lines_aux {before after linestart lineend} {

    set input_line [.t get $linestart $lineend];
    set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
    set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
    if {![file exists $loc_file]} {
        addToStatus "File <$loc_file> was not found";
        return;
    }
    .t delete $linestart $lineend;
    
    set first_line [expr $loc_line - ($before)];
    set last_line [expr $loc_line + ($after)];
    set lnum 0;
    set fp [open $loc_file r];
    set cnt 0;
    while {![eof $fp]} {
        set line [gets $fp];
        incr lnum;
        if {$lnum >= $first_line && $lnum <= $last_line} {
            .t insert [expr $cnt + $linestart] "${loc_file}:${lnum}:${line}\n" sel
            incr cnt;
        } elseif { $lnum > $last_line } {
            break;
        }     
    }
    close $fp; 
}

proc delete_grepline_from_file {} {
    set curpos [.t index insert];
    set linestart [.t index "$curpos linestart"];
    set lineend [.t index "$curpos lineend"];
    set input_line [.t get $linestart $lineend];
    set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
    set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
    if {![file exists $loc_file]} {
        addToStatus "File <$loc_file> was not found";
        return;
    }
    set success [delete_lines_in_file $loc_file $loc_line 1];
    if {! $success } {
        addToStatus "Failed to delete line from file";
        return;
    }
    visit_re_quiet "^${loc_file}:\\d+:" increment_impacted_grep_lines $loc_line -1;   
}

proc insert_line_after_grepline {offset} {

    set curpos [.t index insert];
    set linestart [.t index "$curpos linestart"];
    set lineend [.t index "$curpos lineend"];
    set input_line [.t get $linestart $lineend];
    set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
    set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
    if {![file exists $loc_file]} {
        addToStatus "File <$loc_file> was not found";
        return;
    }
    set success [insert_newline $loc_file [expr $loc_line +($offset)] 1];
    if {! $success } {
        addToStatus "Failed to insert newline";
        return;
    }
    visit_re_quiet "^${loc_file}:\\d+:" increment_impacted_grep_lines [expr $loc_line +($offset)] 1;
    set line [lindex [split $linestart "."] 0];
    set insertline [expr $line+1+($offset)];
    .t insert "$insertline.0" "$loc_file:[expr $loc_line + 1 +($offset)]:\n"
}

proc delete_lines_in_file {fname n {m 1}} {
    # Open the file for reading
    set inFile [open $fname r]
    set lines [split [read $inFile] "\n"]
    close $inFile

    # Ensure n and m are within bounds
    set numLines [llength $lines]
    if {$n <= 0 || $n > $numLines} {
        return 0;
    }
    if {$m < 0} {
        error "Range of lines to delete is out of bounds"
        return 0;
    }

    # Remove m lines starting from the nth line
    set lines [lreplace $lines [expr {$n - 1}] [expr {$n + $m - 2}]]

    # Open the file for writing and write back all lines
    set outFile [open $fname w]
    puts $outFile [join $lines "\n"]
    close $outFile
    return 1;
}

proc insert_newline {fname n {m 1}} {
    # Open the file for reading
    set inFile [open $fname r]
    set lines [split [read $inFile] "\n"]
    close $inFile

    # Ensure n is within the bounds
    if {$n <= 0 || $n > [llength $lines]} {

        return 0;
    }

    # Insert a newline at the nth line
    set replacepos [expr {$n - 1}]
    set line [lindex $lines $replacepos];
    append line [string repeat "\n" $m];
    set lines [lreplace $lines $replacepos $replacepos $line]

    # Open the file for writing and write back all lines
    set outFile [open $fname w]
    puts $outFile [join $lines "\n"]
    close $outFile
    return 1;
}

proc increment_impacted_grep_lines {regex cur end source_line increment} {
    addToStatus "increment_impacted_grep_lines $cur $end $source_line"
    set input_line [.t get $cur $end];
    set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
    set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
    if {$loc_line > $source_line} {
        .t delete $cur $end;
       
        .t insert $cur "$loc_file:[expr $loc_line+($increment)]:";
        
    }
}

proc add_ref_to_listed_files {} {
    set input [.t get 0.0 end];
    
    set input_lines [split $input "\n"];
    set editorline 0;
    array set files_done {};
    set all_files {};
    foreach input_line $input_lines {
        update;
        incr editorline;
        set input_line [regsub -all {\\} $input_line {/}];
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
        set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:]?.*} $input_line {\1}];

        if {![file exists $loc_file]} {
          continue;
        }
        add_file_at "${editorline}.end"  $loc_file;
     }
     tk_messageBox -message "Done";
}

proc load_sample_lines {before after {marker {}}} {
    set input [.t get 0.0 end];
    
    set input_lines [split $input "\n"];
    set editorline 0;
    array set files_done {};
    #tk_messageBox -message "About to start processing $time1 $time2";
    set all_files {};
    foreach input_line $input_lines {
        update;
        incr editorline;
        set input_line [regsub -all {\\} $input_line {/}];
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
         set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        set  loc_remaining [regsub -all {^[ \t]*.:?[^\(:]*[\(:][0-9]*[:\)](.*)} $input_line {\1}];
        if {[regexp {[<>]} $loc_file]} {
            continue;
        }
        if {![file exists $loc_file]} {
          continue;
        }
        catch {
            set first_line [expr $loc_line - ($before)];
            set last_line [expr $loc_line + ($after)];
            set lnum 0;
            set fp [open $loc_file r];
            set sample "";
            while {![eof $fp]} {
                incr lnum;
                set sample_line [gets $fp];
                if {$lnum >= $first_line && $lnum <= $last_line} {
                    if {$lnum == $loc_line} {
                        append sample $marker;
                    }
                    append sample  $sample_line "\n";
                } elseif { $lnum > $last_line } {
                    break;
                }     
            }
            close $fp;
            if {$sample != ""} {
                create_note "${editorline}.end" $sample;
            }
        }
        
     }
     tk_messageBox -message "Done";
}


proc trace_locations {} {
    global file_lookup;
    set resultsWindow [createResultsWindow "Trace locations"];
    set ranges [.t tag ranges sel];
    if {$ranges == {} } {
        set ranges {1.0 end};
    }
    foreach {start end} $ranges {
       set cur $start;
       set last_cur "";
       while 1 {
        set cur [.t search -regexp -count length "<T" $cur $end];
        if {$cur == "" || $cur == $last_cur} {
              break
           }
        set matchline [.t get "$cur linestart" "$cur lineend"];
        #addToStatus $matchline
        if {[regexp  {^:\d+<T\d+>} $matchline]} {
            set tagnum "";
            regsub -all {^:\d+<T(\d+)>.*} $matchline {\1} tagnum;
            #addToStatus $tagnum;
            if {[info exists file_lookup($tagnum)]} {
              set file_loc [set file_lookup($tagnum)];
              #addToStatus $file_loc;
              #TODO this might need to change for linux
              set file_name [regsub -all {^[ \t]*(.:[^\(:]*)[\(:].*} $file_loc {\1}];
              set file_line [regsub -all {^[ \t]*.:[^\(:]*[\(:]([0-9]*)[:\)].*} $file_loc {\1}];
              $resultsWindow.results insert end "$file_name:${file_line}:$matchline";
              $resultsWindow.results insert end "\n"; 
            } else {
              $resultsWindow.results insert end "not_found\(0\):$matchline";
              $resultsWindow.results insert end "\n"; 
              }
            }
        set last_cur $cur;
        set cur [.t index "$cur lineend"];
       } 
    }  
}

proc call_stack_from_reversed_trace_file {fname startline} {
    set fp [open $fname r];
    set result "";
    set lnum 0;
    while {![eof $fp]} {
        
        set line [gets $fp];
        incr lnum;
        if { $lnum < $startline } {
            continue;
        } elseif {$lnum == $startline} {
            
            set depthstr {};
            regsub -all "^:(\\d+)<T.*" $line {\1} depthstr;
            if {![regexp {^\d+$} $depthstr]} {
                error "start line is not a stack marker";
                break;
            }
            set depth [string length $depthstr];
            incr depth -1;
            append result $line " " $lnum "\n";
            continue;
        }
        set expr ":(\\d\{1,$depth\})<T.*";
        set depthstr {};
        regsub -all $expr $line {\1} depthstr;
        if {![regexp {^\d+$} $depthstr]} {
            continue;
        }
        set depth [string length $depthstr];
        incr depth -1;
        append result $line " " $lnum "\n";
        if {$depth < 1} break;
    }
    close $fp;
    return $result;
}

proc get_linenumbers_with_tag_in_trace_file {fname tags} {
    array set tag_found {}
    foreach tag $tags {
        set tag_found($tag) 0;
    }
    set tags_left $tags;
    set fp [open $fname r];
    set result "";
    set lnum 0;
    while {![eof $fp]} {
        
        set line [gets $fp];
        incr lnum;
        foreach tag $tags_left {
            if {[regexp $tag $line]} {
                set tag_found($tag) $lnum;
            
                lremove tags_left $tag;
                if {[llength $tags_left] == 0} {
                    close $fp;
                    return [array get tag_found];
                }
            }
        }
    }
    close $fp;
    
    return [array get tag_found];    
    
}

proc callStackOld {pos} {
  set resultsWindow [createResultsWindow "Stack Frame"]
  set word "\n:[.t get "$pos wordstart" "$pos wordend"]<T";
  set startpos [.t index "$pos wordstart"];
  set word "[string range $word 0 end-3]<T";
  #puts stderr "word=\"$word\"";
  set cur $startpos;
  set splitStart [split $cur "."];
  set theLine [lindex $splitStart 0];
  set theCol [lindex $splitStart 1];
  $resultsWindow.results insert end "($theLine):($theCol): " resultHyperlink;
  set line [.t get "$theLine.0" "$theLine.end"];
  .t tag add sel  "$theLine.0" "$theLine.end";
  $resultsWindow.results insert end "$line\n" resultShow;
  
  
  while {1} {
     #addToStatus "cur=<$cur> word=<$word>\n"
     set oldcur $cur;
     set cur  [.t search  -backwards $word $oldcur 1.0];
     if {$cur == ""} {
         break;
     }
     set shortened "[string range $word 0 end-3]<T";
     set shortened_cur  [.t search  -backwards $shortened $oldcur 1.0];
     if {$shortened_cur == ""} {
               set shortened_cur  1.0
     }
     #puts "shortened_cur $shortened_cur";
   


     if {$cur == ""} {
         break;
     }
     set cur [.t index "$cur + 1 char"];
      if {$cur == ""} {
         break;
     }
     set splitStart [split $cur "."];
     set theLine [lindex $splitStart 0];
     set theCol [lindex $splitStart 1];

     $resultsWindow.results insert end "($theLine):($theCol): " resultHyperlink;
     set line [.t get "$theLine.0" "$theLine.end"];
     .t tag add sel  "$theLine.0" "$theLine.end";
     $resultsWindow.results insert end "$line\n" resultShow;

     set word $shortened;
     #puts stderr "word=\"$word\"";
     if {$word == ":<"} {
         break;
     }
   }
   [$resultsWindow.results component text] tag bind resultShow <ButtonRelease-1> {
     set pos [%W index "@%x,%y"];
     load_tag %W $pos load_tag;
  }

}


proc callStack {pos} {
    set resultsWindow [createResultsWindow "Stack Frame"];
    myStackHelper $pos $resultsWindow;
    
   [$resultsWindow.results component text] tag bind resultShow <ButtonRelease-1> {
     set pos [%W index "@%x,%y"];
     load_tag %W $pos load_tag;
   }
}

proc myStackHelper  {pos resultsWindow} {
  
  if {$pos == ".0"} {
      return;
  }
  set lnum0 [lindex [split $pos "."] 0]
  set line0 [.t get "$lnum0.0" "$lnum0.end"];
  #puts $line0;
  if {![regexp {^(:[0-9]*)<.*} $line0]} {
      return;
  }
  regsub -all {^(:[0-9]*)<.*} $line0 {\1} linedepth0;
  #puts $linedepth0;
  set thread0 "";
  if {[regexp { from thread (\d+) } $line0]} {
      regsub -all {^.* from thread (\d+) .*$} $line0 {\1} thread0;
  }

  #puts "thread0=$thread0";

  
  $resultsWindow.results insert end "($lnum0):(0): " resultHyperlink;
  .t tag add sel  "$lnum0.0" "$lnum0.end";
  $resultsWindow.results insert end "$line0\n" resultShow;

  set depth0 [string length $linedepth0];
  for {set i [expr $lnum0-1]} {$i > 0} {incr i -1} {
       set line1 [.t get "$i.0" "$i.end"];
       if {![regexp {^(:[0-9]*)<.*$} $line1]} {
          continue;
       }
       regsub -all {^(:[0-9]*)<.*$} $line1 {\1} linedepth1;
       set thread1 "";
       if {[regexp { from thread (\d+) } $line1]} {
          regsub -all {^.* from thread (\d+) .*$} $line1 {\1} thread1;
       }
       #puts "thread1=$thread1";
       set depth1 [string length $linedepth1];
       if {$thread1 != $thread0} {
           continue;
       }
       if {$depth1 < $depth0} {
           myStackHelper "$i.0" $resultsWindow;
           return; 
       }    
  }
}


proc hyperlink_to_selected {start end} {
    setSelectedWordsAsTargets $start $end;
}


proc setSelectedRegionAsTargetsForHighlights {id} {
    set selranges [.t tag ranges sel];
    set num [expr [llength $selranges] / 2];
    if {$num > 1} {
      tk_messageBox -message "Multiple selections - ambiguous target";
      return;
    }
    if {$num == 0} {
      tk_messageBox -message "No selection - target is not specified";
      return;
    }
    set count 0;
    set selstart [lindex $selranges 0];
    set selend   [lindex $selranges 1];

    global fixed_boxes;
    global currentColor;
    array set preset_colors $fixed_boxes;
    set col "";
    if {$id == 6} {
        set col $currentColor;
    } else {
        set col [set preset_colors($id)];
    }

    set ranges [.t tag ranges $col];
    set randword [randString];
    set tagname "hyperref_${randword}"
    .t tag add "target_${randword}" $selstart $selend;
    .t tag bind "hyperref_${randword}" <Control-ButtonRelease-1> "followTarget $randword"
    .t tag configure  "hyperref_${randword}" -underline 1;

    global replace_existing_hyperlinks;

    foreach {start end} $ranges {
          
         set clashes 0;
         foreach existing [.t tag names $start] {

             if { [string range $existing 0 8] == "hyperref_"} {
                 set clashes 1;
                 if {$replace_existing_hyperlinks} {
                     .t tag remove $existing $start $end;
                 }
             }

         }
         if {$clashes && !$replace_existing_hyperlinks} { 
         } else {
            .t tag add $tagname $start $end;
         }
    }
}



proc  setLastSelectionAsHyperlinkTarget {} {
     
     set selranges [.t tag ranges sel];
     if {[llength $selranges] < 4} {
         puts "At least 2 selections are needed";
         return;
     }
     set insertpos [.t index insert];
     
     set target_start "";
     set target_end "";
     set found_target 0;
     foreach {start end} $selranges {
        if {($start == $insertpos) ||
            ($end == $insertpos)  ||
            ([.t index "$start + 1c"] == $insertpos)  ||
            ([.t index "$end + 1c"] == $insertpos)  ||
            ([.t index "$start - 1c"] == $insertpos)  ||
            ([.t index "$end - 1c"] == $insertpos) } {
            set found_target 1;
            set target_start $start;
            set target_end $end;
            break;
        }
      }
    if {!$found_target} {
          puts "Could not decide hyperlink target";
          return;
      }

     set randword [randString];
     set tagname "hyperref_${randword}"
    .t tag bind $tagname <Control-ButtonRelease-1> "followTarget $randword"
    .t tag configure  $tagname -underline 1;

    global replace_existing_hyperlinks;
    foreach {start end} $selranges {
        if {$start == $target_start  && $end == $target_end}  {
              .t tag add "target_${randword}" $start $end;
        } else {
               
         set clashes 0;
         foreach existing [.t tag names $start] {
             if { [string range $existing 0 8] == "hyperref_"} {
                 set clashes 1;
                 if {$replace_existing_hyperlinks} {
                     .t tag remove $existing $start $end;
                 }
             }
         }
         if {$clashes && !$replace_existing_hyperlinks} { 
         } else {
            .t tag add $tagname $start $end;
         }
           
        } 
    }
}



proc  setFirstSelectionAsHyperlinkTarget {} {
     
     set selranges [.t tag ranges sel];
     if {[llength $selranges] != 4} {
         puts "Exactly 2 selections are needed";
         return;
     }
     set insertpos [.t index insert];
     
     set source_start "";
     set source_end "";
     set found_source 0;
     set target_start "";
     set target_end "";
     foreach {start end} $selranges {
        if {($start == $insertpos) ||
            ($end == $insertpos)  ||
            ([.t index "$start + 1c"] == $insertpos)  ||
            ([.t index "$end + 1c"] == $insertpos)  ||
            ([.t index "$start - 1c"] == $insertpos)  ||
            ([.t index "$end - 1c"] == $insertpos) } {
            set found_source 1;
            set source_start $start;
            set source_end $end;
        } else {
            set target_start $start;
            set target_end $end;
        }
      }
    if {!$found_source} {
          puts "Could not decide hyperlink source";
          return;
      }

     set randword [randString];
     set tagname "hyperref_${randword}"
    .t tag bind "hyperref_${randword}" <Control-ButtonRelease-1> "followTarget $randword"
    .t tag configure  "hyperref_${randword}" -underline 1;

    global replace_existing_hyperlinks;
    .t tag add "target_${randword}" $target_start $target_end;
    set clashes 0;
    foreach existing [.t tag names $source_start] {
        if { [string range $existing 0 8] == "hyperref_"} {
                 set clashes 1;
                 if {$replace_existing_hyperlinks} {
                     .t tag remove $existing $source_start $source_end;
                 }
         }
    }
    if {$clashes && !$replace_existing_hyperlinks} { 
    } else {
        .t tag add $tagname $source_start $source_end;
    }
}



proc setSelectedWordsAsTargets { {spanstart 1.0} {spanend end} } {
    set ranges [.t tag ranges sel];
    set num [expr [llength $ranges] / 2];
    set count 0;
    foreach {start end} $ranges {
         if {[catch {
         incr count;
         setWordAsTarget $start $end $spanstart $spanend;
         addToStatus "setting selected words as targets $count/$num";
         update;
         } msg]} {
             tk_messageBox -message  "Error '$msg' at $count/$num";
         }
    }
}

proc append_to_viewpoints {pos} {
   global viewpoints;
   set cur [lindex $viewpoints end];
   set diff [expr abs ($cur - $pos)];
   if {$diff > 15} {
      lappend viewpoints $pos; 
   }
}

proc followTarget {word} {
    global disable_follow_target;
    if {$disable_follow_target} {
        return;
    }
    global external_hyperrefs;
    
    if {[string first "line_" $word] == 0} {
        regsub -all {line_[^_]+_} $word {} linenum;
        set file [absolutizeFileName [set external_hyperrefs($word)]];
        catch { edit $file };
        .t tag add sel ${linenum}.0 ${linenum}.end;
        .t see ${linenum}.0;
    } else {
        set ranges [.t tag ranges "target_${word}"];
        if {[llength $ranges] == 0 && [info exists external_hyperrefs($word)]}  {
            set file [absolutizeFileName [set external_hyperrefs($word)]];
            catch { edit $file };
            set ranges [.t tag ranges "target_${word}"];
        } else {
            append_to_viewpoints [.t index insert];
        }
        foreach {start end} $ranges {
            .t tag add sel $start $end;
            .t see $start;
            .t mark set insert $start;
            break;
        }
    }
}



proc setWordAsTarget {wordstart wordend {spanstart 1.0} {spanend end} } {
    set current_word [.t get $wordstart $wordend];
    if {[regexp {^\s*$} $current_word]} {
            return;
        }
     set cur $spanstart;
     set last_cur "";

     set endline "";
     set endchar "";

     if {$spanend != "end"} {
       set sp [ split spanend "."];
       set endline [lindex $sp 0];
       set endchar [lindex $sp 1];
     }

     set expr "\\m";
     append expr $current_word;
     append expr "\\M";


     set randword [randString];
     set tagname "hyperref_${randword}"
    .t tag add "target_${randword}" $wordstart $wordend;

    .t tag bind $tagname <Control-ButtonRelease-1> "followTarget $randword"

    .t tag configure  $tagname -underline 1;
    while 1 {
           set cur [.t search -nocase -regexp -count length $expr $cur end]
           if {$cur == "" || $cur == $last_cur } {
               break;
           }
           if {$spanend != "end"} {
              set cp [split $cur "."];
              set curline [lindex $cp 0];
              set curchar [lindex $cp 1];
              if {$curline > $endline || ($curline == $endline && $curchar > $endchar)} {
                  break;
              }
           }
           global replace_existing_hyperlinks;
           if {$cur != $wordstart} {

                set clashes 0;
                foreach existing [.t tag names $cur] {
                if { [string range $existing 0 8] == "hyperref_"} {
                   set clashes 1;
                   if {$replace_existing_hyperlinks} {
                       .t tag remove $existing $cur "$cur + $length char";
                     }
                  }
                }
                if {$clashes && !$replace_existing_hyperlinks} { 
                } else {
                    .t tag add $tagname $cur "$cur + $length char";
                }
               
            }
            if {$length == 0} {
                incr length;
            }
           set cur [.t index "$cur + $length char"];
           set last_cur $cur;
           
       }
}


proc set_multiword_mode {val} {
    global multiword_mode;
    set multiword_mode $val;
}
proc get_multiword_mode {} {
    global multiword_mode;
    return $multiword_mode;
}


proc set_hyphenated_word_mode {val} {
    global hyphenated_word_mode;
    set hyphenated_word_mode $val;
}
proc get_hyphenated_word_mode {} {
    global hyphenated_word_mode;
    return $hyphenated_word_mode;
}

proc get_multiword_at_pos {pos} {
    set wordstart [.t index "$pos wordstart"];
    set found [.t search -regexp -count length {\m([A-Za-z0-9_]+[ \-]*[A-Za-z0-9_]+)+\M} "$pos wordstart" end];
    if {$found == "" || $length == 0} {
        return [.t get $wordstart "$pos wordend"];
    } else {
        return [.t get $wordstart "$wordstart + $length char"];
    }
}

proc get_hyphenated_word_at_pos {pos} {
    set wordstart [.t index "$pos wordstart"];
    set found [.t search -regexp -count length {\m([A-Za-z0-9_]+[\-]*[A-Za-z0-9_]+)+\M} "$pos wordstart" end];
    if {$found == "" || $length == 0} {
        return [.t get $wordstart "$pos wordend"];
    } else {
        return [.t get $wordstart "$wordstart + $length char"];
    }
}


proc set_case_sensitive_mode {val} {
    global case_sensitive;
    set case_sensitive $val;
}
proc get_case_sensitive_mode {} {
    global case_sensitive;
    return $case_sensitive;
}

proc readNumberAloud {textwidget pos} {
   
   global sound_filenames;
   global play_image;
   set current_number [$textwidget get "$pos wordstart" "$pos wordend"];
   
   set txt [numberToWords $current_number];
   global spectral_subfolder;
   global sound_filenames;
   set fname "[get_current_folder]/${spectral_subfolder}/[randString].txt";;
   set fp [open $fname w];
   fconfigure $fp -encoding utf-8
   puts -nonewline $fp $txt;
   close $fp;

   catch {
   exec "[installdir]/wbin/balcon.exe" -n "Microsoft Hazel Desktop" "-f" $fname -o --raw | "[installdir]/wbin/lame.exe" -r -s 14.05 -m m -h - "${fname}.mp3"
   } msg;
   
   
   catch {
     set btn $textwidget.[randString];
   
      $textwidget window create "$pos wordend" -create " button $btn  -image $play_image -command \"playMedia $fname.mp3\" -background #ccd3f7 -activebackground #a78737" ;
    } msg;

    after 200 "setTooltip $btn ${fname}.mp3" ;
    set sound_filenames($btn) "${fname}.mp3" ;
    after 300 "bind $btn <ButtonPress-3> \{showMediaMenu $btn \"${fname}.mp3\"\}";
    after 300 "bind $btn <ButtonPress-2> \{showMediaMenu $btn \"${fname}.mp3\"\}";
  
   
}


proc highlightPreviousOccurrance {textwidget pos} {
    set search_start [$textwidget index "$pos wordstart"]
    set current_word [$textwidget get "$pos wordstart" "$pos wordend"];
    set previous_index [$textwidget search -backwards -regexp "\\m${current_word}\\M" "$search_start - 1 char" 1.0]
    set len [string length $current_word]
   if {$previous_index ne ""} {
       $textwidget tag add sel $previous_index "$previous_index + $len chars"
   }
   $textwidget see $previous_index;
   $textwidget mark set insert $previous_index;
}

proc highlightNextOccurrance {textwidget pos} {
    set search_start [$textwidget index "$pos wordend"]
    set current_word [$textwidget get "$pos wordstart" "$pos wordend"];
    set next_index [$textwidget search  -regexp "\\y${current_word}\\y" "$search_start + 1 char" end]
    set len [string length $current_word]
   if {$next_index ne ""} {
       $textwidget tag add sel $next_index "$next_index + $len chars"
   }
   $textwidget see $next_index;
   $textwidget mark set insert $next_index;
}

proc highlightCurrent {textwidget pos} {
    global modified;
    global multiword_mode;
	global hyphenated_word_mode;
    global case_sensitive;
    
    global default_highlight;
    global default_background;
    set background_code [colorCode $default_background];
    set afont [[.searchFrame.font component entry] get];
    set foreground [[.searchFrame.foreground component entry] get];
     set occurrence_count 0;
    catch {
        global highlight_colors;
        set tagname "";
        if {$default_highlight == ""} {
        set r [expr { int(100 * rand() + 150) }]
        set g [expr { int(100 * rand() + 150) }]
        set b [expr { int(100 * rand() + 150) }]
        set col [format "#%02x%02x%02x" $r $g $b];
        if {$background_code == "#000000"} {
           set col [negateColor $col];
        }
          set tagname "U[uuid::uuid generate]";
          $textwidget tag configure $tagname -background $col;
          lappend highlight_colors $tagname;
       } else {
          set tagname $default_highlight;
          foreach x $afont {
             foreach y $x {
                append tagname $y;
             }
           }
           if {[llength $foreground]} {
              append tagname "_" $foreground;
           }
        }
        
        if {[llength $afont]} {
            $textwidget tag configure $tagname -font $afont;
        }
        if {[llength $foreground]} {
          $textwidget tag configure $tagname -foreground $foreground;
        }
        if { $multiword_mode } {
            set current_word [get_multiword_at_pos $pos];
        } elseif {$hyphenated_word_mode} { 
		     set current_word [get_hyphenated_word_at_pos $pos];
		} else {
            set current_word [$textwidget get "$pos wordstart" "$pos wordend"];
        }
        if {[regexp {^\s*$} $current_word]} {
            return;
        }
        
        # $textwidget tag add sel "$pos wordstart" "$pos wordend"
        # $textwidget tag add $tagname "$pos wordstart" "$pos wordend"
       $textwidget tag raise $tagname;
       set cur 1.0;
       set last_cur "";

       set expr "\\m";
       append expr $current_word;
       append expr "\\M";
       
      
       while 1 {
           if {$case_sensitive} {
              set cur [$textwidget search -regexp -count length $expr $cur end]
           } else {
              set cur [$textwidget search -regexp -nocase -count length $expr $cur end] 
           }
           if {$cur == "" || $cur == $last_cur } {
               break;
           }
           
           set oldtags [$textwidget tag names $cur];
           lappend oldtags [$textwidget tag names "$cur + [expr $length - 1] char"];
           foreach  oldtag $oldtags {
               if {![regexp {(^#)|(^target_)|(^hyperref_)} $oldtag]} {
                  $textwidget tag remove $oldtag $cur "$cur + $length char"
               }
            }
           $textwidget tag add $tagname $cur "$cur + $length char";
           incr occurrence_count;
           if {$length == 0} {
                incr length;
           }
           set cur [$textwidget index "$cur + $length char"];
           set last_cur $cur;
           
       }
    } msg;
    
    addToStatus "\n${occurrence_count} occurrences\n"
    #puts stderr $msg;
    update;
}

proc regex_escape {txt} {
    return [string map [list "\\" "\\\\" "." "\\." "^" "\\^" "$" "\\$" "*" "\\*" "+" "\\+" "?" "\\?" "(" "\\(" ")" "\\)" "[" "\\[" "]" "\\]" "{" "\\{" "}" "\\}" "|" "\\|"] $txt]
}

proc _is_word_char {ch} {
    return [expr {[string length $ch] > 0 && [regexp {[A-Za-z0-9_]} $ch]}]
}

proc _is_whole_word_at {w idx len} {
    set end_idx [$w index "$idx + ${len}c"]
    set before [$w get "$idx - 1c" $idx]
    set after [$w get $end_idx "$end_idx + 1c"]
    if {[_is_word_char $before]} { return 0 }
    if {[_is_word_char $after]} { return 0 }
    return 1
}

proc highlightCurrentBarebones {textwidget pos} {
    global default_highlight
    global highlight_colors
    global case_sensitive
    global multiword_mode
	global hyphenated_word_mode;

    catch {
        if {$textwidget eq ".t" && [winfo exists .t.t]} {
            set textwidget .t.t
        }
        if {![winfo exists $textwidget]} {
            addToStatus "highlight: widget '$textwidget' not found"
            return
        }
        set afont ""
        set foreground ""
        catch {set afont [[.searchFrame.font component entry] get]}
        catch {set foreground [[.searchFrame.foreground component entry] get]}
        if {$multiword_mode} {
            set current_word [get_multiword_at_pos $pos]
        } elseif {$hyphenated_word_mode} {
		    set current_word [get_hyphenated_word_at_pos $pos];
		} else {
            set current_word [$textwidget get "$pos wordstart" "$pos wordend"]
        }
        set current_word [string trim $current_word]
        if {[regexp {^\s*$} $current_word]} {
            return
        }

        if {$default_highlight eq ""} {
            set r [expr {int(56 * rand() + 180)}]
            set g [expr {int(56 * rand() + 180)}]
            set b [expr {int(56 * rand() + 180)}]
            set col [format "#%02x%02x%02x" $r $g $b]
            set tagname "U[randString]"
            $textwidget tag configure $tagname -background $col
            lappend highlight_colors $tagname
        } else {
            set tagname $default_highlight
            catch {$textwidget tag configure $tagname -background $default_highlight}
        }
        if {[llength $afont]} {
            catch {$textwidget tag configure $tagname -font $afont}
        }
        if {[llength $foreground]} {
            catch {$textwidget tag configure $tagname -foreground $foreground}
        }

        set len [string length $current_word]
        set cur 1.0
        set occurrence_count 0
        while 1 {
            if {$case_sensitive} {
                set cur [$textwidget search -exact -- $current_word $cur end]
            } else {
                set cur [$textwidget search -nocase -exact -- $current_word $cur end]
            }
            if {$cur eq ""} {
                break
            }
            if {[_is_whole_word_at $textwidget $cur $len]} {
                $textwidget tag add $tagname $cur "$cur + $len char"
                incr occurrence_count
            }
            set cur [$textwidget index "$cur + 1 char"]
        }
        addToStatus "\n${occurrence_count} occurrences\n"
    } msg
    if {$msg ne ""} {
        addToStatus "highlight error: $msg"
    }
}

proc force_doubleclick_highlight {} {
    set w .t
    if {[winfo exists .t.t]} {
        set w .t.t
    }
    highlightCurrentBarebones $w [$w index insert]
}

proc remove_hyperlinks {} {
   set names [.t tag names];
   set to_remove {};
   foreach name $names {
      if {[string first "hyperref_" $name ] == 0} {
         lappend to_remove $name;
      }
   }

   foreach {start end} [.t tag ranges sel] {
      foreach tname $to_remove {
          .t tag remove $tname $start $end;
      }
   }
   
}

proc remove_targets {} {
   set names [.t tag names];
   set to_remove {};
   foreach name $names {
      if {[string first "target_" $name ] == 0} {
         lappend to_remove $name;
      }
   }

   foreach {start end} [.t tag ranges sel] {
      foreach tname $to_remove {
          .t tag remove $tname $start $end;
      }
   }
   
}

proc match_shortest {regex} {
    set sel_only 0;
    if { [hasSelection] } {
        set sel_only 1;
    }

     set cur 1.0;

     if {$sel_only} {
         catch {
          set cur [lindex [lindex [.t tag ranges sel] 0] 0];
         }
     }

    set shortest_start "";
    set shortest_end "";
    set shortest_len "";
    set last_cur "";
    catch {
       while 1 {
           set cur [.t search -regexp -count length $regex $cur end]
           if {$cur == "" || $cur == $last_cur } {
               break;
           }

           if {$sel_only} {
               set curtag [.t tag names $cur];
               if {[lsearch $curtag "sel"] != -1} {
                   if {$shortest_len == "" || $length < $shortest_len} {
                      set shortest_start $cur;
                      set shortest_end [.t index "$cur + $length c"];
                      set shortest_len $length;
                   }
               }

       }  else {
            if {$shortest_len == "" || $length < $shortest_len} {
                      set shortest_start $cur;
                      set shortest_end [.t index "$cur + $length c"];
                      set shortest_len $length;
                  }
       }
       set last_cur $cur;
       set cur [.t index "$cur + 1 c"];
           
       }
    } msg;
    puts stderr $msg;
    .t tag remove sel 1.0 end;
    if {$shortest_len != ""} {
       .t see $shortest_start
      .t mark set insert $shortest_start;  
      .t tag add sel $shortest_start $shortest_end;
    }
    
    update;
}

proc match_longest {regex} {
    set sel_only 0;
    if { [hasSelection] } {
        set sel_only 1;
    }

     set cur 1.0;

     if {$sel_only} {
         catch {
          set cur [lindex [lindex [.t tag ranges sel] 0] 0];
         }
     }

    set longest_start "";
    set longest_end "";
    set longest_len -1;
    set last_cur "";
    catch {
       while 1 {
           set cur [.t search -regexp -count length $regex $cur end]
           if {$cur == "" || $cur == $last_cur } {
               break;
           }
           if {$sel_only} {
               set curtag [.t tag names $cur];
               if {[lsearch $curtag "sel"] != -1} {
                   if {$length > $longest_len} {
                      set longest_start $cur;
                      set longest_end [.t index "$cur + $length c"];
                      set longest_len $length;
                   }
               }
       }  else {
            if {$length > $longest_len} {
                      set longest_start $cur;
                      set longest_end [.t index "$cur + $length c"];
                      set longest_len $length;
                  }
       }
       set last_cur $cur;
       set cur [.t index "$cur + 1 c"];
           
       }
    } msg;
    puts stderr $msg;
    .t tag remove sel 1.0 end;
    if {$longest_len > 0} {
       .t see $longest_start
      .t mark set insert $longest_start;  
      .t tag add sel $longest_start $longest_end;
    }
    
    update;
}


# this example adds the tag 'highlight' to all occurrences
# of text inside <>
#pack [text .t] -side top -fill both -expand y 
#.t tag configure highlight -foreground red
#<insert text into widget>
#forText .t -regexp {***:<.*?>} 1.0 end {
#   .t tag add highlight matchStart matchEnd
#}

proc forText {args} {
   set w .t
   # initialize search command; we may add to it, depending on the
   # arguments passed in...
   set searchCommand [list $w search -count count]

   # Poor man's switch detection
   set i 0
   while {[string match {-*} [set arg [lindex $args $i]]]} {

      if {[string match $arg* -regexp]} {
         lappend searchCommand -regexp
         incr i
      } elseif {[string match $arg* -elide]} {
         lappend searchCommand  -elide
         incr i
      } elseif {[string match $arg* -nocase]} {
         lappend searchCommand  -nocase
         incr i
      } elseif {[string match $arg* -exact]} {
         lappend searchCommand  -exact
         incr i
      } elseif {[string compare $arg --] == 0} {
         incr i
         break
      } else {
         return -code error "bad switch \"$arg\": must be\
           --, -elide, -exact, -nocase or -regexp"
      }
   }

   # parse remaining arguments, and finish building search command
   foreach {pattern start end script} [lrange $args $i end] {break}
   lappend searchCommand $pattern matchEnd searchLimit

   # make sure these are of the canonical form
   set start [$w index $start]
   set end [$w index $end]

   # place marks in the text to keep track of where we've been
   # and where we're going
   $w mark set matchStart $start
   $w mark set matchEnd $start
   $w mark set searchLimit $end

   # default gravity is right, but we're setting it here just to
   # be pedantic. It's critical that matchStart and matchEnd have
   # left and right gravity, respectively, so that any text inserted
   # by the caller duing the search won't normally (*) cause an infinite
   # loop. 
   # (*) If the script inserts text after the matchEnd mark, and the
   # text that was added matches the pattern, madness will ensue.
   $w mark gravity searchLimit right
   $w mark gravity matchStart left
   $w mark gravity matchEnd right

   # finally, the part that does useful work. Keep running the search
   # command until we don't find anything else. Each time we find 
   # something, adjust the marks and execute the script
   while {1} {
      set cmd $searchCommand
      set index [eval $searchCommand]
      if {[string length $index] == 0} break

      $w mark set matchStart $index
      $w mark set matchEnd  [$w index "$index + $count c"]

      uplevel $script
   }
}
##########################################################
# Merging changes from text file
package require uuid;
proc mergeWithFile {args} {
   set fname "";
   if {[llength $args]} {
     set fname [lindex $args 0];
   } else {
       set fname [tk_getOpenFile];
   }
    if {$fname == ""} {
           return;
   }
   
   
      global tmpdir;
   global installdir;
   set difftool "diff";
   if {[isWindowsExecutable]} {
       set difftool "${installdir}/wbin/diff.exe";
   }

   set fname2 "$tmpdir/[uuid::uuid generate]";
   set fp [open $fname2 w];
   fconfigure $fp -encoding utf-8
   set cont [.t get 1.0 end]
   puts -nonewline $fp $cont;
   close $fp;
   set difffile "$tmpdir/[uuid::uuid generate]";

   catch {
     exec $difftool -n $fname2 $fname ">" $difffile; 
   } msg;
   #puts stderr "diff says : $msg";
   set fp1 [open $difffile r];
   fconfigure $fp1 -encoding utf-8
   set patch [read $fp1];
   close $fp1;
   #puts stderr $patch;
   patch $patch;
}

package require fileutil


# convert \n delimited file to an array indexed by line name
proc file2array {filename arr} {
    upvar 1 $arr lines
    set lnum 0
    fileutil::foreachLine line $filename {
    set lines([incr lnum]) $line
    }
}

# convert \n delimited text to an array indexed by line name
proc text2array {text arr} {
    upvar 1 $arr lines
    set lnum 0
    foreach line [split $text \n] {
    set lines([incr lnum]) $line
    }
}

# Apply some rcs diff -n format patches to the text in array
proc patch {patch} {
    set offset 1;
    set patch [split $patch \n]
    set changes {};
    while {$patch != {}} {
        set pc [string trim [lindex $patch 0]]
        #puts stderr "doing $pc"
        set patch [lrange $patch 1 end]
        switch -glob -- $pc {
            "" {}
            a* {
                foreach {xstart len} [split [string range $pc 1 end]] break
                set adding [join [lrange $patch 0 [expr {$len - 1}]] \n]
               
                set start [expr $xstart + ($offset)];
                append adding "\n";
                .t insert "$start.0" $adding;
                #puts stderr ".t insert $start.0 $adding"
                set patch [lrange $patch $len end];
                set addingLength [string length $adding];
                set startPos "$start.0";
                set endPos [.t index "$start.0 + $addingLength char"];
                .t tag add diffed $startPos $endPos;
                lappend changes [list "a" $startPos $endPos]; 
                set offset [expr $offset + ($len)];
            }
            d* {
                foreach {xstart xlen} [split [string range $pc 1 end]] break
        
                set start [expr $xstart + ($offset)];
                set len $xlen;
                while {$len > 0} {
                    #puts stderr ".t delete [expr $start - 1].0 [expr $start - 1].end + 1 char";
                    set startPos "[expr $start - 1].0";
                    set endPos [.t index "[expr $start - 1].end + 1 char"];
                    set changeEntry "d";
                    lappend changeEntry $startPos;
                    lappend changeEntry $endPos;
                    lappend changeEntry [hlt:save .t $startPos $endPos];
                    lappend changes $changeEntry;
                    .t fastdelete $startPos $endPos ;
                    incr len -1
                 }
                 set offset [expr $offset - ($xlen)];
    
            }
            default {
                error "Unknown patch: '$pc'"
            }
        }
    }
    catch {
    if {[llength $changes]} {
       set resultsWindow [createResultsWindow "Merge Report"];
       set lastLine "";
       foreach change $changes {
           set type [lindex $change 0];
           set start [lindex $change 1];
           set end [lindex $change 2];

           set splitStart [split $start "."];
           set theLine [lindex $splitStart 0];
           set theCol [lindex $splitStart 1];


            if {$type == "a"} {
                 if {$lastLine == $theLine} {
                     $resultsWindow.results insert end "($theLine):($theCol): Modification, Check Editor\n" resultHyperlink;
                 } else {
                     $resultsWindow.results insert end "($theLine):($theCol): Addition, Check Editor\n" resultHyperlink;
                 }
            } elseif {$type == "d"} {
                 if {$lastLine == $theLine} {
                    
                 } else {
                    $resultsWindow.results insert end "($theLine):($theCol): Old, See Below\n" resultHyperlink;
                }
                hlt:restore $resultsWindow.results [lindex $change 3] end;
            }
            set lastLine $theLine;
         }
         .t tag lower diffed;
      }
    } msg;
    addToStatus $msg; 

}

###########################################################
#

set rectStart "";
proc selrectangle {start endx endy} {
   set end [.t index "@$endx,$endy"];
   set from [split $start "."];
   set to [split $end "."];
   set row_from [expr min([lindex $from 0] , [lindex $to 0])];;
   set row_to [expr max([lindex $from 0] , [lindex $to 0])];;
   set col_from [expr min([lindex $from 1] , [lindex $to 1])];
   set col_to [expr max([lindex $from 1] , [lindex $to 1])];
   for {set i $row_from} {$i <= $row_to} {incr i} {
      set xmax [lindex [.t bbox $i.end] 0];
      if {$xmax != "" &&  $xmax  < $endx} {
         .t tag add sel $i.$col_from $i.end;
      } else {
        .t tag add sel $i.$col_from $i.$col_to;
      }
   }  
}

proc selskip {startline endline step} {
    set cnt 0;
    set max [expr abs($startline-$endline) + 1];
    for {set i $startline} {$i < $endline} {incr i $step} {
        .t tag add sel $i.0 [.t index "$i.end + 1 char"]
        if {$cnt > $max} {
            break;
        }
        incr cnt;
    }
}

proc selrect {start end} {
   set from [split $start "."];
   set to [split $end "."];
   set row_from [expr min([lindex $from 0] , [lindex $to 0])];;
   set row_to [expr max([lindex $from 0] , [lindex $to 0])];;
   set col_from [expr min([lindex $from 1] , [lindex $to 1])];
   set col_to [expr max([lindex $from 1] , [lindex $to 1])];
   for {set i $row_from} {$i <= $row_to} {incr i} {
     .t tag add sel $i.$col_from $i.$col_to;
   }  
}
  

proc ::tk::ControlTextSelectTo {w x y {extend 0}} {
    global tcl_platform
    variable ::tk::Priv

    set anchorname [tk::TextAnchor $w]
    set cur [TextClosestGap $w $x $y]
    if {[catch {$w index $anchorname}]} {
    $w mark set $anchorname $cur
    }
    set anchor [$w index $anchorname]
    if {[$w compare $cur != $anchor] || (abs($Priv(pressX) - $x) >= 3)} {
    set Priv(mouseMoved) 1
    }
    switch -- $Priv(selectMode) {
    char {
        if {[$w compare $cur < $anchorname]} {
            $w tag remove sel $cur $anchorname;
        set first $anchorname;
        set last $anchorname;
        } else {
            $w tag remove sel  $anchorname $cur;
        set first $anchorname
        set last $cur
        }
    }
    word {
        # Set initial range based only on the anchor (1 char min width)
        if {[$w mark gravity $anchorname] eq "right"} {
        set first $anchorname
        set last "$anchorname + 1c"
        } else {
        set first "$anchorname - 1c"
        set last $anchorname
        }

        $w tag remove sel $first $last;
        # Extend range (if necessary) based on the current point
        if {[$w compare $cur < $first]} {
        set first $cur
        } elseif {[$w compare $cur > $last]} {
        set last $cur
        }

        # Now find word boundaries
        set first [TextPrevPos $w "$first + 1c" tcl_wordBreakBefore]
        set last [TextNextPos $w "$last - 1c" tcl_wordBreakAfter]
    }
    line {
        # Set initial range based only on the anchor
        set first "$anchorname linestart"
        set last "$anchorname lineend"
        $w tag remove sel $first $last;
        # Extend range (if necessary) based on the current point
        if {[$w compare $cur < $first]} {
        set first "$cur linestart"
        } elseif {[$w compare $cur > $last]} {
        set last "$cur lineend"
        }
        set first [$w index $first]
        set last [$w index "$last + 1c"]
    }
    }
    if {$Priv(mouseMoved) || ($Priv(selectMode) ne "char")} {
    $w mark set insert $cur
    
    $w tag add sel $first $last
    
    update idletasks
    }
}

bind .t <Alt-B1-Motion> {
    
    .t tag remove sel 1.0 end;
    selrectangle $rectStart %x %y;
    .t tag raise sel;
    break;
}
bind .t <Option-B1-Motion> {
    
    .t tag remove sel 1.0 end;
    selrectangle $rectStart %x %y;
    .t tag raise sel;
    break;
}

bind Text <Control-B1-Motion> {
    set tk::Priv(x) %x
    set tk::Priv(y) %y
    tk::ControlTextSelectTo %W %x %y
}

bind .t <Control-1> {
    tk::TextButton1 %W %x %y
}

bind .t <Alt-Control-B1-Motion> {
    selrectangle $rectStart %x %y;
    .t tag raise sel;
    break;
}

bind .t <Alt-ButtonPress-1> {
    set insertPos [.t index insert];
    set rectStart [.t index {@%x,%y}];
    if {$rectStart == [.t index "$insertPos + 1 char"]} {
        set rectStart $insertPos;
    }
    if {$rectStart == [.t index "$insertPos - 1 char"]} {
        set rectStart $insertPos;
    }

}
bind .t <Option-Control-B1-Motion> {
    selrectangle $rectStart %x %y;
    .t tag raise sel;
    break;
}

bind .t <Option-ButtonPress-1> {
    set insertPos [.t index insert];
    set rectStart [.t index {@%x,%y}];
    if {$rectStart == [.t index "$insertPos + 1 char"]} {
        set rectStart $insertPos;
    }
    if {$rectStart == [.t index "$insertPos - 1 char"]} {
        set rectStart $insertPos;
    }

}

bind .t <Control-a> {%W tag add sel 1.0 end; break;}
bind .t <Control-s> {saveFile .t}
bind .t <Control-S> {saveFile .t; saveHtmlFile "[get_current_filename].html" .t; }

bind .t <Return> {
      set selranges [.t tag ranges sel];
     if {[llength $selranges] > 2} {
      set numsel [expr [llength $selranges] / 2];
      for {set i 0} {$i < $numsel} {incr i} {
        set selranges [.t tag ranges sel];
        global update_frozen;
        set update_frozen 1;
        set start [lindex $selranges [expr 2*$i]];
        dott mark set insert $start;
        singleReturnPress;
      }
      set update_frozen 0;
      update;
      break;
     } else {
         singleReturnPress;
         break;
     }
}

proc singleReturnPress {} {
    set pos [.t index insert];
    set startpos $pos
    set endpos   $pos
    regsub {\..*$} $startpos {.0} startpos;
    regsub {\..*$} $endpos {.end} endpos;
    set input_line [.t get $startpos $endpos];
    set input_to_left [.t get $startpos [.t index insert]];
    set input_to_right [string trim [.t get [.t index insert] $endpos]];
    set trimmed [string trim $input_to_left];
    set indent "";
    set last_char [string index $trimmed end];
    set num_lparen [expr {[llength [split $trimmed "("]] - 1}]
    set num_rparen [expr {[llength [split $trimmed ")"]] - 1}]
    if {$last_char == "\{" || $last_char == ":" || $num_lparen > $num_rparen} {
        set indent "    ";
    }
    regsub -all {(^\s*)([^\s].*)?} $input_line {\1} input_line;
    if {$input_to_right == "\}" } {
        .t insert $pos "\n${indent}$input_line\n$input_line";
        set numchar_backwards [expr [string length $input_line] + 1];
        .t mark set insert "[.t index insert] - $numchar_backwards char";
    } else {
        .t insert $pos "\n${indent}$input_line";
    }
    set curinsert [.t index insert];
    set curend [.t index end];
    if { [expr $curinsert + 2] > $curend } {
    .t yview [.t index insert]
    }

}


bind .t <Shift-Tab> {
 catch {
    set has_sel 0;
    set selranges [.t tag ranges sel];
    foreach {start end} $selranges {
       set start [expr int($start)];
       set end   [expr int($end)];
       set has_sel 1;
       for {set line $start} {$line <= $end} {incr line} {
           
           for {set i 1} {$i <= 4} {incr i} {
               set ch [.t get "$line.0" "$line.1"];
               if {$ch == " "} {
                   
                   .t fastdelete "$line.0" "$line.1";
               } else {
                   break;
               }
           }

       }
    }
    if {!$has_sel} {
        set line [expr int([.t index insert])]
        for {set i 1} {$i <= 4} {incr i} {
           set ch [.t get "$line.0" "$line.1"];
           if {$ch == " "} {
               .t fastdelete "$line.0" "$line.1";
           } else {
               break;
           }
       }
    }
}
    break;
}




bind .t <Tab> {
 catch {
    set has_sel 0;
    set selranges [.t tag ranges sel];
    foreach {start end} $selranges {
       set start [expr int($start)];
       set end   [expr int($end)];
       set has_sel 1;
       for {set line $start} {$line <= $end} {incr line} {
           .t insert "$line.0" $tab_inserts;
       }
    }
    if {!$has_sel} {
        set pos [.t index insert];
        .t insert $pos $tab_inserts;
    }
   }
    break;
}

proc splitsel {} {
    set ranges [.t tag ranges sel];
    foreach {start1 end1} $ranges {
       set start [expr int($start1)];
       set end   [expr int($end1)];
       for {set line $start} {$line < $end} {incr line} {
           .t tag remove sel  $line.end "$line.end + 1c" ;
       }
    }
}

proc selendl {} {
    set ranges [.t tag ranges sel];
    .t tag remove sel 1.0 end;
    foreach {start1 end1} $ranges {
       set start [expr int($start1)];
       set end   [expr int($end1)];
       for {set line $start} {$line <= $end} {incr line} {
           .t tag add sel  $line.end "$line.end + 1c" ;
       }
    }
}


proc selend {} {
    set ranges [.t tag ranges sel];
    .t tag remove sel 1.0 end;
    foreach {start end} $ranges {
       .t tag add sel "$end - 1 c" $end;
    }
}

proc selstart {} {
    set ranges [.t tag ranges sel];
    .t tag remove sel 1.0 end;
    foreach {start end} $ranges {
       .t tag add sel $start "$start + 1 c" ;
    }
}

proc selmove {startmove endmove} {
    set ranges [.t tag ranges sel];
    .t tag remove sel 1.0 end;
    foreach {start end} $ranges {
       .t tag add sel "$start + $startmove c" "$end + $endmove c" ;
    }
}

proc selaroundsel {linesbefore linesafter {extrachars_left 0} {extrachars_right 0}} {
    set ranges [.t tag ranges sel];
    .t tag remove sel 1.0 end;
    
    foreach {start1 end1} $ranges {
       set start [expr int($start1)];
       set end   [expr int($end1)];
       set rangestart [expr $start - $linesbefore];
       set rangeend [expr $end + $linesafter];
       
       
       for {set i $rangestart} {$i <= $rangeend} {incr i} {
           if {$i <= 0} continue;
           .t tag add sel "${i}.0 - ${extrachars_left} c" "${i}.end + ${extrachars_right} c"
       }
    }
}

proc selBracedRange {} {
    set ranges [.t tag ranges sel];
    .t tag remove sel 1.0 end;
    
    foreach {start end} $ranges {
      matchNearestEnclosingBrace $start sel
      matchBracket .t ""      
    }
    selmove 0 1;
}

proc remove_border {} {
   substitute {^[ ]*\|[ ]*} {} {} {} {} {}
   substitute {[ ]*\|[ ]*$} {} {} {} {} {}
}

proc add_border {} {
    set longest 0; 
    set ranges [.t tag ranges sel];
    .t tag remove sel 1.0 end;
    foreach {start1 end1} $ranges {
       set start [expr int($start1)];
       set end   [expr int($end1)];
       for {set line $start} {$line <= $end} {incr line} {
         set linelen [string length [.t get "$line.0" "$line.end"]];
         if {$linelen > $longest} {
             set longest $linelen;
         }
       }
    }
    foreach {start1 end1} $ranges {
       set start [expr int($start1)];
       set end   [expr int($end1)];
       for {set line $start} {$line <= $end} {incr line} {
         set linelen [string length [.t get "$line.0" "$line.end"]];
         set padding [expr 1 + $longest - $linelen];
         .t insert $line.end [string repeat " " $padding];
         .t insert $line.end " |";
         .t insert $line.0 " |  "
       }
    }
}

proc selexpand {} {
    set ranges [.t tag ranges sel];
    foreach {start1 end1} $ranges {
       set start [expr int($start1)];
       set end   [expr int($end1)];
       .t tag add sel "${start}.0" "${start}.end";
       .t tag add sel "${end}.0" "${end}.end";
    }
}

proc selexpandendl {} {
    set ranges [.t tag ranges sel];
    foreach {start1 end1} $ranges {
       set start [expr int($start1)];
       set end   [expr int($end1)];
       .t tag add sel "${start}.0" "${start}.end + 1c";
       .t tag add sel "${end}.0" "${end}.end + 1c";
    }
}

proc createBottomPanelPopupMenu {x2 y2} {
    catch {destroy .menu5}
    set x [winfo pointerx .]
    set y [winfo pointery .]
    menu .menu5 -tearoff 0;
    .menu5 add command -label "Show Contents in a New Window" -command {showOutput [.status get 1.0 end] status {} {}}; 
    .menu5 add command -label "Clear Messages" -command {.status delete 1.0 end}; 
    tk_popup .menu5 $x $y;
}

array set extra_popup_menu_items {};
proc add_popup_menu_item {txt cmd} {
    global extra_popup_menu_items;
    set extra_popup_menu_items($txt) $cmd;
}
proc createPopupMenu {x2 y2}  {
    global current_file;
    global extra_popup_menu_items;

    catch {destroy .menu2}
    set x [winfo pointerx .]
    set y [winfo pointery .]
    
    set pos [.t index "@$x2,$y2"]
    set cont [.t dump -all $pos "$pos + 1c"];
    
    menu .menu2 -tearoff 0;
    foreach {type detail pos } $cont {
        if {$type == "image"} {
            .menu2 add command -label "Resize Image" -command "resizeImage $detail $pos";
        }
    }
    
    foreach {type detail pos } $cont {
        if {$type == "image"} {
            .menu2 add command -label "Show Image in Explorer" -command "showInExplorer $detail $pos";
        }
    }
   foreach {type detail pos } $cont {
        if {$type == "image"} {
            .menu2 add command -label "Edit Image" -command "editImage $detail $pos";
        }
    }

    
    .menu2 add command -label "Find Occurrences" -command "find_occurrences ";
    .menu2 add command -label "Lookup Trace Source" -command "load_tag .t $pos  load_tag ";
    if {$current_file == ""} {
      .menu2 add command -label "Edit Trace Source" -command "load_tag_for_edit $pos load_tag_for_edit";
      .menu2 add command -label "Show File from Listing" -command "showFileAtCursor $pos ";
      .menu2 add command -label "Edit File from Listing" -command "editFileAtCursor $pos ";
    }
    .menu2 add command -label "Insert Note" -command "insertNoteFile .t";
    .menu2 add command -label "Show File in Explorer" -command "showListedFileInExplorer $pos ";
    .menu2 add command -label "Stack Backtrace in Trace" -command "callStack $pos;";

    .menu2 add command -label "Show Current View Window in Overview" -command "show_current_view_on_overview";
    .menu2 add command -label "Select All" -command ".t tag add sel 1.0 end";
    .menu2 add command -label "Copy" -command "copySelection .t";
    .menu2 add command -label "Cut" -command "copySelection .t  cut";
    .menu2 add command -label "Paste" -command "multi_paste; break;";
    .menu2 add command -label "Trim" -command "trimSelection";
    .menu2 add command -label "Trim Left" -command "trimSelectionLeft";
    .menu2 add command -label "Trim Right" -command "trimSelectionRight";
    .menu2 add command -label "Format As Table" -command "formatAsTable .t";
    .menu2 add command -label "Copy To Html Clipboard" -command "copyToHtmlClipboard .t";
    .menu2 add command -label "Copy To Spectral" -command "copyToSpectral";
    .menu2 add command -label "Paste From Spectral" -command "pasteFromSpectral";
    .menu2 add command -label "Clear Selected Highlighting" -command "clearHighlights 1";
    .menu2 add command -label "Clear All Highlighting" -command "clearHighlights 0";
    .menu2 add command -label "Set Selected Words As Targets" -command "setSelectedWordsAsTargets";
    .menu2 add command -label "Insert Line Numbers" -command "insert_line_numbers";
    .menu2 add command -label "Delete Line Numbers" -command "delete_line_numbers";
    set extra_items [array names extra_popup_menu_items];
    foreach extra_item $extra_items {
       .menu2 add command -label $extra_item -command [set extra_popup_menu_items($extra_item)];     
    }
    tk_popup .menu2 $x $y;
}


bind .t <Key> {
   set selranges [.t tag ranges sel];
   if {[llength $selranges] > 2} {

    if {"%K" == "Delete"} {
      if {[llength $selranges] > 2} {
         set revranges [lreverse $selranges];
         foreach {end start} $revranges {
           .t fastdelete $start $end;
         }
         break;
       }  
      
  } elseif {"%K" == "BackSpace" } {
      set numsel [expr [llength $selranges] / 2];
      global update_frozen;
      set update_frozen 1;
      for {set i 0} {$i < $numsel} {incr i} {
         set selranges [.t tag ranges sel];
         set start [lindex $selranges [expr 2*$i]];
         if {$numsel == 1} {
             .t delete "$start - 1 char" $start;
         } else {
             .t fastdelete "$start - 1 char" $start;
         }
      }
      set update_frozen 0;
      update;
      break;
  } elseif {[string length %A] == 1 || "%K" ==  "space"} {    
      set numsel [expr [llength $selranges] / 2];
      for {set i 0} {$i < $numsel} {incr i} {
        set selranges [.t tag ranges sel];
        global update_frozen;
        set update_frozen 1;
        set start [lindex $selranges [expr 2*$i]];
        dott fastinsert $start %A;
        #addToStatus "<%K> -> <%A> $start";
      }
      set update_frozen 0;
      update;
      break;
   }  } elseif {"%K" == "braceright"} {
      set line [expr int([.t index insert])];
        set lineText [.t get "$line.0" "$line.end"];
        if {[regexp {^\s+$} $lineText]} {
           for {set i 1} {$i <= 4} {incr i} {
               set ch [.t get "$line.0" "$line.1"];
               if {$ch == " "} {
                   .t fastdelete "$line.0" "$line.1";
               } else {
                   break;
               }
           }
       }
  } elseif {"%K" == "braceleft"} {
        set pos [.t index insert];
        .t insert $pos "\{\}";
        .t mark set insert "$pos + 1 char";
        break;
  }

  after idle {
         set marker "";
         if {$modified} {
           set marker "(M)"
           .bottomFrame.toppos configure -background "orange";
           .bottomFrame.position configure -background "orange";
         } else {
             .bottomFrame.toppos configure -background "green";
            .bottomFrame.position configure -background "green";
        }
         set cursor_pos [.t index insert];
        .bottomFrame.toppos configure -text "END: [.t index end] ${marker}";
        .bottomFrame.position clear;
        .bottomFrame.position insert 0 $cursor_pos;
        update;
    };

}

bind .t <Control-y> {
   .t edit redo
}

proc find_occurrences {} {
  set curpos [.t index insert];
  set start [.t index "$curpos wordstart"];
  set end [.t index "$curpos wordend"];
  
  set selranges [.t tag ranges sel];
  if {[llength $selranges] == 2} {
      set start [lindex $selranges 0];
      set end [lindex $selranges 1];
      .t tag remove  sel 1.0 end;
  }
  set txt [.t get $start $end];
  selre $txt;  
}
proc textLen {save} {
    set num 0;
    foreach {key value} $save \
    {
        #puts stderr "$key :--> $value";
        switch $key \
        {
           
            T    {
                
                    incr num [string length $value];
                } 
        }
    }

   return $num;
}
bind .t <Control-z> {
    if {$last_op_was_overpainting} {
      set update_frozen 1; 
      #.t configure -autoseparators 0;
      #.t edit separator;
      .t configure -undo 0
      set undo_does_delete 0;
      if {$last_op_was_overpainting == 1} {
          set undo_does_delete 1;
      }
       foreach stuff $last_overpainted_stuff {
          foreach {start end richtext} $stuff {
              set one_more_undo 0;
               if {$undo_does_delete == 1} {
                   dott fastdelete $start $end;
               } else {
                   set one_more_undo 1;
               } 
               .t mark set insert $start; 
               catch {hlt:restore .t $richtext $start};
               
               if {$one_more_undo} {
                        .t mark set insert $start; 
                       .t configure -undo 1;
                       .t edit undo;
                       .t configure -undo 0;
                       set len [textLen $richtext]
                       dott fastdelete $start "$start + $len char";    
               }
          }
       }
       .t configure -undo 1;
       #.t edit separator;
       #.t configure -autoseparators 1;
       resetOverpaintedStuff;
       set update_frozen 0; 

    } else {
       dott edit undo;
       resetOverpaintedStuff;
       incr sepdepth -1;
   }
   break;
}

bind .t <Control-d> {
    foreach id {1 2 3 4 5 6} {
       set last_search($id) "";
    }
    break;
}

#b8b0ed12-2b01-4901-b033-61a4cf671b5a show; 
bind .t <Control-g> {
    selendl;
    break;
}

bind .t <Control-G> {
    splitsel;
    break;
}


bind .t <Control-k> {
    catch {delete_grepline_from_file};
    set line [expr int([.t index insert])];
    set end [.t index "$line.end + 1 char"];
    .t delete ${line}.0 $end;
    break;
}

bind .t <Control-n> autoComplete;

proc autoComplete {} {
    set insert_pos [.t index insert];
    set anchor [.t index "$insert_pos - 1 char"];
    set delstart [.t index "$anchor wordstart"];
    set delend [.t index  "$anchor wordend"];
    set word [.t get $delstart $delend];
    set word_len [string length $word];
    set expr "\\m";
    append expr $word;
    append expr "\\w+\\M";
    
    set matches {};
    set cur 1.0;
    set last_cur "";
    while 1 {
        set cur [.t search -regexp -count length $expr $cur end]
        if {$cur == "" || $cur == $last_cur } {
            break;
        }
        set match [.t get $cur "$cur + $length char"];
        if {[lsearch $matches $match] == -1} {
                lappend matches $match;
        }
        set cur [.t index "$cur + $length char"];
        set last_cur $cur;
    }

    global current_keywords;
    foreach kw $current_keywords {
       if {[string range $kw 0 [expr $word_len - 1]] == $word} {
         if {[lsearch $matches $kw] == -1} {  
           lappend matches $kw;
         }
       }
    }
    catch {destroy .menu1}
    set x 0;
    set y 0;
    set rootx [winfo rootx .t];
    set rooty [winfo rooty .t];
    set boundingBox [.t bbox [.t index insert]];
    if {[llength $boundingBox]} {
      set x [expr [lindex $boundingBox 0] + $rootx]
      set y [expr [lindex $boundingBox 1] + $rooty]
    } else {
       return;
    }
    set num_matches [llength $matches];
    if { $num_matches < 1} { } elseif { $num_matches == 1 } {
        .t insert $insert_pos $matches; .t fastdelete $delstart $delend;
    } else {
      menu .menu1 -tearoff 0;
      foreach match $matches {
        .menu1 add command -label $match -command " .t insert $insert_pos $match; .t fastdelete $delstart $delend ;";
      }
      .menu1 add separator;
      .menu1 add command -label "Cancel" -command {catch {destroy .menu1};}
      tk_popup .menu1 $x $y;
    }

}

bind .t <Alt-h> {setLastSelectionAsHyperlinkTarget; setFirstSelectionAsHyperlinkTarget; break;}
bind .t <Option-h> {setLastSelectionAsHyperlinkTarget; setFirstSelectionAsHyperlinkTarget; break;}

bind .t <Control-h> {setLastSelectionAsHyperlinkTarget; break;}
bind .t <Control-H> {setFirstSelectionAsHyperlinkTarget; break;}

bind .t <Control-j> {
    set line [expr int([.t index insert])];
    set cnt 0;
    set cur [.t index "$line.end"]
    set join_pt $cur;
    set did_delete 0;
    global update_frozen;
    set update_frozen 1;
    while {1} {
        set pos [.t index "$cur + 1 char"];

        if {$pos == [.t index end]} {
            break;
        }
        set ch [.t get $cur $pos];
        
        #puts stderr "ch=<$ch>";
        if {$ch == "\n" || $ch == " " || $ch == "\t" || $ch == "\r"} {
            .t fastdelete $cur "$cur + 1 char";
            set did_delete 1;
        } else {
            break;
        }
        #set cur [.t index "$cur + 1 char"];
    }
    if {$did_delete} {
    .t insert $join_pt " ";
    }
    set update_frozen 0;
    update;
}

array set matchdir {
    \{ 1
    \[ 1
    \( 1
    \} -1
    \] -1
    \) -1
    \" 1
    '  1
}

array set matchchar {
    \{ \}
    \[ \]
    \( \)
    \} \{
    \] \[
    \) \(
    \" \"
    '  '
}

proc matchNearestEnclosingBrace {{curPos {}} {bodytag {}}} {
    if {$curPos == ""} {
        set curPos [.t index insert];
    }
    set txt [string reverse [.t get 1.0 $curPos]];
    set distance 0;
    set len [string length $txt];
    set distance 0;
    set bestPos "";
    set depth 0;
    set numClosing 0;
    #puts stderr "text=<$txt>";
    for {set i 0} {$i < $len} {incr i} {
        set ch [string index $txt $i];
        if {$ch == "\{" }  {
            incr numClosing -1;
            if {$numClosing < 0} {
                incr depth;
                set bestPos $i;
                break;
            }
        }
        if {$ch == "\}"}  {
            incr numClosing;
        }  
    }
    if {$bestPos != ""} {
        set r [expr { int(100 * rand() + 150) }];
        set g [expr { int(100 * rand() + 150) }];
        set b [expr { int(100 * rand() + 150) }]
        set col [format "#%02x%02x%02x" $r $g $b];
        set tagname [guid];
        .t tag configure $tagname -background $col;   
        set matchpos [.t index "1.0 + [expr $len - $bestPos - 1] char"];
        set offset [num_glyphs .t 1.0 $matchpos];
        set matchpos [.t index "$matchpos + $offset char"];
        .t tag add $tagname $matchpos "$matchpos + 1 char";
        if {$bodytag != ""} {
            .t tag add $bodytag $matchpos $curPos;
        }
        .t see $matchpos;
        .t mark set insert $matchpos;
    }
}

proc reflow {n} {
    global modified; set modified 1;
    .t configure -autoseparators 0;
   .t edit separator;
    foreach {start end} [.t tag ranges sel] {
      set cur $start;
      set last_cur "";
      set expr {\s};
      set change 0;
      set splitend [split $end "."];
      set splitend0 [lindex $splitend 0];
      set splitend1 [lindex $splitend 1];
      while 1 {
        set newend "[expr $splitend0+$change].$splitend1";
        set cur [.t search -regexp $expr $cur $newend]
       
        if {$cur == ""} {
            break;
        }

        set col [lindex [split $cur "."] 1];
        set row [lindex [split $cur "."] 0];
        set match [.t get $cur "$cur + 1 char"];
        #puts "cur=$cur last_cur=$last_cur newend=$newend match=<$match> row=$row col=$col";

        
        if {$col < $n && ($match == "\n" || $match == "\r")} {
                # puts HERE1;
                .t fastdelete $cur "[expr $row + 1].0";
                .t insert $cur " ";
                incr change -1;
                 set cur [.t index "$cur + 1 char"];
        } elseif {$col > $n && ($match == " " || $match == "\t")} {
                # puts HERE2;
                 .t fastdelete $cur "$cur + 1 char";
                 .t insert $cur "\n";
                 incr change 1;
                 set cur "[expr $row + 1].0";
        } elseif { $match == "\n" || $match == "\r"}  {
                # puts HERE3;
              set cur "[expr $row + 1].0";
        } elseif { $match == " " || $match == "\t"}  {
                # puts HERE4;
             set cur [.t index "$cur + 1 char"];
        } else {
            # puts HERE5;
            set cur [.t index "$cur + 1 char"];
        }
        set last_cur $cur;
     }
   }
   
   .t edit separator;
   .t configure -autoseparators 1;
}

proc matchNearestEnclosingBraceBracketOrParen {{curPos {}} {bodytag {}}} {
    if {$curPos == ""} {
      set curPos [.t index insert];
    }
    set txt [string reverse [.t get 1.0 $curPos]];
    set distance 0;
    set len [string length $txt];
    set distance 0;
    set bestPos "";
    set depth 0;
    set numClosing 0;
    #puts stderr "text=<$txt>";
    for {set i 0} {$i < $len} {incr i} {
        set ch [string index $txt $i];
        if {$ch == "\{" || $ch == "(" || $ch == "\["}  {
            incr numClosing -1;
            if {$numClosing < 0} {
                incr depth;
                set bestPos $i;
                break;
            }
        }
        if {$ch == "\}" || $ch == ")" || $ch == "\]"}  {
            incr numClosing;
        }  
    }
    if {$bestPos != ""} {
        set r [expr { int(100 * rand() + 150) }];
        set g [expr { int(100 * rand() + 150) }];
        set b [expr { int(100 * rand() + 150) }]
        set col [format "#%02x%02x%02x" $r $g $b];
        set tagname [guid];
        .t tag configure $tagname -background $col;
        set matchpos [.t index "1.0 + [expr $len - $bestPos -1] char"];
        set offset [num_glyphs .t 1.0 $matchpos];
        set matchpos [.t index "$matchpos + $offset char"];
        .t tag add $tagname $matchpos "$matchpos + 1 char";
        if {$bodytag != ""} {
            .t tag add $bodytag $matchpos $curPos;
        }
        .t see $matchpos;
        .t mark set insert $matchpos;
    }
}




proc matchBracket {{widget .t} {idx {}} {bodytag {}}} {
    global highlight_colors;
    set r [expr { int(100 * rand() + 150) }];
    set g [expr { int(100 * rand() + 150) }];
    set b [expr { int(100 * rand() + 150) }]
    set col [format "#%02x%02x%02x" $r $g $b];
    set tagname [guid];
    $widget tag configure $tagname -background $col;
    lappend highlight_colors $tagname;
    global matchdir;
    global matchchar;
    if {$idx == ""} {
       set idx [$widget index insert];
    }
    set ch [$widget get $idx];
    if {![info exists matchdir($ch)]} {
        return;
    }
    set dir [set matchdir($ch)];
    set mc  [set matchchar($ch)];
    if {$dir == 1} {
        set txt [$widget get "$idx + 1 char" end];
    } elseif {$dir == -1} {
        set txt [string reverse [$widget get 1.0 $idx]];
    }

    set len [string length $txt];
    set distance 0;
    set depth 1;
    set matched 0;
    #tk_messageBox -message "text=<$txt>";
    for {set i 0} {$i < $len} {incr i} {
       set ach [string index $txt $i];
       #puts $ach;
       incr distance;
       set escape 0;
       if {$ach == $ch || $ach == $mc} {
           if {$dir == -1} {
               for {set j [expr $i + 1]} {$j < $len} {incr j} {
                  if {[string index $txt $j] == "\\"} {
                    incr escape;
                  } else break;
              }
          } else {
              for {set j [expr $i - 1]} {$j >= 0} {incr j -1} {
                  if {[string index $txt $j] == "\\"} {
                    incr escape;
                  } else break;
              }
          }
       }
       set escape [expr $escape%2];
       if {$ach == $mc} {
          if {$escape == 0} {incr depth -1;}
          
       } elseif {$ach == $ch} {
          if {$escape == 0} {incr depth;}
       }
       if {$depth == 0} {
           
           set matched 1;
           break;
       }
    }

    if {$bodytag == ""} {
        set bodytag sel;
    }
    if {$matched} {
      $widget tag add $tagname $idx  "$idx + 1 char";
      set matchpos "";
      set offset 0;
      if {$dir == 1} {
        set matchpos [$widget index "$idx + $distance char"];
        set offset [num_glyphs $widget $idx "$idx + $distance char"];
        set matchpos [$widget index "$matchpos + $offset char"];
          $widget tag add $bodytag "$idx + 1 char" $matchpos;
      } else {
          set matchpos [$widget index "$idx - $distance char"];
          set offset [num_glyphs $widget "$idx - $distance char" $idx];
          set matchpos [$widget index "$matchpos - $offset char"];
         $widget tag add $bodytag $matchpos "$idx + 1 char";
      }
      
      $widget tag add $tagname $matchpos "$matchpos + 1 char";
      $widget see $matchpos;
      $widget mark set insert $matchpos;
      
    }

}

proc matchElement {{bracket "<"}} {
    global highlight_colors;
    set r [expr { int(100 * rand() + 150) }];
    set g [expr { int(100 * rand() + 150) }];
    set b [expr { int(100 * rand() + 150) }]
    set col [format "#%02x%02x%02x" $r $g $b];
    set tagname [guid];
    .t tag configure $tagname -background $col;
    lappend highlight_colors $tagname;
    global matchdir;
    global matchchar;
    set idx [.t index insert];
    set idxStart [.t index "$idx wordstart"];
    set idxEnd   [.t index "$idx wordend"];
    set prevChar [.t get [.t index "$idxStart - 1 c"]]
    set ch [.t get $idxStart $idxEnd];
    
    #puts "idxStart=$idxStart idxEnd=$idxEnd ch=${ch} prevChar=${prevChar}";

    set len [string length $ch]
    
    if {$prevChar == $bracket} {
        set mc "/${ch}";
        set ch "${bracket}${ch}";
        set dir 1;
    } elseif {$prevChar == "/"} {
        set mc "${bracket}${ch}";
        set ch "/${ch}";
        set dir -1;
    } else {
        puts "Html element format not supported"
        return;
    }

    if {$dir == 1} {
        set txt [.t get "$idxEnd + 1 char" end];

    } elseif {$dir == -1} {
        set txt [string reverse [.t get 1.0 $idxStart]];
        set mc [string reverse $mc];
        set ch [string reverse $ch];
    }

    set len [string length $ch];
    set distance 0;
    set depth 1;
    set matched 0;
    #tk_messageBox -message "text=<$txt>";
    set foundMatch "";
    set offset 0;
    set chCount 0;
    set circuitBreakerCount 0;
    while {1} {
        incr circuitBreakerCount;
        if {$circuitBreakerCount > 10000000} {
            puts "circuit breaker condition reached"
            break;
        }
        #puts "searching for ch=$ch and mc=$mc  offset=$offset dir=$dir chCount=$chCount in $txt";
        set locCh [string first $ch $txt];
        set locMc [string first $mc $txt];
        #puts "locCh=$locCh locMc=$locMc";
        if {$locMc == -1} {
           break;
        }
        if {$locCh == -1} {
            if {$chCount == 0} {
                #puts "A breaking locCh=$locCh locMc=$locMc";
              set foundMatch $locMc;
              break;
           } else {
               set offset [expr $offset+$locMc+$len];
               set txt [string range $txt [expr $locMc+$len] end];
               #puts "A decrementing chCount"
              incr chCount -1; 
           }
        } else {
             
           if {$locCh > $locMc} {
             if {$chCount == 0} {
               #puts "B breaking locCh=$locCh locMc=$locMc";
               set foundMatch $locMc;
               break;
             } else {
               set offset [expr $offset+$locMc+$len];
               set txt [string range $txt [expr $locMc+$len] end];
               #puts "B decrementing chCount"
               incr chCount -1;
               
             } 
           } else {
               set offset [expr $offset+$locCh+$len];
               set txt [string range $txt [expr $locCh+$len] end];
               incr chCount;
           }
        }
    }

    if {$foundMatch != ""} {
      
      .t tag add $tagname $idxStart $idxEnd;
      set matchpos "";
      set offsetGlyph 0;
      if {$dir == 1} {
          set distance [expr $foundMatch + $offset+1];
        set matchpos [.t index "$idxEnd + $distance char"];
        set offsetGlyph [num_glyphs .t $idxStart "$idxEnd + $distance char"];
        set matchpos [.t index "$matchpos + $offsetGlyph char"];
          .t tag add sel $idxStart $matchpos;
          .t tag add $tagname $matchpos "$matchpos + $len char";
      } else {
          set distance [expr $foundMatch + $offset];
          set matchpos [.t index "$idxStart - $distance char"];
          set offsetGlyph [num_glyphs .t $matchpos $idxStart];
          set matchpos [.t index "$matchpos - $offsetGlyph char"];
         .t tag add sel $matchpos "$idxEnd + 1 char";
         .t tag add $tagname  "$matchpos - $len char" $matchpos;
      }
      .t see $matchpos;
      .t mark set insert $matchpos;
      
    }

}
bind .t <Control-m> {matchBracket};
bind .t <Control-b> {matchNearestEnclosingBrace};
bind .t <Control-B> {matchNearestEnclosingBraceBracketOrParen};
bind .t <Control-Key-1> {startNote 1;}
bind .t <Control-Key-2> {startNote 2;}
bind .t <Control-Key-3> {startNote 3;}
bind .t <Control-Key-4> {startNote 4;}
bind .t <Control-Key-5> {startNote 5;}
bind .t <Control-Key-6> {startNote 6;}
bind .t <Control-e> {matchElement;}
bind .t <Alt-e> {matchElement;}
bind .t <Control-E> {matchElement {[};}
bind .t <Alt-E> {matchElement {[};}
bind .t <Control-p> {pickColor; break;}
bind .status <Control-o> {showOutput [.status get 1.0 end] status {} {}; break;}
bind .status <Control-O> {.status delete 1.0 end; break;}

bind .t <Control-o> {insert_line_after_grepline  0;break;}
bind .t <Control-O> {insert_line_after_grepline -1;break;}
bind .t <Control-u> {apply_changes_from_greplines; break;};
bind .t <Control-U> {load_all_listed_files;break;};
catch {
    load_trace_lookup;
}

maximizeWindow .

.t tag raise sel;

.t tag configure tiny -font "courier 2 normal" -foreground "grey";
.t tag raise tiny;

catch { .searchFrame.search1 insert end [registry get $regroot search1] }
catch { .searchFrame.search2 insert end [registry get $regroot search2] }
catch { .searchFrame.search3 insert end [registry get $regroot search3] }
catch { .searchFrame.search4 insert end [registry get $regroot search4] }
catch { .searchFrame.search5 insert end [registry get $regroot search5] }
catch { .searchFrame.search6 insert end [registry get $regroot search6] }
catch { .bottomFrame.replace insert end [registry get $regroot replace] }
catch { .bottomFrame.with insert end [registry get $regroot with] }
catch { .bottomFrame.init insert end [registry get $regroot init] }
catch { .bottomFrame.incr insert end [registry get $regroot incr] }
catch { .bottomFrame.subst insert end [registry get $regroot subst] }
catch { .bottomFrame.expr insert end [registry get $regroot expr] }
catch { .bottomFrame.enforceLC insert end [registry get $regroot enforceLC] }
catch { .bottomFrame.enforceRC insert end [registry get $regroot enforceRC] }


proc edit {fname} {
    openFile .t $fname;
    global modified;
    set modified 0;
    return "";
}

proc save {} {
    saveFile .t;
}

#### Font chooser ###########################
catch {package require tile}                    ;# Not needed, but looks better
 
 namespace eval ::ChooseFont {
    variable S
 
    set S(W) .cfont
    set S(fonts) [lsort -dictionary [font families]]
    set S(styles) {Regular Italic Bold "Bold Italic"}
 
    set S(sizes) {8 9 10 11 12 14 16 18 20 22 24 26 28 36 48 72}
    set S(strike) 0
    set S(under) 0
    set S(first) 1
 
    set S(fonts,lcase) {}
    foreach font $S(fonts) { lappend S(fonts,lcase) [string tolower $font]}
    set S(styles,lcase) {regular italic bold "bold italic"}
    set S(sizes,lcase) $S(sizes)
 
 }
 proc ::ChooseFont::ChooseFont {{defaultFont ""}} {
    variable S
 
    destroy $S(W)
    toplevel $S(W) -padx 10 -pady 10
    wm title $S(W) "Font"
 
    set tile [expr {[catch {package present tile}] ? "" : "::ttk"}]
 
    ${tile}::label $S(W).font -text "Font:"
    ${tile}::label $S(W).style -text "Font style:"
    ${tile}::label $S(W).size -text "Size:"
    entry $S(W).efont -textvariable ::ChooseFont::S(font) ;# -state disabled
    entry $S(W).estyle -textvariable ::ChooseFont::S(style) ;# -state disabled
    entry $S(W).esize -textvariable ::ChooseFont::S(size) -width 0 \
        -validate key -vcmd {string is double %P}
 
    ${tile}::scrollbar $S(W).sbfonts -command [list $S(W).lfonts yview]
    listbox $S(W).lfonts -listvariable ::ChooseFont::S(fonts) -height 7 \
        -yscroll [list $S(W).sbfonts set] -height 7 -exportselection 0
    listbox $S(W).lstyles -listvariable ::ChooseFont::S(styles) -height 7 \
        -exportselection 0
    ${tile}::scrollbar $S(W).sbsizes -command [list $S(W).lsizes yview]
    listbox $S(W).lsizes -listvariable ::ChooseFont::S(sizes) \
        -yscroll [list $S(W).sbsizes set] -width 6 -height 7 -exportselection 0
 
    bind $S(W).lfonts <<ListboxSelect>> [list ::ChooseFont::Click font]
    bind $S(W).lstyles <<ListboxSelect>> [list ::ChooseFont::Click style]
    bind $S(W).lsizes <<ListboxSelect>> [list ::ChooseFont::Click size]
 
    set WE $S(W).effects
    ${tile}::labelframe $WE -text "Effects"
    ${tile}::checkbutton $WE.strike -variable ::ChooseFont::S(strike) \
        -text Strikeout -command [list ::ChooseFont::Click strike]
    ${tile}::checkbutton $WE.under -variable ::ChooseFont::S(under) \
        -text Underline -command [list ::ChooseFont::Click under]
 
    ${tile}::button $S(W).ok -text OK -command [list ::ChooseFont::Done 1]
    ${tile}::button $S(W).cancel -text Cancel -command [list ::ChooseFont::Done 0]
    wm protocol $S(W) WM_DELETE_WINDOW [list ::ChooseFont::Done 0]
 
    grid $S(W).font - x $S(W).style - x $S(W).size - x -sticky w
    grid $S(W).efont - x $S(W).estyle - x $S(W).esize - x $S(W).ok -sticky ew
    grid $S(W).lfonts $S(W).sbfonts x \
        $S(W).lstyles - x \
        $S(W).lsizes $S(W).sbsizes x \
        $S(W).cancel -sticky news
    grid config $S(W).cancel -sticky n -pady 5
    grid columnconfigure $S(W) {2 5 8} -minsize 10
    grid columnconfigure $S(W) {0 3 6} -weight 1
 
    grid $WE.strike -sticky w -padx 10
    grid $WE.under -sticky w -padx 10
    grid columnconfigure $WE 1 -weight 1
    grid $WE - x -sticky news -row 100 -column 0
 
    set WS $S(W).sample
    ${tile}::labelframe $WS -text "Sample"
    label $WS.fsample -bd 2 -relief sunken
    label $WS.fsample.sample -text "AaBbYyZz"
    set S(sample) $WS.fsample.sample
    pack $WS.fsample -fill both -expand 1 -padx 10 -pady 10 -ipady 15
    pack $WS.fsample.sample -fill both -expand 1
    pack propagate $WS.fsample 0
 
    grid rowconfigure $S(W) 2 -weight 1
    grid rowconfigure $S(W) 99 -minsize 30
    grid $WS - - - - -sticky news -row 100 -column 3
    grid rowconfigure $S(W) 101 -minsize 30
 
    trace variable ::ChooseFont::S(size) w ::ChooseFont::Tracer
    trace variable ::ChooseFont::S(style) w ::ChooseFont::Tracer
    trace variable ::ChooseFont::S(font) w ::ChooseFont::Tracer
    ::ChooseFont::Init $defaultFont
    tkwait window $S(W)
    trace remove variable ::ChooseFont::S(size) write ::ChooseFont::Tracer
    trace remove variable ::ChooseFont::S(style) write ::ChooseFont::Tracer
    trace remove variable ::ChooseFont::S(font) write ::ChooseFont::Tracer
    return $S(result)
 }
 
 proc ::ChooseFont::Done {ok} {
    if {! $ok} {set ::ChooseFont::S(result) ""}
    destroy $::ChooseFont::S(W)
 }
 proc ::ChooseFont::Init {{defaultFont ""}} {
    variable S
 
    if {$S(first) || $defaultFont ne ""} {
        if {$defaultFont eq ""} {
            set defaultFont [[entry .___e] cget -font]
            destroy .___e
        }
        array set F [font actual $defaultFont]
        set S(font) $F(-family)
        set S(size) $F(-size)
        set S(strike) $F(-overstrike)
        set S(under) $F(-underline)
        set S(style) "Regular"
        if {$F(-weight) eq "bold" && $F(-slant) eq "italic"} {
            set S(style) "Bold Italic"
        } elseif {$F(-weight) eq "bold"} {
            set S(style) "Bold"
        } elseif {$F(-slant) eq "italic"} {
            set S(style) "Italic"
        }
 
        set S(first) 0
    }
 
    ::ChooseFont::Tracer a b c
    ::ChooseFont::Show
 }
 
 proc ::ChooseFont::Click {who} {
    variable S
 
    if {$who eq "font"} {
        set S(font) [$S(W).lfonts get [$S(W).lfonts curselection]]
    } elseif {$who eq "style"} {
        set S(style) [$S(W).lstyles get [$S(W).lstyles curselection]]
    } elseif {$who eq "size"} {
        set S(size) [$S(W).lsizes get [$S(W).lsizes curselection]]
    }
    ::ChooseFont::Show
 }
proc ::ChooseFont::Tracer {var1 var2 op} {
    variable S
 
    set bad 0
    set nstate normal
    # Make selection in each listbox
    foreach var {font style size} {
        set value [string tolower $S($var)]
        $S(W).l${var}s selection clear 0 end
        set n [lsearch -exact $S(${var}s,lcase) $value]
        $S(W).l${var}s selection set $n
        if {$n != -1} {
            set S($var) [lindex $S(${var}s) $n]
            $S(W).e$var icursor end
            $S(W).e$var selection clear
        } else {                                ;# No match, try prefix
            # Size is weird: valid numbers are legal but don't display
            # unless in the font size list
            set n [lsearch -glob $S(${var}s,lcase) "$value*"]
            set bad 1
            if {$var ne "size" || ! [string is double -strict $value]} {
                set nstate disabled
            }
        }
        $S(W).l${var}s see $n
    }
    if {! $bad} ::ChooseFont::Show
    $S(W).ok config -state $nstate
 }
 
 proc ::ChooseFont::Show {} {
    variable S
    set S(result) [list $S(font) $S(size)]
    if {$S(style) eq "Bold"} { lappend S(result) bold }
    if {$S(style) eq "Italic"} { lappend S(result) italic }
    if {$S(style) eq "Bold Italic"} { lappend S(result) bold italic}
    if {$S(strike)} { lappend S(result) overstrike}
    if {$S(under)} { lappend S(result) underline}
 
    $S(sample) config -font $S(result)
 }
##########################################
proc stacktrace {} {
    set stack "Stack trace:\n"
    for {set i 1} {$i < [info level]} {incr i} {
        set lvl [info level -$i]
        set pname [lindex $lvl 0]
        append stack [string repeat " " $i] $pname
        if 0 {
        foreach value [lrange $lvl 1 end] arg [info args $pname] {
            if {$value == ""} {
                info default $pname $arg value
            }
            append stack " $arg='$value'"
        }
        }
        append stack "\n"
    }
    return $stack
}
set send_bgerror_to_status 0;
proc configure_send_bgerror_to_status {val} {
    global send_bgerror_to_status;
    set send_bgerror_to_status $val;
}

proc bgerror {message} {
    
    set timestamp [clock format [clock seconds]]
    global ::errorInfo;
    global send_bgerror_to_status;
    if {$send_bgerror_to_status} {
        addToStatus "$timestamp: Error '$message' $::errorInfo";
    }
}

rename .t dott;
proc .t {args} {
    global autosyn_mode;
    global last_op_was_overpainting;
    global modified;
    global viewpoints;
    if {!$autosyn_mode} {
        set subcmd [lindex $args 0];
        if {$subcmd == "insert"} {
            set modified 1;
            set last_op_was_overpainting 0;
            uplevel [list dott fastinsert {*}[lrange $args 1 end]];
        } elseif {$subcmd == "delete" || $subcmd == "fastdelete"} {
              dott tag add sel {*}[lrange $args 1 end];
              set ng 0;
              set nc 0;
              if {$subcmd == "delete"} {
                set ngnc [num_glyphs_and_chars .t {*}[lrange $args 1 end]];
                set ng [lindex $ngnc 0]
                set nc [lindex $ngnc 1]
                if {$ng || ($nc > 2)} {
                resetOverpaintedStuff;
                saveSelectionForUndo .t;
                set last_op_was_overpainting 2;
                #dott configure -undo 0;
                }
              }
              uplevel [list dott fastdelete {*}[lrange $args 1 end]];
               if {($subcmd == "delete") && $ng && $nc > 2} {
                  #dott configure -undo 1;
                  set last_op_was_overpainting 2;
              }
            
        } elseif {$subcmd == "see" || $subcmd == "yview"} {
            if {![catch {expr {*}[lrange $args 1 end]}]}  {
              if  {[llength  $args] > 1} {
                append_to_viewpoints {*}[lrange $args 1 end];
              }
          }
         uplevel [list dott $subcmd {*}[lrange $args 1 end]];
            
        } elseif {$subcmd == "tag"} {
             set subsubcmd [lindex $args 1];
             global modified;
             if {$subsubcmd == "add" || $subsubcmd == "remove"} {
                 if { [lindex $args 2] != "sel"} {
                     set modified 1;
                 }
             }
             uplevel [list dott {*}[set args]];

        } elseif {$subcmd == "edit"} {
            set subsubcmd [lindex $args 1];
            if {$subsubcmd == "separator"} {
                global sepdepth;
                incr sepdepth;
                #jmtodo
            }
            uplevel [list dott {*}[set args]];
              
        } else {
           uplevel [list dott {*}[set args]];
        }
    } else {
        uplevel [list dott {*}[set args]];
    }
}

append all_commands " " [info commands];

rename info nkTVeN7o2Qp

proc info {args} {
   set subcmd [lindex $args 0];
   if {$subcmd == "body"} {
        return "";
    } else {
        uplevel [list nkTVeN7o2Qp {*}[set args]];
    }
}
proc vanillaMode {} {
   global autosyn_mode;
   set autosyn_mode 0;
}
proc ctextMode {} {
   global autosyn_mode;
   set autosyn_mode 1;
}

#rename .t dott; proc .t {args} { set subcmd [lindex $args 1]; if {$subcmd == "insert"} { dott fastinsert {*}[lrange $args 1 end]; } elseif {$subcmd == "delete"} { dott fastdelete {*}[lrange $args 1 end]; } else { dott {*}[set args]; } }

##########################################
proc cmd_to_editor {} {
    global cmd_to_editor;
    return $cmd_to_editor;
}



proc reformat_xml {{xml {} }} {
   if {$xml == ""} {
        set selranges [.t tag ranges sel];
        foreach {start end} $selranges {
        append xml [.t get $start $end];
       }
   }
   set dom [dom parse $xml];
   set doc [$dom documentElement];
   set result [$doc asXML];
   return $result;
}


proc reformat_xml_file {fname} {
    set fp [open $fname r];
    set xml [read $fp];
    close $fp;
    set result $xml;
    if {[catch {
       set dom [dom parse $xml];
       set doc [$dom documentElement];
       set result [$doc asXML];
           } ] } {
               tk_messageBox -message "Failed to reformat xml file" -title "Error";
           } else {
               set fp [open $fname w];
               puts $fp $result;
               close $fp;
           }
}

proc seltoend {} {
   .t tag remove sel 1.0 end;
   set cur [.t index insert];
   .t tag add sel $cur end;
}

proc selfromstart {} {
   .t tag remove sel 1.0 end;
   set cur [.t index insert];
   .t tag add sel 1.0 $cur;
}

proc sel {args} {
 catch {
  .t tag remove sel 1.0 end;
  set numargs [llength $args];
  set curline [expr int([.t index insert])];
  if {$numargs == 0} {
     .t tag add sel $curline.0 $curline.end;
  } elseif {$numargs == 1} {
      .t tag add sel $curline.0 [expr "$curline + ($args)"].0;
  } else {
      foreach {start end} $args {
       if {[string first $start "."] == -1} {
            set start "$start.0"
        }
        if {[string first $end "."] == -1} {
            set end "$end.end + 1 char"
        }
      .t tag add sel $start $end;
      }
    }
 } msg;
  puts $msg;
}

proc hl {id args} {
 catch {
    set id [expr (($id - 1) % 6) +1]
    global fixed_boxes;
    global all_tags;
    global currentColor;
    array set colors [set fixed_boxes];
    set colors(6) [set currentColor];
    set color [set colors($id)];
    .t tag configure $color -background $color;

  set numargs [llength $args];
  set curline [expr int([.t index insert])];
  if {$numargs == 0} {
      foreach other $all_tags {
               if {![regexp {(^target_)|(^hyperref_)} $other]} {
                .t tag remove $other $curline.0 $curline.end;
               }
            }
      .t tag add $color $curline.0 $curline.end;
  } elseif {$numargs == 1} {
       foreach other $all_tags {
                if {![regexp {(^target_)|(^hyperref_)} $other]} {
                .t tag remove $other $curline.0 [expr "$curline + ($args)"].0;
               }
            }
      .t tag add $color $curline.0 [expr "$curline + ($args)"].0;
  } else {
      foreach {start end} $args {
       if {[string first $start "."] == -1} {
            set start "$start.0"
        }
        if {[string first $end "."] == -1} {
            set end "$end.end + 1 char"
        }
        foreach other $all_tags {
               if {![regexp {(^target_)|(^hyperref_)} $other]} {
                .t tag remove $other $start $end ;
              }
         }
      .t tag add $color $start $end;
      }
    }
 } msg;
  puts $msg;
}

proc delline {regex} {

    set lines {};
    
      set selranges [.t tag ranges sel];
      foreach {start end} $selranges {
         set first [lindex [split $start "."] 0];     
         set last [lindex [split $end "."] 0]; 
         for {set i $first} {$i <= $last} {incr i} {
             set linecont [.t get $i.0 $i.end];
             if {[regexp $regex $linecont]} {
                 lappend lines $i;
             }
         }
       }  
    
    set lines [lsort -integer -decreasing $lines];
    foreach line $lines {
        .t fastdelete "$line.0" "$line.end + 1c";
    }
}

proc dellines {args} {
    set numargs [llength $args]; 
    
    if {$numargs == 0} {
      set selranges [.t tag ranges sel];
      set lines {};
      foreach {start end} $selranges {
         set first [lindex [split $start "."] 0];     
         set last [lindex [split $end "."] 0]; 
         for {set i $first} {$i <= $last} {incr i} {
             if {[lsearch $lines $i] == -1} {
                 lappend lines $i;
             }
         }
         
    }
    set lines [lsort -integer -decreasing $lines];
    foreach line $lines {
        .t fastdelete "$line.0" "$line.end + 1c";
    }
  }  else {
         foreach line $args {
            .t fastdelete "$line.0" "$line.end + 1c";
         }
    }
}

proc keeplines {args} {
    set numargs [llength $args]; 
    set lines {};
    set lastline [lindex [split [.t index end] "."] 0]; 
    for {set i 1} {$i <= $lastline} {incr i} {
        lappend lines $i;
    }
    if {$numargs == 0} {
       set selranges [.t tag ranges sel];

       foreach {start end} $selranges {
         set first [lindex [split $start "."] 0];     
         set last [lindex [split $end "."] 0]; 
         for {set i $first} {$i <= $last} {incr i} {
            lremove lines $i; 
          }
        }
        set lines [lsort -integer -decreasing $lines];
        foreach line $lines {
           .t fastdelete "$line.0" "$line.end + 1c";
        }
    } else {
         foreach line $args {
             lremove lines $line;
         }

         foreach line $lines {
            .t fastdelete "$line.0" "$line.end + 1c";
         }
    }

}




proc del {args} {
 catch {
  set numargs [llength $args];
  set curline [expr int([.t index insert])];
  if {$numargs == 0} {
      if {[hasSelection]} {
          set selranges [.t tag ranges sel];
          foreach {start end} $selranges {
              .t fastdelete $start $end;
           }
      } else {
         .t fastdelete $curline.0 "$curline.end + 1c";
      }
  } elseif {$numargs == 1} {
      .t fastdelete $curline.0 [expr "$curline + ($args)"].0;
  } else {
      foreach {start end} $args {
        if {[string first $start "."] == -1} {
            set start "$start.0"
        }
        if {[string first $end "."] == -1} {
            set end "$end.end + 1 char"
        }
        .t fastdelete $start $end;
      }
    }
 } msg;
  puts $msg;
}

proc set_bg {color} {
    global default_background;
    .t configure -background $color;
    set default_background $color;
}

proc set_fg {color} {
    global default_foreground;
    .t configure -foreground $color;
    set default_foreground $color;
}

proc u {} {
    global sepdepth;
    .t edit undo;
    incr sepdepth -1;
}

proc p {} {
    set clp [clipboard get -type STRING];
    if {$clp == ""} {return;}
    set lastchar [string index $clp end-1];
    set pos [.t index insert];
    
    if {$lastchar == "\n"} {
      set pos [.t index "$pos lineend"];
      .t mark set insert $pos;
      set pos2 [.t index "$pos + 1 char"];
      if {$pos2 == $pos} {
          .t insert [.t index insert] "\n";
      } else {
          .t mark set insert $pos2;
      }
      
    }
    pasteSingleSelection;
}

proc pn {n} {
    set clp [clipboard get -type STRING];
    set lastchar [string index $clp end-1];
    set pos [.t index insert];
    
    if {$lastchar == "\n"} {
      set pos [.t index "$pos lineend"];
      .t mark set insert $pos;
      set pos2 [.t index "$pos + 1 char"];
      if {$pos2 == $pos} {
          .t insert [.t index insert] "\n";
      } else {
          .t mark set insert $pos2;
      }
      
    }
    for {set i 0} {$i < $n} {incr i} {
        pasteSingleSelection;
    }
}

proc yp {args} {
    yy;
    if {[llength $args]} {
      foreach x $args {
        pn $x; 
      }
    } else {
        p;
    }
}
proc yy {args} {
 catch {
  set numargs [llength $args];
  set curline [expr int([.t index insert])];
  set start NA;
  set end NA;
  set items {};
  clipboard clear;
  #puts stderr $numargs;
  if {$numargs == 0} {
          set start $curline.0;
          set end "$curline.end + 1c";

          set items [hlt:save .t $start $end]
          clipboard append -type STRING [.t get $start $end];
          clipboard append -type STRING "\n";
          clipboard append -type HLT $items;
          #puts stderr $items;
          #.t delete $start $end;
          
  } elseif {$numargs == 1} {
      if {$args > 0} {
          set start $curline.0;
          set end [expr "$curline + ($args)"].0;
      } else {
          set start [expr "$curline + ($args)"].0;;
          set end [expr "$curline + 1"].0;
      }

      #puts stderr "copy range = $start $end" 
      set items [hlt:save .t $start $end]
      clipboard append -type STRING [.t get $start $end];
      clipboard append -type HLT $items;
      clipboard append -type STRING "\n";
          #puts stderr $items;
      #.t delete $start $end;

  } else {
      foreach {start end} $args {
        if {[string first $start "."] == -1} {
            set start "$start.0"
        }
        if {[string first $end "."] == -1} {
            set end "$end.end + 1 char"
        }
        set saved [hlt:save .t $start $end];
        foreach  item $saved {
           lappend items $item;
        }
        clipboard append -type STRING [.t get $start $end];
        clipboard append -type STRING "\n";
        #break;
      }
      
      clipboard append -type HLT $items;
    }
 } msg;
  puts $msg;
}


proc dd {args} {
 catch {
  set numargs [llength $args];
  set curline [expr int([.t index insert])];
  set start NA;
  set end NA;
  clipboard clear;
  if {$numargs == 0} {
          set start $curline.0;
          set end "$curline.end + 1c";

          set items [hlt:save .t $start $end]
          clipboard append -type STRING [.t get $start $end];
          clipboard append -type STRING "\n";
          clipboard append -type HLT $items;
          .t delete $start $end;
          
  } elseif {$numargs == 1} {

      if {$args > 0} {
           set start $curline.0;
           set end [expr "$curline + ($args)"].0;
      } else {
           set start [expr "$curline + ($args)"].0;;
           set end [expr "$curline + 1"].0;
      }

      
      set items [hlt:save .t $start $end]
      clipboard append -type STRING [.t get $start $end];
      clipboard append -type STRING "\n";
      clipboard append -type HLT $items;
      .t delete $start $end;

  } else {

      set items {};
      foreach {start end} $args {
        if {[string first $start "."] == -1} {
            set start "$start.0"
        }
        if {[string first $end "."] == -1} {
            set end "$end.end + 1 char"
        }
        set saved [hlt:save .t $start $end];
        foreach item $saved {
           lappend items $item;
        }
        clipboard append -type STRING [.t get $start $end];
        .t delete $start $end;
        break;
       
      }
      clipboard append -type STRING "\n";
      clipboard append -type HLT $items;
    }
 } msg;
  #puts stderr $msg;
}


proc / {args} {
   [.searchFrame.search6 component entry] delete 0 end;
   [.searchFrame.search6 component entry] insert end $args;
   focus [.searchFrame.search6 component entry]; 
   searchString 1 6 {}
}

foreach id {1 2 3 4 5 6} {
   set body "
   \[.searchFrame.search$id component entry\] delete 0 end;
   \[.searchFrame.search$id component entry\] insert end \$args;
   focus \[.searchFrame.search$id component entry\]; 
   searchString 1 $id {} "
   proc "$id/" {args}  $body;
   interp alias $qcInterp "$id/" {} "$id/";
}
proc quilt {} {

    global highlight_colors;
    if {[llength $highlight_colors] < 20} {
        for {set i 0} {$i < 20} {incr i} {
        set tagname "";
        set r [expr { int(100 * rand() + 150) }]
        set g [expr { int(100 * rand() + 150) }]
        set b [expr { int(100 * rand() + 150) }]
        set col [format "#%02x%02x%02x" $r $g $b];
        set tagname "U[uuid::uuid generate]";
        .t tag configure $tagname -background $col;
        lappend highlight_colors $tagname;
        }
    }
    set ncolors [llength $highlight_colors];
    
   
   set ranges [.t tag ranges sel];
   foreach {start end} $ranges {
       set wordstart [.t index "$start wordstart"];
       set wordend [.t index "$start wordend"];
       while {1} {
        
        
        set names1 [.t tag names $wordstart];
        if {[lsearch $names1 sel] == -1} {
             set names2 [.t tag names $wordend];
             if {[lsearch $names2 sel] == -1} {
                break;
             }
        }

        if {[regexp {^\s*$} [.t get $wordstart $wordend]]} {
            set isgray [expr int($wordstart) % 2];
            if {$isgray} {
               .t tag add bg_lavender $wordstart $wordend; 
            }
        } else {
            set tagname [lindex $highlight_colors [expr {int(rand()*$ncolors)}]]
            .t tag add $tagname $wordstart $wordend;
        }

        set nextpos [.t search -regexp {\s*[^ \t\n\r]} "$wordend" end];
        if {$nextpos == ""} {
          break;
        }
        set wordstart [.t index "$nextpos wordstart"];
        set wordend [.t index "$nextpos wordend"];
          
       }
   }
}

proc dw {{n 1}} {
    set pos [.t index insert];
    set start "$pos wordstart";
    set end "$pos wordend";
    for {set i 0} {$i < [expr $n-1]} {incr i} {
         set end1 [.t search -regexp {\s*} $end end];
         if {$end1 != $end} {
            incr i -1;
         }
         if {$end1 == ""} break;
         set end1 [.t index "$end1 wordend"];
         if {$end1 == ""} break;
         set end $end1;
         
    }
    .t delete $start $end;
}

proc yw {{n 1}} {
    clipboard clear;
    set pos [.t index insert];
    set start "$pos wordstart";
    set end "$pos wordend";
    for {set i 0} {$i < [expr $n-1]} {incr i} {
         set end1 [.t search -regexp {\s*} $end end];
         if {$end1 != $end} {
            incr i -1;
         }
         if {$end1 == ""} break;
         set end1 [.t index "$end1 wordend"];
         if {$end1 == ""} break;
         set end $end1;
         
    }
    clipboard append -type HLT [hlt:save .t $start $end];
    clipboard append -type STRING [.t get $start $end];
}

proc uc {} {
    global last_op_was_overpainting;
   .t configure -autoseparators 0;
   .t edit separator;
   .t configure -undo 0;
    resetOverpaintedStuff;
    saveSelectionForUndo .t;
    set selranges [.t tag ranges sel];
          foreach {start end} $selranges {
            set cont [hlt:save .t $start $end];
            .t fastdelete $start $end;
            .t mark set insert $start;
            hlt:restore .t  $cont $start toupper;
          }
    set last_op_was_overpainting 1;
   .t configure -undo 1;
   .t edit separator;
   .t configure -autoseparators 1;
}


proc lc {} {
    global last_op_was_overpainting;
   .t configure -autoseparators 0;
   .t edit separator;
   .t configure -undo 0;
    resetOverpaintedStuff;
    saveSelectionForUndo .t;
    set selranges [.t tag ranges sel];
          foreach {start end} $selranges {
            set cont [hlt:save .t $start $end];
            .t fastdelete $start $end;
            .t mark set insert $start;
            hlt:restore .t  $cont $start tolower;
          }
    set last_op_was_overpainting 1;
   .t configure -undo 1;
   .t edit separator;
   .t configure -autoseparators 1;
}

proc camel {} {
    global last_op_was_overpainting;
   .t configure -autoseparators 0;
   .t edit separator;
   .t configure -undo 0;
    resetOverpaintedStuff;
    saveSelectionForUndo .t;
    set selranges [.t tag ranges sel];
          foreach {start end} $selranges {
            set cont [hlt:save .t $start $end];
            .t fastdelete $start $end;
            .t mark set insert $start;
            hlt:restore .t  $cont $start camelcase;
          }
    set last_op_was_overpainting 1;
   .t configure -undo 1;
   .t edit separator;
   .t configure -autoseparators 1;
}

proc snake {} {
    global last_op_was_overpainting;
   .t configure -autoseparators 0;
   .t edit separator;
   .t configure -undo 0;
    resetOverpaintedStuff;
    saveSelectionForUndo .t;
    set selranges [.t tag ranges sel];
          foreach {start end} $selranges {
            set cont [hlt:save .t $start $end];
            .t fastdelete $start $end;
            .t mark set insert $start;
            hlt:restore .t  $cont $start snakecase;
          }
    set last_op_was_overpainting 1;
   .t configure -undo 1;
   .t edit separator;
   .t configure -autoseparators 1;
}

proc kebab {} {
    global last_op_was_overpainting;
   .t configure -autoseparators 0;
   .t edit separator;
   .t configure -undo 0;
    resetOverpaintedStuff;
    saveSelectionForUndo .t;
    set selranges [.t tag ranges sel];
          foreach {start end} $selranges {
            set cont [hlt:save .t $start $end];
            .t fastdelete $start $end;
            .t mark set insert $start;
            hlt:restore .t  $cont $start kebabcase;
          }
    set last_op_was_overpainting 1;
   .t configure -undo 1;
   .t edit separator;
   .t configure -autoseparators 1;
}

proc pascal {} {
    global last_op_was_overpainting;
   .t configure -autoseparators 0;
   .t edit separator;
   .t configure -undo 0;
    resetOverpaintedStuff;
    saveSelectionForUndo .t;
    set selranges [.t tag ranges sel];
          foreach {start end} $selranges {
            set cont [hlt:save .t $start $end];
            .t fastdelete $start $end;
            .t mark set insert $start;
            hlt:restore .t  $cont $start pascalcase;
          }
    set last_op_was_overpainting 1;
   .t configure -undo 1;
   .t edit separator;
   .t configure -autoseparators 1;
}

proc check_for_file_modification {} {
    global file_lastmod;
    global modified;
    global current_file;
    global saving;
    catch {
    if {(!$saving) && $current_file != "" && $file_lastmod != ""} {
        set updated_lastmod [file mtime $current_file];
        if {$updated_lastmod > $file_lastmod} {
            set result [tk_messageBox -title "File modified externally"  -message "File modified outside spectral. Reload?" -icon question -type yesno];
            if {$result == "yes"} {
                set file_to_reload $current_file;
                if {$modified} {
                    set result1 [tk_messageBox -title "Save changes?"  -message "Save current changes to a file before reload?" -icon question -type yesno];            
                    if {$result1 == "yes"} {
                        saveFileAs .t;
                    }
                }
                
                # Save the old position
                set oldpos [.t index insert];
                # Load the file 
                openFile .t $file_to_reload; 
                # Set the insert cursor to the old position
                catch {
                    .t mark set insert $oldpos;
                    .t see $oldpos;
                }
            } elseif {$result == "no"}  {
                set file_lastmod $updated_lastmod;
            }
        }
    }
    }
  
    after 3000 check_for_file_modification;

}
proc : {args} {
   if {[string is integer $args]} {
      catch {
        set lineNum $args;
        sel $lineNum $lineNum;
        change_yview "[expr $lineNum -2]";
      };
    
   } elseif {$args == "w" || $args == "w!"} {
       save;
   } elseif {$args == "q"} {
       exit;
   } elseif {$args == "wq"} {
       save;
       exit;
   }  elseif {[string range $args 0 1] == "%s"} {
       set cmd "simpleReplace ";
       append cmd [string range $args 2 end];
       eval $cmd;
   } elseif {[string index $args 0] == "!"}  {
       set cmd "exec ";
       append cmd [string range $args 1 end];
       eval $cmd;
   } elseif {[regexp {^\d+,\d+s} $args]} {
       regsub -all {^(\d+),\d+s.*$} $args {\1} startline;
       regsub -all {^\d+,(\d+)s.*$} $args {\1} endline;
       regsub -all {^\d+,\d+s[ \t]*([^\t ].*)$} $args {\1} rest;
       set cmd "simpleReplaceLineRange $startline $endline ";
       append cmd $rest;
       eval $cmd;
   } elseif {[regexp {^\d+s} $args]} {
       set startline [expr int([.t index insert])];
       regsub -all {^(\d+)s.*$} $args {\1} numlines;
       set endline [expr $startline + $numlines - 1];
       regsub -all {^\d+s[ \t]*([^\t ].*)$} $args {\1} rest;
       set cmd "simpleReplaceLineRange $startline $endline ";
       append cmd $rest;
       eval $cmd;
   } else {
       eval $args;
   }
}

proc :w {} {
    save;
}

proc :w! {} {
    save;
}

proc :q {} {
    exit;
}

proc :wq {} {
    save;
    exit;
}

proc selOnly {val} {
  global sel_only;
  set sel_only $val;
}
proc cc {} {
    clipboard clear;
}
##############################################
############ BEGIN  SNIPPET EXPANDER   #######
 proc permutations {list {prefix ""}} {
    if {![llength $list]} then {return [list $prefix]}
    set res [list]
    set n 0
    foreach e $list {
        eval [list lappend res]\
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
   set res "";
   foreach item $lst {
      if {$res != ""} {
          append res ","
      }
      append res "${lparen}${item}${rparen}"
   }
   return $res;
}


proc suffixes {lst {result {}}} {
   set len [llength $lst];
   for {set i 0} {$i < $len} {incr i}  {
       lappend  result [lrange $lst $i end];
   }
   return $result;
}

proc prefixes {lst {result {}}} {
    set len [llength $lst];
    for {set i 0} {$i < $len} {incr i} {
        lappend  result [lrange $lst 0 $i];
    }
    return $result;
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
    append cmd $body;
    append cmd "; return \$code;}"
    uplevel #0 $cmd
}

proc remove-newline {lst} {
  return [regsub -all {[\r\n]} $lst { }]
}


proc expand_macro {name args}  {
    puts "expanding macro $name with arguments $args"
    set cmd "macroexpand_**_$name "
    append cmd $args;
    set result [uplevel #0 $cmd];

    emit $result;

}

proc seq {from to} {
    if {$from >= $to} {
        for {set i $from} {$i <= $to} {incr i}    {lappend out $i}
    } else {
        for {set i $from} {$i >= $to} {incr i -1} {lappend out $i}
    }
    return $out
}



############################################
############ END  SNIPPET EXPANDER   #######

#### BEGIN CODE CHECKER ####
set lnum  0;
set scope "";
set scope_start_line 0;
set verbose 0;
proc generic_count {count_type args} {
    global scope;
    global lnum;
    set result 0;
    global verbose
    global current_file
    global scope_start_line;
    set count 0;

    set cur ${scope_start_line}.0;
    set last_cur "";
   
    array set run_length {}
    foreach substring $args {
       set run_length($substring) 0;
    }

    while 1 {
       set closest 0;
       set maxDist 1e10;
       set bestcur "";
       set bestsub "";
       set bestlen 0;

       foreach substring $args {
           set cur1 [.t search -regexp -count length $substring $cur end]
           if {$cur1 == "" || $cur1 == $last_cur } {
               continue;
           }
           set s1 [.t get $cur $cur1];
           set dist1 [string length $s1];
           #puts "$substring starting $cur dist ==> $dist1";
           if {$dist1 < $maxDist} {
               set maxDist $dist1;
               set bestcur $cur1;
               set bestsub $substring;
               set bestlen $length;
           }
       }
       if {$bestcur != "" && $bestsub != ""} {
            set cur [.t index "$bestcur + $bestlen char"] ;

            incr run_length($bestsub);
            set rl_backup  $run_length($bestsub)
            foreach others $args {
                     set run_length($others) 0;
            }
            set run_length($bestsub) $rl_backup;
            puts "$bestcur: $bestsub RL=$rl_backup";
            incr count;


       } else {
           break;
       }
   }

   return $count;
}
proc count {args} {
    return [generic_count substring {*}$args]; 
}

proc idcount {args} {
    return [generic_count id {*}$args]; 
}

proc symcount {args} {
    return [generic_count sym {*}$args]; 
}

proc assert {cond msg} {
  if {![uplevel #0 "expr $cond"]} {
    print $msg
  }
} 

proc line_check {rexp msg} {
   global scope;
   global lnum;
   global scope_start_line;
   global current_file
   set scope_lines [split $scope "\n"];
   set scope_lnum $scope_start_line;
   foreach aline $scope_lines {
     incr scope_lnum;
     if {[regexp $rexp $aline]} {
        puts "$current_file\($lnum\): $msg"
     }
   }
}

proc print {msg} {
   global lnum;
   global current_file;
   puts -nonewline "$current_file\($lnum\): "
   puts $msg
}


proc ascheck {}  {
    global lnum;
    global current_file;
    global scope;
    global scope_start_line;
    global verbose;

    set content [.t get 1.0 end];
    set all_lines [split $content "\n"]
    set lnum 0;
    set scope_start_line 0;
    set num_lines [llength $all_lines];
    puts "Number of lines : $num_lines";
    set scope "";
    set loc "";
    set verbose 0;

    foreach line $all_lines {
      incr lnum;
      set code "";
      set scope "";
      if [regexp {^[ \t\/\*]*CC_BEGIN} $line] {
         set scope_end $line;
         regsub -all {.*CC_BEGIN} $scope_end {} scope_end;
         if {[llength $scope_end] == 0} {
            set scope_end EOF
         } else {
            set scope_end [lindex $scope_end 0];
         }
         set i $lnum;
         for {} {$i < [expr $num_lines -1] } {incr i} {
            set newline [lindex $all_lines $i];
            if  [regexp {^[ \t\/\*]*CC_END} $newline] {
                incr i;
                break;
            } else {
                regsub -all {^[ \t\/\/]*} $newline {} newline
                append code $newline "\n";
            }
         }
         set scope_start_line  $i;
         for {} {$i < [expr $num_lines -1] } {incr i} {
            set newline [lindex $all_lines $i];
            if  { $scope_end != "EOF"  &&
                [regexp {^[ \t\/\*]*CC_MARK[ \t]} $newline] &&
                [regexp $scope_end $newline] } {
    
                break;
            } else {
                append scope $newline "\n";
            }
         }
         set loc "$current_file\($lnum\): "
         uplevel #0 $code;
      }
    }
}


#### END CODE CHECKER ####
proc d/ {re {times 1}} {
   if {$re == ""} {
       return;
   }
   set cur [.t index insert];
   for {set i 0} {$i < $times} {incr i} {
     set next [.t search -regexp -count length $re $cur end];
     if {$next == ""} {
         break;
     } else {
         .t fastdelete $cur "$next + $length c" ;
         
     }
   }
}

proc dx/ {re {times 1}} {
   if {$re == ""} {
       return;
   }
   set cur [.t index insert];
   for {set i 0} {$i < $times} {incr i} {
     set next [.t search -regexp -count length $re $cur end];
     if {$next == ""} {
         break;
     } else {
         if {$i == [expr $times - 1]} {
             .t fastdelete $cur $next;
         } else {
            .t fastdelete $cur "$next + $length c" ;
        }
         
     }
   }
}

proc sel/ {re {times 1}} {
   if {$re == ""} {
       return;
   }
   set cur [.t index insert];
   for {set i 0} {$i < $times} {incr i} {
     set next [.t search -regexp -count length $re $cur end];
     if {$next == ""} {
         break;
     } else {
         .t tag add sel $cur [.t index "$next + $length c"];
         set cur [.t index "$next + $length c"];
     }
   }
}


proc selx/ {re {times 1}} {
   if {$re == ""} {
       return;
   }
   set cur [.t index insert];
   for {set i 0} {$i < $times} {incr i} {
     set next [.t search -regexp -count length $re $cur end];
     if {$next == ""} {
         break;
     } else {
         if { $i == [expr $times - 1] } {
             .t tag add sel $cur [.t index $next];
         } else {
             .t tag add sel $cur [.t index "$next + $length c"];
         }
         set cur [.t index "$next + $length c"];
     }
   }
}

######## SOS BEGIN  ##############################
set sos_do_subst 0;
set sos_last_file "";
set sos_last_file_lines "";
set sos_processing_seq_number 0;
set sos_serial 0;

proc sos_regexp {pat str ignore_case} {
   set negate 0;
   if {[string index $pat 0] == "-"} {
       if {[string index $pat 1] != "-"} {
         set pat [string range $pat 1 end];
         set negate 1;
       } else {
     #two leading "-"s will be regarded as one leading "-"
     set pat_original [string range $pat 1 end];
     set pat "\\";
     append pat $pat_original;
       }
   }
   set val 0;
   if {$ignore_case} {
    set val [regexp -nocase $pat $str];
   } else {
    set val [regexp $pat $str];
   }
   if {$negate} {
        return [expr !$val];
    } else {
    return $val;
    }
}

proc sos_show_dialog {window} {
global default_foreground;
global default_background;
global sos_do_subst;
global sos_do_subst;
    global sos_serial;
    global sos_processing_seq_number;
    global sos_last_file;
    global sos_last_file_lines;
    global regroot;
if {[catch "toplevel $window"] } {
  wm deiconify $window; 
} else {
    
wm protocol $window WM_DELETE_WINDOW "wm withdraw $window;"; 

frame $window.searchFrame -background $default_background;
iwidgets::entryfield $window.searchFrame.file_pattern -labeltext "File Pattern" -labelpos n -command  {} -width 20 -textbackground $default_background -background $default_background -foreground $default_foreground -insertbackground blue;
iwidgets::entryfield $window.searchFrame.line_pattern -labeltext "Line Pattern" -labelpos n -command  {} -width 20 -textbackground $default_background -background $default_background -foreground $default_foreground -insertbackground blue;
iwidgets::entryfield $window.searchFrame.target -labeltext "Subst Target" -labelpos n -command  {} -width 20 -textbackground $default_background -background $default_background -foreground $default_foreground -insertbackground blue;
iwidgets::entryfield $window.searchFrame.replacement -labeltext "Subst Text" -labelpos n -command  {} -width 20 -textbackground $default_background -background $default_background -foreground $default_foreground -insertbackground blue;
iwidgets::entryfield $window.searchFrame.vicinity_extent -labeltext "Vicinity Extent" -labelpos n -command  {} -width 20 -textbackground $default_background -background $default_background -foreground $default_foreground -insertbackground blue;
checkbutton $window.searchFrame.subst -text "VarSubst?" -variable sos_do_subst -relief flat -background $default_background -foreground red ;
button $window.searchFrame.find -text find -command "sos_perform_replacement $window -1" -background $default_background -foreground $default_foreground 
button $window.searchFrame.collect -text collect -command "sos_perform_replacement $window -2" -background $default_background -foreground $default_foreground 
button $window.searchFrame.replace -text replace -command "sos_perform_replacement $window 0" -background $default_background -foreground $default_foreground 
button $window.searchFrame.preview -text preview -command "sos_perform_replacement $window 1" -background $default_background -foreground $default_foreground 
button $window.searchFrame.apply -text apply -command "sos_apply_changes $window 0 0" -background $default_background -foreground $default_foreground 
button $window.searchFrame.prev_apply -text "preview\napply" -command "sos_apply_changes $window 1 0" -background $default_background -foreground $default_foreground 
button $window.searchFrame.insert_after -text "insert\nafter" -command "sos_apply_changes $window 0 1" -background $default_background -foreground $default_foreground
button $window.searchFrame.insert_before -text "insert\nbefore" -command "sos_apply_changes $window 0 -1" -background $default_background -foreground $default_foreground
pack $window.searchFrame -side top -fill x
pack $window.searchFrame.file_pattern $window.searchFrame.line_pattern $window.searchFrame.target $window.searchFrame.replacement $window.searchFrame.vicinity_extent $window.searchFrame.find $window.searchFrame.collect $window.searchFrame.replace  $window.searchFrame.preview $window.searchFrame.apply $window.searchFrame.prev_apply $window.searchFrame.insert_before $window.searchFrame.insert_after $window.searchFrame.subst\
-side left -fill both 

[$window.searchFrame.file_pattern component label] configure -foreground $default_foreground -background $default_background;
[$window.searchFrame.line_pattern component label] configure -foreground $default_foreground -background $default_background;
[$window.searchFrame.target component label] configure -foreground $default_foreground -background $default_background;
[$window.searchFrame.replacement component label] configure -foreground $default_foreground -background $default_background;
[$window.searchFrame.vicinity_extent component label] configure -foreground $default_foreground -background $default_background;

wm title $window "Second Order Search";

catch { 

  $window.searchFrame.line_pattern insert end [registry get $regroot vicinity_repl_pattern];
  $window.searchFrame.target  insert end [registry get $regroot vicinity_repl_target];
  $window.searchFrame.replacement  insert end [registry get $regroot vicinity_repl_replacement];
  $window.searchFrame.vicinity_extent    insert end [registry get $regroot vicinity_repl_extent];
  $window.searchFrame.file_pattern insert end [registry get $regroot vicinity_repl_file_pattern];

  }
}
}


proc sos_apply_changes {window preview_only insert} {

    global regroot;
    set filepat [$window.searchFrame.file_pattern component entry get];
    set linepat [$window.searchFrame.line_pattern component entry get];
    set target [$window.searchFrame.target component entry get];
    set replacement [$window.searchFrame.replacement component entry get ];
    set extent [$window.searchFrame.vicinity_extent   component entry get ];


    registry set $regroot vicinity_repl_pattern $linepat;
    registry set $regroot vicinity_repl_file_pattern $filepat;
    registry set $regroot vicinity_repl_target   $target;
    registry set $regroot vicinity_repl_replacement   $replacement;
    registry set $regroot vicinity_repl_extent      $extent;

    if { [llength $linepat]  == 0 ||
         [llength $extent] < 2 
             } {
         return;
         }
        set result {};
    set time1 [time {set input [.t get 0.0 end]}];
    set time2 [time {set input_lines [split $input "\n"]}];
    
    set input_lines [lreverse $input_lines];
    
    array set insertions "";
    set last_file_name "";
    set last_line_num "";
    set last_start "";
    if {$insert == 1} {
        foreach input_line $input_lines {
            update;
            if {[ catch {
            set input_line [regsub -all {^[0-9]*>} $input_line {}];
            set  loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
            set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
            set  loc_cont [regsub -all {^[ \t]*.:?[^\(:]*[\(:][0-9]*[:\)](.*)} $input_line {\1}];
            set skip_file 0;

            foreach file_pat $filepat {
                if {![sos_regexp $file_pat $loc_file 0]} {
                   set skip_file 1;
                   break;
                }
            }
            if {$skip_file} {
                continue;
            }

            if { $last_file_name == $loc_file && $loc_line == [expr $last_line_num - 1] } {
                 set sofar "";

                 if {[info exists insertions($loc_file,$last_start)]} { 
                    set sofar [set insertions($loc_file,$last_start)];
                 }
                 set str "";
                 append str $loc_cont "\n" $sofar;
                 set insertions($loc_file,$last_start) $str;   
            } else {
                set insertions($loc_file,$loc_line) $loc_cont;
                set last_start $loc_line;
            }
            
            set last_file_name $loc_file;
            set last_line_num $loc_line
        } exception_msg ] } {
            addToStatus $exception_msg;
        }
      }
    }
 
    foreach input_line $input_lines {
        update;
        
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
        set  loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        set  loc_cont [regsub -all {^[ \t]*.:?[^\(:]*[\(:][0-9]*[:\)](.*)} $input_line {\1}];
        set skip_file 0;
        foreach file_pat $filepat {
            if {![sos_regexp $file_pat $loc_file 0]} {
               set skip_file 1;
               break;
            }
        }
        if {$skip_file} {
            continue;
         }
        update;
        if {$insert == 1} {
            if {[info exists insertions($loc_file,$loc_line) ]} {
                append result [sos_apply_changes_to_file $loc_file $loc_line [set insertions($loc_file,$loc_line)] $linepat $extent $preview_only $insert];     
            }
        } else {
            append result [sos_apply_changes_to_file $loc_file $loc_line $loc_cont $linepat $extent $preview_only $insert]; 
        }

        update;
    }
    
    showOutput $result substitution_log {} {};
}

proc apply_changes_from_greplines {} {
    
    set editor_content [.t get 1.0 end];
    set input_lines [split $editor_content "\n"];
    foreach input_line $input_lines {
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
        set  loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        set  loc_cont [regsub -all {^[ \t]*.:?[^\(:]*[\(:][0-9]*[:\)](.*)} $input_line {\1}];
        if {![string is integer $loc_line]} {
            continue;
        }   
        
        if {![file exists $loc_file]} { 
            continue;
        }
        set result [sos_apply_changes_to_file $loc_file $loc_line $loc_cont ".*" {0 0} 0 0]; 
   }
}

proc add_postscript {txt} {
 set input [.t get 0.0 end];
    set input_lines [split $input "\n"];
    set editorline 0;
    array set files_done {};
    #tk_messageBox -message "About to start processing $time1 $time2";
    foreach input_line $input_lines {
        update;
        incr editorline;
                set input_line [regsub -all {\\} $input_line {/}];
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
        set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        if {[info exists files_done($loc_file)]} {
            continue;
        }
        set files_done($loc_file) 1;
         
        if [catch {set fp [open $loc_file "r"]; }] {
            addToStatus "Failed to open file  $loc_file\n";
            continue;
        }
        fconfigure $fp -encoding utf-8;
        set content [read $fp];
        close $fp;
        if [catch {set fp [open $loc_file "w"]; }] {
            addToStatus "Failed to open file $loc_file for writing\n";
            continue;
        }
        fconfigure $fp -encoding utf-8
        puts -nonewline $fp $content;
        puts -nonewline $fp $txt;
        close $fp;
        .t tag add sel "$editorline.0" "$editorline.end";
    }
}

proc load_all_listed_files {} {
    
    set files [get_listed_files];
    .t delete 1.0 end;
    foreach file $files {
        set cont [read_file_contents $file];
        set lines [split $cont "\n"];
        set lnum 0;
        .t insert end "##########  FILE $file ###########\n"
        foreach line $lines {
            incr lnum;
            .t insert end "$file:$lnum:$line\n";
        }
            
    }
}


proc get_grep_lines {} {
    set input [.t get 0.0 end];
    set input_lines [lreverse [split $input "\n"]];

    #tk_messageBox -message "About to start processing $time1 $time2";
    set result {}
    foreach input_line $input_lines {
        update;
        catch {

    set input_line [regsub -all {^[0-9]*>} $input_line {}];
    set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        if {[file exists $loc_file]} {
            lappend result $loc_file;
        } else {
            continue;
        }
        if {[string is integer $loc_line] } {
            lappend result $loc_line
        } else {
            lappend result {}
        }
      }
   }
    return $result;
}

proc sel_grep_lines {} {
    visit_re_quiet {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)]} actuallySelectGrepLines
}

proc actuallySelectGrepLines {regex cur end} {     
    .t tag add sel $cur  $end;
    update;
}


proc get_listed_files {} {
    set input [.t get 0.0 end];
    set input_lines [lreverse [split $input "\n"]];

    #tk_messageBox -message "About to start processing $time1 $time2";
    set result {}
    foreach input_line $input_lines {
        update;
        catch {
            set input_line [regsub -all {^[0-9]*>} $input_line {}];
            set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
            set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
            if {  [file exists $loc_file] && [lsearch $result $loc_file] == -1 } {
                lappend result $loc_file;
            } 
        }
   }
    return $result;
}


proc hyperlink_selected_grep_lines {} {
    selexpand;
    global external_hyperrefs;
    set current_filename [get_current_filename];
    set selranges [.t tag ranges sel];
    foreach { start end } $selranges {
       set input [.t get $start $end];
       set startline [lindex [split $start "."] 0]  
       set input_lines [split $input "\n"];
       set line_offset 0;
       foreach input_line $input_lines {
 
        update;
        catch {
            set input_line [regsub -all {^[0-9]*>} $input_line {}];
            set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
            set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];

            if {![file exists $loc_file]} {
                continue;
            }
            
            set offset [expr [string length $loc_line] + [string length $loc_file] + 2]

            if {[string is integer $loc_line]} {
               set tagline "[expr $startline+$line_offset]";
               set tag "line_[guid]_${loc_line}";
               addToStatus "adding tag $tag";
               .t tag add  "hyperref_${tag}" "${tagline}.0" [.t index "${tagline}.0 + $offset c"] ;
               .t tag configure  "hyperref_${tag}" -underline 1;
               .t tag bind "hyperref_${tag}" <Control-ButtonRelease-1> "followTarget ${tag}"
               if {$loc_file == $current_filename} {
                      
               } else {
                   set external_hyperrefs($tag) [relativizeFileName $loc_file];    
               }
    
            } 
          }
          incr line_offset;
      }
    }
}
      

proc insert_before {txt} {
    set input [.t get 0.0 end];
    set input_lines [lreverse [split $input "\n"]];
    set editorline 0;

    #tk_messageBox -message "About to start processing $time1 $time2";
    foreach input_line $input_lines {
        update;
        catch {
        incr editorline;
    set input_line [regsub -all {^[0-9]*>} $input_line {}];
    set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
      #  puts "loc_line == $loc_line";
         
        if [catch {set fp [open $loc_file "r"]; }] {
            addToStatus "Failed to open file  $loc_file\n";
            continue;
        }
        fconfigure $fp -encoding utf-8;
        set content [read $fp];
    close $fp;
        
        if [catch {set fp [open $loc_file "w"]; }] {
            addToStatus "Failed to open file $loc_file for writing\n";
            continue;
        }
    fconfigure $fp -encoding utf-8;
    set file_lines [split $content "\n"];
    set lcount 0;
    set fullcount [llength $file_lines];
    foreach file_line $file_lines {
            incr lcount;
            if {$lcount == $loc_line} {
                   puts -nonewline $fp $txt;
            }
            if {$lcount == $fullcount} {
                  puts -nonewline $fp $file_line;
            } else {
                  puts  $fp $file_line;
            }
    }
        close $fp;
        }
    }
}

proc insert_after {txt} {
    set input [.t get 0.0 end];
    set input_lines [lreverse [split $input "\n"]];
    set editorline 0;

    #tk_messageBox -message "About to start processing $time1 $time2";
    foreach input_line $input_lines {
         catch {
        update;
        incr editorline;
    set input_line [regsub -all {^[0-9]*>} $input_line {}];
    set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        
         
        if [catch {set fp [open $loc_file "r"]; }] {
            addToStatus "Failed to open file  $loc_file\n";
            continue;
        }
        fconfigure $fp -encoding utf-8;
        set content [read $fp];
    close $fp;
        
        if [catch {set fp [open $loc_file "w"]; }] {
            addToStatus "Failed to open file $loc_file for writing\n";
            continue;
        }
    fconfigure $fp -encoding utf-8;
    set file_lines [split $content "\n"];
    set lcount 0;
    set fullcount [llength $file_lines];
    foreach file_line $file_lines {
            incr lcount;
            if {$lcount == $fullcount} {
                  puts -nonewline $fp $file_line;
            } else {
                  puts  $fp $file_line;
            }
            if {$lcount == $loc_line} {
                   puts -nonewline $fp $txt;
            }
            
    }
        close $fp;
        }
    }
}

proc insert_at {txt} {
    set input [.t get 0.0 end];
    set input_lines [lreverse [split $input "\n"]];
    set editorline 0;

    #tk_messageBox -message "About to start processing $time1 $time2";
    foreach input_line $input_lines {
         catch {
        update;
        incr editorline;
    set input_line [regsub -all {^[0-9]*>} $input_line {}];
    set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        
         
        if [catch {set fp [open $loc_file "r"]; }] {
            addToStatus "Failed to open file  $loc_file\n";
            continue;
        }
        fconfigure $fp -encoding utf-8;
        set content [read $fp];
    close $fp;
        
        if [catch {set fp [open $loc_file "w"]; }] {
            addToStatus "Failed to open file $loc_file for writing\n";
            continue;
        }
    fconfigure $fp -encoding utf-8;
    set file_lines [split $content "\n"];
    set lcount 0;
    set fullcount [llength $file_lines];
    foreach file_line $file_lines {
            incr lcount;
            if { $lcount == $fullcount || $lcount == $loc_line } {
                  puts -nonewline $fp $file_line;
            } else {
                  puts  $fp $file_line;
            }
            if { $lcount == $loc_line } {
                   puts $fp $txt;
            }
            
         }
         close $fp;
        }
    }
}

proc hlt_insert_at {txt} {
    set input [.t get 0.0 end];
    set input_lines [lreverse [split $input "\n"]];
    set editorline 0;
    ## todo any further sanitization
    regsub -all {[\t\r{}]} $txt { } txt;

    #tk_messageBox -message "About to start processing $time1 $time2";
    foreach input_line $input_lines {
         catch {
        update;
        incr editorline;
    set input_line [regsub -all {^[0-9]*>} $input_line {}];
    set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        
         
         if [catch {set fp [open "${loc_file}.hlt" "r"]; }] {
            addToStatus "Failed to open file  ${loc_file}.hlt\n";
            continue;
     }

        fconfigure $fp -encoding utf-8;
        set content [read $fp];
    close $fp;
    
        if [catch {set fp [open "${loc_file}.hlt" "w"]; }] {
            addToStatus "Failed to open file ${loc_file}.hlt for writing\n";
            continue;
     }
     catch {
    fconfigure $fp -encoding utf-8;
    set file_lines [split $content "\n"];
    set lcount 0;
    set fullcount [llength $file_lines];
    foreach file_line $file_lines {
            incr lcount;
            if {$lcount == $fullcount  || $lcount == $loc_line} {
                  puts -nonewline $fp $file_line;
            } else {
                  puts  $fp $file_line;
            }
            if {$lcount == $loc_line} {
               if {[string index $file_line end] == "\{"} {
                           puts -nonewline $fp "\}";
               puts -nonewline $fp " T \{";
               puts -nonewline $fp $txt;
               puts $fp "\} T \{";
               } elseif {[string index $file_line end] == "\}"} {
               puts -nonewline $fp " T \{";
               puts -nonewline $fp $txt;
               puts -nonewline $fp "\}";
               }  else {}
            }
            
    }
     } msg1;
     addToStatus $msg1;
        close $fp;
        } msg;
    addToStatus $msg;
    }

    insert_at $txt;
}

proc reverse_line_order {} {
    set input [.t get 0.0 end];
    set input_lines [lreverse [split $input "\n"]];
    .t insert end "\n";
    foreach input_line $input_lines {
        .t insert end $input_line;
        .t insert end "\n";
    }
}

proc reverse_char_order {} {
    set input [string trimright [.t get 1.0 end]];
    .t delete 1.0 end;
    set reverted [string reverse $input]
    .t insert 1.0 $reverted;
}

proc add_preamble {txt} {
    set input [.t get 0.0 end];
    set input_lines [split $input "\n"];
    set editorline 0;
    array set files_done {};
    #tk_messageBox -message "About to start processing $time1 $time2";
    foreach input_line $input_lines {
        update;
        incr editorline;
                set input_line [regsub -all {\\} $input_line {/}];
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
        set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        if {[info exists files_done($loc_file)]} {
            continue;
        }
        set files_done($loc_file) 1;
         
        if [catch {set fp [open $loc_file "r"]; }] {
            addToStatus "Failed to open file  $loc_file\n";
            continue;
        }
        fconfigure $fp -encoding utf-8;
        set content [read $fp];
        close $fp;
        if [catch {set fp [open $loc_file "w"]; }] {
            addToStatus "Failed to open file $loc_file for writing\n";
            continue;
        }
        fconfigure $fp -encoding utf-8
        puts -nonewline $fp $txt;
        puts -nonewline $fp $content;
        close $fp;
        .t tag add sel "$editorline.0" "$editorline.end";
    }
}


proc sos_perform_replacement {window preview_only} {

    global regroot;
    set filepat [$window.searchFrame.file_pattern component entry get];
    set linepat [$window.searchFrame.line_pattern component entry get];
    set target [$window.searchFrame.target component entry get];
    set replacement [$window.searchFrame.replacement component entry get ];
    set extent [$window.searchFrame.vicinity_extent   component entry get ];
    
    #puts "$linepat $target $replacement $extent";

    registry set $regroot vicinity_repl_pattern $linepat;
    registry set $regroot vicinity_repl_file_pattern $filepat;
    registry set $regroot vicinity_repl_target   $target;
    registry set $regroot vicinity_repl_replacement   $replacement;
    registry set $regroot vicinity_repl_extent      $extent;


    if { [llength $linepat]  == 0 ||
         [llength $extent] < 2 
             } {
         return;
         }
        set result {};
    set time1 [time {set input [.t get 0.0 end]}];
    set time2 [time {set input_lines [split $input "\n"]}];
    set editorline 0;    
    #tk_messageBox -message "About to start processing $time1 $time2";
    foreach input_line $input_lines {
        update;
        incr editorline;
        
        set input_line [regsub -all {^[0-9]*>} $input_line {}];
        set loc_file [regsub -all {^[ \t]*(.:?[^\(:]*)[\(:].*} $input_line {\1}];
        set  loc_line [regsub -all {^[ \t]*.:?[^\(:]*[\(:]([0-9]*)[:\)].*} $input_line {\1}];
        set skip_file 0;
        foreach file_pat $filepat {
            if {![sos_regexp $file_pat $loc_file 0]} {
               set skip_file 1;
               break;
            }
        }
        if {$skip_file} {
            continue;
        }
        update;
        append result [sos_process_file $loc_file $loc_line $linepat $target $replacement $extent $preview_only $editorline];
        update;
    }
    showOutput $result substitution_log {} {};
}


proc sos_mult_regexp {pats text} {
    foreach pat $pats {
       if {![sos_regexp $pat $text 0]} {
       return 0;
       }
   }
   return 1;
}


proc sos_process_file {file linenum pat target repl extent preview editorline} {
    global sos_do_subst;
    global sos_serial;
    global sos_processing_seq_number;
    global sos_last_file;
    global sos_last_file_lines;
    incr sos_processing_seq_number;

     #puts  "\n$sos_processing_seq_number file: $file\nline: $linenum\npat: $pat\nrepl: $repl\nextent: $extent";
    addToStatus "$sos_processing_seq_number file: $file line: $linenum pat: $pat repl: $repl extent: $extent\n";
    update;
        #return;

    set result {};
    if {!$preview} {
            #catch {exec TF checkout $file};
        }
   
    set lines {};
    if {$sos_last_file == $file && $preview} {
       set lines $sos_last_file_lines;
    } else {
         if [catch {set fp [open $file "r"]; }] {
            append result "Failed to open file \"" $file "\"\n";
            return $result;
        }
        set content [read $fp];
        close $fp;
        set sos_last_file $file;
        set lines [split $content "\n"];
        set sos_last_file_lines $lines;
    }
    set line_from [expr $linenum+([lindex $extent 0])];
    set line_to [expr $linenum+([lindex $extent 1])];
    set output {};
    set msg    {};
    set affected_lines {};
    if {[catch {
          set cnt 0;
          set done_once 0;
          set snippet "";
          set snippet_lines 0;
          foreach line $lines {
              incr cnt;
              
              if {$cnt >= $line_from &&
                  $cnt <= $line_to} {
                 
                 if {$cnt == $linenum && $preview == -2} {
                     append snippet "@@@@@@@@@@@@@@@@@@@@@";
                 }
                append snippet $line  "\n";
                incr snippet_lines; 
                if {$preview == -2} {
                     ## Only while collecting snippets
                     append output $line "\n"
                } elseif { [sos_mult_regexp $pat $line] && !$done_once } {
                  .t tag add sel "$editorline.0"   "$editorline.end";        
                  lappend affected_lines [expr $cnt+1];
                  if {$preview == -1} {
                     append result $file ":" [expr $cnt+0] ":$line \n";
                     append output $line "\n";

                     if {$snippet_lines > 1} {
                         create_note  "$editorline.end" $snippet;
                     }
                  } elseif {$repl == "DELETE_LINE"} {
                      append result $file ":" [expr $cnt+0] ":DELETED\n";
                  } else {
                      append result $file ":" [expr $cnt+0] ":REPLACE " $line " --> "
                      set serial $sos_serial;
                      if {$sos_do_subst} {
                          set repl [subst $repl]
                      }
                      incr sos_serial;
                      regsub -all $target $line $repl line
                      append output $line "\n"
                      append result $line "\n"
                   } 
                   #TODO formalize this (i.e. let the user choose whether to stop after the first action)
                   set done_once 1;
                 } else {

                   append output $line "\n"
               }

             } elseif {$preview != -2} {
                 set snippet "";
                 set snippet_lines 0;
                 append output $line "\n"
             }
           }
           if {$preview == -2} {
               create_note  "$editorline.end" $snippet;
           }
              } msg]} {

        append result "Failed for ${file}:$linenum --> $msg"
        addToStatus "Failed for ${file}:$linenum --> $msg\n"
        
          } else {
        if $preview  {
           if {[llength $affected_lines] } {
               global replacement_window_id;
               incr replacement_window_id;
               
              # showOutput $output "replacement_result_${replacement_window_id}" $file $affected_lines;
               }
            } else {
           
           set fp [open $file w];
           puts -nonewline $fp [string range $output 0 end-1];
           close $fp;
                 }
          }
          return $result;
      }


proc sos_apply_changes_to_file {file linenum cont pat extent preview insert} {
    global sos_do_subst;
    global sos_serial;
    global sos_processing_seq_number;
    global sos_last_file;
    global sos_last_file_lines;
    incr sos_processing_seq_number;

    addToStatus "$sos_processing_seq_number file: $file line: $linenum pat: extent: $extent\n";
    update;

    set result {};
        if {!$preview} {
            #catch {exec TF checkout $file};
        }
   
    set lines {};
    if {$sos_last_file == $file && $preview} {
       set lines $sos_last_file_lines;
    } else {
         if [catch {set fp [open $file "r"]; }] {
            append result "Failed to open file \"" $file "\"\n";
            return $result;
        }
        set content [read $fp];
        close $fp;
        set sos_last_file $file;
        set lines [split $content "\n"];
        set sos_last_file_lines $lines;
    }
    
    set line_from [expr $linenum+([lindex $extent 0])];
    set line_to [expr $linenum+([lindex $extent 1])];
    set output {};
    set msg    {};
        set affected_lines {};
    if {[catch {
          set cnt 0;
          set done_once 0;
          foreach line $lines {
              incr cnt;
           
          if {$cnt >= $line_from &&
              $cnt <= $line_to &&
              [sos_mult_regexp $pat $line] && !$done_once } {
            
            if {$insert == 1} {
                   append output $line "\n";
            }
            lappend affected_lines [expr $cnt+1];
            if {$preview == -1} {
               append result $file ":" [expr $cnt+0] ":$cont \n";
               append output $cont "\n"
            } elseif {$cont == "DELETE_LINE"} {
                append result $file ":" [expr $cnt+0] ":DELETED\n";
            } else {
                append result $file ":" [expr $cnt+0] ":REPLACE " $line " --> "
                append output $cont "\n"
                append result $cont "\n"
           } 
             #TODO formalize this (i.e. let the user choose whether to stop after the first action)
             set done_once 1;
             if {$insert == -1} {
                 append output $line "\n";
             }

             } else {
                 append output $line "\n"
             }
           } 
              } msg]} {

        append result "Failed for ${file}:$linenum --> $msg"
        addToStatus "Failed for ${file}:$linenum --> $msg\n"
        
          } else {
        if $preview  {
           if {[llength $affected_lines] } {
               global replacement_window_id;
               incr replacement_window_id;
               
              # showOutput $output "replacement_result_${replacement_window_id}" $file $affected_lines;
               }
            } else {
           
           set fp [open $file w];
           puts -nonewline $fp [string range $output 0 end-1];
           close $fp;
                 }
          }
          return $result;
      }

################ SOS END   ######################
    


proc title {title} {
    global title_prefix;
    set current_title  [wm title .];
    if {$title_prefix != "" && [regexp "^$title_prefix" $current_title]} {
         regsub "^$title_prefix-" $current_title "" current_title
    }
    wm title . "$title-$current_title";
    set title_prefix $title;
}
proc installdir {} {
    global installdir;
    return $installdir;
}

proc tk_exec_fileevent {id} {
    global tk_exec_data
    global tk_exec_cond
    global tk_exec_pipe

    if {[eof $tk_exec_pipe($id)]} {
        fileevent $tk_exec_pipe($id) readable ""
        set tk_exec_cond($id) 1
        addToStatus "...done\n";
        return;
    }
    

    append tk_exec_data($id) [read $tk_exec_pipe($id) 1024]
}

proc trace_hotspots { {head 50} {fname {}} } {
    set wbin "[installdir]/wbin/";
    if {$fname == ""} {
        set fname [tk_getOpenFile]
    }

    puts "${wbin}grep.exe \":\[0-9\]*<\"  $fname | ${wbin}sed.exe \"s/:\[0-9\]*<//g\" | ${wbin}sed.exe \"s/>.*//g\" | ${wbin}sort.exe | ${wbin}uniq.exe -c | ${wbin}sort.exe -nr | ${wbin}head.exe -n $head | ${wbin}gawk.exe '{printf(\":1<%s> %s\\n\", \$2,\$1);}' "
    exec ${wbin}grep.exe {:[0-9]*<}  $fname | ${wbin}sed.exe {s/:[0-9]*<//g} | ${wbin}sed.exe {s/>.*//g} | ${wbin}sort.exe | ${wbin}uniq.exe -c | ${wbin}sort.exe -nr | ${wbin}head.exe -n $head | ${wbin}gawk.exe   "\{printf(\":1<%s> %s\\n\", \$2,\$1);\}"
}

proc tk_exec {args} {
    addToStatus "\nCommand $args ... ";
    global tk_exec_id
    global tk_exec_data
    global tk_exec_cond
    global tk_exec_pipe
    global tcl_platform
    global env

    if {![info exists tk_exec_id]} {
        set tk_exec_id 0
    } else {
        incr tk_exec_id
    }

    set keepnewline 0

    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -glob -- $arg {
            -keepnewline { 
                set keepnewline 1
            }
            -- {
                incr i
                break
            }
            -* {
                error "unknown option: $arg"
            }
            ?* {
                # the glob should be on *, but the wiki reformats
                # that as a bullet
                break
            }
        }
    }

    if {$i > 0} {
        set args [lrange $args $i end]
    }
   if 0 {
       if {$tcl_platform(platform) == "windows" && \
          [info exists env(COMSPEC)]} {
          set args [linsert $args 0 $env(COMSPEC) "/c"]
      }
   }

    set pipe [open "|$args" r]

    set tk_exec_pipe($tk_exec_id) $pipe
    set tk_exec_data($tk_exec_id) ""
    set tk_exec_cond($tk_exec_id) 0

    fconfigure $pipe -blocking 0
    fileevent $pipe readable "tk_exec_fileevent $tk_exec_id"

    vwait tk_exec_cond($tk_exec_id)

    if {$keepnewline} {
        set data $tk_exec_data($tk_exec_id)
    } else {
        set data [string trimright $tk_exec_data($tk_exec_id) \n]
    }

    unset tk_exec_pipe($tk_exec_id)
    unset tk_exec_data($tk_exec_id)
    unset tk_exec_cond($tk_exec_id)

    if {[catch {close $pipe} err]} {
        error "pipe error: $err"
    }

    return $data
  }

proc choosedir {} {
    return [tk_chooseDirectory];
}

proc addmenu {root name label {tearoff 0}} {
 
    global qcInterp;
    $root add cascade -label $label -menu [menu $root.$name  -tearoff $tearoff];
    interp alias $qcInterp $root.$name {} $root.$name;

    return $root.$name
}
proc addmenucommand {root label command} {
   $root add command -label $label -command $command;
}

proc args {cmd} {
    return [info args $cmd];
}

proc commands {{pattern .} args} {
    global all_commands;
    set result {};
    set last_one {};
    set cmds_sorted [lsort -dictionary -increasing $all_commands];
    foreach cmd $cmds_sorted {
          if {[regexp $pattern $cmd]} {
                  if {$last_one != $cmd} {
                  append result $cmd "\n";
                    }
              set last_one $cmd;
          }   
      }
     return $result;
}

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

proc replace_by_analogy {target replacement} {
    set tasks {};

    global case_sensitive;
    set case_sensitive_backup $case_sensitive; 
    set case_sensitive 1;
    if {[
    catch {
    lappend tasks "\\m${target}\\M";
    lappend tasks "${replacement}";
    
    lappend tasks "\\m[camel_case ${target}]\\M";
    lappend tasks "[camel_case ${replacement}]";
    
    lappend tasks "\\m[pascal_case ${target}]\\M";
    lappend tasks "[pascal_case ${replacement}]";
    
    lappend tasks "\\m[regsub -all {_} ${target}  \\.]\\M";
    lappend tasks "[regsub -all {_} ${replacement} .]";
    
    lappend tasks "\\m[string toupper ${target}]\\M";
    lappend tasks "[string toupper ${replacement}]";
    
    lappend tasks "\\m[string tolower ${target}]\\M";
    lappend tasks [string tolower ${replacement}];

    foreach {targ repl} $tasks {
        addToStatus "replacing $targ by $repl";
        simpleReplace $targ $repl 1;
    }
    } msg]} {
        addToStatus $msg;
    }

    set case_sensitive $case_sensitive_backup; 
}


proc replace_substring_by_analogy {target replacement} {
    set tasks {};

    global case_sensitive;
    set case_sensitive_backup $case_sensitive; 
    set case_sensitive 1;
    if {[
    catch {
    lappend tasks "${target}";
    lappend tasks "${replacement}";
    
    lappend tasks "[camel_case ${target}]";
    lappend tasks "[camel_case ${replacement}]";
    
    lappend tasks "[pascal_case ${target}]";
    lappend tasks "[pascal_case ${replacement}]";
    
    lappend tasks "[regsub -all {_} ${target}  \\.]";
    lappend tasks "[regsub -all {_} ${replacement} .]";
    
    lappend tasks "[string toupper ${target}]";
    lappend tasks "[string toupper ${replacement}]";
    
    lappend tasks "[string tolower ${target}]";
    lappend tasks [string tolower ${replacement}];

    foreach {targ repl} $tasks {
        addToStatus "replacing $targ by $repl";
        simpleReplace $targ $repl 1;
      }
    } msg]} {
        addToStatus $msg;
    }

    set case_sensitive $case_sensitive_backup; 
}


proc wrap {mode} {
    .t configure -wrap $mode;
}

proc addToStatus {msg} {
    .status insert end "\n";
    .status insert end $msg;
    .status yview end;
}

proc regexRepeatedWord {} {
    return {\m(\w+)\s+\1\M};
}

proc regexNonAsciiChar {} {
    return {[^\x00-\x7F]};
}
## CURL TESTS 
proc abort_tests {} {
    global should_abort_curl_tests;
    set should_abort_curl_tests 1;
}

proc init_abort_tests {} {
    global should_abort_curl_tests;
    set should_abort_curl_tests 0;
}
init_abort_tests;

proc find_in_folder_or_parents {folder find_file_name} {
    set fname "${folder}/${find_file_name}"
    if {[file exists $fname]} {
        return $fname;
    }
    regsub -all {/[^/]*$} $folder {} parent_folder;
    if {$folder != $parent_folder} {
        return [find_in_folder_or_parents $parent_folder $find_file_name];
    } else {
        return "";
    }
}

set curltest_runCount 0;
set curltest_failCount 0;

proc ue_init {} {
   lappend d + { }
   for {set i 0} {$i < 256} {incr i} {
      set c [format %c $i]
      set x %[format %02x $i]
      if {![string match {[a-zA-Z0-9]} $c]} {
         lappend e $c $x
         lappend d $x $c
      }
   }
   set ::ue_map $e
   set ::ud_map $d
}
ue_init
proc urlencode {s} { string map $::ue_map $s }
proc urldecode {s} { string map $::ud_map $s }

proc reindent_json_file {fname} {
    if {[catch {exec python -m json.tool $fname > $fname.tmp} msg]} {
        addToStatus $msg;
    }
    file copy -force ${fname}.tmp $fname;
    file delete -force ${fname}.tmp;
    
}

proc curltest {filename {lnum ""}} {
    set default_url "http://localhost:9990";
    set default_endpoint "/api/servicestatus";
    resttest_helper $filename $default_url $default_endpoint 0 0 $lnum
}

proc resttest {filename url endpoint } {
    resttest_helper $filename $url $endpoint 1 1 ""
}

proc resttest_helper {filename default_url default_endpoint ignoreurlfile ignoreendpointfile {lnum ""}} {
    global curltest_runCount;
    global curltest_failCount;
    global should_abort_curl_tests;

    set folder [regsub -all {/[^/]*$} $filename ""];
    set filebase [regsub -all {\.[^.]*$} $filename ""];
    
    set default_difftool "diff";
    set default_difftool_args {};

    set difftool $default_difftool;
    set difftool_file [find_in_folder_or_parents $folder "difftool.txt"];
    if {$difftool_file != ""} {
        set difftool [string trim [read_file_contents $difftool_file]];
    }
    
    set default_preproctool "";
    
     set preproctool $default_preproctool;
    set preproctool_file [find_in_folder_or_parents $folder "preproctool.txt"];
    if {$preproctool_file != ""} {
        set preproctool [string trim [read_file_contents $preproctool_file]];
    }
    
    set difftool_args $default_difftool_args;
    set difftool_args_file [find_in_folder_or_parents $folder "difftool_args.txt"];
    if {$difftool_args_file != ""} {
        set difftool_args [string trim [read_file_contents $difftool_args_file]];
    } 
    
    set url $default_url;
    if { ! $ignoreurlfile } {
        set urlfile [find_in_folder_or_parents $folder "url.txt"];
        if {$urlfile != ""} {
            set url [string trim [read_file_contents $urlfile]];
        }
    }
    
    set endpoint $default_endpoint;
    if { !$ignoreendpointfile } {
        set endpointfile [find_in_folder_or_parents $folder "endpoint.txt"];
        if {$endpointfile != ""} {
            set endpoint [string trim [read_file_contents $endpointfile]];
        }
    }

    set hostname $url;
    regsub -all {https?://([^/:]+)[:/]?.*} $hostname {\1} hostname;
    
    addToStatus "looking for token file ${hostname}.token";
    set tokenfile [find_in_folder_or_parents $folder "${hostname}.token"];
    if {$tokenfile != "" } { addToStatus "tokenfile=$tokenfile " }
    set access_token "";
    if {$tokenfile != ""} {
        set access_token [string trim [read_file_contents $tokenfile]];
    }
    
    addToStatus "looking for xtoken file ${hostname}.xtoken";
    set xtokenfile [find_in_folder_or_parents $folder "${hostname}.xtoken"];
    if {$xtokenfile != "" } { addToStatus "xtokenfile=$xtokenfile " }
    set access_xtoken {};
    if {$xtokenfile != ""} {
        set access_xtoken [string trim [read_file_contents $xtokenfile]];
    }
    set xtoken_header {}
    if {$access_xtoken != ""} {
        set xtoken_header [list "-H" "X-SECURITY-TOKEN: $access_xtoken"] 
    }
    
    addToStatus "looking for authtoken file ${hostname}.authtoken";
    set authtokenfile [find_in_folder_or_parents $folder "${hostname}.authtoken"];
    if {$authtokenfile != "" } { addToStatus "authtokenfile=$authtokenfile " }
    set access_authtoken {};
    if {$authtokenfile != ""} {
        set access_authtoken [string trim [read_file_contents $authtokenfile]];
    }
    set authtoken_header {}
    if {$access_authtoken != ""} {
        set authtoken_header [list "-H" "Authorization: Token $access_authtoken"]
    }
    
    set request [string trim [read_file_contents $filename]];
    set is_getfile [regexp {\.get$} $filename];
    set is_egetfile [regexp {\.eget$} $filename];
    
    update;
    set tt [time {
        if {$access_token == ""} {
            if {$request == "" || $is_getfile || $is_egetfile} {
                if {$is_egetfile} { set erequest [urlencode $request]} else { set erequest $request}           
                addToStatus "curl --request GET -s -d @${filename} -H \"Content-Type: application/json\"  $xtoken_header $authtoken_header ${url}${endpoint}${erequest}" ;
                catch {exec curl --request GET -s -d "@${filename}" -H "Content-Type: application/json" {*}$xtoken_header {*}$authtoken_header "${url}${endpoint}${erequest}" >    ${filebase}.out} msg;
            } else {
                addToStatus "curl -s -d @${filename} -H \"Content-Type: application/json\" $xtoken_header $authtoken_header ${url}${endpoint}" ;
                catch {exec curl -s -d "@${filename}" -H "Content-Type: application/json" {*}$xtoken_header {*}$authtoken_header  "${url}${endpoint}" >    ${filebase}.out} msg;                
            }
        } else {
            if {$request == "" || $is_getfile || $is_egetfile } {     
                if {$is_egetfile} { set erequest [urlencode $request]} else { set erequest $request}           
                addToStatus "curl --request GET --insecure -s -d @${filename} --oauth2-bearer $access_token -H \"Content-Type: application/json\"   $xtoken_header ${url}${endpoint}${erequest}" ;
                catch {exec curl --request GET --insecure -s -d "@${filename}" --oauth2-bearer $access_token -H "Content-Type: application/json"  {*}$xtoken_header "${url}${endpoint}${erequest}" > ${filebase}.out} msg;
            } else {
                addToStatus "curl --insecure -s -d @${filename} --oauth2-bearer $access_token -H \"Content-Type: application/json\" $xtoken_header  ${url}${endpoint}" ;
                catch {exec curl --insecure -s -d "@${filename}" --oauth2-bearer $access_token -H "Content-Type: application/json" {*}$xtoken_header  "${url}${endpoint}" > ${filebase}.out} msg;
                
            }
        }
    if {$msg != ""} {
        addToStatus $msg;
    }
   }];
   
   set outcont [string trim [read_file_contents ${filebase}.out]];
   
   file copy -force ${filebase}.out ${filebase}.rawout;
   
   if {$preproctool != ""} {
        catch {exec {*}$preproctool  "${filebase}.out"} msg;
        if {$msg != ""} {
            addToStatus $msg;
        }
   }

   set firstchar [string index $outcont 0];
   if { $firstchar == "\{" || $firstchar == "\[" } {
      reindent_json_file ${filebase}.out;
   }

   update;
   if {$lnum != "" } {
       set linestart "${lnum}.0";
       set lineend [[editor] index "${lnum}.0 lineend"];
   }

   if {![file exists "${filebase}.golden"]} {
     file copy -force "${filebase}.out" "${filebase}.golden";
     addToStatus "$filename CREATING GOLDEN OUTPUT";
     if {$lnum != ""} {
         [editor] tag remove #aafba2 $linestart $lineend;
         [editor] tag remove #fd9f9f $linestart $lineend;
         [editor] tag add #f0f583 $linestart $lineend;
     }
   } else {
    catch {exec $difftool {*}$difftool_args "${filebase}.golden" "${filebase}.out" > ${filebase}.diff} msg;
    if {$msg != ""} {
        addToStatus $msg;
    }
    
    
    set fpdiff [open "${filebase}.diff" r];
    set diffcont [string trim [read $fpdiff]];
    close $fpdiff;
    
    set fail 0;
    set dont_fail_on_diff [string match *DONT_FAIL_ON_DIFF* $outcont]
    set dont_fail_on_error [string match *DONT_FAIL_ON_ERROR* $outcont]
    set has_error [string match *ERROR* $outcont]
    set has_test_failed [string match *TEST_FAILED* $outcont]    
    if { $dont_fail_on_diff } {
        if {$dont_fail_on_error} {
            set fail $has_test_failed;
        } else {
            set fail $has_error;
        }
    } else {
        set fail [expr [string length $diffcont] != 0]
    }
    
    if {$fail} {
        if {$lnum != ""} {
            [editor] tag remove #aafba2 $linestart $lineend;
            [editor] tag remove #f0f583 $linestart $lineend;
            [editor] tag add #fd9f9f $linestart $lineend;
            add_file_at $lineend  "${filebase}.diff";
        }
        incr curltest_failCount;
        addToStatus "$filename FAILED : $tt";
    } else {
        if {$lnum != ""} {
            [editor] tag remove #fd9f9f $linestart $lineend;
            [editor] tag remove #f0f583 $linestart $lineend;
            [editor] tag add #aafba2 $linestart $lineend;
        }
        addToStatus "$filename PASS : $tt";
    }
  }
  incr curltest_runCount;
}

proc rebaseline_tests {} {
    global should_abort_curl_tests;
    set fulltext [[editor] get 1.0 end];
    set lines [split $fulltext "\n"];
    set cnt 0;
    foreach line $lines {
        if {$should_abort_curl_tests} {
            set should_abort_curl_tests 0;
            break;
        }
        incr cnt;
        set line [string trim $line];
        if {$line == "" || [string range $line 0 0] == "#"} {
            continue;
        }
        set filebase [regsub -all {.[^.]*$} $line ""];
        catch {
            file copy -force ${filebase}.out ${filebase}.golden;
       } msg;
       addToStatus $msg;
   }
   tk_messageBox -message "Finished rebaselining";
}
proc make_tempfile {} {
    set tmpdir "/tmp"
    global tcl_platform
    if {$tcl_platform(platform) == "windows"} {
        set tmpdir "c:/tmp"
    }
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
 
    global curltest_runCount;
    global curltest_failCount;
    global should_abort_curl_tests;
    set default_executable "bash";
    set default_preamble "";
    set default_args {};

    set folder [regsub -all {/[^/]*$} $filename ""];
    set filebase [regsub -all {\.[^.]*$} $filename ""];
    

    set executable $default_executable;
    set execfile [find_in_folder_or_parents $folder "executable.txt"];
    if {$execfile != ""} {
        set executable [string trim [read_file_contents $execfile]];
    }
    
    set args $default_args;
    set argsfile [find_in_folder_or_parents $folder "args.txt"];
    if {$argsfile != ""} {
        set args [string trim [read_file_contents $argsfile]];
    }

    set default_difftool "diff";
    set default_difftool_args {};

    set difftool $default_difftool;
    set difftool_file [find_in_folder_or_parents $folder "difftool.txt"];
    if {$difftool_file != ""} {
        set difftool [string trim [read_file_contents $difftool_file]];
    }
  
    set filtertool "";
    set filtertool_file [find_in_folder_or_parents $folder "filtertool.txt"]
    if {$filtertool_file != ""} {
        set filtertool [string trim [read_file_contents $filtertool_file]]
    }

    set filterpipe {}
    if {$filtertool != "" } {
        set filterpipe [list "|" {*}$filtertool];
    }

    set difftool_args $default_difftool_args;
    set difftool_args_file [find_in_folder_or_parents $folder "difftool_args.txt"];
    if {$difftool_args_file != ""} {
        set difftool_args [string trim [read_file_contents $difftool_args_file]];
    } 
    
 
    set preamble $default_preamble;
    set preamblefile [find_in_folder_or_parents $folder "preamble.txt"];
    if {$preamblefile != ""} {
        set preamble [string trim [read_file_contents $preamblefile]];
    }

    set tmpfile [make_tempfile]
    set fptmp [open $tmpfile w];
    puts $fptmp $preamble;
    set testfilecontent [read_file_contents $filename];
    puts $fptmp $testfilecontent;
    close $fptmp;
    set rundir [pwd];
    
    cd $folder;
    update;

    set tt [time {
        addToStatus "exec $executable $args $tmpfile $filterpipe" ;
        catch {exec $executable {*}$args $tmpfile {*}$filterpipe >   ${tmpfile}.out} msg;    
    if {$msg != ""} {
        addToStatus $msg;
    }
   }];
    cd $rundir;
    file copy -force ${tmpfile}.out ${filebase}.out;
   
    file delete -force $tmpfile
    file delete -force ${tmpfile}.out
 
   update;
   if {$lnum != "" } {
       set linestart "${lnum}.0";
       set lineend [[editor] index "${lnum}.0 lineend"];
   }

   if {![file exists "${filebase}.golden"]} {
     file copy -force "${filebase}.out" "${filebase}.golden";
     addToStatus "$filename CREATING GOLDEN OUTPUT";
     if {$lnum != ""} {
         [editor] tag remove #aafba2 $linestart $lineend;
         [editor] tag remove #fd9f9f $linestart $lineend;
         [editor] tag add #f0f583 $linestart $lineend;
     }
   } else {
    catch {exec $difftool {*}$difftool_args "${filebase}.golden" "${filebase}.out"  > ${filebase}.diff} msg;
    if {$msg != ""} {
        addToStatus $msg;
    }
    
    set fpdiff [open "${filebase}.diff" r];
    set diffcont [string trim [read $fpdiff]];
    close $fpdiff;
    
    set fail 0;
    set dont_fail_on_diff [string match *DONT_FAIL_ON_DIFF* $outcont]
    set dont_fail_on_error [string match *DONT_FAIL_ON_ERROR* $outcont]
    set has_error [string match *ERROR* $outcont]
    set has_test_failed [string match *TEST_FAILED* $outcont]    
    if { $dont_fail_on_diff } {
        if {$dont_fail_on_error} {
            set fail $has_test_failed;
        } else {
            set fail $has_error;
        }
    } else {
        set fail [expr [string length $diffcont] != 0]
    }
    
    if {$fail} {
            if {$lnum != ""} {
                [editor] tag remove #aafba2 $linestart $lineend;
                [editor] tag remove #f0f583 $linestart $lineend;
                [editor] tag add #fd9f9f $linestart $lineend;
            }
            incr curltest_failCount;
            addToStatus "$filename FAILED : $tt";
    } else {
        if {$lnum != ""} {
            [editor] tag remove #fd9f9f $linestart $lineend;
            [editor] tag remove #f0f583 $linestart $lineend;
            [editor] tag add #aafba2 $linestart $lineend;
        }
        addToStatus "$filename PASS : $tt";
    }
  }
  
  incr curltest_runCount;
}

proc run_test_suite {{cmd curltest}} {
    global should_abort_curl_tests;
    global curltest_runCount;
    global curltest_failCount;
    set curltest_runCount 0;
    set curltest_failCount 0;
    set fulltext [[editor] get 1.0 end];
    set lines [split $fulltext "\n"];
    set cnt 0;
    foreach line $lines {
        if {$should_abort_curl_tests} {
            set should_abort_curl_tests 0;
            break;
        }
        incr cnt;
        set line [string trim $line];
        if {$line == "" || [string range $line 0 0] == "#"} {
            continue;
        }
        set filename $line;
        set filebase [regsub -all {\.[^.]*$} $line ""];
        catch {
          $cmd $filename  $cnt
       } msg;
       addToStatus $msg;
   }
   tk_messageBox -message "Finished : Ran $curltest_runCount tests, $curltest_failCount failed";
}
proc sum {args} {
    set sum 0.0;
    foreach s $args {
        foreach t $s {
            set sum [expr $sum+$t];
        }
    }
    return $sum;
}

proc prod {args} {
    set prod 1.0;
    foreach s $args {
        foreach t $s {
            set prod  [expr $prod+$t];
        }
    }
    return $prod;
}
proc max {args} {
    set result "";
    foreach s $args {
      set max [tcl::mathfunc::max {*}$s]
      if {$result == ""} { set result $max} elseif {$max > $result} {
          set result $max;
      }
  }
  return $result;
}
proc min {args} {
    set result "";
    foreach s $args {
      set min [tcl::mathfunc::min {*}$s]
      if {$result == ""} { set result $min} elseif {$min < $result} {
          set result $min;
      }
  }
  return $result;
}

proc processStringInput {title prompt callback} {
     set suffix [guid]
    # Create a dialog window
    toplevel .dialog${suffix}
    wm title .dialog${suffix} $title
    wm geometry .dialog${suffix}  600x120
    
    # Create a label with the prompt
    label .dialog${suffix}.label -text $prompt
    pack .dialog${suffix}.label -padx 4 -pady 4 -fill x -expand yes
    
    # Create an entry widget for input
    entry .dialog${suffix}.entry
    pack .dialog${suffix}.entry -padx 4 -pady 4 -fill x -expand yes
    
    # Create an OK button
    button .dialog${suffix}.ok -text "OK" -command "
        set result \[.dialog${suffix}.entry get\]
        destroy .dialog${suffix};
        eval \[list {*}$callback \$result\]
        
    "
    pack .dialog${suffix}.ok -side left -padx 4 -pady 4
    
    # Create a Cancel button
    button .dialog${suffix}.cancel -text "Cancel" -command "
        destroy .dialog${suffix}
    "
    pack .dialog${suffix}.cancel -side right -padx 4 -pady 4
    
    # Focus the entry widget
    focus .dialog${suffix}.entry
    
    # Start the Tk event loop
    tkwait window .dialog${suffix}
}


proc processMultipleStringInputs {title prompts callback} {
     set suffix [guid]
    # Create a dialog window
    toplevel .dialog${suffix}
    wm title .dialog${suffix} $title
    wm geometry .dialog${suffix}  "600x[expr 100*[llength $prompts]]"
    foreach prompt $prompts {
        # Create a label with the prompt
        label .dialog${suffix}.label${prompt} -text $prompt
        pack .dialog${suffix}.label${prompt} -padx 4 -pady 4 -fill x -expand yes
    
        # Create an entry widget for input
        entry .dialog${suffix}.entry${prompt}
        pack .dialog${suffix}.entry${prompt} -padx 4 -pady 4 -fill x -expand yes
    }
    
    # Create an OK button
    button .dialog${suffix}.ok -text "OK" -command "
        set result {};
        foreach prompt \{$prompts\} \{
           lappend result \[.dialog${suffix}.entry\${prompt} get\] 
        \}
        destroy .dialog${suffix};
        eval \[list {*}$callback {*}\$result\]
        
    "
    pack .dialog${suffix}.ok -side left -padx 4 -pady 4
    
    # Create a Cancel button
    button .dialog${suffix}.cancel -text "Cancel" -command "
        destroy .dialog${suffix}
    "
    pack .dialog${suffix}.cancel -side right -padx 4 -pady 4
    
    
    # Start the Tk event loop
    tkwait window .dialog${suffix}
}

proc replace_in_file {pattern substitution filename} {
    # Read the file contents
    set fp [open $filename r]
    set content [read $fp]
    close $fp

    # Perform the replacement using regsub -all for global replacement
    set new_content [regsub -all -- $pattern $content $substitution]

    # Overwrite the original file with the new content
    set fp [open $filename w]
    puts -nonewline $fp $new_content
    close $fp
}
proc rename_listed_files {pattern substitution} {
    set files_seen {}
    foreach {filename linenum} [get_grep_lines] {
        # Remove leading ./ from filename
        regsub -all {^\./} $filename {} filename

        # Skip files already processed
        if {[lsearch -exact $files_seen $filename] >= 0} continue
        lappend files_seen $filename

        # Only process files matching the pattern
        if {![regexp $pattern $filename]} continue

        # Compute new name
        set newname [regsub -all $pattern $filename $substitution]

        # Optionally check if file exists and newname is different
        if {$filename eq $newname} continue
        if {![file exists $filename]} continue

        # Rename the file
        file rename $filename $newname

        # Report status
        addToStatus "Renamed $filename to $newname"
    }
}

proc replace_in_listed_files {pattern substitution} {
    set files_seen {}
    foreach {filename linenum} [get_grep_lines] {
        # Remove leading ./ from filename
        regsub -all {^\./} $filename {} filename

        # Skip files already processed
        if {[lsearch -exact $files_seen $filename] >= 0} continue
        lappend files_seen $filename

        # Optionally check if file exists
        if {![file exists $filename]} continue

        # Read file content
        set fp [open $filename r]
        set content [read $fp]
        close $fp

        # Perform substitution (global)
        set new_content [regsub -all -- $pattern $content $substitution]

        # Only write if something changed
        if {$content ne $new_content} {
            set fp [open $filename w]
            puts -nonewline $fp $new_content 
            close $fp
            addToStatus "Replaced '$pattern' with '$substitution' in $filename"
        } else {
            addToStatus "No changes needed in $filename"
        }
    }
}

proc selincr { {delta 1} }  {
    selre {\d+}
    set selranges [.t tag ranges sel];
    set selranges [lreverse $selranges]
    foreach {end start} $selranges {
        set txt [.t get $start $end];
        if {[string is integer $txt]} {
            .t delete $start $end;
            .t insert $start [expr $txt+$delta] sel;
        }
    }
}
proc str2hex {s} {
    binary scan $s H* hex
    puts $hex
}
##### aliases ALIASES ##### 
proc add_spectral_alias {cmd} {
    global qcInterp;
    global all_commands;
    append all_commands " " $cmd;
    uplevel #0 "interp alias $qcInterp $cmd {} $cmd";
}

proc spectral_qc_puts {args} {
    set newline 1
    set channel stdout
    if {[llength $args] == 0} {
        error {wrong # args: should be "puts ?-nonewline? ?channelId? string"}
    }
    if {[lindex $args 0] eq "-nonewline"} {
        set newline 0
        set args [lrange $args 1 end]
    }
    if {[llength $args] == 1} {
        set msg [lindex $args 0]
    } elseif {[llength $args] == 2} {
        set channel [lindex $args 0]
        set msg [lindex $args 1]
    } else {
        error {wrong # args: should be "puts ?-nonewline? ?channelId? string"}
    }

    if {$channel ni {stdout stderr}} {
        if {$newline} {
            return [::puts $channel $msg]
        }
        return [::puts -nonewline $channel $msg]
    }

    set target .status
    if {[cmd_to_editor]} {
        set target .t
    }
    $target insert end $msg
    if {$newline} {
        $target insert end "\n"
    }
    $target yview end
    return
}

proc lunique {lst} {
    return [lsort -unique $lst];
}

proc enlargeFonts {w {inc 2}} {
    proc _inc_font {w inc} {
        if {[catch {$w cget -font} curFont]} {
            return
        }
        set fontSpec [font actual $curFont]
        set curSize [dict get $fontSpec -size]
        set newSize [expr {$curSize + $inc}]
        if {$newSize < 6} {set newSize 6}   ;# Prevent tiny/invisible fonts
        set newFont [font create -family [dict get $fontSpec -family] \
            -size $newSize -weight [dict get $fontSpec -weight] \
            -slant [dict get $fontSpec -slant] -underline [dict get $fontSpec -underline] \
            -overstrike [dict get $fontSpec -overstrike]]
        $w configure -font $newFont
    }

    _inc_font $w $inc
    foreach child [winfo children $w] {
        enlargeFonts $child $inc
    }
}
add_spectral_alias str2hex;
add_spectral_alias rename_listed_files;
add_spectral_alias selincr;
add_spectral_alias replace_in_file;
add_spectral_alias toggleTopFrames;
add_spectral_alias replace_in_listed_files;
add_spectral_alias load_all_listed_files;
add_spectral_alias enlargeFonts;
add_spectral_alias get_listed_files;
add_spectral_alias insert_line_after_grepline;
add_spectral_alias selBracedRange;
add_spectral_alias selaroundsel;
add_spectral_alias show_text_input ;
add_spectral_alias resttest ;
add_spectral_alias show_choice ;
add_spectral_alias count_re;
add_spectral_alias urlencode;
add_spectral_alias urldecode;
add_spectral_alias comma_separate;
add_spectral_alias suffixes;
add_spectral_alias prefixes;
add_spectral_alias defmacro;
add_spectral_alias def_p_macro;
add_spectral_alias expand_macro;
add_spectral_alias processMultipleStringInputs;
add_spectral_alias add_sel_as_notes;
add_spectral_alias upper_case;
add_spectral_alias lower_case;
add_spectral_alias lunique;
add_spectral_alias sort_selected;
add_spectral_alias puts_list;
add_spectral_alias add_hypertargets_at_sel;
add_spectral_alias load_one_line_before;
add_spectral_alias load_one_line_after;
add_spectral_alias load_more_lines;
add_spectral_alias add_popup_menu_item;
add_spectral_alias popupStatusContent;
add_spectral_alias selected_device;
add_spectral_alias processStringInput;
add_spectral_alias saveWalkthroughZip;
add_spectral_alias clear_hyperlink_targets;
add_spectral_alias clear_hyperlinks;
add_spectral_alias show_hyperlink_targets;
add_spectral_alias show_hyperlinks;
add_spectral_alias isWindowsExecutable;
add_spectral_alias exportButtonsToHtml
add_spectral_alias pasteMultiLine;
add_spectral_alias pasteMultiLineEnd;
add_spectral_alias sum;
add_spectral_alias followTarget;
add_spectral_alias hyperlink_selected_grep_lines;
add_spectral_alias min;
add_spectral_alias prod;
add_spectral_alias max;
add_spectral_alias run_generators;
add_spectral_alias add_generator;
add_spectral_alias run_verifiers;
add_spectral_alias add_verifier;
add_spectral_alias dyslexiaOfNumbers;
add_spectral_alias debug_special_notes;
add_spectral_alias tags_in_range;
add_spectral_alias show_tooltip;
add_spectral_alias add_tags_to_sel;
add_spectral_alias addNotesForNumbers;
add_spectral_alias add_ref_to_listed_files;
add_spectral_alias selskip;
add_spectral_alias enlarge_font;
add_spectral_alias add_border;
add_spectral_alias remove_border;
add_spectral_alias f1;
add_spectral_alias add_media_file_at;
add_spectral_alias isWindowsExecutable;
add_spectral_alias selected_device;
add_spectral_alias spectral_script;
add_spectral_alias selfrac;
add_spectral_alias adhd;
add_spectral_alias get_external_hyperrefs;
add_spectral_alias hyperref;
add_spectral_alias seltags;
add_spectral_alias alltags;
add_spectral_alias tags_overlapping_selection;
add_spectral_alias tags_contained_in_selection;
add_spectral_alias add_hypertarget;
add_spectral_alias get_hypertarget;
add_spectral_alias abort_tests;
add_spectral_alias reindent_json_file;
add_spectral_alias curltest;
add_spectral_alias generaltest;
add_spectral_alias rebaseline_tests;
add_spectral_alias run_test_suite;
add_spectral_alias visit_re_quiet;
add_spectral_alias visit_re;
add_spectral_alias add_double_click_handler;
add_spectral_alias load_line_fields;
add_spectral_alias diffdiff;
add_spectral_alias load_line_stringrange;
add_spectral_alias delete_notes_by_content;
add_spectral_alias delete_images;
add_spectral_alias make_slides_template;
add_spectral_alias convert_images;
add_spectral_alias get_linenumbers_with_tag_in_trace_file;
add_spectral_alias call_stack_from_reversed_trace_file;
add_spectral_alias set_case_sensitive_mode;
add_spectral_alias get_case_sensitive_mode;
add_spectral_alias set_multiword_mode;
add_spectral_alias get_multiword_mode;
add_spectral_alias annotate_coverage_inline;
add_spectral_alias pasteMultiselClipAtEnd;
add_spectral_alias clearHighlightsInRange
add_spectral_alias complete_filenames;
add_spectral_alias load_sample_lines;
add_spectral_alias find_in_folder_or_parents;
add_spectral_alias tk_getOpenFile;
add_spectral_alias tk_messageBox;
add_spectral_alias tk_chooseDirectory;
add_spectral_alias tk_chooseColor;
add_spectral_alias find_files;
add_spectral_alias signedRegexp;

add_spectral_alias quotesel;
add_spectral_alias configure_send_bgerror_to_status;
add_spectral_alias read_file_contents;
add_spectral_alias read_ascii_file_contents;
add_spectral_alias collect_trace_snippets;
add_spectral_alias add_file_at;
add_spectral_alias hlre;
add_spectral_alias load_coverage_hits_multifile;
add_spectral_alias tesseract_ocr;
add_spectral_alias addToStatus;
add_spectral_alias really_exit;
add_spectral_alias replace_by_analogy;
add_spectral_alias replace_substring_by_analogy;
add_spectral_alias regexRepeatedWord;
add_spectral_alias regexRepeatedWord;
add_spectral_alias regexNonAsciiChar;
add_spectral_alias  delete_selected_notes;
add_spectral_alias  load_more_lines;
add_spectral_alias  load_more_lines_at_sel;
add_spectral_alias  reverse_char_order;
add_spectral_alias  cmdhistory;
add_spectral_alias  trace_hotspots;
add_spectral_alias  readTextAloud;
add_spectral_alias   every;
add_spectral_alias   stopevery;
add_spectral_alias  search_multiple;
add_spectral_alias  wrap;
add_spectral_alias  count;
add_spectral_alias  idcount;
add_spectral_alias  symcount;
add_spectral_alias  assert;
add_spectral_alias  ascheck;
add_spectral_alias  addAudioReadoutsOfNotes;
add_spectral_alias  embed_html_notes;
add_spectral_alias  note;
add_spectral_alias  set_bg;
add_spectral_alias  sel_grep_lines;
add_spectral_alias  set_fg;
add_spectral_alias  insert_image;
add_spectral_alias  load_slides;
add_spectral_alias  shuffle;
add_spectral_alias  get_notefiles;
add_spectral_alias  notesgrep;
add_spectral_alias  notesgrep_postfilter;
add_spectral_alias  sort_lines;
add_spectral_alias  camel;
add_spectral_alias  camel_case;
add_spectral_alias  pascal;
add_spectral_alias  pascal_case;
add_spectral_alias  snake;
add_spectral_alias  snake_case;
add_spectral_alias  kebab;
add_spectral_alias  kebab_case;
add_spectral_alias  annot_search;
add_spectral_alias  set_hl_bg;
add_spectral_alias  set_hl_fg;
add_spectral_alias  pickColor;
add_spectral_alias  selexpand;
add_spectral_alias  selexpandendl;
add_spectral_alias  selendl;
add_spectral_alias  set_hl_font;
add_spectral_alias  load_html;
add_spectral_alias  create_note;
add_spectral_alias  insert_text;
add_spectral_alias  delete_notes_in_files;
add_spectral_alias  save_html_files;
add_spectral_alias  save_context_annotated_html;
add_spectral_alias  save_context_annotated_ehtml;
add_spectral_alias  save_coverage_annotated_html;
add_spectral_alias  substitute_in_files;
add_spectral_alias  execute_on_files;
add_spectral_alias  insert_before;
add_spectral_alias  base64::encode;
add_spectral_alias  base64::decode;
add_spectral_alias  get_grep_lines;
add_spectral_alias  insert_after;
add_spectral_alias  hlt_insert_at;
add_spectral_alias  insert_at;
add_spectral_alias  reverse_line_order;
add_spectral_alias  args;
add_spectral_alias  selfromstart;
add_spectral_alias  seltoend;
add_spectral_alias  selend;
add_spectral_alias  selstart;
add_spectral_alias  selmove;
add_spectral_alias  add_preamble;
add_spectral_alias  add_postscript;
add_spectral_alias  delete_notes;
add_spectral_alias  trace_locations;
add_spectral_alias  load_coverage_hits;
add_spectral_alias  clear_coverage_hits;
add_spectral_alias  annotate_coverage;
add_spectral_alias  annotate_contexts;
add_spectral_alias  clock_decode;
add_spectral_alias  quilt;
add_spectral_alias  reformat_xml;
add_spectral_alias  reformat_xml_file;
add_spectral_alias  strdiff;
add_spectral_alias  strdiff++;
add_spectral_alias  strdiff_files;
add_spectral_alias  commands;
add_spectral_alias  embedded_content_on_single_line;
add_spectral_alias  addmenu;
add_spectral_alias  bind;
add_spectral_alias  tempfilename;
add_spectral_alias  clear_file_history;
add_spectral_alias  clear_command_history;
add_spectral_alias  recent_commands;
add_spectral_alias  recent_files;
add_spectral_alias  clipboard;
add_spectral_alias  addmenucommand;
add_spectral_alias  .menu;
add_spectral_alias  menu;
add_spectral_alias  set_image_editor;
add_spectral_alias  enumerate;
add_spectral_alias  hex2bin  
add_spectral_alias  bin2hex  
add_spectral_alias  bin2chex  
add_spectral_alias  bin2double  
add_spectral_alias  bin2float   
add_spectral_alias  double2bin  
add_spectral_alias  float2bin   
add_spectral_alias  int2bin         
add_spectral_alias  bin2int         
add_spectral_alias  save_binary 
add_spectral_alias  save_hex 
add_spectral_alias  hex2dec;
add_spectral_alias  bin2dec;
add_spectral_alias  load_binary;
add_spectral_alias  load_hex;
add_spectral_alias  substitute;
add_spectral_alias  registry;
add_spectral_alias  read_trace_lookup;
add_spectral_alias  reflow;
add_spectral_alias  load_trace_lookup;
add_spectral_alias  selre;
add_spectral_alias  unselre;
add_spectral_alias  invsel;
add_spectral_alias  delline;
add_spectral_alias   splitsel;
add_spectral_alias  embed_images;
add_spectral_alias   hyperlink_to_selected;
add_spectral_alias  choosedir;
add_spectral_alias  grepnotes;
add_spectral_alias  tk_exec;
add_spectral_alias  installdir;
add_spectral_alias  exit;
add_spectral_alias  filepath;
add_spectral_alias  applyWatermark;
add_spectral_alias  sortuniq;
add_spectral_alias  ascheck;
add_spectral_alias  title;
add_spectral_alias  macex;
add_spectral_alias  yw;
add_spectral_alias  :;
add_spectral_alias  cc;
add_spectral_alias   d/;
add_spectral_alias   dx/;
add_spectral_alias   sel/;
add_spectral_alias   selx/;
add_spectral_alias  lc;
add_spectral_alias  uc;
add_spectral_alias  p;
add_spectral_alias  u;
add_spectral_alias  /;
add_spectral_alias  dw;
add_spectral_alias  :w;
add_spectral_alias  :w!;
add_spectral_alias  :q;
add_spectral_alias  :wq;
add_spectral_alias  get_current_filename
add_spectral_alias  get_current_folder;
add_spectral_alias  del;
add_spectral_alias  editor;
add_spectral_alias  hlt:save;
add_spectral_alias  hlt:restore;
add_spectral_alias  bgerror;
add_spectral_alias  hl;
add_spectral_alias  selOnly;
add_spectral_alias  match_longest;
add_spectral_alias  match_shortest;
add_spectral_alias  yy;
add_spectral_alias  yp;
add_spectral_alias  dd;
add_spectral_alias  copySelection;
add_spectral_alias  sel;
add_spectral_alias  dellines;
add_spectral_alias  keeplines;
add_spectral_alias  seltag;
add_spectral_alias  selrect
add_spectral_alias  getmenu;
add_spectral_alias  userproc;
add_spectral_alias  set_keywords;
add_spectral_alias  load_plugin;
add_spectral_alias  set_spectral_subfolder;
add_spectral_alias  $menu.syntax;
add_spectral_alias  $menu.file;
add_spectral_alias  $menu.edit;
add_spectral_alias  $menu.navi;
add_spectral_alias  $menu.options;
add_spectral_alias  edit;
add_spectral_alias  edit:close;
add_spectral_alias  save;
add_spectral_alias  guid;
add_spectral_alias  vanillaMode;
add_spectral_alias  ctextMode;
add_spectral_alias  forText;
add_spectral_alias  cmd_to_editor;
add_spectral_alias  .status;
add_spectral_alias gentablelogger;

proc add_to_all_commands {cmd} {
    global all_commands;
    append all_commands " " $cmd;
}

add_spectral_alias add_to_all_commands;
foreach util {HtmlClipboard agrep ansi2knr basename bc bison bunzip2 bzip2 bzip2recover cat chgrp chmod chown cksum cmp comm compress cp csplit cut date dc df diff diff3 dircolors dirname du echo egrep env expand factor fgrep find flex fmt fold fsplit gawk gclip gplay grep gsar gunzip gzip head id indent install jwhois less lesskey ln logname ls m4 make makedepend makemsg man md5sum mkdir mkfifo mknod mv mvdir nl od paste patch pathchk pclip pr printenv printf ptx recode rm rman rmdir sdiff sed seq sha1sum shar sleep sort  stego su sum sync tac tail tar tee test touch tr tsort type uname unexpand uniq unrar unshar unzip uudecode uuencode wc wget which whoami xargs yes zcat zip} { 
        add_to_all_commands $util;
};

$qcInterp eval {
    catch {
        foreach util {HtmlClipboard agrep ansi2knr basename bc bison bunzip2 bzip2 bzip2recover cat chgrp chmod chown cksum cmp comm compress cp csplit cut date dc df diff diff3 dircolors dirname du echo egrep env expand factor fgrep find flex fmt fold fsplit gawk gclip gplay grep gsar gunzip gzip head id indent install jwhois less lesskey ln logname ls m4 make makedepend makemsg man md5sum mkdir mkfifo mknod mv mvdir nl od paste patch pathchk pclip pr printenv printf ptx recode rm rman rmdir sdiff sed seq sha1sum shar sleep sort  stego su sum sync tac tail tar tee test touch tr tsort type uname unexpand uniq unrar unshar unzip uudecode uuencode wc wget which whoami xargs yes zcat zip} { 
            if [isWindowsExecutable] {
                proc $util {args} "
                    tk_exec [installdir]/wbin/${util}.exe \{*\}\$args
                "
           } else {
               proc $util {args} "
                    exec ${util} \{*\}\$args
                "
           }
         }
     } 
 };

interp alias $qcInterp puts {} spectral_qc_puts



addToStatus $msg;

wm protocol . WM_DELETE_WINDOW {confirmAndExit}


bind .t <<Modified>> {
    set modified 1;
    updateModifiedStatus;
    .t edit modified 0;
}


proc resetOverpaintedStuff {} {
    global last_overpainted_stuff;
    global last_op_was_overpainting;
    global last_op_was_overpainting 0;
    set last_overpainted_stuff {};
}

proc saveSelectionForUndo {w} {
    global last_overpainted_stuff;
    global last_op_was_overpainting;
    set last_op_was_overpainting 1;
    catch {
            set selranges [$w tag ranges sel];
            set selranges [sortRanges $selranges];
            set new_item {};
            foreach {start end} $selranges {
               set new_item [linsert $new_item 0 [hlt:save $w $start $end]];
               set new_item [linsert $new_item 0 $end];  
               set new_item [linsert $new_item 0 $start];  
             }
             set last_overpainted_stuff [linsert $last_overpainted_stuff 0 $new_item];

    } msg;
    #puts stderr $msg;
}


bind .t <ButtonRelease-1> {
    catch {
    if {$default_highlight != ""} {
        set tagname $default_highlight;

        set afont [[.searchFrame.font component entry] get];
        set foreground [[.searchFrame.foreground component entry] get];
        foreach x $afont {
            foreach y $x {
                append tagname $y;
            }
        }
        if {[llength $foreground]} {
            append tagname "_" $foreground;
        }

        if {[llength $afont]} {
            .t tag configure $tagname -font $afont;
        }
        if {[llength $foreground]} {
          .t tag configure $tagname -foreground $foreground;
        }
        if {$default_highlight != "white" && $default_highlight != "#FFFFFF" && $default_highlight != "#ffffff"} {
              .t tag configure $tagname  -background $default_highlight ;
        }
       
        .t tag raise $tagname;
        set selranges [.t tag ranges sel];
         if {[llength $selranges]} {
                resetOverpaintedStuff;
                saveSelectionForUndo .t;
         }
        if {[llength $selranges] > 2} {
            foreach {start end} $selranges {
                foreach other $all_tags {
                  if {![regexp {(^target_)|(^hyperref_)} $other]} {
                     .t tag remove $other $start $end;
                 }
                }
                .t tag add  $tagname $start $end;
                .t tag remove sel $start $end;
              }
        } else {
            foreach {start end} $selranges {
            
              if {$start != [.t index insert]} {        
                foreach other $all_tags {
                   if {![regexp {(^target_)|(^hyperref_)} $other]} {
                       .t tag remove $other $start $end;
                   }
                }
                .t tag add  $tagname $start $end;
              } else {
                 if {![regexp {(^target_)|(^hyperref_)} $tagname]} {
                     .t tag remove  $tagname $start $end;
                 }
              }
              .t tag remove sel $start $end;
           }
           
        }
        .t tag raise sel;
        if {[lsearch $all_tags $tagname] == -1} {
            lappend all_tags $tagname;
        }
        #loadOverview;    
    }
  }
};


 set font(Button)      {Helvetica -12}
 set font(Checkbutton) {Helvetica -12}
 set font(Radiobutton) {Helvetica -12}
 set font(Label)       {Helvetica -12}
 set font(Entry)       {Helvetica -10}
 set font(Listbox)     {Helvetica -12}
 set font(Menuentry)   {Helvetica -12}
 set font(Menu)        {Helvetica -12}
 set font(Menubutton)  {Helvetica -12}
 set font(Message)     {Helvetica -12}
 set font(Scale)       {Helvetica -12}
 set font(Text)        $default_font;

proc refont_tree { path } {
    global font

    foreach child [winfo children $path] {
        set childtype [winfo class $child]
        if { [info exists font($childtype)] } {
            if {[catch {$child configure -font $font($childtype)} msg] } {
                #puts stderr "$child ($childtype) ERROR: $msg"
            }
        }
        refont_tree $child
    }
 }

refont_tree .

set play_image [image create photo -file "$installdir/wbin/play.png"]
proc setTooltip {widget text} {
        if { $text != "" } {
                
                # 2) Adjusted timings and added key and button bindings. These seem to
                # make artifacts tolerably rare.
                bind $widget <Any-Enter>    [list after 500 " showTooltip %W $text"]
                bind $widget <Any-Leave>    [list after 500 "catch  {destroy %W.tooltip};.t tag remove tempsel 1.0 end"]
                bind $widget <Any-KeyPress> [list after 500 "catch {destroy %W.tooltip};.t tag remove tempsel 1.0 end"]
                bind $widget <Any-Button>   [list after 500 "catch {destroy %W.tooltip}; .t tag remove tempsel 1.0 end"]
        }
 }
 
 set global_show_tooltip 0;
 proc show_tooltip {show} {
     global global_show_tooltip;
     set global_show_tooltip $show;
 }
 proc showTooltip {widget text} {
        global tcl_platform
        if { [string match $widget* [winfo containing  [winfo pointerx .] [winfo pointery .]] ] == 0  } {
                return
        }
        global global_show_tooltip;

        catch { destroy $widget.tooltip }
        
        global comment_tags;
        global global_verifier_tags;
        global global_generator_tags;
        foreach tags_array {
           comment_tags
           global_verifier_tags 
           global_generator_tags } {
             set elemref "";
             append  elemref [set tags_array] "(" $widget ")";
                
             if { [info exists $elemref] } {
                set cmttag [set $elemref]
                set tagranges [.t tag ranges $cmttag];
                foreach {start end} $tagranges {
                    .t tag add tempsel $start $end;
                }
                if {$global_show_tooltip}  {
                  catch {
                   set text [read_file_contents $text]
                   regsub -all {[\n\r]} $text " " text;
                  }
                }
                break;
             }
        }
        

        if {$global_show_tooltip} {
            set scrh [winfo screenheight $widget]    ; # 1) flashing window fix
            set scrw [winfo screenwidth $widget]     ; # 1) flashing window fix
            set tooltip [toplevel $widget.tooltip -bd 1 -bg black]
            wm geometry $tooltip +$scrh+$scrw        ; # 1) flashing window fix
            wm overrideredirect $tooltip 1
    
            if {$tcl_platform(platform) == {windows}} { ; # 3) wm attributes...
                    wm attributes $tooltip -topmost 1   ; # 3) assumes...
            }                                           ; # 3) Windows
            pack [label $tooltip.label -bg lightyellow -fg black -text $text -justify left]
    
            set width [winfo reqwidth $tooltip.label]
            set height [winfo reqheight $tooltip.label]
    
            set pointer_below_midline [expr [winfo pointery .] > [expr [winfo screenheight .] / 2.0]]                ; # b.) Is the pointer in the bottom half of the screen?
    
            set positionX [expr [winfo pointerx .] - round($width / 2.0)]    ; # c.) Tooltip is centred horizontally on pointer.
            set positionY [expr [winfo pointery .] + 35 * ($pointer_below_midline * -2 + 1) - round($height / 2.0)]  ; # b.) Tooltip is displayed above or below depending on pointer Y position.
    
            # a.) Ad-hockery: Set positionX so the entire tooltip widget will be displayed.
            # c.) Simplified slightly and modified to handle horizontally-centred tooltips and the left screen edge.
            if  {[expr $positionX + $width] > [winfo screenwidth .]} {
                    set positionX [expr [winfo screenwidth .] - $width]
            } elseif {$positionX < 0} {
                    set positionX 0
            }
    
            wm geometry $tooltip [join  "$width x $height + $positionX + $positionY" {}]
            raise $tooltip
    
            # 2) Kludge: defeat rare artifact by passing mouse over a tooltip to destroy it.
            bind $widget.tooltip <Any-Enter> {destroy %W}
            bind $widget.tooltip <Any-Leave> {destroy %W}
            }
 }

 foreach id {1 2 3 4 5 6} {
     setTooltip [.searchFrame.search$id component label] "Left click to highlight selected text\nRight click for more options";
 }






proc ctext::highlight {win start end {afterTriggered 0}} {
    ctext::getAr $win config configAr

    if {$afterTriggered} {
    set configAr(highlightAfterId) ""
    }

    if {!$configAr(-highlight)} {
    return
    }

    set si $start
    set twin "$win._t"

    #The number of times the loop has run.
    set numTimesLooped 0
    set numUntilUpdate 600

    ctext::getAr $win highlight highlightAr
    ctext::getAr $win highlightSpecialChars highlightSpecialCharsAr
    ctext::getAr $win highlightRegexp highlightRegexpAr
    ctext::getAr $win highlightCharStart highlightCharStartAr

    while 1 {
    set res [$twin search -count length -regexp -- {([^\s\&\(\{\[\}\]\)\.\t\n\r;\"'\|,\<\>\:\/\+\-\^\$\%\*]+)} $si $end]
    if {$res == ""} {
        break
    }

    set wordEnd [$twin index "$res + $length chars"]
    set word [$twin get $res $wordEnd]
    set firstOfWord [string index $word 0]

    if {[info exists highlightAr($word)] == 1} {
        set wordAttributes [set highlightAr($word)]
        foreach {tagClass color} $wordAttributes break

        $twin tag add $tagClass $res $wordEnd
        $twin tag configure $tagClass -foreground $color

    } elseif {[info exists highlightCharStartAr($firstOfWord)] == 1} {
        set wordAttributes [set highlightCharStartAr($firstOfWord)]
        foreach {tagClass color} $wordAttributes break

        $twin tag add $tagClass $res $wordEnd
        $twin tag configure $tagClass -foreground $color
    }
    set si $wordEnd

    incr numTimesLooped
    if {$numTimesLooped >= $numUntilUpdate} {
        ctext::update
        set numTimesLooped 0
    }
    }

    foreach {ichar tagInfo} [array get highlightSpecialCharsAr] {
    set si $start
    foreach {tagClass color} $tagInfo break

    while 1 {
        set res [$twin search -- $ichar $si $end]
        if {"" == $res} {
        break
        }
        set wordEnd [$twin index "$res + 1 chars"]

        $twin tag add $tagClass $res $wordEnd
        $twin tag configure $tagClass -foreground $color
        set si $wordEnd

        incr numTimesLooped
        if {$numTimesLooped >= $numUntilUpdate} {
        ctext::update
        set numTimesLooped 0
        }
    }
    }

    foreach {tagClass tagInfo} [array get highlightRegexpAr] {
    set si $start
    foreach {re color} $tagInfo break
    while 1 {
        set res [$twin search -count length -regexp -- $re $si $end]
        if {"" == $res} {
        break
        }

        set wordEnd [$twin index "$res + $length chars"]
        $twin tag add $tagClass $res $wordEnd
        $twin tag configure $tagClass -foreground $color
        set si $wordEnd

        incr numTimesLooped
        if {$numTimesLooped >= $numUntilUpdate} {
        ctext::update
        set numTimesLooped 0
        }
    }
    }
}


#args is here because -yscrollcommand may call it
proc ctext::linemapUpdate {win args} {
    if {[winfo exists $win.l] != 1} {
    return
    }

    set currentPixel 0
    set lastLine {}
    set lastLineL {};
    set lineList [list]
    set fontMetrics [font metrics [$win.l cget -font]]
    set incrBy [lindex $fontMetrics 5];
    set currentPixel [expr $incrBy / 2];
    
    #set incrBy [expr [lindex $fontMetrics 5]]
    #puts stderr "incrBy = $incrBy currentPixel = $currentPixel winfo height of .t = [winfo height $win.t]"

    while {$currentPixel < [winfo height $win.t]} {
    $win.l insert end "\n";
    set idx [$win._t index @0,$currentPixel]
    set idxL [$win.l index @0,$currentPixel]
     

    if {$idxL != $lastLineL} {
       if {$idx != $lastLine} {
          set line [lindex [split $idx .] 0]
          lappend lineList $line
          set lastLine $idx;
       } else {
          lappend lineList [lindex [split $lastLine .] 0]
       }
       set lastLineL $idxL;
     }
     incr currentPixel $incrBy;
     #puts stderr "currentPixel=$currentPixel last Line=$lastLine last line L = $lastLineL";

    } 
    #puts stderr $lineList

    ctext::getAr $win linemap linemapAr

    $win.l delete 1.0 end
    set lastLine {}
    foreach line $lineList {
    if {$line == $lastLine} {
        $win.l insert end "\n"
    } else {
        if {[info exists linemapAr($line)]} {
        $win.l insert end "$line\n" lmark
        } else {
        $win.l insert end "$line\n"
        }
      }
    set lastLine $line
    }
    if {[llength $lineList] > 0} {
       linemapUpdateOffset $win $lineList
    }
    set endrow [lindex [split [$win._t index end-1c] .] 0]
    $win.l configure -width [string length $endrow]
}


 proc ctext::linemapUpdateOffset {win lineList} {
    # reset view for line numbering widget
    $win.l yview 0.0

    # find the first line that is visible and calculate the
    # corresponding line in the line numbers widget
    set lline 1
    foreach line $lineList {
        if {$line != " "} {
        set tystart [lindex [$win.t bbox $line.0] 1]
        if {$tystart != ""} {
        break
        }
        }
        incr lline
    }


    # return in case the line numbers text widget is not up to
    # date
    if {[catch {
        set lystart [lindex [$win.l bbox $lline.0] 1]
    }]} {
        return
    }

    # return in case the bbox for any of the lines returned an
    # empty value
    if {($tystart == "") || ($lystart == "")} {
        return
    }

    # calculate the offset and then scroll by specified number of
    # pixels
    set offset [expr {$lystart - $tystart}]
    $win.l yview scroll $offset pixels
    }

after 100 {
catch {destroy $splash}
}
wm deiconify .
wm iconbitmap . $installdir/wbin/bm0.ico

bind . <Control-Key-space> {toggleTopFrames}
set showTopFrames 1;
proc toggleTopFrames {} { 
    global showTopFrames;
    set showTopFrames [expr !$showTopFrames];
    if {!$showTopFrames} {
        pack forget .topFrame;
        pack forget .searchFrame;
	
    } else {
        
        pack forget .textFrame
        pack .topFrame -side top -fill x -expand yes;
        pack .searchFrame -side top -fill x -expand yes;
		
        pack .textFrame -expand yes -fill both
		
    }
}

bind .t <Escape> {
   focus [.topFrame.quickCommand component entry]
   [.topFrame.quickCommand component entry] configure -background lightblue;
    set stay_in_quick_command 0;
    }

bind [.topFrame.quickCommand component entry] <Escape> {
   [.topFrame.quickCommand component entry] configure -background white;
   set stay_in_quick_command 0;
  focus .t.t;
}

bind [.topFrame.quickCommand component entry] <Key-d> {
  set cmd "[[.topFrame.quickCommand component entry] get]d";

  if {[regexp {^(-)?\d*dd$} $cmd]} {
     set num [string range $cmd 0 end-2];
     [.topFrame.quickCommand component entry] delete 0 end;
     [.topFrame.quickCommand component entry] insert end "dd $num";
     quickCommandExec;
     break;
  }

}
bind [.topFrame.quickCommand component entry] <Key-y> {
  
  set cmd "[[.topFrame.quickCommand component entry] get]y";
  if {[regexp {^(-)?\d*yy$} $cmd]} {
     set num [string range $cmd 0 end-2];
     [.topFrame.quickCommand component entry] delete 0 end;
     [.topFrame.quickCommand component entry] insert end "yy $num";
     quickCommandExec;
     break
  }

}
bind [.topFrame.quickCommand component entry] <Key-w> {
  set cmd "[[.topFrame.quickCommand component entry] get]w";
  if {[regexp {^\d*((dw)|(yw))$} $cmd]} {
     set num [string range $cmd 0 end-2];
     set cmdx [string range $cmd  end-1 end];
     [.topFrame.quickCommand component entry] delete 0 end;
     [.topFrame.quickCommand component entry] insert end "$cmdx $num";
     quickCommandExec;
     break
  }

}

bind [.topFrame.quickCommand component entry] <Key-p> {
  set cmd "[[.topFrame.quickCommand component entry] get]p";
  if {[regexp {^\d*yp$} $cmd]} {
     set num [string range $cmd 0 end-2];
     [.topFrame.quickCommand component entry] delete 0 end;
     [.topFrame.quickCommand component entry] insert end "yp $num";
     quickCommandExec;
     break
  } else {

  after 1000 {
  set cmd [[.topFrame.quickCommand component entry] get];
  if {$cmd == "p" } {
      set no_hlt_clipboard [catch {clipboard get}];
      if {!$no_hlt_clipboard} {
        quickCommandExec;
      }
     }
    }
  }
}

bind [.topFrame.quickCommand component entry] <ButtonRelease-1> {
    [.topFrame.quickCommand component entry] configure -background #f1aca5
    set stay_in_quick_command 1;
}

bind [.topFrame.quickCommand component entry] <Return> { 
  quickCommandExec;
}

.t tag configure attention -background #5555ce
.t tag configure tempsel -background #ebd7ff
load_plugin "plugins.tcl"
load_plugin "plugin_*.tcl"

proc init_spectral {} {
    set old_cb ""; 
    catch {set old_cb [clipboard get]};
     .t configure -undo 0;
     .t insert 1.0 "from Beautiful Mondays Ltd\n" highlight3;
     .t insert 1.0 "Welcome to Spectral Editor\n" highlight2;
     .t tag add sel 1.0 end;
     copySelection .t cut;
     .t mark set insert 1.0;
     pasteSingleSelection;
     .t fastdelete 1.0 end;
     .t configure -undo 1;
     
     global modified;
     set modified 0;
    .t edit reset;
    .t edit modified 0;
    updateModifiedStatus;
    clipboard clear;
    clipboard append $old_cb;
 }

init_spectral; 


if {[llength $argv]} {
   catch {
       set fname [lindex $argv 0];
       regsub -all {\\} $fname {/} fname;
       set firstchar [string index $fname 0];
       set secondchar [string index $fname 1];
       if {$firstchar == "/" || $secondchar == ":"} {
            
       } else {
           set temp $fname;
           set fname [pwd] ;
           append fname "/" $temp;
       }
       set fname2 "";
       regsub -all {\.hlt$} $fname {} fname2;
       if { ($fname != $fname2) && [file exists $fname2] } {
           openFile .t $fname2;
       } elseif {[regexp {\.hlt$} $fname]} {
           loadFromHltFile .t $fname;
           loadOverview;
       } else {
           openFile .t $fname;
       }
   } msg;
   #puts stderr $msg;
}

.t tag raise sel;

foreach w {.bottomFrame.replace .bottomFrame.with .bottomFrame.init .bottomFrame.incr
.bottomFrame.subst .bottomFrame.expr .bottomFrame.enforceLC .bottomFrame.enforceRC
.searchFrame.search1 .searchFrame.search2 .searchFrame.search3 .searchFrame.search4
.searchFrame.search5 .searchFrame.search6} {
    bind [$w component entry] <Escape> {focus .t.t;}
}
if {!$::spectral_has_real_iwidgets} {
    foreach w {.bottomFrame.with .bottomFrame.init .bottomFrame.incr
    .bottomFrame.subst .bottomFrame.expr .bottomFrame.enforceLC .bottomFrame.enforceRC} {
        bind [$w component entry] <Return> {doReplacement; break}
        bind [$w component entry] <KP_Enter> {doReplacement; break}
    }
}

catch {cd [registry get $regroot pwd] }
lappend auto_path $installdir/wbin/


add_popup_menu_item "Add Hyperlink Target" add_hypertarget;
add_popup_menu_item "Hyperlink to Last Target" hyperref;



after 3000 {check_for_file_modification}


catch {
package require tkdnd
tkdnd::drop_target register . *
bind . <<Drop>> {handle_event %D};
proc handle_event {files} {
    global action_on_dnd;
    if {$action_on_dnd == "edit"} {
      foreach file $files {
         if {[file exists $file]} {
            edit $file;
            break;
         }
    }
  } elseif {$action_on_dnd == "puts"}  {
      foreach fname $files {
         regsub -all {\\} $fname {/}  fname;
         if {[regexp -all {[ \t]} $fname]} {
             clipboard append " \"$fname\" ";
            puts  $fname;
        } else {
             clipboard append " $fname ";
             puts $fname;
        }
      }
  } elseif {$action_on_dnd == "addref"} {
    foreach fname $files {
      insert_text [.t index insert] "\n${fname}";
      add_file_at [.t index insert] $fname;
    }
  } elseif {$action_on_dnd == "add_image"} {
    foreach fname $files {
      insert_image [.t index insert] $fname;
    }
  } elseif {$action_on_dnd == "add_media"} {
    foreach fname $files {
      add_media_file_at [.t index insert] $fname;
    }
  }
}
}


