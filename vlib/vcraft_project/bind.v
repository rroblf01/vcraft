module vcraft_project

import os

// `vcraft bind`: V declarations for the functions a C header declares.
//
// V calls C through `fn C.name(...)` declarations, and writing them by hand is where the
// classic mistake lives: C's `int` is 32 bits and V's is 64, so `fn C.f(n int)` reads half
// of every argument and nothing warns. This reads the function prototypes of a header --
// not the whole of C: no macros, no struct layouts -- and writes the declarations with the
// widths C means, plus the `#flag`/`#include` lines that compile it in.
//
// Anything it cannot translate faithfully (varargs, a struct passed by value, a function
// pointer) is written as a comment saying why, so nothing is silently wrong.

// BindOptions are what `vcraft bind` was asked for.
pub struct BindOptions {
pub:
	header  string
	module  string
	sources []string
	libs    []string
}

// c_type_to_v maps a C parameter or result type to V, or '' when it has no faithful V
// spelling. `const` is dropped; pointers to known scalars keep their element type.
pub fn c_type_to_v(c_type string) string {
	mut t := c_type.replace('\t', ' ').trim_space()
	for q in ['const ', 'volatile ', 'restrict ', '__restrict ', 'extern ', 'static ', 'inline '] {
		t = t.replace(q, '')
	}
	t = t.replace(' const', '').replace(' *', '*').replace('* ', '*').trim_space()
	for t.contains('  ') {
		t = t.replace('  ', ' ')
	}
	stars := t.count('*')
	base := t.replace('*', '').trim_space()
	if stars >= 2 {
		return 'voidptr'
	}
	if stars == 1 {
		if base == 'void' {
			return 'voidptr'
		}
		if base == 'char' {
			return '&char'
		}
		scalar := c_scalar_to_v(base)
		if scalar.len > 0 {
			return '&' + scalar
		}
		// A pointer to a struct or an opaque typedef: an address V does not look into.
		return 'voidptr'
	}
	return c_scalar_to_v(base)
}

fn c_scalar_to_v(t string) string {
	return match t {
		'void' { 'void' }
		'char', 'signed char', 'int8_t' { 'i8' }
		'unsigned char', 'uint8_t' { 'u8' }
		'short', 'short int', 'signed short', 'int16_t' { 'i16' }
		'unsigned short', 'unsigned short int', 'uint16_t' { 'u16' }
		'int', 'signed', 'signed int', 'int32_t' { 'i32' }
		'unsigned', 'unsigned int', 'uint32_t' { 'u32' }
		// LP64: `long` is 64 bits on Linux and macOS (32 on Windows; use int64_t there).
		'long', 'long int', 'signed long', 'long long', 'long long int', 'int64_t' { 'i64' }
		'unsigned long', 'unsigned long int', 'unsigned long long', 'uint64_t' { 'u64' }
		'size_t', 'uintptr_t' { 'u64' }
		'ssize_t', 'ptrdiff_t', 'intptr_t' { 'i64' }
		'float' { 'f32' }
		'double' { 'f64' }
		'bool', '_Bool' { 'bool' }
		else { '' }
	}
}

// strip_c_comments removes `/* */` and `//` comments and preprocessor lines.
fn strip_c_comments(src string) string {
	mut out := []u8{cap: src.len}
	mut i := 0
	for i < src.len {
		if i + 1 < src.len && src[i] == `/` && src[i + 1] == `*` {
			end := src.index_after('*/', i + 2) or { src.len - 2 }
			i = end + 2
			continue
		}
		if i + 1 < src.len && src[i] == `/` && src[i + 1] == `/` {
			for i < src.len && src[i] != `\n` {
				i++
			}
			continue
		}
		out << src[i]
		i++
	}
	mut lines := []string{}
	for line in out.bytestr().split_into_lines() {
		if !line.trim_space().starts_with('#') {
			lines << line
		}
	}
	return lines.join('\n')
}

