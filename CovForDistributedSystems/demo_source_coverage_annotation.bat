@echo off
setlocal

tclsh "%~dp0demo_source_coverage_annotation.tcl" %*
exit /b %errorlevel%
