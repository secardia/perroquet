#!/bin/bash
# System-wide RAM cost per backend (includes ANE / GPU memory held outside the process).
cd "$(dirname "$0")"
export BENCH_NO_SAVE=1
M=.venv-mlx/bin/python; O=.venv-onnx/bin/python
S() { $M sysmem.py "$1" $M guard.py "${@:2}"; sleep 10; }
S coreml-ane-6bit   $M bench_fluid.py ane ane int8
S coreml-ane-8bit   $M bench_fluid.py ane ane int8-v2
S coreml-ane-encgpu $M bench_fluid.py ane gpu int8
S coreml-cpu        $M bench_fluid.py cpu cpu int8
S ggml-q8-metal     $M bench_nemocpp.py metal
S mlx-gpu-q8        $M bench_mlx.py gpu-q8
S mlx-gpu-q6        $M bench_mlx.py gpu-q6
S onnx-int8-cpu-t4  $O bench_onnx.py onnxasr-int8-cpu-t4
S sherpa-int8-cpu-t4 $O bench_onnx.py sherpa-int8-cpu-t4
echo ALL DONE
