"""FluidAudio (CoreML) backend: runs the Swift binary, then scores its output.

Usage: python bench_fluid.py <units> <encoder_units> <int8|int8-v2|int4> [limit]
"""

import json
import subprocess
import sys

from harness import ROOT, save

units, enc, prec = sys.argv[1:4]
limit = sys.argv[4:5]
name = f"coreml-{units}-enc{enc}-{prec}"
out = ROOT / "results/raw" / f"{name}.swift.json"
out.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(
    [
        str(ROOT / "fluidbench/.build/release/fluidbench"),
        units,
        enc,
        prec,
        str(out),
        *limit,
    ],
    check=True,
)
d = json.loads(out.read_text())
save(
    name,
    d["rows"],
    d["load_s"],
    d["warmup_s"],
    d["mem_baseline_mb"],
    d["mem_loaded_mb"],
    d["mem_after_mb"],
    d["mem_peak_mb"],
    d["rss_peak_mb"],
)
