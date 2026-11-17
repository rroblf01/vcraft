"""A line-based TCP server: each request runs its heavy part in V, off the event loop.

    $ vcraft develop
    $ python server.py            # listens on 127.0.0.1:8765
    $ printf 'primes 1000000\nstretch secret salt 200000\n' | nc 127.0.0.1 8765

Requests are `primes <limit>` and `stretch <password> <salt> <rounds>`; each answer is
one line. While one client's request computes, the loop keeps serving the others: the
V functions are awaitable and release the GIL.
"""

from __future__ import annotations

import asyncio
import sys

import async_server as native


async def answer(line: str) -> str:
    parts = line.split()
    try:
        if parts[:1] == ["primes"] and len(parts) == 2:
            return str(await native.count_primes(int(parts[1])))
        if parts[:1] == ["stretch"] and len(parts) == 4:
            return await native.stretch(parts[1], parts[2], int(parts[3]))
    except ValueError as exc:
        return f"error: {exc}"
    return "error: unknown request"


async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    while line := await reader.readline():
        writer.write((await answer(line.decode().strip()) + "\n").encode())
        await writer.drain()
    writer.close()


async def serve(host: str = "127.0.0.1", port: int = 8765) -> asyncio.Server:
    return await asyncio.start_server(handle, host, port)


async def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = await serve(port=port)
    print(f"listening on 127.0.0.1:{port}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
