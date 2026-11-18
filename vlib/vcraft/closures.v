module vcraft

fn C.vpy_release_closure(f voidptr)

// release_closure frees the closure `f` once the runtime function it was handed to has run
// it. V keeps every closure, and everything it captured, alive until a `closure.Lifetime`
// reclaims it, so a function that builds one per call -- the body of a `par_range`, the
// block of a `released` -- would otherwise grow by the size of its captures on every call.
// `f` is consumed, the way V consumes a closure given to a detached `spawn`: pass these
// functions a closure literal, not one you call again afterwards. A named function is not
// a closure and is left alone.
fn release_closure(f voidptr) {
	C.vpy_release_closure(f)
}
