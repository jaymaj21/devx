#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: cdstr-to-svg.sh input.cdstr|input.json [spec-to-dot options]
Produces input.json, input.dot, and input.svg next to the source file, or reuses an existing .json input directly.
Extra arguments are passed directly to spec-to-dot.js.
Useful option: --max-states N to truncate very large universes.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

input=$1
shift

if [[ ! -f "$input" ]]; then
  echo "Error: input file not found: $input" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cdstr_project="$script_dir/clj-dstr"
spec_to_dot="$script_dir/scripts/spec-to-dot.js"

if [[ ! -f "$cdstr_project/pom.xml" ]]; then
  echo "Error: clj-dstr Maven project not found: $cdstr_project" >&2
  exit 1
fi

if [[ ! -f "$spec_to_dot" ]]; then
  echo "Error: spec-to-dot script not found: $spec_to_dot" >&2
  exit 1
fi

input_dir="$(cd "$(dirname "$input")" && pwd)"
input_abs="$input_dir/$(basename "$input")"
input_stem="$(basename "${input%.*}")"
json_out="$input_dir/$input_stem.json"
dot_out="$input_dir/$input_stem.dot"
svg_out="$input_dir/$input_stem.svg"

if [[ "${input##*.}" != "json" ]]; then
  mvn -q -f "$cdstr_project/pom.xml" compile exec:java "-Dexec.args=$input_abs $json_out"
else
  json_out="$input_abs"
fi

node "$spec_to_dot" "$json_out" "$dot_out" "$@"
dot -Tsvg "$dot_out" -o "$svg_out"

echo "Wrote $json_out"
echo "Wrote $dot_out"
echo "Wrote $svg_out"
