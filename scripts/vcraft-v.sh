#!/usr/bin/env bash
# The only way this project invokes the V compiler.
#
# It exists because a bare `v` call is not safe to run unattended:
#
#   * V retries a failed C compilation with a *bootstrap of the V compiler
#     itself*, which builds the whole of `vlib/v` from source. That is the
#     20 GiB, multi-minute event this wrapper exists to prevent. `-new-compiler`
#     turns the retry off, so a C error surfaces as a C error.
#   * V's parallel stages scale with the core count and hold per-worker arenas.
#     On a 12-core host that is a lot of resident memory for a small module.
#     VJOBS plus -no-parallel bounds it; the numbers are kept low on purpose.
#   * systemd-run puts a kernel-enforced ceiling on the whole build. If something
#     does go wrong, the build dies instead of the desktop.
#
# A normal build of the runtime test module peaks around 100 MiB with these
# settings, against a 4 GiB ceiling.
#
# Usage: scripts/vcraft-v.sh <same flags v would take>
set -euo pipefail

# 4 GiB address-space ceiling, and no swap to absorb it, so a runaway build is
# killed rather than taking the machine down with it.
readonly memory_max="${VCRAFT_MEMORY_MAX:-4G}"

# VJOBS bounds the worker pools. V's own source notes that high values multiply
# RSS and shared-cache pressure.
export VJOBS="${VCRAFT_JOBS:-2}"

# No compatibility-compiler bootstrap, and no automatic bug reports going out to
# the network on a C failure.
export V_MACOS_V3_NO_FALLBACK=1
export V_C_ERROR_BUG_REPORT_DISABLED=1

command -v v >/dev/null || { echo "the V compiler is not on PATH" >&2; exit 1; }

# systemd-run is only used when it understands every option below: an older
# systemd-run accepts the command but rejects `--working-directory`, and the build
# then fails on the wrapper rather than on anything it compiled. Checking the help
# text detects that, because the version number alone does not say which options a
# distribution built in.
if command -v systemd-run >/dev/null && systemd-run --help 2>&1 | grep -q -- '--working-directory' && [ -z "${VCRAFT_NO_MEMORY_LIMIT:-}" ]; then
	exec systemd-run --user --wait --collect --pipe --quiet \
		--working-directory="$PWD" \
		-p "MemoryMax=$memory_max" \
		-p MemorySwapMax=0 \
		v -new-compiler -no-parallel "$@"
fi

# Without systemd the flags above still bound the build, there is just no hard
# ceiling.
exec v -new-compiler -no-parallel "$@"
