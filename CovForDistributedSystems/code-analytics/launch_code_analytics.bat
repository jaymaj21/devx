@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "SERVER_JAR=%ROOT%\target\clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar"
set "MAIN_CLASS=com.codeanalytics.ClojureShell"

set "MODE=run"
if /I "%~1"=="--build-only" set "MODE=build-only"
if /I "%~1"=="--rebuild" set "MODE=rebuild"
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="--help" goto :usage

if "%MODE%"=="rebuild" goto :build
if exist "%SERVER_JAR%" goto :after_build

:build
echo.
echo === Building code-analytics ===
pushd "%ROOT%" >nul
call mvn -DskipTests package
if errorlevel 1 goto :fail
popd >nul

:after_build
if not exist "%SERVER_JAR%" (
  echo Server jar not found:
  echo   %SERVER_JAR%
  exit /b 1
)

if "%MODE%"=="build-only" (
  echo Build complete:
  echo   %SERVER_JAR%
  exit /b 0
)

echo.
echo === Launching code-analytics ===
echo Working directory:
echo   %ROOT%
echo Trace files will be written here as plant-trace-*.txt
echo.

pushd "%ROOT%" >nul
java -cp "%SERVER_JAR%" %MAIN_CLASS%
set "EXITCODE=%ERRORLEVEL%"
popd >nul
exit /b %EXITCODE%

:usage
echo Usage:
echo   launch_code_analytics.bat
echo   launch_code_analytics.bat --rebuild
echo   launch_code_analytics.bat --build-only
echo.
echo Options:
echo   --rebuild     Force a fresh Maven build before launch
echo   --build-only  Build the jar and exit without launching
exit /b 2

:fail
echo.
echo launch_code_analytics.bat failed.
exit /b 1
