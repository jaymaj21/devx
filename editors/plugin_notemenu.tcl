add_note_context_menu_item "Duplicate note" copy_note

userproc copy_note {file_path index buttonPath} {
  set fp [open $file_path r];
  set content [read $fp]; 
  close $fp;
  create_note $index $content;
}  