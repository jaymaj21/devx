
userproc sum {args} {
    set result 0.0;
    foreach arg $args {
        foreach item $arg {
            set result [expr $result + $item];
        }
    }
    return $result;
}

userproc prod {args} {
    set result 1.0;
    foreach arg $args {
        foreach item $arg {
            set result [expr $result * $item];
        }
    }
    return $result;
}


userproc max {args} {
    set result "";
    foreach arg $args {
        foreach item $arg {
            if {$result == ""} {
                set result $item;   
            } else {
                set result [expr max($result, $item)];
            }
        }
    }
    return $result;
}


userproc min {args} {
    set result "";
    foreach arg $args {
        foreach item $arg {
            if {$result == ""} {
                set result $item;   
            } else {
                set result [expr min($result, $item)];
            }
        }
    }
    return $result;
}
