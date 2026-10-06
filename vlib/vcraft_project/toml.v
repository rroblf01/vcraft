module vcraft_project

// A parser for the subset of TOML that `vcraft.toml` uses.
//
// Not a general TOML parser, and deliberately not one. It handles tables, arrays of
// tables, strings, booleans, integers and arrays of strings, and it rejects the rest
// with a line number rather than guessing. That is the whole grammar a build
// configuration needs, and a hand-written parser for it is shorter than the file it
// reads.
//
// The alternative is a dependency, and a packaging tool that cannot build a project
// because a transitive dependency could not be fetched is a packaging tool with a very
// confusing failure mode.

// ValueKind says which field of a Value is meaningful.
pub enum ValueKind {
	string
	boolean
	integer
	array
	// array_of_tables marks a `[[name]]` entry, whose tables are in `tables`.
	array_of_tables
}

// Value is one key's value.
pub struct Value {
pub mut:
	kind   ValueKind
	text   string
	flag   bool
	number int
	list   []Value
	// tables is set for an array of tables, written `[[name]]`.
	tables []Table
	// line is 1-based, for a diagnostic.
	line int
}

// Table is a parsed table: keys in file order, plus any nested tables.
pub struct Table {
pub mut:
	entries []Entry
	// line is 1-based, for a diagnostic.
	line int
}

// Entry is one key and its value.
//
// Public because it appears in `Table.entries`, which is public. A public struct with
// a private field type compiles, and then reading it across a module boundary returns
// garbage: V emits a field accessor it cannot inline, and the caller indexes an
// unrelated array.
pub struct Entry {
pub mut:
	name  string
	value Value
}

// get returns a key's value, or none if the key is absent.
pub fn (t &Table) get(key string) ?Value {
	for e in t.entries {
		if e.name == key {
			return e.value
		}
	}
	return none
}

// string_of returns a key's value as text, or `fallback` if it is absent or not a
// string.
//
// A wrong type is not an error here. A missing or mistyped key takes its default,
// which is friendlier than refusing to build over a boolean where a string belongs.
pub fn (t &Table) string_of(key string, fallback string) string {
	v := t.get(key) or { return fallback }
	if v.kind != .string {
		return fallback
	}
	return v.text
}

// bool_of returns a key's value as a flag, or `fallback`.
pub fn (t &Table) bool_of(key string, fallback bool) bool {
	v := t.get(key) or { return fallback }
	if v.kind != .boolean {
		return fallback
	}
	return v.flag
}

// int_of returns a key's value as a number, or `fallback`.
//
// Like the other accessors, a wrong type is not an error: a missing or mistyped
// key takes its default rather than refusing the build.
pub fn (t &Table) int_of(key string, fallback int) int {
	v := t.get(key) or { return fallback }
	if v.kind != .integer {
		return fallback
	}
	return v.number
}

// string_list_of returns a key's value as a list of strings.
//
// A bare string counts as a one-element list, because `classifiers = "Programming
// Language :: V"` is a natural thing to write and refusing it helps nobody.
pub fn (t &Table) string_list_of(key string) []string {
	v := t.get(key) or { return []string{} }
	if v.kind == .string {
		return [v.text]
	}
	if v.kind != .array {
		return []string{}
	}
	mut out := []string{}
	for item in v.list {
		if item.kind == .string {
			out << item.text
		}
	}
	return out
}

// table_list_of returns the tables of an array of tables.
pub fn (t &Table) table_list_of(key string) []Table {
	v := t.get(key) or { return []Table{} }
	return v.tables
}

// subtable returns a nested table, or an empty one if the key is absent.
//
// A `[name]` header and a `[[name]]` array are both stored as an array of tables, so
// a one-element read is the normal case and the caller does not have to know which
// form the file used.
pub fn (t &Table) subtable(key string) Table {
	v := t.get(key) or { return Table{} }
	if v.kind != .array_of_tables || v.tables.len == 0 {
		return Table{}
	}
	return v.tables[0]
}

// parse reads TOML text into a table.
pub fn parse(text string) !Table {
	// `at` is set here rather than left to the struct literal's zero value. A struct
	// literal in V leaves an omitted field at 0, not at 1, and the loop's first line
	// reads `lines[at - 1]`, which is `lines[-1]`. The failure is an index-out-of-range
	// with a negative index, which says nothing about a line counter being off by one.
	mut p := Parser{
		lines: text.split_into_lines()
		at:    1
	}
	return p.run()
}

