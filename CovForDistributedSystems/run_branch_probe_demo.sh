#!/usr/bin/env bash
set -euo pipefail

# End-to-end: build instrumenter, build demo, build runtime, instrument demo, run instrumented demo.
# Requires: Java 17+, Maven or Gradle. Assumes UDP server on 127.0.0.1:8083.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

info() { printf "\n==> %s\n" "$*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

build_maven() {
  mvn -DskipTests clean package
}

build_gradle() {
  if [[ -x ./gradlew ]]; then
    ./gradlew clean build -x test
  else
    gradle clean build -x test
  fi
}

# 1) Build instrumenter (fat jar)
info "Building branch-probe-instrumenter (fat JAR)"
pushd "$ROOT_DIR/branch-probe-instrumenter" >/dev/null
rm -rf target build 2>/dev/null || true
if have_cmd mvn; then build_maven; else build_gradle; fi
INSTR_JAR=""
shopt -s nullglob
for f in target/*-jar-with-dependencies.jar build/libs/*all.jar; do INSTR_JAR="$PWD/$f"; break; done
shopt -u nullglob
[[ -n "$INSTR_JAR" ]] || die "Instrumenter fat JAR not found"
echo "Instrumenter: $INSTR_JAR"
popd >/dev/null

# 2) Build demo app
info "Building branch-probe-demoapp (input JAR)"
pushd "$ROOT_DIR/branch-probe-demoapp" >/dev/null
rm -rf target build 2>/dev/null || true
if have_cmd mvn; then build_maven; else build_gradle; fi
DEMO_IN=""
shopt -s nullglob
for f in target/*.jar build/libs/*.jar; do DEMO_IN="$PWD/$f"; break; done
shopt -u nullglob
[[ -n "$DEMO_IN" ]] || die "Demo input JAR not found"
echo "Demo input: $DEMO_IN"
# Compute output path next to input
DEMO_DIR="$(dirname "$DEMO_IN")"
DEMO_BASE="$(basename "$DEMO_IN" .jar)"
DEMO_OUT="$DEMO_DIR/${DEMO_BASE}-instrumented.jar"
popd >/dev/null

# 3) Build runtime (mprewriter-runtime)
info "Building mprewriter-runtime (runtime JAR)"
pushd "$ROOT_DIR/branch-probe-suite/mprewriter-runtime" >/dev/null
rm -rf target 2>/dev/null || true
build_maven
RUNTIME_JAR=""
shopt -s nullglob
for f in target/mprewriter-runtime-*.jar; do RUNTIME_JAR="$PWD/$f"; break; done
shopt -u nullglob
[[ -n "$RUNTIME_JAR" ]] || die "Runtime JAR not found"
echo "Runtime: $RUNTIME_JAR"
popd >/dev/null

# 4) Instrument demo
info "Instrumenting demo JAR"
EXCL="$ROOT_DIR/branch-probe-demoapp/exclusions.txt"
INCL="$ROOT_DIR/branch-probe-demoapp/inclusions.txt"; [[ -f "$INCL" ]] || INCL="$ROOT_DIR/branch-probe-demoapp/inclusions.example.txt"
EXCL_PROP="$EXCL"; INCL_PROP="$INCL"
if [[ "${OS:-}" == "Windows_NT" ]] && command -v cygpath >/dev/null 2>&1; then
  EXCL_PROP="$(cygpath -w "$EXCL")"
  INCL_PROP="$(cygpath -w "$INCL")"
fi
echo "java -Dbp.excludefile=\"$EXCL_PROP\" -Dbp.includefile=\"$INCL_PROP\" -jar \"$INSTR_JAR\" --sidecar \"$DEMO_IN\" \"$DEMO_OUT\""
java -Dbp.excludefile="$EXCL_PROP" -Dbp.includefile="$INCL_PROP" -jar "$INSTR_JAR" --sidecar "$DEMO_IN" "$DEMO_OUT"
[[ -f "$DEMO_OUT" ]] || die "Instrumented demo not produced: $DEMO_OUT"
echo "Instrumented: $DEMO_OUT"

# 5) Run instrumented demo with runtime on classpath
info "Running instrumented demo (ensure UDP server on 127.0.0.1:8083)"
CPSEP=':'
if [[ "${OS:-}" == "Windows_NT" ]]; then CPSEP=';'; fi
CP_DEMO="$DEMO_OUT"
CP_RT="$RUNTIME_JAR"
if [[ "${OS:-}" == "Windows_NT" ]] && command -v cygpath >/dev/null 2>&1; then
  CP_DEMO="$(cygpath -w "$DEMO_OUT")"
  CP_RT="$(cygpath -w "$RUNTIME_JAR")"
fi
CP="$CP_DEMO${CPSEP}$CP_RT"
echo "java -cp \"$CP\" com.example.demo.Main"
exec java -cp "$CP" com.example.demo.Main
