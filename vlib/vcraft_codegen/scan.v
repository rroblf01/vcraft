module vcraft_codegen

import os
import strings

// Reading annotations and doc comments out of the source text.
//
// V keeps declaration attributes in the type checker, not in the parse tree, so a
// tool that works on the tree cannot see them. V's own `v.astquery` documents the
// same limitation and advises reading the source. That is what this module does.
//
// Reading the text has a second payoff. `v.astquery` also fails to attach a doc
// comment when an annotation sits between the comment and the declaration, which
// is exactly the shape vcraft asks for:
//
//	// Adds two integers.
//	@[vc.fn]
//	pub fn add(a int, b int) int
//
// So both the annotation block and the docstring are read here, in one pass
// upwards from the declaration.

// AttrBlock is what was found immediately above a declaration.
pub struct AttrBlock {
pub mut:
	// attrs are the annotation names, in source order, without arguments.
	attrs []string
	// doc is the doc comment with its `//` markers and one space of indent
	// removed, or empty when there was none.
	doc string
}

// read_inline reads the annotation and doc comment of a declaration written on one
// line, which is how a struct field looks:
//
//	@[vc_field] value int
//
// The annotation sits on the declaration's own line, so `read_above` would read the
// line before it and pick up the previous field's annotation instead.
pub fn read_inline(lines []string, line int) AttrBlock {
	mut block := AttrBlock{}
	if line < 1 || line > lines.len {
		return block
	}
	block.attrs = parse_attr_names(lines[line - 1])
	block.doc = doc_above(lines, line)
	return block
}

// starts_comment_at reports whether a doc comment opens on or above `index`.
fn starts_comment_at(lines []string, index int) bool {
	for i in index .. 0 {
		trimmed := lines[i].trim_space()
		if trimmed == '' {
			continue
		}
		return trimmed.starts_with('//')
	}
	return false
}

// doc_above reads the doc comment immediately above `line`, skipping blanks.
fn doc_above(lines []string, line int) string {
	mut doc_lines := []string{}
	mut i := line - 2
	for i >= 0 {
		trimmed := lines[i].trim_space()
		if trimmed == '' {
			break
		}
		if !trimmed.starts_with('//') {
			break
		}
		doc_lines.prepend(strip_comment_marker(trimmed))
		i--
	}
	return doc_lines.join('\n')
}

// read_above reads the annotation block and doc comment that precede `line`, which
// is 1-based. This is the form a function or struct declaration takes, where the
// annotation is on its own line above.
//
// `lines` is the whole file split into lines, which the caller already has.
pub fn read_above(lines []string, line int) AttrBlock {
	mut block := AttrBlock{}
	mut attrs_acc := []string{}
	mut i := line - 2 // zero-based index of the line above the declaration

	// Attributes come first: walk them, allowing the block to span lines while
	// the brackets stay balanced.
	for i >= 0 {
		trimmed := lines[i].trim_space()
		if trimmed == '' {
			i--
			continue
		}
		if !trimmed.starts_with('@[') {
			break
		}
		// A doc comment above the attribute block belongs to it. The attributes are
		// still read from below; the comment is what stops the walk, because the
		// annotation and its docstring are separate things in V and the next block up
		// is a different declaration's.
		if starts_comment_at(lines, i) {
			break
		}
		// Walk back to the start of this attribute, which may open on an earlier
		// line than it closes.
		mut start := i
		for start >= 0 && !lines[start].trim_space().starts_with('@[') {
			start--
		}
		if start < 0 {
			break
		}
		block_text := join_lines(lines[start..i + 1])
		for name in parse_attr_names(block_text) {
			attrs_acc.prepend(name)
		}
		i = start - 1
	}
	block.attrs = attrs_acc

	// Then the doc comment, which must be contiguous lines directly above the
	// attributes, ignoring blank lines.
	mut doc_lines := []string{}
	for i >= 0 {
		trimmed := lines[i].trim_space()
		if trimmed == '' {
			break
		}
		if !trimmed.starts_with('//') {
			break
		}
		doc_lines.prepend(strip_comment_marker(trimmed))
		i--
	}
	block.doc = doc_lines.join('\n')
	return block
}

// strip_comment_marker removes the `//` and one following space.
fn strip_comment_marker(line string) string {
	rest := line.all_after_first('//')
	return if rest.starts_with(' ') { rest[1..] } else { rest }
}

// join_lines folds a slice of lines back into one string, joining with a space so
// that a multi-line annotation block reads as `@[vc.fn, inline]`.
fn join_lines(lines []string) string {
	mut out := strings.Builder{}
	for i, line in lines {
		if i > 0 {
			out.write_string(' ')
		}
		out.write_string(line.trim_space())
	}
	return out.str()
}

// parse_attr_names pulls the names out of one or more `@[...]` blocks.
//
// It is a small scanner rather than a V parser: it only needs to find `@[`, then
// read names up to `:` or `,` or `]`, tracking nesting so that an argument
// containing brackets does not end the block early. Anything it cannot make sense
// of is skipped rather than guessed at, because a wrong name here means a missing
// export.
pub fn parse_attr_names(text string) []string {
	mut names := []string{}
	mut i := 0
	for i < text.len {
		if text[i] != `@` {
			i++
			continue
		}
		j := i + 1
		if j >= text.len || text[j] != `[` {
			i++
			continue
		}
		mut depth := 0
		mut k := j
		mut current := strings.Builder{}
		for k < text.len {
			ch := text[k]
			if ch == `[` {
				depth++
				if depth == 1 {
					k++
					continue
				}
			} else if ch == `]` {
				depth--
				if depth == 0 {
					flush_attr(mut names, mut current)
					k++
					break
				}
			} else if depth == 1 && (ch == `,` || ch == `:`) {
				flush_attr(mut names, mut current)
				k++
				continue
			}
			if depth >= 1 {
				current.write_u8(ch)
			}
			k++
		}
		flush_attr(mut names, mut current)
		i = k
	}
	return names
}

// flush_attr records a candidate name, discarding an empty one and any argument
// text left over from a `name: value` pair.
fn flush_attr(mut names []string, mut current strings.Builder) {
	raw := current.str().trim_space()
	if raw == '' {
		return
	}
	// A bare `@[]` contributes nothing, and a bare `@[inline]` is a name.
	names << raw
}

// read_lines splits a source file into lines, tolerating CRLF.
pub fn read_lines(path string) []string {
	content := os.read_file(path) or { return [] }
	return content.replace('\r\n', '\n').split('\n')
}