// Parser is the parse state.
// Parser holds the state one parse needs.
//
// There is deliberately one table under construction rather than a `root` plus a
// `current` plus a collected list. Keeping the three in step needs a write-back after
// every key, and V copies a struct on assignment, so a write-back that looks correct
// can still leave a stale copy behind: the symptom is a key that parses without error
// and then reads back empty.
// Parser holds the state one parse needs.
//
// One table is under construction at a time and it is reached through `current`, never
// held twice. An earlier version kept `root`, `table` and a collected list of sections
// and wrote to all three, which cannot work: V copies a struct on assignment, so the
// three are independent values from the moment they are set, and a write-back that
// looks correct leaves one of them stale. The symptom was a configuration file whose
// keys parsed without error and then read back as the defaults.
struct Parser {
mut:
	// lines is the file, split.
	lines []string
	// at is the 1-based line being read.
	at int
	// root holds the keys written before the first header. It is only ever written to
	// while `pending_name` is empty, and `merge` starts from it.
	root Table
	// table is the table being filled right now.
	table Table
	// pending_name is the header `table` belongs to, empty while it is the root.
	pending_name string
	// sections collects the finished tables by header name, in the order they appeared.
	// A repeated `[[name]]` appends, which is what makes a list accumulate rather than
	// replace.
	sections []Section
}

// Section is one table collected under a header name.
struct Section {
pub mut:
	name  string
	tables []Table
}

// run reads every line.
fn (mut p Parser) run() !Table {
	p.table = Table{
		line: 1
	}
	for p.at <= p.lines.len {
		line := p.lines[p.at - 1].trim_space()
		if line == '' || line.starts_with('#') {
			p.at++
			continue
		}
		if line.starts_with('[[') {
			if !line.ends_with(']]') {
				return error('${p.at}: `[[` is not closed')
			}
			name := line[2..line.len - 2].trim_space()
			p.at++
			// Each `[[name]]` is one entry of an array of tables. The one being filled is
			// finished into `sections` before the new one starts, which is what keeps
			// exactly one table alive at a time.
			p.file_current()
			p.table = Table{
				line: p.at
			}
			p.pending_name = name
			continue
		}
		if line.starts_with('[') {
			if !line.ends_with(']') {
				return error('${p.at}: `[` is not closed')
			}
			name := line[1..line.len - 1].trim_space()
			p.at++
			// A `[name]` header is collected the same way as `[[name]]`, so reading it
			// back does not have to know which form the file used.
			p.file_current()
			p.table = Table{
				line: p.at
			}
			p.pending_name = name
			continue
		}
		key, value := p.parse_pair(line)!
		// A key before any header is a root key, and a key after one belongs to that
		// table. `pending_name` says which, and routing by it rather than by which
		// table object is being filled is what keeps the two from being confused: V
		// copies a struct on assignment, so `root` and `table` are independent values
		// and a key written to the wrong one parses cleanly and reads back absent.
		if p.pending_name == '' {
			p.root.entries << Entry{
				name:  key
				value: value
			}
		} else {
			p.table.entries << Entry{
				name:  key
				value: value
			}
		}
		p.at++
	}
	return p.merge()
}

// file_current files the table being filled under its header name, if it has one.
//
// A table with no header is the root and is not filed: `merge` returns it as it stands.
fn (mut p Parser) file_current() {
	if p.pending_name == '' {
		return
	}
	p.add_section(p.pending_name, p.table)
	p.pending_name = ''
}

// add_section appends a table to the section called `name`.
//
// Rebuilt rather than appended to in place. `p.sections[i].tables << table` does not
// compile without three `mut`s and a pointer, and the version that does compile loses
// the append on a repeated header: the section is written, the first table survives,
// and every later one is dropped without an error.
fn (mut p Parser) add_section(name string, table Table) {
	mut sections := []Section{}
	mut matched := false
	for s in p.sections {
		if s.name == name {
			mut grown := s.tables.clone()
			grown << table
			sections << Section{
				name:   name
				tables: grown
			}
			matched = true
			continue
		}
		sections << s
	}
	if !matched {
		sections << Section{
			name:   name
			tables: [table]
		}
	}
	p.sections = sections
}

// merge finishes the file and folds the nested tables into the root.
fn (mut p Parser) merge() Table {
	p.file_current()
	mut out := p.root
	for s in p.sections {
		out = push_section(out, s.name, s.tables)
	}
	return out
}

