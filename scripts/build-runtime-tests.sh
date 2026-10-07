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
	printf '{\n\tglobal: PyInit_%s;\n\tlocal: *;\n};\n' "$name" > "$exports_file"
	link_flags=(-ldflags "-Wl,--version-script=$exports_file")
fi

# VCRAFT_SANITIZE=1 builds with AddressSanitizer and UndefinedBehaviorSanitizer, for
# the CI job that runs the suites under them. gcc rather than V's default tcc, which
# has no sanitizers; the interpreter then needs the ASan runtime preloaded.
sanitize=()
if [ -n "${VCRAFT_SANITIZE:-}" ]; then
	sanitize=(-cc gcc -ldflags "-fsanitize=address,undefined")
	sanitize_cflags="-fsanitize=address,undefined -fno-omit-frame-pointer -g"
else
	sanitize_cflags=""
fi

"$here/scripts/vcraft-v.sh" -shared -o "$out$suffix" \
	${sanitize[@]+"${sanitize[@]}"} \
	${link_flags[@]+"${link_flags[@]}"} \
	-path "$here/vlib|@vlib" \
	-cflags "-I$include $sanitize_cflags" \
	"$here/tests/runtime"

# For macOS V appends `.dylib` to an output name that does not already end in it,
# and CPython only imports a file ending in its EXT_SUFFIX, so the file is moved back.
if [ -f "$out$suffix.dylib" ]; then
	mv -f "$out$suffix.dylib" "$out$suffix"
fi

echo "built $out$suffix"
