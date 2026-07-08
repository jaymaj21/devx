@echo off
setlocal

set HOST=127.0.0.1
set PORT=8083
set TIMEOUT_MS=3000
set SEND_EXIT=0

if not "%~1"=="" set HOST=%~1
if not "%~2"=="" set PORT=%~2

echo Compiling capinger.java
javac capinger.java
if errorlevel 1 exit /b 1

echo.
echo Sending capinger sequence to %HOST%:%PORT%
echo.

java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD status
java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD help

java capinger --host %HOST% --port %PORT% CTX smoke-suite
java capinger --host %HOST% --port %PORT% LOG 1 1001 11 0 smoke-suite started
java capinger --host %HOST% --port %PORT% HIT 1 1001 11 0 1000 3
java capinger --host %HOST% --port %PORT% HIT 1 1001 11 1 1001 5
java capinger --host %HOST% --port %PORT% HIT 1 1001 11 2 1002 2
java capinger --host %HOST% --port %PORT% LOG 1 1001 11 2 after first branch group

java capinger --host %HOST% --port %PORT% CTX smoke-suite database
java capinger --host %HOST% --port %PORT% HIT 1 1001 12 0 2000 10
java capinger --host %HOST% --port %PORT% HIT 1 1001 12 1 2001 4
java capinger --host %HOST% --port %PORT% HIT 1 1001 12 2 2002 1
java capinger --host %HOST% --port %PORT% LOG 1 1001 12 2 database branch group complete
java capinger --host %HOST% --port %PORT% CTX_WITHDRAW smoke-suite database

java capinger --host %HOST% --port %PORT% CTX smoke-suite service
java capinger --host %HOST% --port %PORT% HIT 1 1001 13 0 3000 6
java capinger --host %HOST% --port %PORT% HIT 1 1001 13 1 3001 6
java capinger --host %HOST% --port %PORT% HIT 1 1001 13 2 3002 6
java capinger --host %HOST% --port %PORT% LOG 1 1001 13 2 service branch group complete
java capinger --host %HOST% --port %PORT% CTX_WITHDRAW smoke-suite service

java capinger --host %HOST% --port %PORT% CTX smoke-suite error-path
java capinger --host %HOST% --port %PORT% HIT 1 1001 14 0 4000 1
java capinger --host %HOST% --port %PORT% HIT 1 1001 14 1 4001 1
java capinger --host %HOST% --port %PORT% LOG 1 1001 14 1 simulated error path reached
java capinger --host %HOST% --port %PORT% CTX_WITHDRAW smoke-suite error-path

java capinger --host %HOST% --port %PORT% HIT 2 2002 21 0 5000 8
java capinger --host %HOST% --port %PORT% HIT 2 2002 21 1 5001 3
java capinger --host %HOST% --port %PORT% LOG 2 2002 21 1 second app instance emitted hits

java capinger --host %HOST% --port %PORT% CTX_WITHDRAW smoke-suite

java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD status
java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD coverage-report 1 1001 capinger-sequence-app1.cov
java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD coverage-report 2 2002 capinger-sequence-app2.cov
java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD coverage-hits capinger-sequence-hits.csv
java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD flush-trace
java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD trace-persist
java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD status

if "%SEND_EXIT%"=="1" (
    java capinger --host %HOST% --port %PORT% --timeout %TIMEOUT_MS% CMD exit
) else (
    echo.
    echo Skipping CMD exit. Set SEND_EXIT=1 in this file to stop the server at the end.
)

endlocal
