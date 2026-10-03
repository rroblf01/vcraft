#!/usr/bin/env bash
# Builds the `vcraft` binary into bin/.
#
# The binary is compiled with the vcraft V modules on its path and `-prod`, because it
# is a tool rather than an extension: it is not distributed inside a wheel and there is
# no reason to ship it unoptimised.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/bin"

"$root/scripts/vcraft-v.sh" -enable-globals -o "$root/bin/vcraft" -path "$root/vlib|@vlib" "$root/cmd/vcraft"
echo "built $root/bin/vcraft"
