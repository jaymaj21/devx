userproc git_stage {} {
 set pwd [pwd];
 cd [get_current_folder];
 catch {
  set fname [get_current_filename];
  regsub -all {^.*/([^/]*)} $fname {\1} fname;
  exec git stage $fname --force;
 } msg;
 puts $msg;
 cd $pwd;
};
catch {
set gitmenu [addmenu [getmenu] git "Git"];
addmenucommand $gitmenu "Git Stage Current File" git_stage;
 } msg;
 puts $msg;
##########

userproc git_base_folders {} {
   return {
     Git/testrepo
   }
}

# Find the root repo folder from a list of base folders
userproc find_git_root {file base_folders} {
    foreach base $base_folders {
        if {[string match "$base/*" $file] || $file eq $base} {
            return $base
        }
    }
    return ""
}

# Stage all files listed in the grep output
userproc git_stage_listed {} {
    set base_folders [git_base_folders]
    set files_seen {}
    foreach {filename linenum} [get_grep_lines] {
	    regsub -all {\./} $filename {} filename;
        if {[lsearch -exact $files_seen $filename] >= 0} continue;
        lappend files_seen $filename

        set repo_root [find_git_root $filename $base_folders]
        if {$repo_root eq ""} continue

        set abs_file [file join [pwd] $filename]
        set repo_dir [file join [pwd] $repo_root]
        if {![file exists $abs_file]} continue

        puts "Staging $abs_file in $repo_root..."
        set olddir [pwd]
        cd $repo_dir
        catch {
		  set result [exec git add $abs_file];
		  puts $result;
		} err
        cd $olddir
    }
}

# Commit once per repo found in the grep listing
userproc git_commit_on_listed_repos {msg} {
    set base_folders [git_base_folders]
    set repos_committed {}

    foreach {filename linenum} [get_grep_lines] {
	    regsub -all {\./} $filename {} filename;
        set repo_root [find_git_root $filename $base_folders]
        if {$repo_root eq ""} continue
        if {[lsearch -exact $repos_committed $repo_root] >= 0} continue

        puts "Running git commit in $repo_root..."
        lappend repos_committed $repo_root

        set olddir [pwd]
        cd $repo_root
        if [catch {
            set result [exec git commit -a -m $msg];
			puts $result;
        } err] {
		   addToStatus $err;
		}
        cd $olddir
    }
}


# Commit once per repo found in the grep listing
userproc git_cmd_on_listed_repos {args} {
    set base_folders [git_base_folders]
    set repos_committed {}

    foreach {filename linenum} [get_grep_lines] {
	    regsub -all {\./} $filename {} filename;
        set repo_root [find_git_root $filename $base_folders]
        if {$repo_root eq ""} continue
        if {[lsearch -exact $repos_committed $repo_root] >= 0} continue

        puts "Running command $args in $repo_root ..."
        lappend repos_committed $repo_root

        set olddir [pwd]
        cd $repo_root
        if [catch {
            set result [exec {*}$args]; 
			puts $result;
			
        } err ] {
		   addToStatus $err;
		}		
        cd $olddir
    }
}

userproc git_cmd_on_all_repos {args} {
  set repos [git_base_folders];
  foreach repo $repos {
     set olddir [pwd]
     cd $repo
	 if [catch {
	        puts "Running command $args in $repo ..."
            set result [exec {*}$args];
            puts $result;			
        } err ] {
		   addToStatus $err;
	}
    cd $olddir
  }
}

# Push once per repo found in the grep listing
userproc git_push_on_listed_repos {} {
    set base_folders [git_base_folders]
    set repos_pushed {}

    foreach {filename linenum} [get_grep_lines] {
	    regsub -all {\./} $filename {} filename;
        set repo_root [find_git_root $filename $base_folders]
        if {$repo_root eq ""} continue
        if {[lsearch -exact $repos_pushed $repo_root] >= 0} continue

        puts "Running git push in $repo_root..."
        lappend repos_pushed $repo_root

        set olddir [pwd]
        cd $repo_root
        catch {
            set result [exec git push];
			puts $result;
        } err
        cd $olddir
    }
}
 
 userproc handle_ui_git_command_on_all_repos  {git_command} {
	git_cmd_on_all_repos {*}$git_command;
 }

userproc ui_git_command_on_all_repos {} {
   processMultipleStringInputs "Git command on all repos" \{git_command\} handle_ui_git_command_on_all_repos;
}

catch {
addmenucommand $gitmenu "Run Git command on all repos" ui_git_command_on_all_repos;
 } msg;
 puts $msg;
 
 
#########
 
userproc handle_ui_git_command_on_listed_repos  {git_command} {
	git_cmd_on_listed_repos {*}$git_command;
 }

userproc ui_git_command_on_listed_repos {} {
   processMultipleStringInputs "Git command on listed repos" \{git_command\} handle_ui_git_command_on_listed_repos;
}

catch {
addmenucommand $gitmenu "Run Git command on listed repos" ui_git_command_on_listed_repos;
 } msg;
 puts $msg; 
 
 
 
#########
 
userproc handle_ui_git_commit_on_listed_repos  {commit_message} {
	git_commit_on_listed_repos $commit_message;
 }

userproc ui_git_commit_on_listed_repos {} {
   processMultipleStringInputs "Git commit on listed repos" \{commit_message\} handle_ui_git_commit_on_listed_repos;
}

catch {
addmenucommand $gitmenu "Run Git commit on listed repos" ui_git_commit_on_listed_repos;
 } msg;
 puts $msg; 
 
 ###########
 $gitmenu add command -label "Stage Listed Files" \
    -command {
        if {[tk_messageBox -message "Stage listed files?" -type yesno] eq "yes"} {
            git_stage_listed
        }
    }

$gitmenu add command -label "Push Repos from Listing" \
    -command {
        if {[tk_messageBox -message "Push repos from listing?" -type yesno] eq "yes"} {
            git_push_on_listed_repos
        }
    }

