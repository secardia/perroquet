"""OpenWhispr's running sherpa-onnx server (sherpa-onnx-ws on port 6006), benchmarked as-is.

OpenWhispr must be running with its Parakeet model. Each file goes over the local websocket,
so the latency is the one OpenWhispr sees. Memory is the server process's footprint, sampled
every 100 ms. Needs to run outside the sandbox (it reads another process's memory).
Usage: python bench_openwhispr.py [limit]
"""

import asyncio
import json
import struct
import subprocess
import threading
import time

import soundfile as sf
import websockets
from footprint import footprint_mb
from harness import MANIFEST, args_limit, save

URL = "ws://127.0.0.1:6006"


def server_pid() -> int:
    return int(
        subprocess.run(
            ["pgrep", "-f", "sherpa-onnx-ws"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.split()[0]
    )


async def _send(path: str) -> str:
    audio, sr = sf.read(path, dtype="float32")
    async with websockets.connect(URL, max_size=None) as ws:
        await ws.send(struct.pack("<ii", sr, audio.nbytes) + audio.tobytes())
        result = json.loads(await ws.recv())
        await ws.send("Done")
    return result["text"]


def transcribe(path: str) -> str:
    return asyncio.run(_send(path))


def main() -> None:
    limit = args_limit(1)
    files = MANIFEST[:limit] if limit else MANIFEST
    pid = server_pid()
    mem_before = footprint_mb(pid)

    peak = [mem_before]
    stop = threading.Event()

    def sample():
        while not stop.is_set():
            peak[0] = max(peak[0], footprint_mb(pid))
            time.sleep(0.1)

    threading.Thread(target=sample, daemon=True).start()

    t0 = time.perf_counter()
    transcribe(files[len(files) // 2]["path"])
    warmup_s = time.perf_counter() - t0

    rows = []
    for m in files:
        t0 = time.perf_counter()
        hyp = transcribe(m["path"])
        rows.append(
            {
                "id": m["id"],
                "duration": m["duration"],
                "time": time.perf_counter() - t0,
                "hyp": hyp,
                "ref": m["ref"],
            }
        )
    stop.set()
    mem_after = footprint_mb(pid)
    save(
        "openwhispr-sherpa-ws",
        rows,
        0.0,
        warmup_s,
        mem_before,
        mem_before,
        mem_after,
        peak[0],
        peak[0],
    )


if __name__ == "__main__":
    main()
