"""NeMo-Speech.cpp (ggml) backend through its C API.

Usage: python bench_nemocpp.py <metal|cpu> [limit]
"""

import atexit
import ctypes as C
import sys

import soundfile as sf
from harness import ROOT, args_limit, run

device = sys.argv[1]
LIB = C.CDLL(str(ROOT / "nemo-speech-bin/lib/libnemo_speech_asr_c.1.dylib"))
MODEL = ROOT / "models/nvidia/parakeet-tdt-0.6b-v3.q8_0.gguf"


class Backend(C.Structure):
    _fields_ = [("size", C.c_size_t), ("gpu", C.c_int32)]


class Model(C.Structure):
    _fields_ = [("size", C.c_size_t), ("path", C.c_char_p), ("name", C.c_char_p)]


class RecognizerConfig(C.Structure):
    _fields_ = [
        ("size", C.c_size_t),
        ("backend", C.POINTER(Backend)),
        ("model", C.POINTER(Model)),
    ] + [
        (n, C.c_void_p)
        for n in (
            "streaming",
            "decoder",
            "vad",
            "endpointing",
            "postproc",
            "diar",
            "batching",
            "salm",
        )
    ]


class SpeechContext(C.Structure):
    _fields_ = [
        ("size", C.c_size_t),
        ("phrases", C.POINTER(C.c_char_p)),
        ("phrase_count", C.c_size_t),
        ("boost", C.c_float),
    ]


class Options(C.Structure):
    _fields_ = [
        ("size", C.c_size_t),
        ("request_id", C.c_char_p),
        ("language_code", C.c_char_p),
        ("interim_results", C.c_bool),
        ("enable_word_time_offsets", C.c_bool),
        ("enable_automatic_punctuation", C.c_bool),
        ("verbatim_transcripts", C.c_bool),
        ("profanity_filter", C.c_bool),
        ("stop_history_eou_ms", C.c_int32),
        ("speech_contexts", C.POINTER(SpeechContext)),
        ("speech_context_count", C.c_size_t),
        ("max_alternatives", C.c_int32),
        ("enable_speaker_diarization", C.c_bool),
        ("max_speaker_count", C.c_int32),
    ]


LIB.nemo_speech_asr_recognition_options_default.restype = Options
LIB.nemo_speech_asr_create.argtypes = [
    C.POINTER(RecognizerConfig),
    C.POINTER(C.c_void_p),
]
LIB.nemo_speech_asr_recognize_f32.argtypes = [
    C.c_void_p,
    C.POINTER(Options),
    C.POINTER(C.c_float),
    C.c_size_t,
    C.c_int32,
    C.POINTER(C.c_void_p),
]
LIB.nemo_speech_asr_result_transcript.restype = C.c_char_p
LIB.nemo_speech_asr_result_transcript.argtypes = [C.c_void_p, C.c_size_t]
LIB.nemo_speech_asr_result_destroy.argtypes = [C.c_void_p]
LIB.nemo_speech_asr_last_error.restype = C.c_char_p


def check(status):
    if status != 0:
        raise RuntimeError(
            f"nemo-speech error {status}: {LIB.nemo_speech_asr_last_error().decode()}"
        )


def load():
    backend = Backend(C.sizeof(Backend), 0 if device == "metal" else -1)
    model = Model(C.sizeof(Model), str(MODEL).encode(), None)
    cfg = RecognizerConfig(
        size=C.sizeof(RecognizerConfig),
        backend=C.pointer(backend),
        model=C.pointer(model),
    )
    rec = C.c_void_p()
    check(LIB.nemo_speech_asr_create(C.byref(cfg), C.byref(rec)))
    opts = LIB.nemo_speech_asr_recognition_options_default()
    atexit.register(LIB.nemo_speech_asr_destroy, rec)
    return rec, opts


def transcribe(state, path):
    rec, opts = state
    audio, sr = sf.read(path, dtype="float32")
    buf = audio.ctypes.data_as(C.POINTER(C.c_float))
    res = C.c_void_p()
    check(
        LIB.nemo_speech_asr_recognize_f32(
            rec, C.byref(opts), buf, len(audio), sr, C.byref(res)
        )
    )
    text = LIB.nemo_speech_asr_result_transcript(res, 0).decode()
    LIB.nemo_speech_asr_result_destroy(res)
    return text


run(f"nemocpp-q8-{device}", load, transcribe, args_limit())
