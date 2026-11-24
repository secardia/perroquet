"""parakeet-mlx backend, quantized weights. Usage: python bench_mlx.py <gpu|cpu>-q<8|6>[-beam] [limit]

Weights come from convert_mlx.py. The MLX buffer cache is capped: uncapped, it kept every
audio length's buffers and reached ~12 GB.
"""

import json
import sys

import mlx.core as mx
import soundfile as sf
from harness import ROOT, args_limit, run
from mlx import nn
from parakeet_mlx.audio import get_logmel
from parakeet_mlx.parakeet import Beam, DecodingConfig, Greedy
from parakeet_mlx.utils import from_config

variant = sys.argv[1]
device, quant, *rest = variant.split("-")
mx.set_default_device(mx.gpu if device == "gpu" else mx.cpu)
mx.set_cache_limit(256 * 2**20)
config = DecodingConfig(decoding=Beam() if "beam" in rest else Greedy())
MODEL = ROOT / f"models/mlx-{quant}"


def load():
    cfg = json.loads((MODEL / "config.json").read_text())
    q = cfg["quantization"]
    model = from_config(cfg)
    model.set_dtype(mx.bfloat16)
    nn.quantize(
        model,
        group_size=q["group_size"],
        bits=q["bits"],
        class_predicate=lambda _, m: (
            isinstance(m, (nn.Linear, nn.Embedding))
            and m.weight.shape[-1] % q["group_size"] == 0
        ),
    )
    model.load_weights(str(MODEL / "model.safetensors"))
    mx.eval(model.parameters())
    return model


def transcribe(model, path):
    audio, _ = sf.read(path, dtype="float32")
    mel = get_logmel(mx.array(audio), model.preprocessor_config)
    text = model.generate(mel, decoding_config=config)[0].text
    return text


run(f"mlx-{variant}", load, transcribe, args_limit())