// split_param splits `const uint8_t *data` into its type and name; a parameter written
// without a name gets `argN`.
fn split_param(p string, index int) (string, string) {
	s := p.trim_space()
	mut name_start := s.len
	for name_start > 0 && (s[name_start - 1].is_letter() || s[name_start - 1].is_digit()
		|| s[name_start - 1] == `_`) {
		name_start--
	}
	name := s[name_start..]
	typ := s[..name_start].trim_space()
	// A lone type (`int`, `size_t`) has no name: the last word is the type itself.
	if typ.len == 0 || typ == 'const' || typ in ['unsigned', 'signed', 'long', 'short'] {
		return s, 'arg${index}'
	}
	safe := if name in ['type', 'module', 'fn', 'struct', 'map', 'string', 'match', 'in', 'is',
		'as', 'or', 'mut', 'pub', 'go', 'spawn', 'select', 'return', 'none', 'enum', 'interface',
		'lock', 'rlock', 'shared', 'unsafe', 'defer', 'assert', 'const', 'import', 'chan', 'it'] {
		'${name}_'
	} else {
		name.to_lower()
	}
	return typ, safe
}

// bind_declarations translates the prototypes of a header's text into V declarations.
pub fn bind_declarations(header_text string) []string {
	src := strip_c_comments(header_text)
	mut out := []string{}
	mut depth := 0
	mut stmt := []u8{}
	for ch in src.bytes() {
		if ch == `{` {
			depth++
			stmt.clear()
			continue
		}
		if ch == `}` {
			depth--
			stmt.clear()
			continue
		}
		if depth > 0 {
			continue
		}
		if ch == `;` {
			decl := stmt.bytestr().replace('\n', ' ').trim_space()
			stmt.clear()
			line := bind_prototype(decl)
			if line.len > 0 {
				out << line
			}
			continue
		}
		stmt << ch
	}
	return out
}

fn bind_prototype(decl string) string {
	if !decl.contains('(') || !decl.ends_with(')') || decl.starts_with('typedef')
		|| decl.contains('(*') {
		if decl.contains('(*') && !decl.starts_with('typedef') {
			return '// skipped (a function pointer is not translated): ${decl}'
		}
		return ''
	}
	head := decl.all_before('(').trim_space()
	params_text := decl.all_after('(').all_before_last(')').trim_space()
	mut name_start := head.len
	for name_start > 0 && (head[name_start - 1].is_letter() || head[name_start - 1].is_digit()
		|| head[name_start - 1] == `_`) {
		name_start--
	}
	name := head[name_start..]
	ret_c := head[..name_start].trim_space()
	if name.len == 0 || ret_c.len == 0 {
		return ''
	}
	if params_text.contains('...') {
		return '// skipped (varargs cannot be declared to V): ${decl}'
	}
	ret := c_type_to_v(ret_c)
	if ret.len == 0 {
		return '// skipped (result `${ret_c}` has no V equivalent; a struct by value?): ${decl}'
	}
	mut params := []string{}
	if params_text.len > 0 && params_text != 'void' {
		for i, p in params_text.split(',') {
			typ, pname := split_param(p, i)
			vt := c_type_to_v(typ)
			if vt.len == 0 || vt == 'void' {
				return '// skipped (parameter `${p.trim_space()}` has no V equivalent): ${decl}'
			}
			params << '${pname} ${vt}'
		}
	}
	suffix := if ret == 'void' { '' } else { ' ' + ret }
	return 'fn C.${name}(${params.join(', ')})${suffix}'
}

// bind_file renders the whole V file `vcraft bind` writes.
pub fn bind_file(opt BindOptions, header_text string) string {
	header_dir := os.dir(opt.header)
	header_name := os.file_name(opt.header)
	mut out := 'module ${opt.module}\n\n'
	out += '// Declarations generated by `vcraft bind ${opt.header}`. Check them against the header:\n'
	out += '// the widths are C\'s (an `int` is `i32`), pointers to structs are `voidptr`, and\n'
	out += '// anything that could not be translated faithfully is a comment below.\n\n'
	if os.is_abs_path(header_dir) {
		out += '#flag -I ${header_dir}\n'
	} else if header_dir.len > 0 && header_dir != '.' {
		out += '#flag -I @VMODROOT/${header_dir}\n'
	}
	for src in opt.sources {
		out += '#flag @VMODROOT/${src}\n'
	}
	for lib in opt.libs {
		out += '#flag -l${lib}\n'
	}
	out += '#include "${header_name}"\n\n'
	decls := bind_declarations(header_text)
	for d in decls {
		out += d + '\n'
	}
	if decls.len == 0 {
		out += '// no function prototypes were found in ${header_name}\n'
	}
	return out
}
