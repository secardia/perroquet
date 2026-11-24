"""Run a benchmark command under a memory watchdog.

Kills the command's process group if the physical footprint (which includes GPU / unified memory)
of the command and all its descendants goes over
MAX_FOOTPRINT_MB, or if the system's free memory level drops under MIN_FREE_PERCENT.
Usage: python guard.py <cmd> [args...]
"""

import ctypes
import os
import signal
import subprocess
import sys
import time

from footprint import footprint_mb

MAX_FOOTPRINT_MB = 6144
MIN_FREE_PERCENT = 15

_libc = ctypes.CDLL("/usr/lib/libSystem.dylib")


def children(pid: int) -> list[int]:
    out = subprocess.run(
        ["pgrep", "-P", str(pid)], capture_output=True, text=True, check=False
    ).stdout
    return [int(p) for p in out.split()]


def tree_footprint_mb(pid: int) -> float:
    return footprint_mb(pid) + sum(tree_footprint_mb(c) for c in children(pid))


def free_percent() -> int:
    value = ctypes.c_int(0)
    size = ctypes.c_size_t(ctypes.sizeof(value))
    _libc.sysctlbyname(
        b"kern.memorystatus_level", ctypes.byref(value), ctypes.byref(size), None, 0
    )
    return value.value


def main() -> int:
    if free_percent() < MIN_FREE_PERCENT + 5:
        print(
            f"GUARD: only {free_percent()}% memory free before start, refusing to run",
            file=sys.stderr,
        )
        return 3
    proc = subprocess.Popen(sys.argv[1:], start_new_session=True)
    peak = 0.0
    try:
        while proc.poll() is None:
            fp = tree_footprint_mb(proc.pid)
            peak = max(peak, fp)
            free = free_percent()
            if fp > MAX_FOOTPRINT_MB or free < MIN_FREE_PERCENT:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
                print(
                    f"GUARD: killed (footprint {fp:.0f} MB, system free {free}%)",
                    file=sys.stderr,
                )
                return 2
            time.sleep(0.2)
    except KeyboardInterrupt:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        print("GUARD: interrupted, command killed", file=sys.stderr)
        return 130
    print(f"GUARD: peak footprint {peak:.0f} MB", file=sys.stderr)
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
