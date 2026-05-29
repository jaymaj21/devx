#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: cdstr.sh input.cdstr [output.json]
Compiles a .cdstr model to normalized JSON. If output is omitted, writes adjacent input.json.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
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
output="${2:-}"
if [[ ! -f "$input" ]]; then
  echo "Error: input file not found: $input" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cdstr_project="$script_dir/clj-dstr"

if [[ ! -f "$cdstr_project/pom.xml" ]]; then
  echo "Error: clj-dstr Maven project not found: $cdstr_project" >&2
  exit 1
fi

input_dir="$(cd "$(dirname "$input")" && pwd)"
input_abs="$input_dir/$(basename "$input")"
input_stem="$(basename "${input%.*}")"
json_out="${output:-$input_dir/$input_stem.json}"

mvn -q -f "$cdstr_project/pom.xml" compile exec:java "-Dexec.args=$input_abs $json_out"