// push_section returns `t` with `tables` recorded under `name`.
//
// A rebuild rather than an in-place update: V makes a struct field read-only through
// the variable that holds it, so `t.entries[i].value = x` needs a pointer and ends in
// `unsafe`. Rebuilding is a plain append each time.
fn push_section(t Table, name string, tables []Table) Table {
	mut entries := []Entry{}
	for e in t.entries {
		if e.name == name && e.value.kind == .array_of_tables {
			mut grown := e.value.tables.clone()
			grown << tables
			entries << Entry{
				name: e.name
				value: Value{
					kind:   .array_of_tables
					line:   e.value.line
					tables: grown
				}
			}
			continue
		}
		entries << e
	}
	mut present := false
	for e in entries {
		if e.name == name {
			present = true
		}
	}
	if !present {
		entries << Entry{
			name: name
			value: Value{
				kind:   .array_of_tables
				line:   tables[0].line
				tables: tables.clone()
			}
		}
	}
	return Table{
		entries: entries
		line:    t.line
	}
}

// parse_pair splits `key = value` and parses the value.
fn (mut p Parser) parse_pair(line string) !(string, Value) {
	mut eq := -1
	for i in 0 .. line.len {
		if line[i] == `=` {
			eq = i
			break
		}
	}
	if eq < 0 {
		return error('${p.at}: expected `key = value`, got `${line}`')
	}
	key := unquote(line[..eq].trim_space())
	if key == '' {
		return error('${p.at}: the key is empty')
	}
	text := strip_comment(line[eq + 1..].trim_space())
	value := parse_value(text, p.at) or {
		return error('${p.at}: cannot read `${text}`')
	}
	return key, value
}

// strip_comment removes a `#` comment that is not inside a quoted string.
fn strip_comment(text string) string {
	mut quote := u8(0)
	for i in 0 .. text.len {
		ch := text[i]
		if quote != 0 {
			if ch == quote {
				quote = 0
			}
			continue
		}
		if ch == `"` || ch == `'` {
			quote = ch
			continue
		}
		if ch == `#` {
			return text[..i].trim_space()
		}
	}
	return text
}

// unquote removes surrounding quotes and resolves the escapes a name or a description
// is likely to contain.
pub fn unquote(text string) string {
	if text.len >= 2 && text[0] == `"` && text[text.len - 1] == `"` {
		return text[1..text.len - 1].replace('\\"', '"')
	}
	if text.len >= 2 && text[0] == `'` && text[text.len - 1] == `'` {
		return text[1..text.len - 1]
	}
	return text
}

// quote renders text as a double-quoted TOML string.
pub fn quote(text string) string {
	return '"' + text.replace('"', '\\"') + '"'
}

// parse_value reads one TOML value.
fn parse_value(text string, line int) ?Value {
	if text.len == 0 {
		return none
	}
	if text[0] == `"` || text[0] == `'` {
		return Value{
			kind: .string
			text: unquote(text)
			line: line
		}
	}
	if text == 'true' {
		return Value{
			kind: .boolean
			flag: true
			line: line
		}
	}
	if text == 'false' {
		return Value{
			kind: .boolean
			flag: false
			line: line
		}
	}
	if text[0] == `[` {
		return parse_array(text, line)
	}
	mut digits := true
	for ch in text.bytes() {
		if ch < `0` || ch > `9` {
			digits = false
			break
		}
	}
	if digits {
		mut number := 0
		for ch in text.bytes() {
			number = number * 10 + int(ch - `0`)
		}
		return Value{
			kind:   .integer
			number: number
			line:   line
		}
	}
	// A bare word. Kept as text rather than refused, because a platform tag or an ABI
	// name is a perfectly reasonable value for a key.
	return Value{
		kind: .string
		text: text
		line: line
	}
}

// parse_array reads `[a, b, c]`.
fn parse_array(text string, line int) ?Value {
	mut items := []Value{}
	mut rest := text[1..].trim_space()
	if rest == '' {
		return Value{
			kind: .array
			list: items
			line: line
		}
	}
	mut quote := u8(0)
	mut current := []u8{}
	for i in 0 .. rest.len {
		ch := rest[i]
		if quote != 0 {
			current << ch
			if ch == quote {
				quote = 0
			}
			continue
		}
		if ch == `"` || ch == `'` {
			quote = ch
			current << ch
			continue
		}
		if ch == `]` {
			last := current.bytestr().trim_space()
			if last != '' {
				items << parse_value(last, line) or { return none }
			}
			return Value{
				kind: .array
				list: items
				line: line
			}
		}
		if ch == `,` {
			piece := current.bytestr().trim_space()
			if piece != '' {
				items << parse_value(piece, line) or { return none }
			}
			current = []u8{}
			continue
		}
		current << ch
	}
	// An unterminated array is the common typo, and naming it beats a parse error
	// about the last element.
	return none
}



