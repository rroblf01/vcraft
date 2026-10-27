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
	printf("slot_iter %d\n", Py_tp_iter);
	printf("slot_iternext %d\n", Py_tp_iternext);
	printf("slot_dealloc %d\n", Py_tp_dealloc);
	printf("slot_init %d\n", Py_tp_init);
	printf("slot_methods %d\n", Py_tp_methods);
	printf("slot_new %d\n", Py_tp_new);
	printf("slot_repr %d\n", Py_tp_repr);
	printf("slot_members %d\n", Py_tp_members);
	printf("slot_getset %d\n", Py_tp_getset);
	printf("slot_richcompare %d\n", Py_tp_richcompare);
	printf("slot_hash %d\n", Py_tp_hash);
	printf("slot_sq_length %d\n", Py_sq_length);
	printf("slot_sq_item %d\n", Py_sq_item);
	printf("slot_sq_contains %d\n", Py_sq_contains);
	printf("slot_sq_ass_item %d\n", Py_sq_ass_item);
	printf("slot_mp_length %d\n", Py_mp_length);
	printf("slot_mp_subscript %d\n", Py_mp_subscript);
	printf("slot_mp_ass_subscript %d\n", Py_mp_ass_subscript);
	printf("slot_str %d\n", Py_tp_str);
	printf("slot_nb_add %d\n", Py_nb_add);
	printf("slot_nb_subtract %d\n", Py_nb_subtract);
	printf("slot_nb_multiply %d\n", Py_nb_multiply);
	printf("slot_nb_remainder %d\n", Py_nb_remainder);
	printf("slot_nb_power %d\n", Py_nb_power);
	printf("slot_nb_negative %d\n", Py_nb_negative);
	printf("slot_nb_positive %d\n", Py_nb_positive);
	printf("slot_nb_absolute %d\n", Py_nb_absolute);
	printf("slot_nb_invert %d\n", Py_nb_invert);
	printf("slot_nb_lshift %d\n", Py_nb_lshift);
	printf("slot_nb_rshift %d\n", Py_nb_rshift);
	printf("slot_nb_and %d\n", Py_nb_and);
	printf("slot_nb_xor %d\n", Py_nb_xor);
	printf("slot_nb_or %d\n", Py_nb_or);
	printf("slot_nb_floor_divide %d\n", Py_nb_floor_divide);
	printf("slot_nb_true_divide %d\n", Py_nb_true_divide);
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
slot_iter 62
slot_iternext 63
slot_hash 59
slot_sq_length 45
slot_sq_item 44
slot_sq_contains 41
slot_sq_ass_item 39
slot_mp_length 4
slot_mp_subscript 5
slot_mp_ass_subscript 3
slot_str 70
slot_nb_add 7
slot_nb_subtract 36
slot_nb_multiply 29
slot_nb_remainder 34
slot_nb_power 33
slot_nb_negative 30
slot_nb_positive 32
slot_nb_absolute 6
slot_nb_invert 27
slot_nb_lshift 28
slot_nb_rshift 35
slot_nb_and 8
slot_nb_xor 38
slot_nb_or 31
slot_nb_floor_divide 12
slot_nb_true_divide 37
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
