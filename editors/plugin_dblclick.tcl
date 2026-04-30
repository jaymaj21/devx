add_double_click_handler myHandler "Invoke myHandler on double click";

userproc load_data {} {
 global gblLookup;
 catch {
   unset gblLookup;
 }
 array set gblLookup {performance 1001 if 1002 at 1003}
 
}
load_data;
userproc myHandler {pos} {
  global gblLookup;
  set editor [editor];
  set start [$editor index "$pos wordstart"];
  set end [$editor index "$pos wordend"];
  set cont [$editor get $start $end];
  create_note $end [set gblLookup($cont)];
}