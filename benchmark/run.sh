#!/usr/bin/env bash
# Builds the four projects from clean, installs their wheels into a uv virtualenv,
# and runs bench.py against them.
#
# Needs on PATH: uv, cargo and a V compiler built at the commit pinned in docker/ (vcraft
# passes flags the V releases predate). zig 0.16 is optional: without it, or when its
# build fails (another zig version), zig-maturin is left out of the run with a warning
# rather than failing the whole comparison. pybind11 needs a C++17 compiler (`c++`); it is
# left out the same way when there is none. Nothing is installed outside
# benchmark/.venv; cargo, zig and uv keep their usual global caches, so a "clean" build here
# is a clean project build with the toolchain's dependency caches warm.
#
#   ./run.sh               full run
#   ./run.sh --quick       fewer timing repeats
#
# BENCH_PYTHON picks the interpreter (default 3.13, the newest all of them support).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
venv="$here/.venv"

for tool in uv cargo v; do
	command -v "$tool" >/dev/null || { echo "$tool is not on PATH" >&2; exit 1; }
done

uv venv -q --allow-existing --python "${BENCH_PYTHON:-3.13}" "$venv"
uv pip install -q --python "$venv/bin/python" maturin psutil
with_zig=1
command -v zig >/dev/null || with_zig=0
[ "$with_zig" = 1 ] && uv pip install -q --python "$venv/bin/python" zig-maturin
with_pybind11=1
command -v c++ >/dev/null || with_pybind11=0
# Pinned like PyO3 in Cargo.toml, and built without isolation so the run records it.
[ "$with_pybind11" = 1 ] && uv pip install -q --python "$venv/bin/python" pybind11==3.1.0 setuptools
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
if [ "$with_zig" = 1 ]; then
	(cd "$here/zig-maturin" && rm -rf .zig-cache zig-out dist &&
		timed zig-maturin zig-maturin build --release --out dist) || with_zig=0
fi
[ "$with_zig" = 1 ] || echo "warning: zig-maturin is left out of this run (zig $(zig version 2>/dev/null || echo missing); it needs 0.16)" >&2
if [ "$with_pybind11" = 1 ]; then
	(cd "$here/pybind11" && rm -rf build dist src/*.egg-info &&
		timed pybind11 uv build -q --wheel --no-build-isolation --python "$python" --out-dir dist) ||
		with_pybind11=0
fi
[ "$with_pybind11" = 1 ] || echo "warning: pybind11 is left out of this run (no working C++ compiler)" >&2

echo "== installing"
projects="pyo3 vcraft"
[ "$with_zig" = 1 ] && projects="$projects zig-maturin"
[ "$with_pybind11" = 1 ] && projects="$projects pybind11"
for project in $projects; do
	uv pip install -q --python "$python" --reinstall "$here/$project"/dist/*.whl
done

echo "== benchmarking"
only="pyo3 vcraft python"
[ "$with_zig" = 1 ] && only="$only zig-maturin"
[ "$with_pybind11" = 1 ] && only="$only pybind11"
# shellcheck disable=SC2086 # $only is a word list
"$python" "$here/bench.py" --build-times "$times" --only $only "$@"
