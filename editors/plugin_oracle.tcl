userproc ora_set_maxrows {maxrows} {
    userproc ora_maxrows {} "return $maxrows";
}
ora_set_maxrows 100;
userproc ora_setenv {env} {
    if {$env == "mydb"} {
        userproc ora_connstring {} {return "DSN=MYDB;UID=INVENTORY1;PWD=INVENTORY1";} } else {
        error "Invalid environment"
    }
}
ora_setenv "mydb";

userproc print_dict {dict {pattern *}} {
    set longest 0;
    set keys [dict keys $dict $pattern];
    foreach key $keys {
        set l [string length $key];
        if {$l > $longest} {set longest $l}
    }
    foreach key $keys {
        insert_text end [format "\n%-${longest}s = %s" $key [dict get $dict  $key]]
    }
}

userproc sql {query} {
    package require tdbc;
    package require tdbc::odbc;
    set cmd "db[guid]";
    insert_text end "\nQUERY: $query\n";
    insert_text end "--------------------------" 3;
    tdbc::odbc::connection create $cmd [ora_connstring];
    catch {
        set stmt [$cmd prepare $query];
        set resultset [$stmt execute];
        set cols [$resultset columns];
        insert_text end "\nRESULT COLUMNS=$cols\nTSV:";
        set tsv_insert_point [.t index end];
        insert_text end "\n";
        set table "";
        set sep "\t";
        foreach col $cols {
           append table {"} $col {"} $sep;
        }

        set rownum 1;
        set hasrows 0;
        while {[$resultset nextdict val]} {
            if {$rownum > [ora_maxrows]} break;
            append table "\n";
            foreach col $cols {
               if {[dict exists $val $col]} {
                     set aval [dict get $val $col];
                     regsub -all {[\n]} $aval {<LF>} aval 
                     regsub -all {[\r]} $aval {<CR>} aval 
                     regsub -all {[\t]} $aval {<TAB>} aval
                     append table $aval $sep;

               } else {
                   append table $sep;

               }
            }
            insert_text end "\n"
            insert_text end "row# $rownum --------------" 2;
            print_dict $val;
            incr rownum;
            set hasrows 1;
        }

        append table "\n";
        if {$hasrows} {
           create_note $tsv_insert_point $table;
       }
    
    } msg;
    puts $msg;
    
    $cmd close;
}



