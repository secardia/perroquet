"""One-off: quantize the MLX weights to 8 or 6 bits and save them. Usage: python convert_mlx.py <8|6>"""

import json
import shutil
import sys
from pathlib import Path

import mlx.core as mx
from mlx import nn
from mlx.utils import tree_flatten
from parakeet_mlx import from_pretrained

ROOT = Path(__file__).parent

bits = int(sys.argv[1])
GROUP = 64
src, dst = ROOT / "models/mlx", ROOT / f"models/mlx-q{bits}"
dst.mkdir(exist_ok=True)


def quantizable(_, m):
    return isinstance(m, (nn.Linear, nn.Embedding)) and m.weight.shape[-1] % GROUP == 0


model = from_pretrained(str(src), dtype=mx.bfloat16)
nn.quantize(model, group_size=GROUP, bits=bits, class_predicate=quantizable)
mx.save_safetensors(
    str(dst / "model.safetensors"), dict(tree_flatten(model.parameters()))
)
config = json.loads((src / "config.json").read_text())
config["quantization"] = {"group_size": GROUP, "bits": bits}
(dst / "config.json").write_text(json.dumps(config))
for f in src.iterdir():
    if f.name not in ("model.safetensors", "config.json") and f.is_file():
        shutil.copy(f, dst / f.name)
print(dst, sum(f.stat().st_size for f in dst.iterdir()) // 2**20, "MB")
