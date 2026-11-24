"""NeMo-Speech.cpp CPU thread sweep through the CLI (the C API has no thread setting).

Transcribes the whole data/ folder in one process; per-file compute = (total - load) where load is
measured by a run on a single file. Usage: python bench_nemocpp_cli.py <threads>
"""

import json
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from harness import MANIFEST, ROOT

threads = sys.argv[1]
BIN = ROOT / "nemo-speech-bin/bin/nemo-speech"
MODEL = ROOT / "models/nvidia/parakeet-tdt-0.6b-v3.q8_0.gguf"


def _time_mb(stderr: str, label: str) -> float:
    match = re.search(rf"(\d+)\s+{label}", stderr)
    if match is None:
        raise RuntimeError(f"/usr/bin/time output has no '{label}' line")
    return int(match.group(1)) / 2**20


def timed(inp):
    with tempfile.TemporaryDirectory() as out:
        cmd = [
            "/usr/bin/time",
            "-l",
            str(BIN),
            "transcribe",
            str(inp),
            "-m",
            str(MODEL),
            "--device",
            "cpu",
            "--asr.backend.threads",
            threads,
            "-c",
            "1",
            "--no-batching",
            "-f",
            "text",
            "--force",
        ]
        cmd += ["--output-dir", out] if inp.is_dir() else ["-o", f"{out}/one.txt"]
        t0 = time.perf_counter()
        p = subprocess.run(cmd, capture_output=True, text=True, check=True)
        dt = time.perf_counter() - t0
    return (
        dt,
        _time_mb(p.stderr, "peak memory footprint"),
        _time_mb(p.stderr, "maximum resident set size"),
    )


DATA = ROOT / "data"
assert {p.stem for p in DATA.glob("*.wav")} == {m["id"] for m in MANIFEST}, (
    "data/ does not match manifest.json"
)
one = Path(MANIFEST[0]["path"])
load_s, _, _ = timed(one)
total_s, peak, rss = timed(DATA)
audio = sum(m["duration"] for m in MANIFEST)
compute = total_s - load_s
summary = {
    "backend": f"nemocpp-q8-cpu-t{threads}",
    "files": len(MANIFEST),
    "load_s": round(load_s, 2),
    "compute_s": round(compute, 1),
    "rtfx": round(audio / compute, 1),
    "mem_peak_mb": round(peak),
    "rss_peak_mb": round(rss),
}
with open(ROOT / "results/summary.jsonl", "a") as f:
    f.write(json.dumps(summary) + "\n")
print(json.dumps(summary))
