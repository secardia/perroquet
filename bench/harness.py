"""Shared benchmark harness: timing, memory, WER, results file.

A backend script builds `load() -> state` and `transcribe(state, path) -> str` and calls `run(name, load, transcribe)`.
"""

import json
import os
import re
import resource
import sys
import time
import unicodedata
from pathlib import Path

import jiwer
from footprint import footprint_mb, peak_footprint_mb

ROOT = Path(__file__).parent
MANIFEST = json.loads((ROOT / "manifest.json").read_text())


def memory_mb() -> tuple[float, float]:
    """Current and lifetime-peak physical footprint of this process."""
    pid = os.getpid()
    return footprint_mb(pid), peak_footprint_mb(pid)


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFC", text.lower())
    text = text.replace("’", "'").replace("'", " ").replace("-", " ")
    text = re.sub(r"[^\w\s]", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def run(name: str, load, transcribe, limit: int | None = None) -> None:
    files = MANIFEST[:limit] if limit else MANIFEST
    mem_before, _ = memory_mb()

    t0 = time.perf_counter()
    state = load()
    load_s = time.perf_counter() - t0
    mem_loaded, _ = memory_mb()

    # Warm-up on a mid-length file (first call compiles kernels / graphs).
    warm = files[len(files) // 2]["path"]
    t0 = time.perf_counter()
    transcribe(state, warm)
    warmup_s = time.perf_counter() - t0

    rows = []
    for m in files:
        t0 = time.perf_counter()
        hyp = transcribe(state, m["path"])
        dt = time.perf_counter() - t0
        rows.append(
            {
                "id": m["id"],
                "duration": m["duration"],
                "time": dt,
                "hyp": hyp,
                "ref": m["ref"],
            }
        )
    mem_after, mem_peak = memory_mb()

    rss_peak = (
        resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 2**20
    )  # bytes on macOS
    save(
        name,
        rows,
        load_s,
        warmup_s,
        mem_before,
        mem_loaded,
        mem_after,
        mem_peak,
        rss_peak,
    )


def save(
    name, rows, load_s, warmup_s, mem_before, mem_loaded, mem_after, mem_peak, rss_peak
) -> None:
    if not rows:
        print(f"{name}: no successful rows, nothing saved")
        return
    refs = [normalize(r["ref"]) for r in rows]
    hyps = [normalize(r["hyp"]) for r in rows]
    keep = [i for i, r in enumerate(refs) if r]
    wer = (
        jiwer.wer([refs[i] for i in keep], [hyps[i] for i in keep])
        if keep
        else float("nan")
    )

    audio = sum(r["duration"] for r in rows)
    compute = sum(r["time"] for r in rows)

    def lat(lo, hi):
        ts = sorted(r["time"] for r in rows if lo <= r["duration"] < hi)
        return round(ts[len(ts) // 2] * 1000) if ts else None

    summary = {
        "backend": name,
        "files": len(rows),
        "audio_min": round(audio / 60, 1),
        "load_s": round(load_s, 2),
        "warmup_s": round(warmup_s, 2),
        "compute_s": round(compute, 1),
        "rtfx": round(audio / compute, 1),
        "p50_ms": round(sorted(r["time"] for r in rows)[len(rows) // 2] * 1000, 1),
        "p90_ms": round(
            sorted(r["time"] for r in rows)[int(len(rows) * 0.9)] * 1000, 1
        ),
        "p50_ms_<5s": lat(0, 5),
        "p50_ms_5-15s": lat(5, 15),
        "p50_ms_15-30s": lat(15, 30),
        "p50_ms_30-60s": lat(30, 60),
        "p50_ms_60s+": lat(60, 1e9),
        "wer": round(wer * 100, 1),
        "mem_baseline_mb": round(mem_before),
        "mem_loaded_mb": round(mem_loaded),
        "mem_after_mb": round(mem_after),
        "mem_peak_mb": round(mem_peak),
        "rss_peak_mb": round(rss_peak),
    }
    if os.environ.get(
        "BENCH_NO_SAVE"
    ):  # memory-only reruns (sysmem.py) must not duplicate results
        print(json.dumps(summary, indent=1))
        return
    out = ROOT / "results"
    (out / "raw").mkdir(parents=True, exist_ok=True)
    (out / "raw" / f"{name}.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=1)
    )
    with open(out / "summary.jsonl", "a") as f:
        f.write(json.dumps(summary) + "\n")
    print(json.dumps(summary, indent=1))


def args_limit(index: int = 2) -> int | None:
    return int(sys.argv[index]) if len(sys.argv) > index else None
