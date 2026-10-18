#!/usr/bin/env bash
# Builds the `vcraft` binary into bin/.
#
# The binary is compiled with the vcraft V modules on its path and `-prod`, because it
# is a tool rather than an extension: it is not distributed inside a wheel and there is
# no reason to ship it unoptimised.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/bin"

# `VCRAFT_CC` picks the C compiler. The release sets it to `clang` on macOS: V's
# bundled TCC writes a Mach-O whose load commands `install_name_tool` refuses
# ("symbol table out of place"), and the shipped binary has to be edited to make its
# `libgc.dylib` dependency relative. A clang/ld64 binary can be edited.
cc_opt=""
if [ -n "${VCRAFT_CC:-}" ]; then
	cc_opt="-cc ${VCRAFT_CC}"
fi
# shellcheck disable=SC2086
"$root/scripts/vcraft-v.sh" -enable-globals $cc_opt -o "$root/bin/vcraft" -path "$root/vlib|@vlib" "$root/cmd/vcraft"
echo "built $root/bin/vcraft"
