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
"$here/scripts/vcraft-v.sh" -shared -o "$project/python/$module$suffix" \
	-path "$here/vlib|@vlib" \
	-cflags "-I$include" \
	"$project"

echo "built $project/python/$module$suffix"
