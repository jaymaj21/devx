@echo off
setlocal EnableExtensions EnableDelayedExpansion

if "%~1"=="" goto :usage
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="--help" goto :usage

set "DSTR_ROOT=%~dp0"
if "%DSTR_ROOT:~-1%"=="\" set "DSTR_ROOT=%DSTR_ROOT:~0,-1%"

set "SPEC_ARG=%~1"
set "START_ID=%~2"
set "APP_ID=%~3"
set "INSTANCE_ID=%~4"

if "%START_ID%"=="" set "START_ID=10001"
if "%APP_ID%"=="" set "APP_ID=410"
if "%INSTANCE_ID%"=="" set "INSTANCE_ID=1"

set "TOOLS_ROOT=%DSTR_ROOT%\development_tools\CovForDistributedSystems"
if not exist "%TOOLS_ROOT%" set "TOOLS_ROOT=%DSTR_ROOT%\..\development_tools\CovForDistributedSystems"

set "INSTR_DIR=%TOOLS_ROOT%\branch-probe-instrumenter"
set "RUNTIME_DIR=%TOOLS_ROOT%\branch-probe-suite\mprewriter-runtime"

set "SPEC_PATH=%SPEC_ARG%"
if not exist "%SPEC_PATH%" set "SPEC_PATH=%DSTR_ROOT%\%SPEC_ARG%"
if not exist "%SPEC_PATH%" (
  echo Spec file not found:
  echo   %SPEC_ARG%
  exit /b 1
)

set "INSTR_JAR=%INSTR_DIR%\target\branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar"
set "RUNTIME_JAR=%RUNTIME_DIR%\target\mprewriter-runtime-1.0.0.jar"
set "DSTR_JAR=%DSTR_ROOT%\target\dstr-0.1.0.jar"
set "INSTRUMENTED_JAR=%DSTR_ROOT%\target\dstr-instrumented.jar"
set "SIDECAR_CSV=%DSTR_ROOT%\target\dstr-instrumented-branch-probes.csv"

echo.
echo === Building branch-probe instrumenter ===
pushd "%INSTR_DIR%" >nul
call mvn -DskipTests clean package
if errorlevel 1 goto :fail
popd >nul

echo.
echo === Building mprewriter runtime ===
pushd "%RUNTIME_DIR%" >nul
call mvn -DskipTests package
if errorlevel 1 goto :fail
popd >nul

echo.
echo === Building dstr and copying runtime dependencies ===
pushd "%DSTR_ROOT%" >nul
call mvn -DskipTests package dependency:copy-dependencies -DincludeScope=runtime
if errorlevel 1 goto :fail
popd >nul

if not exist "%DSTR_JAR%" (
  echo dstr jar not found:
  echo   %DSTR_JAR%
  exit /b 1
)

echo.
echo === Instrumenting dstr jar ===
if exist "%INSTRUMENTED_JAR%" del "%INSTRUMENTED_JAR%"
if exist "%SIDECAR_CSV%" del "%SIDECAR_CSV%"
java -jar "%INSTR_JAR%" --startid=%START_ID% --sidecar "%DSTR_JAR%" "%INSTRUMENTED_JAR%"
if errorlevel 1 goto :fail

echo.
echo === Running instrumented dstr ===
java -cp "%RUNTIME_JAR%;%INSTRUMENTED_JAR%;%DSTR_ROOT%\target\dependency\*" ^
  -Dmprewriter.host=127.0.0.1 ^
  -Dmprewriter.port=8083 ^
  -Dmprewriter.appId=%APP_ID% ^
  -Dmprewriter.instanceId=%INSTANCE_ID% ^
  org.dstr.cli.DstrCli "%SPEC_PATH%"
if errorlevel 1 goto :fail

echo.
echo Instrumented jar:
echo   %INSTRUMENTED_JAR%
echo Probe CSV:
echo   %SIDECAR_CSV%
exit /b 0

:usage
echo Usage:
echo   instrument_and_run.bat ^<spec-file^> [startId] [appId] [instanceId]
echo.
echo Examples:
echo   instrument_and_run.bat test-suite\specs\mutex-2proc.json
echo   instrument_and_run.bat test-suite\specs\bakery-3proc.json 20001 411 2
echo.
echo Notes:
echo   - The instrumented run supplies com.trading.domain.mprewriter from:
echo     %RUNTIME_DIR%\target\mprewriter-runtime-1.0.0.jar
echo   - If Code Analytics is running on UDP 8083, the probes will send hits there.
exit /b 2

:fail
echo.
echo instrument_and_run.bat failed.
exit /b 1
