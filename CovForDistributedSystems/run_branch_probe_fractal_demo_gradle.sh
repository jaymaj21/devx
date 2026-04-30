#!/usr/bin/env bash
set -euo pipefail

# Gradle-only runner for the fractal demo (no source probes):
# build instrumenter (fat), build fractal demo, build runtime; instrument demo; run instrumented app.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

info() { printf "\n==> %s\n" "$*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

gradle_build() {
  if [[ -x ./gradlew ]]; then ./gradlew clean build -x test; else gradle clean build -x test; fi
}

# 1) Instrumenter
info "Building branch-probe-instrumenter (Gradle)"
pushd "$ROOT_DIR/branch-probe-instrumenter" >/dev/null
rm -rf build 2>/dev/null || true
gradle_build
INSTR_JAR=""
shopt -s nullglob
for f in build/libs/*-jar-with-dependencies.jar build/libs/*all.jar; do INSTR_JAR="$PWD/$f"; break; done
shopt -u nullglob
[[ -n "$INSTR_JAR" ]] || die "Instrumenter fat JAR not found (build/libs/*all.jar)"
echo "Instrumenter: $INSTR_JAR"
popd >/dev/null

# 2) Fractal demo app
info "Building branch-probe-fractal-demoapp (Gradle)"
pushd "$ROOT_DIR/branch-probe-fractal-demoapp" >/dev/null
rm -rf build 2>/dev/null || true
gradle_build
DEMO_IN=""
shopt -s nullglob
for f in build/libs/*.jar; do DEMO_IN="$PWD/$f"; break; done
shopt -u nullglob
[[ -n "$DEMO_IN" ]] || die "Fractal demo input JAR not found (build/libs/*.jar)"
echo "Demo input: $DEMO_IN"
DEMO_DIR="$(dirname "$DEMO_IN")"; DEMO_BASE="$(basename "$DEMO_IN" .jar)"; DEMO_OUT="$DEMO_DIR/${DEMO_BASE}-instrumented.jar"
popd >/dev/null

# 3) Runtime
info "Building mprewriter-runtime (Gradle)"
pushd "$ROOT_DIR/branch-probe-suite/mprewriter-runtime" >/dev/null
rm -rf build 2>/dev/null || true
gradle_build
RUNTIME_JAR=""
shopt -s nullglob
for f in build/libs/*.jar; do RUNTIME_JAR="$PWD/$f"; break; done
shopt -u nullglob
[[ -n "$RUNTIME_JAR" ]] || die "Runtime JAR not found (build/libs/*.jar)"
echo "Runtime: $RUNTIME_JAR"
popd >/dev/null

# 4) Instrument with exclusion
info "Instrumenting fractal demo JAR (Gradle path)"
EXCL="$ROOT_DIR/branch-probe-fractal-demoapp/exclusions.txt"
INCL="$ROOT_DIR/branch-probe-fractal-demoapp/inclusions.txt"
# Fallback to example inclusion file if a concrete one is not present
[[ -f "$INCL" ]] || INCL="$ROOT_DIR/branch-probe-fractal-demoapp/inclusions.example.txt"

EXCL_PROP="$EXCL"; INCL_PROP="$INCL"; PROPS=( )
if [[ "${OS:-}" == "Windows_NT" ]] && command -v cygpath >/dev/null 2>&1; then
  EXCL_PROP="$(cygpath -w "$EXCL")"
  INCL_PROP="$(cygpath -w "$INCL")"
fi

PROPS+=( "-Dbp.excludefile=$EXCL_PROP" )
if [[ -f "$INCL" ]]; then
  PROPS+=( "-Dbp.includefile=$INCL_PROP" )
fi

echo "java ${PROPS[*]} -jar \"$INSTR_JAR\" --sidecar \"$DEMO_IN\" \"$DEMO_OUT\""
java "${PROPS[@]}" -jar "$INSTR_JAR" --sidecar "$DEMO_IN" "$DEMO_OUT"
[[ -f "$DEMO_OUT" ]] || die "Instrumented demo not produced"
echo "Instrumented: $DEMO_OUT"

# 5) Run instrumented fractal demo
info "Running instrumented fractal demo (ensure UDP server on 127.0.0.1:8083)"
CPSEP=':'; [[ "${OS:-}" == "Windows_NT" ]] && CPSEP=';'
CP_DEMO="$DEMO_OUT"; CP_RT="$RUNTIME_JAR"
if [[ "${OS:-}" == "Windows_NT" ]] && command -v cygpath >/dev/null 2>&1; then
  CP_DEMO="$(cygpath -w "$DEMO_OUT")"; CP_RT="$(cygpath -w "$RUNTIME_JAR")"
fi
CP="$CP_DEMO${CPSEP}$CP_RT"
echo "java -cp \"$CP\" com.example.fractaldemo.Main"
exec java -cp "$CP" com.example.fractaldemo.Main
