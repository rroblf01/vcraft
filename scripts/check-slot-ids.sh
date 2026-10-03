#!/usr/bin/env bash
# Compares the slot ids vcraft repeats against the ones in CPython's headers.
#
# Slot ids are macros, so the runtime hard-codes them. Nothing in a built extension
# notices when CPython renumbers them: the type is created, the slots are quietly
# left unset, and the symptom is a method or property that does not exist.
set -euo pipefail

python_include="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["include"])')"
python_version="$(python3 -c "import sysconfig; print(sysconfig.get_config_var('py_version_short'))")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/slots.c" <<'SRC'
#include <Python.h>
#include <stdio.h>

int main(void) {
	printf("slot_doc %d\n", Py_tp_doc);
	printf("slot_bases %d\n", Py_tp_bases);
	printf("slot_clear %d\n", Py_tp_clear);
	printf("slot_traverse %d\n", Py_tp_traverse);
	printf("slot_dealloc %d\n", Py_tp_dealloc);
	printf("slot_init %d\n", Py_tp_init);
	printf("slot_methods %d\n", Py_tp_methods);
	printf("slot_new %d\n", Py_tp_new);
	printf("slot_repr %d\n", Py_tp_repr);
	printf("slot_members %d\n", Py_tp_members);
	printf("slot_getset %d\n", Py_tp_getset);
	printf("slot_richcompare %d\n", Py_tp_richcompare);
	printf("slot_hash %d\n", Py_tp_hash);
	printf("slot_str %d\n", Py_tp_str);
	printf("sizeof_type_spec %zu\n", sizeof(PyType_Spec));
	printf("sizeof_type_slot %zu\n", sizeof(PyType_Slot));
	return 0;
}
SRC

gcc -I"$python_include" "$tmp/slots.c" -o "$tmp/slots"
"$tmp/slots" > "$tmp/actual.txt"

# The values vlib/vcraft/cpython.c.v declares.
cat > "$tmp/expected.txt" <<'SRC'
slot_doc 56
slot_clear 51
slot_bases 49
slot_dealloc 52
slot_init 60
slot_methods 64
slot_new 65
slot_repr 66
slot_members 72
slot_getset 73
slot_richcompare 67
slot_traverse 71
slot_hash 59
slot_str 70
sizeof_type_spec 32
sizeof_type_slot 16
SRC

status=0
while read -r name expected; do
	actual="$(grep "^${name} " "$tmp/actual.txt" | cut -d' ' -f2)"
	if [ "$actual" = "$expected" ]; then
		printf '%-18s %s ok\n' "$name" "$actual"
	else
		printf '%-18s %s MISMATCH, vcraft says %s\n' "$name" "$actual" "$expected"
		status=1
	fi
done < "$tmp/expected.txt"

if [ "$status" -eq 0 ]; then
	printf 'slot ids match CPython %s\n' "$python_version"
fi
exit "$status"
