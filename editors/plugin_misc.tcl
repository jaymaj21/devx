userproc diff2html {file1 file2 html} {
  set cmd "";
  append cmd "C:/Program Files/Beyond Compare 4/BCompare.exe" /silent @d:/jmtools/bcompare_report.txt $file1 $file2 $html;
  puts $cmd;
  catch {
    exec "C:/Program Files/Beyond Compare 4/BCompare.exe" /silent @d:/jmtools/bcompare_report.txt $file1 $file2 $html
  } msg;
  puts $msg;
}