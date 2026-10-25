"""async_callback: an example of V calling a Python async function."""

from __future__ import annotations

import asyncio

from async_callback_native import *  # noqa: F401,F403


def make_async_fn():
    """A Python async function V will call and drive to completion."""

    async def add_one(x):
        # The await is what exercises the fast path: it completes without suspending.
        await asyncio.sleep(0)
        return x + 1

    return add_one


def demo() -> None:
    fn = make_async_fn()
    print("run_async(add_one, 41) =", run_async(fn, 41))


if __name__ == "__main__":
    demo()
