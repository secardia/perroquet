"""ONNX Runtime backends.

Usage: python bench_onnx.py <onnxasr|sherpa>-<fp32|int8>-<cpu|coreml>[-t<threads>] [limit]
"""

import sys

import soundfile as sf
from harness import ROOT, args_limit, run

variant = sys.argv[1]
lib, quant, provider, *rest = variant.split("-")
threads = int(rest[0][1:]) if rest else 4


def load_onnxasr():
    import onnx_asr
    import onnxruntime as rt

    opts = rt.SessionOptions()
    opts.intra_op_num_threads = threads
    providers = ["CPUExecutionProvider"]
    if provider == "coreml":
        providers = [
            (
                "CoreMLExecutionProvider",
                {"ModelFormat": "MLProgram", "MLComputeUnits": "ALL"},
            ),
            "CPUExecutionProvider",
        ]
    return onnx_asr.load_model(
        "nemo-parakeet-tdt-0.6b-v3",
        ROOT / "models/onnx",
        quantization="int8" if quant == "int8" else None,
        sess_options=opts,
        providers=providers,
    )


def transcribe_onnxasr(model, path):
    audio, sr = sf.read(path, dtype="float32")
    return model.recognize(audio, sample_rate=sr)


def load_sherpa():
    import sherpa_onnx

    d = ROOT / "models/sherpa-int8"
    return sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=str(d / "encoder.int8.onnx"),
        decoder=str(d / "decoder.int8.onnx"),
        joiner=str(d / "joiner.int8.onnx"),
        tokens=str(d / "tokens.txt"),
        model_type="nemo_transducer",
        num_threads=threads,
        provider=provider,
    )


def transcribe_sherpa(rec, path):
    audio, sr = sf.read(path, dtype="float32")
    s = rec.create_stream()
    s.accept_waveform(sr, audio)
    rec.decode_stream(s)
    return s.result.text


if lib == "sherpa":
    run(f"onnx-{variant}", load_sherpa, transcribe_sherpa, args_limit())
else:
    run(f"onnx-{variant}", load_onnxasr, transcribe_onnxasr, args_limit())
