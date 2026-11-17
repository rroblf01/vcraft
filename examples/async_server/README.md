# async_server

An asyncio TCP server whose CPU-bound work is written in V. `stretch` (iterated SHA-256)
and `count_primes` are `@[vc_async]`: each call returns an asyncio future and runs on its
own thread without the GIL, so the event loop keeps serving other clients meanwhile.

```console
$ vcraft develop
$ python server.py 8765
$ printf 'primes 1000000\nstretch secret salt 200000\n' | nc 127.0.0.1 8765
$ python test_async_server.py
```

What to look at: `src/async_server.v` (an error chosen by code, since the function runs
off the GIL) and `server.py` (plain `await native.stretch(...)`, no executor).
