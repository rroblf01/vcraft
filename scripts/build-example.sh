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
	printf '{\n\tglobal: PyInit_%s;\n\tlocal: *;\n};\n' "$module" > "$exports_file"
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

"$here/scripts/vcraft-v.sh" -enable-globals -shared -o "$project/python/$module$suffix" \
	${sanitize[@]+"${sanitize[@]}"} \
	${link_flags[@]+"${link_flags[@]}"} \
	-path "$here/vlib|@vlib" \
	-cflags "-I$include $sanitize_cflags" \
	"$project"

# For macOS V appends `.dylib` to an output name that does not already end in it,
# and CPython only imports a file ending in its EXT_SUFFIX, so the file is moved back.
if [ -f "$project/python/$module$suffix.dylib" ]; then
	mv -f "$project/python/$module$suffix.dylib" "$project/python/$module$suffix"
fi

echo "built $project/python/$module$suffix"
