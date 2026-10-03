module vcraft_wheel

// Wheel filenames encode the compatibility tag twice: once in the name, which is
// what an installer reads, and once in `WHEEL`, which is what a checker reads. They
// have to agree, and computing both from one place is the only way to keep them that
// way.

// Platform is the operating system and architecture a wheel targets.
pub struct Platform {
pub mut:
	// os is the platform tag: linux, macosx or win.
	os string
	// arch is the architecture tag: x86_64, aarch64, universal2 or amd64.
	arch string
}

// Interpreter is the CPython version a wheel targets.
pub struct Interpreter {
pub mut:
	// major and minor are the Python version, 3 and 14 here.
	major int
	minor int
	// abi is the ABI tag: cp314, or cp37 for an abi3 wheel.
	abi string
	// limited_api is true when the wheel is built against the stable ABI.
	limited_api bool
}

// abi_tag returns the ABI part of a compatibility tag.
//
// A free-threaded build is `cp313t` and a GIL build is `cp313`, so the free-threaded
// marker is part of the ABI rather than the version. Getting this wrong produces a
// wheel that pip installs happily and then refuses to import, because the
// interpreter checks the tag before loading anything.
pub fn (i Interpreter) abi_tag() string {
	if i.limited_api {
		return 'cp${i.minor}'
	}
	return i.abi
}

// platform_tag returns the platform part of a compatibility tag.
pub fn (p Platform) tag() string {
	return '${p.os}_${p.arch}'
}

// tag returns the full compatibility tag, e.g. `cp314-cp314-manylinux_2_17_x86_64`.
pub fn (i Interpreter) tag(p Platform) string {
	return 'cp${i.major}${i.minor}-${i.abi_tag()}-${p.tag()}'
}

// filename returns the wheel's file name.
//
// Only the version is normalised. PEP 427 says the distribution name is escaped, not
// normalised: `escape` replaces a run of `-_.` with a single `_`, while the version
// uses PEP 440's normalisation, which uses `-`. Applying one rule to both produces
// `vcraft-demo-0-1-0-...`, and pip rejects that with "wrong number of parts" because
// it split the name on the dashes it just introduced.
pub fn filename(distribution string, version string, i Interpreter, p Platform) string {
	return '${escape(distribution)}-${normalize_version(version)}-${i.tag(p)}.whl'
}

// escape replaces a run of `-`, `_` and `.` with a single `_`.
//
// This is the distribution-name half of PEP 427's file name grammar, and it differs
// from PEP 503's normalisation on purpose: a name inside a wheel file name is escaped,
// not normalised, so `zope.interface` becomes `zope_interface` rather than
// `zope-interface`.
pub fn escape(name string) string {
	mut out := []u8{}
	mut last_was_sep := false
	for ch in name.bytes() {
		if ch == `-` || ch == `_` || ch == `.` {
			if !last_was_sep {
				out << `_`
			}
			last_was_sep = true
		} else {
			out << ch
			last_was_sep = false
		}
	}
	return out.bytestr()
}

// normalize_version escapes a version for a wheel file name.
//
// PEP 427 says the version is escaped by replacing every run of `-` with `_`, and
// nothing else. A `.` stays a `.`.
//
// This is the part that is easy to get backwards. PEP 440 normalises `0.1.0` and
// `0-1-0` to the same version, so writing the separator as `-` looks equivalent and
// is not: the installer splits the file name on `-`, so `0-1-0` reads as three extra
// name parts and the wheel is rejected with "wrong number of parts" before it is
// opened. pip's own parse accepts `0.1.0` and rejects `0-1-0`.
pub fn normalize_version(text string) string {
	mut out := []u8{}
	mut last_was_sep := false
	for ch in text.bytes() {
		if ch == `-` {
			if !last_was_sep {
				out << `_`
			}
			last_was_sep = true
		} else {
			out << ch
			last_was_sep = false
		}
	}
	return out.bytestr()
}
