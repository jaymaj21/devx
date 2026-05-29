@echo off
setlocal EnableExtensions EnableDelayedExpansion

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
set "INPUT_EXT=%~x1"
set "JSON_OUT=%INPUT_DIR%%INPUT_STEM%.json"
set "DOT_OUT=%INPUT_DIR%%INPUT_STEM%.dot"
set "SVG_OUT=%INPUT_DIR%%INPUT_STEM%.svg"

set "SCRIPT_DIR=%~dp0"
set "COMPILER=%SCRIPT_DIR%scripts\tdstr-dsl-compiler.tcl"
set "SPEC_TO_DOT=%SCRIPT_DIR%scripts\spec-to-dot.js"

if not exist "%COMPILER%" (
  echo Error: compiler script not found: %COMPILER% 1>&2
  exit /b 1
)

if not exist "%SPEC_TO_DOT%" (
  echo Error: spec-to-dot script not found: %SPEC_TO_DOT% 1>&2
  exit /b 1
)

shift
set "DOT_ARGS="

:parse_args
if "%~1"=="" goto :run
if /I "%~1"=="--all-states" (
  set "DOT_ARGS=!DOT_ARGS! --all-states"
  shift
  goto :parse_args
)
if /I "%~1"=="--rankdir" (
  if "%~2"=="" (
    echo Error: --rankdir expects a value such as TB or LR 1>&2
    exit /b 1
  )
  set "DOT_ARGS=!DOT_ARGS! --rankdir %~2"
  shift
  shift
  goto :parse_args
)
if /I "%~1"=="--max-states" (
  if "%~2"=="" (
    echo Error: --max-states expects a positive integer 1>&2
    exit /b 1
  )
  set "DOT_ARGS=!DOT_ARGS! --max-states %~2"
  shift
  shift
  goto :parse_args
)

echo Error: unknown option: %~1 1>&2
goto :usage_error

:run
if /I "%INPUT_EXT%"==".json" (
  set "JSON_OUT=%INPUT%"
) else (
  tclsh "%COMPILER%" "%INPUT%" "%JSON_OUT%"
  if errorlevel 1 exit /b %errorlevel%
)

node "%SPEC_TO_DOT%" "%JSON_OUT%" "%DOT_OUT%"!DOT_ARGS!
if errorlevel 1 exit /b %errorlevel%

dot -Tsvg "%DOT_OUT%" -o "%SVG_OUT%"
if errorlevel 1 exit /b %errorlevel%

echo Wrote %JSON_OUT%
echo Wrote %DOT_OUT%
echo Wrote %SVG_OUT%
exit /b 0

:usage
echo Usage: %~n0 input.tdstr^|input.json [--all-states] [--rankdir TB^|LR] [--max-states N] 1>&2
echo Produces input.json, input.dot, and input.svg next to the source file, or reuses an existing .json input directly. 1>&2
echo Useful option: --max-states N to truncate very large universes. 1>&2
exit /b 0

:usage_error
echo Usage: %~n0 input.tdstr^|input.json [--all-states] [--rankdir TB^|LR] [--max-states N] 1>&2
exit /b 1
