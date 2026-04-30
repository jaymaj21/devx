userproc import_using_tika {} {
    set types {
        {{Docx File} {.docx}}
        {{PDF File} {.pdf}}
        {{Doc File} {.doc}}
     }
    set fname [tk_getOpenFile -filetypes $types];
    if {$fname != ""} {
          set tmpname [tempfilename txt];
          set failed [catch "exec java -jar [installdir]/tika-app-1.12.jar --text \"$fname\"  >  $tmpname" msg];

          if {$failed} {
              tk_messageBox -message "Import failed: $msg";
          } else {
              set fp [open $tmpname r];
              fconfigure $fp -encoding utf-8;
              set cont [read $fp];
              close $fp;
              clipboard clear;
              clipboard append $cont;
              tk_messageBox -message "The imported text is in clipboard";
              file delete -force $tmpname;
          }
    }

}

userproc import_utf16 {} {
    set fname [tk_getOpenFile];
    if {$fname != ""} {
          set tmpname [tempfilename txt];

          set failed [catch "exec [installdir]/iconv -f UTF-16 -t UTF-8 $fname > $tmpname" msg];

          if {$failed} {
              tk_messageBox -message "Import failed: $msg";
          } else {
              set fp [open $tmpname r];
              fconfigure $fp -encoding utf-8;
              set cont [read $fp];
              close $fp;
              clipboard clear;
              clipboard append $cont;
              tk_messageBox -message "The imported text is in clipboard";
              file delete -force $tmpname;
          }
    }

}

set importmenu [addmenu [getmenu] import "Import"];
addmenucommand $importmenu "PDF or Doc using Tika" import_using_tika;
addmenucommand $importmenu "UTF16 using iconv" import_utf16;

