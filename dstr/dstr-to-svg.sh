#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: dstr-to-svg.sh input.dstr [spec-to-dot options]
Produces input.json, input.dot, and input.svg next to the source file.
Extra arguments are passed directly to spec-to-dot.js.
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
compiler="$script_dir/scripts/dstr-dsl-compiler.lisp"
spec_to_dot="$script_dir/scripts/spec-to-dot.js"

if [[ ! -f "$compiler" ]]; then
  echo "Error: compiler script not found: $compiler" >&2
  exit 1
fi

if [[ ! -f "$spec_to_dot" ]]; then
  echo "Error: spec-to-dot script not found: $spec_to_dot" >&2
  exit 1
fi

input_dir="$(cd "$(dirname "$input")" && pwd)"
input_stem="$(basename "${input%.*}")"
json_out="$input_dir/$input_stem.json"
dot_out="$input_dir/$input_stem.dot"
svg_out="$input_dir/$input_stem.svg"

sbcl --script "$compiler" "$input" "$json_out"
node "$spec_to_dot" "$json_out" "$dot_out" "$@"
dot -Tsvg "$dot_out" -o "$svg_out"

echo "Wrote $json_out"
echo "Wrote $dot_out"
echo "Wrote $svg_out"
