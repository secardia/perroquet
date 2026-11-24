"""System-wide RAM cost of a benchmark run, including memory held outside the process (ANE, GPU driver).

Samples "used" memory (anonymous + wired + compressed pages, roughly Activity Monitor's
"Memory Used") every 100 ms: 3 s before the run as a baseline, then during the run.
Reports the peak increase over the baseline. Nothing else heavy should run at the same time.

Usage: python sysmem.py <label> <cmd> [args...]
"""

import json
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

PAGE = 16384


def used_mb() -> float:
    out = subprocess.run(["vm_stat"], capture_output=True, text=True, check=True).stdout
    pages = {k: int(v) for k, v in re.findall(r"^(.+?):\s+(\d+)\.", out, re.MULTILINE)}
    used = (
        pages["Anonymous pages"]
        + pages["Pages wired down"]
        + pages["Pages occupied by compressor"]
    )
    return used * PAGE / 2**20


def main() -> None:
    label, cmd = sys.argv[1], sys.argv[2:]
    base = []
    t_end = time.time() + 3
    while time.time() < t_end:
        base.append(used_mb())
        time.sleep(0.1)
    baseline = statistics.median(base)

    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    samples = []
    while proc.poll() is None:
        samples.append(used_mb())
        time.sleep(0.1)
    after = statistics.median([used_mb() for _ in range(10)])

    result = {
        "run": label,
        "exit": proc.returncode,
        "baseline_mb": round(baseline),
        "system_peak_delta_mb": round(max(samples) - baseline) if samples else None,
        "system_p90_delta_mb": round(
            sorted(samples)[int(len(samples) * 0.9)] - baseline
        )
        if samples
        else None,
        "after_exit_delta_mb": round(after - baseline),
    }
    with open(Path(__file__).parent / "results/sysmem.jsonl", "a") as f:
        f.write(json.dumps(result) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
