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
link_flags=()
if [ "$(uname -s)" = Darwin ]; then
	link_flags=(-ldflags "-undefined dynamic_lookup")
fi

# On Linux, export only the init function: V hides most of its runtime, but on musl
# its own backtrace() family reached the dynamic symbol table. A version script hides
# everything else, whatever the libc. macOS takes `-undefined dynamic_lookup` above.
if [ "$(uname -s)" = Linux ]; then
	# In the repository's build/ rather than mktemp: the compiler runs in a
	# `systemd-run` unit (scripts/vcraft-v.sh), which need not see this shell's /tmp.
	mkdir -p "$here/build"
	exports_file="$here/build/$(basename "$0" .sh).exports"
	printf '{\n\tglobal: PyInit_%s;\n\tlocal: *;\n};\n' "probe" > "$exports_file"
	link_flags=(-ldflags "-Wl,--version-script=$exports_file")
fi

"$here/scripts/vcraft-v.sh" -shared -o "$probe_dir/probe$suffix" \
	${link_flags[@]+"${link_flags[@]}"} \
	-cflags "-I$include" "$probe_dir/src/"

# For macOS V appends `.dylib` to an output name that does not already end in it,
# and CPython only imports a file ending in its EXT_SUFFIX, so the file is moved back.
if [ -f "$probe_dir/probe$suffix.dylib" ]; then
	mv -f "$probe_dir/probe$suffix.dylib" "$probe_dir/probe$suffix"
fi

echo "built $probe_dir/probe$suffix"
