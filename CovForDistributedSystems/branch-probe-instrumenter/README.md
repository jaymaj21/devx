# Branch-Probe Instrumenter — v1.3.0 (METHOD_ENTRY with line numbers)

This release adds **delayed** METHOD_ENTRY probes so you get a real source line:
- For normal methods: entry emits at the **first source line**.
- For constructors: entry emits at the **first source line after `super(...)`** executes.
- If a method/class has **no line info**, we **fallback** to emitting METHOD_ENTRY with `?` just before return.

All previous branch probes (IF_NOT_TAKEN, BRANCH_TAKEN, switch arms) remain, and the
CSV index is still embedded at `META-INF/branch-probes.csv`.

## Build
```bash
mvn -q -DskipTests clean package
```
Produces:
`target/branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar`

## Use
```bash
java -jar target/branch-probe-instrumenter-1.3.0-jar-with-dependencies.jar input.jar output-instrumented.jar
```

## Output examples
```
PROBE 10 com.example.demo.Service#fizzBuzz (Service.java:7) METHOD_ENTRY
PROBE 11 com.example.demo.Service#fizzBuzz (Service.java:12) IF_NOT_TAKEN
PROBE 12 com.example.demo.Service#fizzBuzz (Service.java:13) BRANCH_TAKEN
```
For constructors:
```
PROBE 20 com.example.demo.Widget#<init> (Widget.java:15) METHOD_ENTRY
```
(ensured to be after `super(...)`)

## Notes
- Needs classes compiled with line numbers (javac default `-g:lines`). Shrinkers can strip lines.
- For extreme accuracy (stack-neutral injection points, exotic prologues), a 2-pass MethodNode+Analyzer
  strategy is possible; this build keeps a streaming design for simplicity and speed.
