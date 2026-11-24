"""Physical memory footprint of a process (includes Metal / unified memory), read through libSystem."""

import ctypes

_libc = ctypes.CDLL("/usr/lib/libSystem.dylib")
_RUSAGE_INFO_V4 = 4
_PHYS_FOOTPRINT = 7
_LIFETIME_MAX_PHYS_FOOTPRINT = 28


def _rusage(pid: int) -> "ctypes.Array[ctypes.c_uint64] | None":
    buf = (ctypes.c_uint64 * 64)()
    if (
        _libc.proc_pid_rusage(ctypes.c_int(pid), _RUSAGE_INFO_V4, ctypes.byref(buf))
        != 0
    ):
        return None
    return buf


def footprint_mb(pid: int) -> float:
    buf = _rusage(pid)
    # buf[0:2] is the 16-byte uuid; the uint64 fields start at index 2.
    return buf[2 + _PHYS_FOOTPRINT] / 2**20 if buf else 0.0


def peak_footprint_mb(pid: int) -> float:
    buf = _rusage(pid)
    return buf[2 + _LIFETIME_MAX_PHYS_FOOTPRINT] / 2**20 if buf else 0.0
