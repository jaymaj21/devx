REM cd ..\branch-probe-suite
REM mvn package
REM cd ..\branch-probe-demoapp
java -jar ..\branch-probe-suite\branch-probe-instrumenter\target\branch-probe-instrumenter-1.0.0-shaded.jar --startid=5001 --sidecar %1.jar %1-instrumented.jar
java -cp "..\branch-probe-suite\mprewriter-runtime\target\mprewriter-runtime-1.0.0.jar;%1-instrumented.jar" com.example.demo.Main


