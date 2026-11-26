"""Oriloq's running app, benchmarked through its CLI (`Oriloq transcribe`, delegated to the open app over IPC).

Oriloq must be open. The time is the app's own `processingTimeSeconds` (no IPC or process start);
wall-clock time is kept as `wall`. Memory is the app process's footprint, sampled every 100 ms
(ANE memory is not in it). Files the app fails on are counted and left out of the speed figures.
Needs to run outside the sandbox. Usage: python bench_oriloq.py [limit]
"""

import json
import subprocess
import threading
import time

from footprint import footprint_mb
from harness import MANIFEST, args_limit, save

CLI = "/Applications/Oriloq.app/Contents/MacOS/Oriloq"


def app_pid() -> int:
    out = subprocess.run(
        ["pgrep", "-x", "Oriloq"], capture_output=True, text=True, check=True
    ).stdout
    return int(out.split()[0])


def transcribe(path: str) -> tuple[str, float, float] | str:
    """Returns (text, app processing time, wall time), or the error message."""
    t0 = time.perf_counter()
    out = subprocess.run(
        [CLI, "transcribe", path, "--format", "json", "--no-corrections"],
        capture_output=True,
        check=False,
        text=True,
    )
    wall = time.perf_counter() - t0
    start = out.stdout.find("{")
    if start < 0:
        lines = (out.stdout + out.stderr).strip().splitlines()
        return lines[-1] if lines else "no output"
    result = json.loads(out.stdout[start:])
    if not result.get("success"):
        return json.dumps(result)[:200]
    return result["text"].strip(), result["metadata"]["processingTimeSeconds"], wall


def main() -> None:
    limit = args_limit(1)
    files = MANIFEST[:limit] if limit else MANIFEST
    pid = app_pid()
    mem_before = footprint_mb(pid)
    peak = [mem_before]
    stop = threading.Event()

    def sample():
        while not stop.is_set():
            peak[0] = max(peak[0], footprint_mb(pid))
            time.sleep(0.1)

    threading.Thread(target=sample, daemon=True).start()

    t0 = time.perf_counter()
    transcribe(files[0]["path"])
    warmup_s = time.perf_counter() - t0

    rows, failures = [], []
    for m in files:
        r = transcribe(m["path"])
        if isinstance(r, str):
            failures.append({"id": m["id"], "duration": m["duration"], "error": r})
            continue
        text, proc, wall = r
        rows.append(
            {
                "id": m["id"],
                "duration": m["duration"],
                "time": proc,
                "wall": wall,
                "hyp": text,
                "ref": m["ref"],
            }
        )
    stop.set()

    print(f"{len(rows)} ok, {len(failures)} failed")
    if failures:
        print(
            f"failed durations: {min(f['duration'] for f in failures):.1f}–{max(f['duration'] for f in failures):.1f} s"
        )
        print(f"first error: {failures[0]['error']}")
        ok_max = max((r["duration"] for r in rows), default=0)
        print(f"longest file that worked: {ok_max:.1f} s")
    walls = sorted(r["wall"] for r in rows)
    if walls:
        print(
            f"wall-clock p50 incl. CLI start + IPC: {walls[len(walls) // 2] * 1000:.0f} ms"
        )
    save(
        "oriloq-coreml-fr",
        rows,
        0.0,
        warmup_s,
        mem_before,
        mem_before,
        footprint_mb(pid),
        peak[0],
        peak[0],
    )


if __name__ == "__main__":
    main()
