#!/usr/bin/env bash
# Runs a command with extensions built and loaded under ASan and UBSan.
#
#   scripts/run-sanitized.sh python3 tests/runtime/test_runtime.py
#
# The build scripts read VCRAFT_SANITIZE and compile with gcc and the sanitizers. The
# interpreter is not built with them, so the ASan runtime is preloaded for it to be
# first in the process, as ASan requires. Leak detection is off: CPython keeps
# interned objects alive until exit by design, and the leak suite covers leaks with
# its own measurements. Stack use-after-return is off because V's collector scans
# stacks and ASan's fake stacks hide pointers from it.
set -euo pipefail

if [ "$(uname -s)" != Linux ]; then
	echo "sanitized runs are Linux-only" >&2
	exit 2
fi
asan="$(gcc -print-file-name=libasan.so)"
if [ ! -f "$asan" ]; then
	echo "gcc has no libasan.so" >&2
	exit 2
fi

export VCRAFT_SANITIZE=1
export LD_PRELOAD="$asan${LD_PRELOAD:+:$LD_PRELOAD}"
export ASAN_OPTIONS="detect_leaks=0:detect_stack_use_after_return=0:abort_on_error=1:halt_on_error=1"
export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1"
exec "$@"
