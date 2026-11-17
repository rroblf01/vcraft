module csvfast

// A CSV parser: Python's `csv` module's default dialect, as a single pass over the text
// in V. Rows cross to Python as `list[list[str]]`, records as `list[dict[str, str]]`.

import strings
import vcraft

// parse splits CSV text into rows of fields. Quoted fields may hold the separator, a
// doubled quote and line breaks; `\r\n` and `\n` both end a row, and an empty line is an
// empty row, as `csv.reader` gives them. An unterminated quote is a ValueError naming
// the line it opened on.
@[vc_fn]
@[vc_defaults: 'sep=","']
pub fn parse(text string, sep string) ![][]string {
	if sep.len != 1 || sep[0] == `"` || sep[0] == `\n` || sep[0] == `\r` {
		return vcraft.raise_domain(.value_error, 'sep must be one character other than a quote or a line break')
	}
	s := sep[0]
	mut rows := [][]string{}
	mut row := []string{cap: 8}
	// A field without quotes is a view of `text` itself: no copy is made in V, and the
	// one copy that matters, into a Python str, happens when the result is returned,
	// while `text` is still the caller's argument. Only a quoted field, whose doubled
	// quotes have to be undone, is assembled in a builder.
	mut field := strings.new_builder(32)
	mut quoted := false
	// in_quoted marks a field opened by a quote: its text is in `field`, and `""` alone
	// on a line is one empty field rather than an empty row.
	mut in_quoted := false
	mut start := 0
	mut opened := 0
	mut line := 1
	mut i := 0
	for i < text.len {
		c := text[i]
		if quoted {
			if c == `"` {
				if i + 1 < text.len && text[i + 1] == `"` {
					field.write_u8(`"`)
					i += 2
					continue
				}
				quoted = false
			} else {
				if c == `\n` {
					line++
				}
				field.write_u8(c)
			}
			i++
			continue
		}
		if c == `"` && i == start && !in_quoted {
			quoted = true
			in_quoted = true
			opened = line
		} else if c == s {
			row << take(text, start, i, mut field, in_quoted)
			in_quoted = false
			start = i + 1
		} else if c == `\n` || c == `\r` {
			if row.len > 0 || i > start || in_quoted {
				row << take(text, start, i, mut field, in_quoted)
			}
			in_quoted = false
			rows << row
			row = []string{cap: row.len}
			if c == `\r` && i + 1 < text.len && text[i + 1] == `\n` {
				i++
			}
			start = i + 1
			line++
		} else if in_quoted {
			// Text after a closing quote joins the field, as `csv` does.
			field.write_u8(c)
		}
		i++
	}
	if quoted {
		return vcraft.raise_domain(.value_error, 'unterminated quoted field opened on line ${opened}')
	}
	if row.len > 0 || text.len > start || in_quoted {
		row << take(text, start, text.len, mut field, in_quoted)
		rows << row
	}
	return rows
}

// take is the field that ends at `end`: the builder's text for a quoted one, else a view
// of `text[start..end]` that shares its bytes.
@[inline]
fn take(text string, start int, end int, mut field strings.Builder, in_quoted bool) string {
	if in_quoted {
		return field.str()
	}
	return unsafe { tos(text.str + start, end - start) }
}

// records parses CSV text whose first row names the columns, as `csv.DictReader` does:
// one dict per remaining non-empty row. A row with a different number of fields is a
// ValueError naming it.
@[vc_fn]
@[vc_defaults: 'sep=","']
pub fn records(text string, sep string) ![]map[string]string {
	rows := parse(text, sep)!
	if rows.len == 0 {
		return []map[string]string{}
	}
	header := rows[0]
	mut out := []map[string]string{cap: rows.len - 1}
	for n, row in rows[1..] {
		if row.len == 0 {
			continue
		}
		if row.len != header.len {
			return vcraft.raise_domain(.value_error, 'row ${n + 2} has ${row.len} fields, the header ${header.len}')
		}
		mut record := map[string]string{}
		for j, name in header {
			record[name] = row[j]
		}
		out << record
	}
	return out
}
