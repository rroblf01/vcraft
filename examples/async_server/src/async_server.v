module async_server

// The V half of an asyncio server: the CPU-bound work a request needs. Each
// `@[vc_async]` function returns an asyncio future and runs on a thread of its own
// without the GIL, so the event loop keeps accepting and answering other clients while
// it computes. `server.py` is the Python half.

import crypto.sha256
import vcraft

// stretch hashes `salt + password` with SHA-256, then the digest again `rounds - 1`
// times, and returns the hex digest: deliberately slow work, as a password hash is.
@[vc_fn]
@[vc_async]
pub fn stretch(password string, salt string, rounds int) !string {
	if rounds < 1 {
		// Off the GIL, an exception is chosen through the error's code, not raise_domain.
		return error_with_code('rounds must be at least 1', int(vcraft.PyExc.value_error))
	}
	mut digest := sha256.sum((salt + password).bytes())
	for _ in 1 .. rounds {
		digest = sha256.sum(digest)
	}
	return digest.hex()
}

// count_primes counts the primes below `limit` with a sieve: another request whose
// cost grows with its argument.
@[vc_fn]
@[vc_async]
pub fn count_primes(limit int) int {
	if limit < 3 {
		return 0
	}
	mut composite := []bool{len: limit}
	mut count := 0
	for i in 2 .. limit {
		if composite[i] {
			continue
		}
		count++
		for j := i * i; j < limit; j += i {
			composite[j] = true
		}
	}
	return count
}
