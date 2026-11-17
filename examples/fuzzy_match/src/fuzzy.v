module fuzzy

import vcraft

// Fuzzy string matching, the kind of hot loop pure-Python libraries such as `jellyfish`
// or `difflib` spend their time in. Everything works on code points, so `"café"` is four
// characters, as in Python.

// levenshtein is the edit distance between two strings: the fewest single-character
// insertions, deletions and substitutions that turn one into the other.
@[vc_fn]
pub fn levenshtein(a string, b string) int {
	return distance(a.runes(), b.runes())
}

// distance is the two-row dynamic programme, over the shorter string's length.
fn distance(a []rune, b []rune) int {
	if a.len < b.len {
		return distance(b, a)
	}
	if b.len == 0 {
		return a.len
	}
	mut prev := []int{len: b.len + 1, init: index}
	mut cur := []int{len: b.len + 1}
	for i in 1 .. a.len + 1 {
		cur[0] = i
		ai := a[i - 1]
		for j in 1 .. b.len + 1 {
			cost := if ai == b[j - 1] { 0 } else { 1 }
			mut best := prev[j] + 1
			if cur[j - 1] + 1 < best {
				best = cur[j - 1] + 1
			}
			if prev[j - 1] + cost < best {
				best = prev[j - 1] + cost
			}
			cur[j] = best
		}
		for j in 0 .. cur.len {
			prev[j] = cur[j]
		}
	}
	return prev[b.len]
}

// similarity is 1 - distance / the longer length: 1.0 for equal strings, 0.0 for
// strings with nothing in common.
@[vc_fn]
pub fn similarity(a string, b string) f64 {
	ra := a.runes()
	rb := b.runes()
	longest := if ra.len > rb.len { ra.len } else { rb.len }
	if longest == 0 {
		return 1.0
	}
	return 1.0 - f64(distance(ra, rb)) / f64(longest)
}

// jaro_winkler is the Jaro similarity with Winkler's bonus for a common prefix (up to
// four characters, scale 0.1), the measure record-linkage uses for names.
@[vc_fn]
pub fn jaro_winkler(a string, b string) f64 {
	return winkler(a.runes(), b.runes())
}

fn winkler(a []rune, b []rune) f64 {
	j := jaro(a, b)
	mut prefix := 0
	for prefix < 4 && prefix < a.len && prefix < b.len && a[prefix] == b[prefix] {
		prefix++
	}
	return j + f64(prefix) * 0.1 * (1.0 - j)
}

fn jaro(a []rune, b []rune) f64 {
	if a.len == 0 && b.len == 0 {
		return 1.0
	}
	if a.len == 0 || b.len == 0 {
		return 0.0
	}
	longer := if a.len > b.len { a.len } else { b.len }
	window := if longer / 2 - 1 > 0 { longer / 2 - 1 } else { 0 }
	mut a_hit := []bool{len: a.len}
	mut b_hit := []bool{len: b.len}
	mut matches := 0
	for i in 0 .. a.len {
		lo := if i - window > 0 { i - window } else { 0 }
		hi := if i + window + 1 < b.len { i + window + 1 } else { b.len }
		for k in lo .. hi {
			if !b_hit[k] && a[i] == b[k] {
				a_hit[i] = true
				b_hit[k] = true
				matches++
				break
			}
		}
	}
	if matches == 0 {
		return 0.0
	}
	mut transpositions := 0
	mut k := 0
	for i in 0 .. a.len {
		if !a_hit[i] {
			continue
		}
		for !b_hit[k] {
			k++
		}
		if a[i] != b[k] {
			transpositions++
		}
		k++
	}
	m := f64(matches)
	return (m / f64(a.len) + m / f64(b.len) + (m - f64(transpositions) / 2.0) / m) / 3.0
}

// Match is one result of `extract`: Python receives it as a tuple with named fields, a
// struct sequence like `os.stat_result`.
@[vc_structseq]
pub struct Match {
pub:
	choice string
	score  f64
	index  int
}

// extract scores every choice against `query` and returns the `limit` best, highest
// score first (ties keep the choices' order): `rapidfuzz.process.extract` in a few
// lines. `scorer` is 'similarity' or 'jaro_winkler'.
//
// The loop allocates almost nothing: an ASCII pair is compared byte by byte (no code
// point conversion), the distance rows are reused from one choice to the next, and only
// the `limit` best are kept rather than all of them sorted.
@[vc_fn]
@[vc_defaults: 'limit=5, scorer="similarity"']
pub fn extract(query string, choices []string, limit int, scorer string) ![]Match {
	if scorer != 'similarity' && scorer != 'jaro_winkler' {
		return error_with_code("scorer must be 'similarity' or 'jaro_winkler', not '${scorer}'",
			int(vcraft.PyExc.value_error))
	}
	if limit <= 0 {
		return []Match{}
	}
	q := query.runes()
	ascii_query := is_ascii(query)
	mut prev := []int{len: 64}
	mut cur := []int{len: 64}
	mut best := []Match{cap: limit + 1}
	for i, choice in choices {
		score := if scorer == 'jaro_winkler' {
			winkler(q, choice.runes())
		} else if ascii_query && is_ascii(choice) {
			longest := if query.len > choice.len { query.len } else { choice.len }
			if longest == 0 {
				1.0
			} else {
				1.0 - f64(ascii_distance(query, choice, mut prev, mut cur)) / f64(longest)
			}
		} else {
			c := choice.runes()
			longest := if q.len > c.len { q.len } else { c.len }
			if longest == 0 { 1.0 } else { 1.0 - f64(distance(q, c)) / f64(longest) }
		}
		if best.len == limit && score <= best[best.len - 1].score {
			continue
		}
		// Insert in order; a later choice with an equal score goes after the earlier one.
		mut at := best.len
		for at > 0 && best[at - 1].score < score {
			at--
		}
		best.insert(at, Match{
			choice: choice
			score:  score
			index:  i
		})
		if best.len > limit {
			best.delete_last()
		}
	}
	return best
}

// is_ascii reports whether every byte of `s` is ASCII, so bytes are characters.
@[inline]
fn is_ascii(s string) bool {
	for c in s {
		if c >= 0x80 {
			return false
		}
	}
	return true
}

// ascii_distance is `distance` over the bytes of two ASCII strings, reusing the rows.
@[direct_array_access]
fn ascii_distance(a string, b string, mut prev []int, mut cur []int) int {
	if a.len < b.len {
		return ascii_distance(b, a, mut prev, mut cur)
	}
	if b.len == 0 {
		return a.len
	}
	if prev.len < b.len + 1 {
		prev = []int{len: b.len + 1}
		cur = []int{len: b.len + 1}
	}
	for j in 0 .. b.len + 1 {
		prev[j] = j
	}
	for i in 1 .. a.len + 1 {
		cur[0] = i
		ai := a[i - 1]
		for j in 1 .. b.len + 1 {
			cost := if ai == b[j - 1] { 0 } else { 1 }
			mut v := prev[j] + 1
			if cur[j - 1] + 1 < v {
				v = cur[j - 1] + 1
			}
			if prev[j - 1] + cost < v {
				v = prev[j - 1] + cost
			}
			cur[j] = v
		}
		for j in 0 .. b.len + 1 {
			prev[j] = cur[j]
		}
	}
	return prev[b.len]
}
