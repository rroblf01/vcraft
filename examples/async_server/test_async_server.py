"""Run with the built extension importable: `vcraft develop`, then `python test_async_server.py`."""

import asyncio
import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import async_server as native
import server


def reference(password: str, salt: str, rounds: int) -> str:
    digest = hashlib.sha256((salt + password).encode()).digest()
    for _ in range(rounds - 1):
        digest = hashlib.sha256(digest).digest()
    return digest.hex()


async def ask(port: int, lines: list[str]) -> list[str]:
    reader, writer = await asyncio.open_connection("127.0.0.1", port)
    out = []
    for line in lines:
        writer.write((line + "\n").encode())
        await writer.drain()
        out.append((await reader.readline()).decode().strip())
    writer.close()
    return out


async def main() -> None:
    assert await native.stretch("pw", "salt", 1000) == reference("pw", "salt", 1000)
    assert await native.count_primes(100) == 25
    try:
        await native.stretch("pw", "salt", 0)
    except ValueError as exc:
        assert "at least 1" in str(exc)
    else:
        raise AssertionError("rounds=0 was accepted")

    # The loop stays responsive while V computes: a ticker keeps running.
    ticks = 0

    async def ticker():
        nonlocal ticks
        while True:
            await asyncio.sleep(0.005)
            ticks += 1

    task = asyncio.create_task(ticker())
    await native.stretch("pw", "salt", 400_000)
    task.cancel()
    assert ticks >= 3, f"the event loop was blocked ({ticks} ticks)"

    srv = await server.serve(port=0)
    port = srv.sockets[0].getsockname()[1]
    async with srv:
        answers = await asyncio.gather(
            ask(port, ["primes 1000000", "stretch a b 5000"]),
            ask(port, ["stretch c d 5000", "bogus"]),
        )
    assert answers[0] == ["78498", reference("a", "b", 5000)], answers
    assert answers[1] == [reference("c", "d", 5000), "error: unknown request"], answers
    print("ok async_server")


asyncio.run(main())
