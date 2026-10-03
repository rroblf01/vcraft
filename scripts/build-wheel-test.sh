#!/usr/bin/env bash
# Builds the example extension and packages it as a wheel with vcraft's own writer.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${1:-$root/build}"

./scripts/build-example.sh hello hello_native

extension="$(find "$root/examples/hello/python" -maxdepth 1 -name 'hello_native*.so' -print -quit)"
if [ -z "$extension" ]; then
	echo "no extension was built" >&2
	exit 1
fi

mkdir -p "$out_dir"
"$root/scripts/vcraft-v.sh" -enable-globals -o "$out_dir/build_wheel" \
	-path "$root/vlib|@vlib" "$root/tests/wheel"
"$out_dir/build_wheel" --binary "$extension" --out "$out_dir"
