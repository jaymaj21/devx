@echo off
setlocal EnableExtensions

if "%~1"=="" goto :usage
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="--help" goto :usage

set "INPUT=%~1"
if not exist "%INPUT%" (
  echo Error: input file not found: %INPUT% 1>&2
  exit /b 1
)

set "INPUT_DIR=%~dp1"
set "INPUT_STEM=%~n1"
set "JSON_OUT=%INPUT_DIR%%INPUT_STEM%.json"
if not "%~2"=="" set "JSON_OUT=%~2"

set "SCRIPT_DIR=%~dp0"
set "CDSTR_PROJECT=%SCRIPT_DIR%clj-dstr"

if not exist "%CDSTR_PROJECT%\pom.xml" (
  echo Error: clj-dstr Maven project not found: %CDSTR_PROJECT% 1>&2
  exit /b 1
)

call mvn -q -f "%CDSTR_PROJECT%\pom.xml" compile exec:java "-Dexec.args=%~f1 %JSON_OUT%"
exit /b %errorlevel%

:usage
echo Usage: %~n0 input.cdstr [output.json] 1>&2
echo Compiles a .cdstr model to normalized JSON. If output is omitted, writes adjacent input.json. 1>&2
exit /b 0
