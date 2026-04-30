package require Tk
 package require twapi


set dir [lindex $argv 0];
cd $dir;
wm iconbitmap . -default $dir/bm0.ico
wm  overrideredirect  .  1
wm attributes . -topmost 1;
wm  geometry  .  "+100+100"


set fname [lindex $argv 1];
set cmd "|./sox.exe -t waveaudio -d $fname";
set fp [open $cmd "r"];
set apid [pid $fp];
button .b -text "Stop Recording" -command {
    catch {
    twapi::end_process $apid -force;
    }
    exit;

} -background red

pack .b -side top -fill x;
update;

update;
