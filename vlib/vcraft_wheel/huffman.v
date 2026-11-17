module vcraft_wheel

// Building the Huffman codes of a dynamic block (RFC 1951, 3.2.7).

// code_length_order is the order in which the code-length code's own lengths are
// written in a dynamic block header: the ones most often zero go last, so they can be
// left out.
const code_length_order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

// ensure_two gives an alphabet at least two symbols with a nonzero count.
//
// A one-symbol code has no complete Huffman tree, and decoders disagree on whether a
// lone 1-bit code is acceptable. Two symbols of length 1 are a complete code that every
// decoder reads. The symbol added this way is never emitted.
fn ensure_two(mut freq []int) {
	mut used := 0
	for f in freq {
		if f > 0 {
			used++
		}
	}
	for i := 0; used < 2 && i < freq.len; i++ {
		if freq[i] == 0 {
			freq[i] = 1
			used++
		}
	}
}

// huffman_lengths returns the code length of each symbol, none longer than `max_bits`,
// with zero for a symbol whose count is zero.
//
// The tree is built with two queues over the leaves sorted by count, which needs no
// heap: merged nodes come out in nondecreasing weight, so the smallest two are always at
// the fronts of the two queues. Ties are broken by symbol, so the result, and the wheel
// built from it, is the same on every run.
//
// A tree deeper than the format allows is then flattened the way miniz does it: the
// count of codes per length is clamped and rebalanced until the code is complete again,
// and the lengths are handed out to the symbols in count order, the rarest getting the
// longest. The result can be slightly worse than an optimal length-limited code and is
// always a valid one.
fn huffman_lengths(freq []int, max_bits int) []int {
	mut lengths := []int{len: freq.len}
	mut leaves := []int{}
	for i, f in freq {
		if f > 0 {
			leaves << i
		}
	}
	if leaves.len == 0 {
		return lengths
	}
	if leaves.len == 1 {
		lengths[leaves[0]] = 1
		return lengths
	}
	leaves.sort_with_compare(fn [freq] (a &int, b &int) int {
		if freq[*a] != freq[*b] {
			return if freq[*a] < freq[*b] { -1 } else { 1 }
		}
		return if *a < *b { -1 } else if *a > *b { 1 } else { 0 }
	})
	m := leaves.len
	// Nodes 0 .. m-1 are the leaves in sorted order; m .. 2m-2 are the merges.
	mut weight := []i64{len: 2 * m - 1}
	mut parent := []int{len: 2 * m - 1}
	for i in 0 .. m {
		weight[i] = i64(freq[leaves[i]])
	}
	mut next_leaf := 0
	mut next_node := m
	mut built := m
	for built < 2 * m - 1 {
		mut pick := [0, 0]
		for k in 0 .. 2 {
			if next_leaf < m && (next_node >= built || weight[next_leaf] <= weight[next_node]) {
				pick[k] = next_leaf
				next_leaf++
			} else {
				pick[k] = next_node
				next_node++
			}
		}
		weight[built] = weight[pick[0]] + weight[pick[1]]
		parent[pick[0]] = built
		parent[pick[1]] = built
		built++
	}
	// Depth of each node, from the root down: a node's parent always has a higher index.
	mut depth := []int{len: 2 * m - 1}
	for node := 2 * m - 3; node >= 0; node-- {
		depth[node] = depth[parent[node]] + 1
	}
	mut deepest := 0
	for i in 0 .. m {
		if depth[i] > deepest {
			deepest = depth[i]
		}
	}
	mut bl_count := []int{len: if deepest > max_bits { deepest + 1 } else { max_bits + 1 }}
	for i in 0 .. m {
		bl_count[depth[i]]++
	}
	if deepest > max_bits {
		for d in max_bits + 1 .. bl_count.len {
			bl_count[max_bits] += bl_count[d]
			bl_count[d] = 0
		}
		mut total := i64(0)
		for d in 1 .. max_bits + 1 {
			total += i64(bl_count[d]) << (max_bits - d)
		}
		for total > (i64(1) << max_bits) {
			bl_count[max_bits]--
			for d := max_bits - 1; d > 0; d-- {
				if bl_count[d] != 0 {
					bl_count[d]--
					bl_count[d + 1] += 2
					break
				}
			}
			total--
		}
	}
	// The rarest leaves come first in `leaves`, and take the longest codes.
	mut next := 0
	for d := max_bits; d >= 1; d-- {
		for _ in 0 .. bl_count[d] {
			lengths[leaves[next]] = d
			next++
		}
	}
	return lengths
}

// canonical_codes assigns the canonical code of each length, as RFC 1951 3.2.2 defines
// it: codes of one length are consecutive, in symbol order, and shorter codes sort
// before longer ones. The decoder rebuilds the same codes from the lengths alone.
fn canonical_codes(lengths []int, max_bits int) []u32 {
	mut bl_count := []int{len: max_bits + 1}
	for l in lengths {
		if l > 0 {
			bl_count[l]++
		}
	}
	mut next_code := []u32{len: max_bits + 2}
	mut code := u32(0)
	for bits in 1 .. max_bits + 1 {
		code = (code + u32(bl_count[bits - 1])) << 1
		next_code[bits] = code
	}
	mut codes := []u32{len: lengths.len}
	for i, l in lengths {
		if l > 0 {
			codes[i] = next_code[l]
			next_code[l]++
		}
	}
	return codes
}

// run_length encodes a block's code lengths with the code-length alphabet: 0-15 for a
// length, 16 to repeat the previous length 3-6 times, 17 for 3-10 zeros and 18 for
// 11-138 zeros. Each item is the symbol in the low byte and its extra-bits value above.
//
// The literal/length and distance lengths form one sequence, and a run may cross from
// one into the other, which the format allows.
fn run_length(lengths []int) []int {
	mut out := []int{cap: lengths.len}
	mut i := 0
	for i < lengths.len {
		value := lengths[i]
		mut run := 1
		for i + run < lengths.len && lengths[i + run] == value {
			run++
		}
		i += run
		if value == 0 {
			for run >= 11 {
				take := if run > 138 { 138 } else { run }
				out << (18 | ((take - 11) << 8))
				run -= take
			}
			if run >= 3 {
				out << (17 | ((run - 3) << 8))
				run = 0
			}
			for _ in 0 .. run {
				out << 0
			}
			continue
		}
		out << value
		run--
		for run >= 3 {
			take := if run > 6 { 6 } else { run }
			out << (16 | ((take - 3) << 8))
			run -= take
		}
		for _ in 0 .. run {
			out << value
		}
	}
	return out
}

// code_length_extra is how many extra bits follow a code-length symbol.
fn code_length_extra(sym int) int {
	return match sym {
		16 { 2 }
		17 { 3 }
		18 { 7 }
		else { 0 }
	}
}
