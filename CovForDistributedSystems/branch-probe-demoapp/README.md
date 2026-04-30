# Branch-Probe Demo App

A tiny Java console app with lots of branches (if/else, switch, recursion, try/catch/finally, and a lambda) to exercise your instrumenter.

## Build
```bash
cd branch-probe-demoapp
mvn -q -DskipTests clean package
```
Output: `target/branch-probe-demoapp-1.0.0.jar`

## Run (uninstrumented)
```bash
java -jar target/branch-probe-demoapp-1.0.0.jar
```

## Instrument with your branch-probe-instrumenter
```bash
# assuming sibling project: ../branch-probe-instrumenter
java -jar ../branch-probe-instrumenter/target/branch-probe-instrumenter-1.2.0-jar-with-dependencies.jar   target/branch-probe-demoapp-1.0.0.jar   target/branch-probe-demoapp-1.0.0-instrumented.jar
```

## Run (instrumented)
```bash
java -jar target/branch-probe-demoapp-1.0.0-instrumented.jar
```

You’ll see the app’s normal output plus many lines like:
```
PROBE 37 com.example.demo.Service#fizzBuzz IF_NOT_TAKEN
PROBE 38 com.example.demo.Service#fizzBuzz BRANCH_TAKEN
...
```
