set octets "";
set numoctets 0;
array set fspec {};
userproc item {fspecid name desc sz mand pres valdoc args} {
    global octets;
    global numoctets;
    global fspec;
    set bits "";
    set fspec($fspecid) $pres;
    if {$pres == "P"} {
       foreach arg $args {
           append bits $arg;  
       }
       append octets "\n    // $name - $desc - $sz octets - $mand : $valdoc\n    ";
       set added [bin2chex $bits];
       append octets $added;
       incr numoctets [llength $added]
   }
}
userproc cadd {str} {clipboard append $str}
userproc begin_items {} {
    global octets;
    global numoctets;
    global fspec;
    set octets "";
    set numoctets 0;
    for {set i 1} {$i <= 32} {incr i} {
        set fspec($i) "A";
    }
}
userproc enc {let} {
    array set encoding { A 1 B 2 C 3 D 4 E 5 F 6
    G 7 H 8 I 9 J 10 K 11 L 12 M 13 N 14 O 15
    P 16 Q 17 R 18 S 19 T 20 U 21 V 22 W 23 X
    24 Y 25 Z 26 { } 32 0 48 1 49 2 50 3 51 4
    52 5 53 6 54 7 55 8 56 9 57 }    
   if [info exists encoding($let)] {
       return [int2bin 6 $encoding($let)];
   } else {
       return [int2bin 6 32];
   }  
}
userproc encode_time {timestr} {
    set time [split $timestr ":"];
    set factors {3600 60 1 1e-3 1e-6 1e-9};
    set partidx 0;
    set timeinseconds 0.0;
    foreach timepart  $time {
        regsub -all {^0*}  $timepart {} timepart;
        if {$timepart == ""} { set timepart 0.0;}
        set factor [lindex $factors $partidx];
        set timeinseconds [expr $timeinseconds + $factor*$timepart];
        incr partidx;
    }
    set encoded_value [expr int(128*$timeinseconds)];
    return [int2bin 24 $encoded_value];
}
userproc end_items {} {
    global octets;
    global numoctets;
    global fspec;
    set size [expr 7 + $numoctets];
    set result "\n    // Indicator\n    0x14, ";
    append result "\n    // size=$size\n    ";
    set sizeHex [bin2chex [int2bin 16 $size]];
    append result $sizeHex;
    
    set fspecbits "";
    for {set i 1} {$i <= 32} {incr i} {
        if {$i == 8 || $i == 16 || $i == 24} {
            append fspecbits 1;
        } elseif {$fspec($i) == "P"} {
            append fspecbits 1;
        } else {
            append fspecbits 0;
        }
    }
    append result "\n    // FSPEC $fspecbits\n    ";
    append result [bin2chex $fspecbits]
    append result $octets; 
    cc;
    cadd $result;
    puts $result;
}

