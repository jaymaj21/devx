@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SAMPLE_DIR=%SCRIPT_DIR%hltdiff_demo_3way"

wish "%SCRIPT_DIR%hltdiff.tcl" ^
  -a "%SAMPLE_DIR%\ancestor.hlt" ^
  "%SAMPLE_DIR%\yours.hlt" ^
  "%SAMPLE_DIR%\theirs.hlt" ^
  -o "%SAMPLE_DIR%\merged_output.hlt"

endlocal
