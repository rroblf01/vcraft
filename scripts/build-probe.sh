#!/usr/bin/env bash
# Builds the Gate 0 probe: a CPython extension module produced by the V compiler.
#
# Nothing is installed. It uses the `v` already on PATH and the CPython headers
# that ship with the interpreter.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_dir="$here/examples/probe"

include="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["include"])')"
suffix="$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX"))')"

if [ ! -f "$include/Python.h" ]; then
	echo "CPython development headers not found in $include" >&2
	exit 1
fi

echo "V:       $(command -v v)"
echo "Python:  $(python3 -VV)"
echo "headers: $include"

# `v -shared` appends a shared library suffix on its own, but it does not know
# about CPython's EXT_SUFFIX, so vcraft supplies the full output name. Python
# will only load a module whose file name ends in that suffix.
# Extensions leave the `Py*` symbols for the interpreter to resolve at import.
# Apple's linker refuses undefined symbols in a shared object unless told so;
# ELF linkers allow them by default.
macos_ldflags=()
if [ "$(uname -s)" = Darwin ]; then
	macos_ldflags=(-ldflags "-undefined dynamic_lookup")
fi

"$here/scripts/vcraft-v.sh" -shared -o "$probe_dir/probe$suffix" \
	${macos_ldflags[@]+"${macos_ldflags[@]}"} \
	-cflags "-I$include" "$probe_dir/src/"

# For macOS V appends `.dylib` to an output name that does not already end in it,
# and CPython only imports a file ending in its EXT_SUFFIX, so the file is moved back.
if [ -f "$probe_dir/probe$suffix.dylib" ]; then
	mv -f "$probe_dir/probe$suffix.dylib" "$probe_dir/probe$suffix"
fi

echo "built $probe_dir/probe$suffix"
