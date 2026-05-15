@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem End-to-end Windows demo:
rem 1) build code-analytics
rem 2) build top-level branch-probe-instrumenter
rem 3) build mprewriter-runtime
rem 4) build branch-probe-demoapp
rem 5) instrument the demo jar
rem 6) launch code-analytics
rem 7) launch the instrumented demo app
rem 8) ask code-analytics to print :hits and exit

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "SERVER_DIR=%ROOT%\code-analytics"
set "INSTR_DIR=%ROOT%\branch-probe-instrumenter"
set "RUNTIME_DIR=%ROOT%\branch-probe-suite\mprewriter-runtime"
set "DEMO_DIR=%ROOT%\branch-probe-demoapp"

set "SERVER_JAR=%SERVER_DIR%\target\clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar"
set "INSTR_JAR=%INSTR_DIR%\target\branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar"
set "RUNTIME_JAR=%RUNTIME_DIR%\target\mprewriter-runtime-1.0.0.jar"
set "DEMO_JAR=%DEMO_DIR%\target\branch-probe-demoapp-1.0.0.jar"
set "DEMO_OUT=%DEMO_DIR%\target\branch-probe-demoapp-1.0.0-instrumented.jar"
set "INCL_FILE=%DEMO_DIR%\inclusions.txt"
set "EXCL_FILE=%DEMO_DIR%\exclusions.txt"
set "SERVER_OUT=%ROOT%\code-analytics-demo-output.txt"

if not exist "%INCL_FILE%" set "INCL_FILE=%DEMO_DIR%\inclusions.example.txt"

if exist "%SERVER_JAR%" (
  echo.
  echo === Reusing existing code-analytics build ===
) else (
  echo.
  echo === Building code-analytics ===
  pushd "%SERVER_DIR%" >nul
  call mvn -DskipTests package
  if errorlevel 1 goto :fail
  popd >nul
)

if exist "%INSTR_JAR%" (
  echo.
  echo === Reusing existing top-level instrumenter build ===
) else (
  echo.
  echo === Building top-level instrumenter ===
  pushd "%INSTR_DIR%" >nul
  call mvn -DskipTests clean package
  if errorlevel 1 goto :fail
  popd >nul
)

if exist "%RUNTIME_JAR%" (
  echo.
  echo === Reusing existing mprewriter-runtime build ===
) else (
  echo.
  echo === Building mprewriter-runtime ===
  pushd "%RUNTIME_DIR%" >nul
  call mvn -DskipTests package
  if errorlevel 1 goto :fail
  popd >nul
)

if exist "%DEMO_JAR%" (
  echo.
  echo === Reusing existing branch-probe-demoapp build ===
) else (
  echo.
  echo === Building branch-probe-demoapp ===
  pushd "%DEMO_DIR%" >nul
  call mvn -DskipTests clean package
  if errorlevel 1 goto :fail
  popd >nul
)

echo.
echo === Instrumenting demo jar ===
if exist "%DEMO_OUT%" del "%DEMO_OUT%"
java -Dbp.excludefile="%EXCL_FILE%" -Dbp.includefile="%INCL_FILE%" -jar "%INSTR_JAR%" --startid=5001 --sidecar "%DEMO_JAR%" "%DEMO_OUT%"
if errorlevel 1 goto :fail

echo.
echo === Starting code-analytics ===
if exist "%SERVER_OUT%" del "%SERVER_OUT%"
start "code-analytics-demo" /b cmd /v:on /c "(timeout /t 8 /nobreak >nul & echo :hits & echo :exit) | java -cp ""%SERVER_JAR%"" com.codeanalytics.ClojureShell > ""%SERVER_OUT%"" 2>&1"
if errorlevel 1 goto :fail

echo Waiting for code-analytics to start...
timeout /t 2 /nobreak >nul

echo.
echo === Running instrumented demo ===
java -cp "%RUNTIME_JAR%;%DEMO_OUT%" -Dmprewriter.host=127.0.0.1 -Dmprewriter.port=8083 -Dmprewriter.appId=12345 -Dmprewriter.instanceId=1 com.example.demo.Main
if errorlevel 1 goto :fail

echo.
echo Waiting for code-analytics to print hits and exit...
:wait_for_server
timeout /t 1 /nobreak >nul
findstr /c:"Bye!" "%SERVER_OUT%" >nul 2>nul
if errorlevel 1 goto :wait_for_server

echo.
echo === code-analytics output ===
type "%SERVER_OUT%"

echo.
echo Demo complete.
echo Output file: "%SERVER_OUT%"
goto :eof

:fail
echo.
echo Script failed.
exit /b 1
