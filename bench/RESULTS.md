# Parakeet TDT 0.6B v3: speed benchmark on this Mac

- **Machine:** MacBook Pro M5 (4 performance + 6 efficiency cores, 10-core GPU), 16 GB, macOS 27.0.
- **Model:** `nvidia/parakeet-tdt-0.6b-v3`, 8-bit or 6-bit weights only.
- **Audio:** 150 French dictation recordings from `Oriloq/FineTuningDataset/Pending_Recordings` (47.5 min in total; 40 shorter than 5 s, 50 of 5–15 s, 30 of 15–30 s, 20 of 30–60 s, 10 longer than 60 s, the longest 190 s). Each file is transcribed in a single call.
- **Method:**
  - Runs one at a time, under a memory guard (`guard.py`), with Docker, OpenWhispr and Cursor closed.
  - The model is loaded and warmed up first; only the transcription time is measured. The Swift (FluidAudio) backend excludes the audio file read from that time; the Python backends include `sf.read`.
- **Scope:** speed only. Quality is studied separately.

## Speed

**RTFx** is how many times faster than real time (audio duration ÷ compute time). **Latency** is the median time per file.

| Runtime | Weights | Hardware | RTFx | Median latency | Latency, files < 5 s | Latency, files 5–15 s | Latency, files > 60 s |
|---|---|---|---|---|---|---|---|
| **CoreML (FluidAudio)** | 6-bit encoder | **ANE** | **162** | **56 ms** | **39 ms** | **49 ms** | **348 ms** |
| CoreML (FluidAudio) | 8-bit encoder | ANE | 161 | 56 ms | 38 ms | 50 ms | 341 ms |
| CoreML (FluidAudio) | 6-bit | CoreML `.all` (picks the ANE) | 162 | 56 ms | 39 ms | 50 ms | 350 ms |
| CoreML (FluidAudio) | 6-bit | encoder on GPU, rest on ANE | 143 | 61 ms | 43 ms | 54 ms | 415 ms |
| ggml (NeMo-Speech.cpp) | q8 GGUF (official NVIDIA file) | Metal GPU | 93 | 92 ms | 50 ms | 77 ms | 795 ms |
| MLX (parakeet-mlx) | q8 | GPU | 91 | 128 ms | 61 ms | 105 ms | 734 ms |
| MLX (parakeet-mlx) | q6 | GPU | 91 | 128 ms | 61 ms | 105 ms | 734 ms |
| MLX, beam search | q8 | GPU | 27 | 391 ms | 152 ms | 309 ms | 2.7 s |
| ONNX Runtime (onnx-asr) | int8 | CPU, 4 threads | 55 | 156 ms | 68 ms | 128 ms | 1.4 s |
| sherpa-onnx (OpenWhispr's engine) | int8 | CPU, 4 threads | 40 | 230 ms | 90 ms | 184 ms | 1.8 s |
| OpenWhispr's running server (`sherpa-onnx-ws`, over its websocket) | int8 | CPU, 4 threads | 38 | 212 ms | 83 ms | 173 ms | 2.1 s |
| CoreML (FluidAudio) | 6-bit | CPU only | 47 | 192 ms | 176 ms | 187 ms | 1.2 s |
| ggml (NeMo-Speech.cpp) | q8 | CPU, 4 threads (CLI; throughput only) | 37 | — | — | — | — |

`results/summary.jsonl` holds one summary per backend run, including latency by duration bucket. Per-file rows are in `results/raw/` (local, git-ignored).

### Oriloq (running app)

Oriloq runs its own French fine-tune of Parakeet v3 (`NeoRoth/oriloq-asr-fr-coreml`, release `qat-20261006-e11`). Its encoder is CoreML with int8 per-channel weights, run on the ANE. `bench_oriloq.py` drives the open app through its CLI (`Oriloq transcribe`, which hands the file to the running app) and uses the app's own processing time.

- **Only files under 5 s work.** The installed encoder takes a fixed 5 s window (128 × 501 mel frames). For a longer file the app pads to 1501 frames, and CoreML rejects it (`MultiArray shape (1 x 128 x 1501) does not match … (1 x 128 x 501)`). This failed on all 110 files of 5 s or more. The release metadata lists 501/1501/3001 buckets, but only 501 is in the installed model.
- **Clips under 5 s (40 files):**

| Runtime | Median latency |
|---|---|
| CoreML (FluidAudio), base model, ANE | **39 ms** |
| MLX q8, base model, GPU | 61 ms |
| **Oriloq**, French fine-tune, ANE | 70 ms |
| OpenWhispr's server (sherpa-onnx), base model, CPU | 83 ms |

The CLI adds about 100 ms on top (168 ms wall-clock median, including the process start and IPC). The app process grew from 216 MB to 309 MB; the ANE's memory is not included.

**Where Oriloq spends its time** (6 s `sample` profile, about 33 clips):
- The encoder is a multi-function CoreML model (`bucket_501`, `bucket_1501`, `bucket_3001`). The CLI only ever uses the default function, `bucket_501`; that is the cause of the failures above.
- The ANE encoder call is short: about 8 ms per clip.
- The decoder (2-layer LSTM predictor and joint network) is not CoreML. It is `predictor_joint.safetensors`, in fp32, run on the CPU through Accelerate's BLAS. BLAS takes 88% of the busy CPU samples, much of it on several threads stopped at the same instruction, which looks like worker threads spin-waiting on matrices too small to split.
- FluidAudio runs its decoder and joint as CoreML models, which likely explains most of the 70 ms vs 39 ms gap.

**About the `wer` field in the results:** the references are not ground truth. All 150 `transcription.txt` files are identical to `transcription_raw.txt`, Oriloq's own raw output (from an older revision of `NeoRoth/oriloq-asr-fr-coreml`), and `Validated_Recordings` is empty. The `wer` values only measure how far each runtime is from Oriloq's earlier output.

### CPU thread sweep (RTFx)

| Threads | 1 | 2 | 4 | 6 | 10 |
|---|---|---|---|---|---|
| ONNX int8 (onnx-asr) | 20 | 36 | **55** | 57 | 57 |
| sherpa-onnx int8 | 19 | 30 | **40** | 40 | 36 |
| ggml q8 (CPU) | 29 | 33 | **37** | 35 | 31 |

Four threads, one per performance core, is the sweet spot. Beyond that, the efficiency cores add almost nothing, and ggml even slows down.

## RAM

Two measurements, because part of the memory lives outside the process:
- **Process:** the process's peak physical footprint (it includes the GPU memory MLX and ggml allocate).
- **System:** the peak increase in system-wide used memory (anonymous + wired + compressed pages) during the run, against a 3 s baseline taken before it. This is the only way to see memory held by the ANE.

| Runtime | Process peak | System peak increase |
|---|---|---|
| CoreML 6-bit, ANE | 173 MB | **~730 MB** |
| CoreML 8-bit, ANE | 173 MB | ~830 MB |
| CoreML 6-bit, CPU only | 353 MB | ~470 MB |
| CoreML 6-bit, encoder on GPU | 817 MB | ~2.2 GB |
| ggml q8, Metal | 567 MB | ~2.6 GB |
| MLX q8 / q6, GPU (cache capped at 256 MB) | 3.5–3.6 GB | ~3.5 GB |
| ONNX int8, CPU | 4.1 GB | ~3.6 GB |
| sherpa-onnx int8, CPU | 4.9 GB | ~4.2 GB |

The peaks come from the longest recordings (up to 190 s): attention memory grows with audio length. With short dictation fragments they will be much lower.

**OpenWhispr's own sherpa server uses less.** OpenWhispr runs `sherpa-onnx-ws`, a C++ build on ONNX Runtime 1.23.2 with a different int8 encoder file. Its footprint grows with the longest clip it has transcribed so far, and it does not shrink afterwards:

| Longest clip so far | idle | 10 s | 30 s | 61 s | 95 s | 187 s |
|---|---|---|---|---|---|---|
| OpenWhispr `sherpa-onnx-ws` footprint | 751 MB | 820 MB | 1.0 GB | 1.4 GB | 1.8 GB | 3.0 GB |

After the full 150-file benchmark (`bench_openwhispr.py`), the server held 4.4 GB, and kept it. Memory is only returned when OpenWhispr restarts.

The Python wheel used in this benchmark (sherpa-onnx 2.0.1) already takes 1.8 GB right after loading, so its RAM figures above overstate what sherpa-onnx itself needs by about 1 GB.

## Findings

1. **CoreML on the ANE is the fastest and uses the least memory:** 162× real time, 39 ms for a clip under 5 s, about 730 MB in total, and the GPU stays free.
2. **6-bit and 8-bit run at the same speed** on the ANE, GPU and MLX. The encoder is compute-bound, so precision only matters for quality.
3. **The GPU loses to the ANE on this M5.** Moving the CoreML encoder to the GPU is 12% slower, and ggml Metal and MLX reach about 90× real time.
4. **The CPU is 3–4× slower than the ANE**, even at its best thread count (4).
5. **Beam search, which in-decoder vocabulary biasing needs, costs 3–4× in speed** (MLX: 152 ms instead of 61 ms on short clips). This matters for the custom-vocabulary feature.
6. **Variants that did not work:**
   - MLX on CPU in q8: the process dies with no error.
   - ONNX Runtime with the CoreML provider: it does not support the int8 model and fails at initialization.
7. **A first run with fp32/fp16 MLX froze the Mac.** MLX's GPU buffer cache grew to about 12 GB. Any MLX use needs `mx.set_cache_limit`.

## Reproduce

Setup (everything below is git-ignored; run from `bench/`):

1. **Dataset:** `python3 make_dataset.py <recordings folder>` (needs `ffmpeg`). Each subfolder holds `audio.wav` or `audio.flac`, `infos.json` and `transcription.txt`; it writes `data/` and `manifest.json`.
2. **Models** with `./dl.sh <HF repo> <dest> [exclude regex]` (stdlib only, needs `curl` and `python3`). The repo names are inferred from the model READMEs, so check them if a download fails:
   - `FluidInference/parakeet-tdt-0.6b-v3-coreml` into `models/coreml`
   - `mlx-community/parakeet-tdt-0.6b-v3` into `models/mlx`; then `python convert_mlx.py 8` and `python convert_mlx.py 6` create `models/mlx-q8` and `models/mlx-q6`
   - `nvidia/parakeet-tdt-0.6b-v3` into `models/nvidia` (provides the q8 GGUF)
   - the onnx-asr export (`models/onnx`) and the sherpa-onnx int8 export (`models/sherpa-int8`)
3. **Python venvs:** `.venv-mlx` (`mlx` 0.32.4, `parakeet-mlx` 0.7.0, `jiwer` 4.0.0, `soundfile` 0.14.0, `numpy` 2.5.5) and `.venv-onnx` (`onnx-asr` 0.12.0, `onnxruntime` 1.32.0, `sherpa-onnx` 2.0.1, `websockets` 17.4, `jiwer`, `soundfile`, `numpy`). `.venv-torch` (`torch` 2.15.0) and `.venv-dl` (`huggingface_hub` 2.4.0) are only for the unused torch backend and downloads.
4. **FluidAudio:** a checkout of FluidAudio 0.5.1 (github.com/FluidInference/FluidAudio) in `fluidaudio-src/`, then `cd fluidbench && swift build -c release`.
5. **NeMo-Speech.cpp:** version 0.3.0 (github.com/NVIDIA/NeMo-Speech.cpp). Sources in `nemo-speech-cpp/`; its install script (`scripts/install.sh`) provides the prebuilt CLI and library in `nemo-speech-bin/` (`bin/nemo-speech`).

Then:

```bash
./run_all.sh      # speed, every variant
./run_sysmem.sh   # system-wide RAM
```

OpenWhispr and Oriloq results come from `bench_openwhispr.py` and `bench_oriloq.py`, which need those apps running.
