#!/usr/bin/env bash
# Builds the vcraft runtime test extension.
#
# Nothing is installed: it uses the `v` already on PATH and the CPython headers
# that ship with the interpreter. The vcraft runtime module is resolved from this
# repository with -path, so VMODULES is never touched.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="vcraft_runtime_check"
out="$here/build/$name"
include="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["include"])')"
suffix="$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))')"

if [ ! -f "$include/Python.h" ]; then
	echo "CPython development headers not found in $include" >&2
	exit 1
fi

mkdir -p "$here/build"

echo "V:       $(command -v v)"
echo "Python:  $(python3 -VV)"
echo "headers: $include"

# Extensions leave the `Py*` symbols for the interpreter to resolve at import.
# Apple's linker refuses undefined symbols in a shared object unless told so;
# ELF linkers allow them by default.
macos_ldflags=()
if [ "$(uname -s)" = Darwin ]; then
	macos_ldflags=(-ldflags "-undefined dynamic_lookup")
fi

"$here/scripts/vcraft-v.sh" -shared -o "$out$suffix" \
	${macos_ldflags[@]+"${macos_ldflags[@]}"} \
	-path "$here/vlib|@vlib" \
	-cflags "-I$include" \
	"$here/tests/runtime"

# For macOS V appends `.dylib` to an output name that does not already end in it,
# and CPython only imports a file ending in its EXT_SUFFIX, so the file is moved back.
if [ -f "$out$suffix.dylib" ]; then
	mv -f "$out$suffix.dylib" "$out$suffix"
fi

echo "built $out$suffix"
