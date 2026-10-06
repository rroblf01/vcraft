#!/usr/bin/env bash
# Builds the example extension and packages it as a wheel with vcraft's own writer.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${1:-$root/build}"

./scripts/build-example.sh hello hello_native

# The exact suffix of this interpreter: a glob would pick up an extension built
# earlier by another Python version and package it under this one's tag.
suffix="$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))')"
extension="$root/examples/hello/python/hello_native$suffix"
if [ ! -f "$extension" ]; then
	echo "no extension was built" >&2
	exit 1
fi

mkdir -p "$out_dir"
"$root/scripts/vcraft-v.sh" -enable-globals -o "$out_dir/build_wheel" \
	-path "$root/vlib|@vlib" "$root/tests/wheel"
# The tag names the interpreter that built the extension, so the wheel installs on
# exactly that one, whichever version the suite runs under.
tag="$(python3 "$root/tests/wheel/wheel_tag.py")"
"$out_dir/build_wheel" --binary "$extension" --out "$out_dir" --tag "$tag"
