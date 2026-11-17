module main

// Compresses each file it is given with vcraft's DEFLATE and writes `<file>.deflate`
// beside it, for test_wheel.py to decompress with zlib. Also checks the stream against
// vcraft's own inflater, so a disagreement between the two shows up as a failure here.

import os
import vcraft_wheel

fn main() {
	for path in os.args[1..] {
		data := os.read_bytes(path) or {
			eprintln('cannot read ${path}')
			exit(1)
		}
		out := vcraft_wheel.compress(data)
		os.write_file_array(path + '.deflate', out) or {
			eprintln('cannot write ${path}.deflate')
			exit(1)
		}
		back := vcraft_wheel.inflate(out) or {
			eprintln('${path}: vcraft cannot inflate its own stream: ${err}')
			exit(1)
		}
		if back != data {
			eprintln('${path}: vcraft inflates its own stream to different bytes')
			exit(1)
		}
	}
}
