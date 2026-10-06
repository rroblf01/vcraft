#!/usr/bin/env bash
# Builds a vcraft example end to end: generate the glue, then compile it.
#
# This is what `vcraft build` will do. It is a script for now because the CLI
# does not exist yet.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
example="${1:-hello}"
module="${2:-hello_native}"
include="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["include"])')"
suffix="$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))')"
project="$here/examples/$example"

# The generator. Rebuilt every time, because a cached one silently keeps stale
# annotation names and produces an empty module rather than an error.
mkdir -p "$here/build"
"$here/scripts/vcraft-v.sh" -o "$here/build/vc-generate" \
	-path "$here/vlib|@vlib" "$here/cmd/vc-generate"

"$here/build/vc-generate" "$project" "$module" "$module"

mkdir -p "$project/python"
# Extensions leave the `Py*` symbols for the interpreter to resolve at import.
# Apple's linker refuses undefined symbols in a shared object unless told so;
# ELF linkers allow them by default.
macos_ldflags=()
if [ "$(uname -s)" = Darwin ]; then
	macos_ldflags=(-ldflags "-undefined dynamic_lookup")
fi

"$here/scripts/vcraft-v.sh" -enable-globals -shared -o "$project/python/$module$suffix" \
	${macos_ldflags[@]+"${macos_ldflags[@]}"} \
	-path "$here/vlib|@vlib" \
	-cflags "-I$include" \
	"$project"

# For macOS V appends `.dylib` to an output name that does not already end in it,
# and CPython only imports a file ending in its EXT_SUFFIX, so the file is moved back.
if [ -f "$project/python/$module$suffix.dylib" ]; then
	mv -f "$project/python/$module$suffix.dylib" "$project/python/$module$suffix"
fi

echo "built $project/python/$module$suffix"
