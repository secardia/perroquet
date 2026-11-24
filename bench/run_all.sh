#!/bin/sh
# Speed benchmark, 8-bit / 6-bit variants only. One run at a time, each under the memory guard.
# Results: results/summary.jsonl, logs: results/logs/
cd "$(dirname "$0")"
mkdir -p results/logs
M=.venv-mlx/bin/python; O=.venv-onnx/bin/python
R() {
  echo "=== $*"
  log="results/logs/$(echo "$*" | tr ' /' '__').log"
  $M guard.py "$@" > "$log" 2>&1 || echo "FAILED: $* ($(grep GUARD "$log" | tail -1))"
  sleep 5
}
# ggml q8 (official NVIDIA GGUF)
R $M bench_nemocpp.py metal
for t in 1 2 4 6 10; do R $M bench_nemocpp_cli.py $t; done
# CoreML (FluidAudio): Encoder = 6-bit palettized, Encoder_v2 = int8
R $M bench_fluid.py ane ane int8
R $M bench_fluid.py ane gpu int8
R $M bench_fluid.py all all int8
R $M bench_fluid.py ane ane int8-v2
R $M bench_fluid.py cpu cpu int8
# MLX, quantized
R $M bench_mlx.py gpu-q8
R $M bench_mlx.py gpu-q6
R $M bench_mlx.py gpu-q8-beam
R $M bench_mlx.py cpu-q8
# ONNX Runtime int8
for t in 1 2 4 6 10; do R $O bench_onnx.py onnxasr-int8-cpu-t$t; done
R $O bench_onnx.py onnxasr-int8-coreml
for t in 1 2 4 6 10; do R $O bench_onnx.py sherpa-int8-cpu-t$t; done
echo ALL DONE
