#!/usr/bin/env bash
# Builds the three projects from clean, installs their wheels into a uv virtualenv,
# and runs bench.py against them.
#
# Needs on PATH: uv, cargo, zig (0.16), and a V compiler built at the commit pinned in
# docker/ (vcraft passes flags the V releases predate). Nothing is installed outside
# benchmark/.venv; cargo and zig keep their usual global caches, so a "clean" build here
# is a clean project build with the toolchain's dependency caches warm.
#
#   ./run.sh               full run
#   ./run.sh --quick       fewer timing repeats
#
# BENCH_PYTHON picks the interpreter (default 3.13, the newest all three support).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
venv="$here/.venv"

for tool in uv cargo zig v; do
	command -v "$tool" >/dev/null || { echo "$tool is not on PATH" >&2; exit 1; }
done

uv venv -q --allow-existing --python "${BENCH_PYTHON:-3.13}" "$venv"
uv pip install -q --python "$venv/bin/python" maturin zig-maturin psutil
export PATH="$venv/bin:$PATH"
python="$venv/bin/python"

vcraft="${VCRAFT:-$root/bin/vcraft}"
if [ ! -x "$vcraft" ]; then
	"$root/scripts/build-vcraft.sh"
fi

times="$here/.build-times.json"
echo '{}' > "$times"

# timed <backend> <command...>: runs the command and records its wall time.
timed() {
	local name="$1"
	shift
	"$python" - "$times" "$name" "$@" <<'PY'
import json, subprocess, sys, time
path, name, *cmd = sys.argv[1:]
start = time.perf_counter()
proc = subprocess.run(cmd)
elapsed = time.perf_counter() - start
if proc.returncode != 0:
    sys.exit(f"{name}: build failed")
data = json.load(open(path))
data[name] = elapsed
json.dump(data, open(path, "w"))
print(f"{name}: built in {elapsed:.1f} s")
PY
}

echo "== building"
(cd "$here/pyo3" && rm -rf target dist &&
	timed pyo3 maturin build --release -i "$python" -o dist)
(cd "$here/vcraft" && rm -rf build dist .vcraft &&
	timed vcraft "$vcraft" build --release --interpreter "$python")
(cd "$here/zig-maturin" && rm -rf .zig-cache zig-out dist &&
	timed zig-maturin zig-maturin build --release --out dist)

echo "== installing"
for project in pyo3 vcraft zig-maturin; do
	uv pip install -q --python "$python" --reinstall "$here/$project"/dist/*.whl
done

echo "== benchmarking"
"$python" "$here/bench.py" --build-times "$times" "$@"
