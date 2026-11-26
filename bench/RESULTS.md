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

## Raw vs Oriloq-cut audio (2026-11-25)

One-off check, code removed afterwards. The 2044 dictations that existed both raw and with silences cut by Oriloq were transcribed on both versions (ANE int8):
- 49% gave the same text, 85% differed by less than 10% of words, and 2.5% by more than 30%.
- On the 121 validated ones: WER 6.9% raw vs 7.3% cut. That gap is not significant, and the references had been annotated while listening to the cut audio.
- Cutting reduced compute time by a third, in proportion to the audio removed.
- On the 13 most divergent pairs, judged blind while listening to the raw audio: raw better 7 times, cut 2, equal 4. On long dictations, the cut version drifts into English mid-sentence.

Decision: the dataset now stores only raw audio. Any silence trimming is applied on the fly and benchmarked on annotated raw recordings.

## Silence trimming (VAD) (2026-11-25)

Question: does cutting silences before transcription give a lower WER than sending the whole audio, and is it worth the compute? Rule: a method is kept only if it beats full audio **significantly** in WER; otherwise the in-app trimming task is cancelled.

**Protocol**
- Set: the 184 validated recordings (46.7 min, 5688 reference words), of which 40 are annotated on raw audio (the subset where references were not made while listening to cut audio). Audio is read directly from the FLAC files.
- ASR: same settings as the app (CoreML v3, int8 encoder, `cpuAndNeuralEngine`, `language: nil`, fresh decoder state per file), warmed up once. One transcription per file per variant, 65 variants, one run.
- Methods:
  - `full`: whole audio (baseline).
  - Silero VAD (FluidAudio): model run once per file, then segmented per config; entry threshold t, exit threshold t − 0.15, `minSpeechDuration` 0.15 s, no forced split. Grid: t {0.5, 0.7, 0.85} × padding {0.1, 0.2, 0.3} × min silence {0.3, 0.75} s (18), plus 12 gentler variants (t 0.3 to 0.85, padding 0.3 to 1.0 s, min silence 0.75 to 3 s).
  - FSMN-VAD (FluidAudio, fixed decision parameters): raw segments, plus padding {0.2, 0.3, 0.5} s (4).
  - Energy gate (model-free): 30 ms frames, 10 ms hop, RMS in dBFS, noise floor = 10th percentile of the file, speech if ≥ floor + D dB. Runs closer than the min silence are merged, runs under 0.15 s dropped, then padded. Grid: D {6, 10, 15} × padding {0.1, 0.2, 0.3} × min silence {0.3, 0.75} (18), plus 12 gentler variants (D 3 to 10, padding 0.3 to 0.5, min silence 0.75 to 3).
- Splice: spans clamped and merged, joined by 150 ms of zeros, no leading or trailing silence. No span means empty text and no ASR call.
- Scoring: corpus WER and CER on normalized text (`harness.normalize`), WER split into substitutions / deletions / insertions. Significance: paired bootstrap over files (2000 resamples, seed 0, same resamples for both metrics) of WER(variant) − WER(full) and CER(variant) − CER(full); significant when the 95% CI excludes 0. Kept audio counts speech only (spliced length minus the 150 ms gaps).
- Cost: trimming cost = VAD (model + segmentation, or the energy step) + splice, per file. Net gain = ASR time of `full` − ASR time of the variant − trimming cost. Timings come from a single run; ASR time of `full` varied by about 15% between three runs (19.7 s to 22.8 s), so gains below about 10% are within noise. The reported timings come from the last run.

**Results (all 184 files, ranked by WER)**

| Variant | WER | CER | S/D/I | ΔWER [95% CI] | ΔCER [95% CI] | Kept audio | Net gain |
|---|---|---|---|---|---|---|---|
| `fsmn-pad0.5` (best FSMN) | 6.07% | 3.28% | 171/70/104 | -0.23 pt [-0.74, +0.26] | -0.15 pt [-0.45, +0.14] | 78.0% | +16.9% |
| `energy-db6-pad0.5-sil1.5` (best energy) | 6.15% | 3.32% | 182/71/97 | -0.14 pt [-0.58, +0.28] | -0.11 pt [-0.36, +0.13] | 95.8% | +3.7% |
| `silero-t0.3-pad0.5-sil1.5` (best Silero) | 6.15% | 3.39% | 180/72/98 | -0.14 pt [-0.69, +0.43] | -0.05 pt [-0.35, +0.28] | 81.9% | +9.6% |
| `full` | 6.29% | 3.44% | 187/68/103 | | | 100% | 0 |
| `fsmn-pad0.3` | 6.59% | 3.59% | 202/80/93 | +0.30 pt [-0.56, +1.27] | +0.15 pt [-0.31, +0.67] | 73.0% | +20.3% |
| `silero-t0.5-pad0.1-sil0.3` (app-like defaults) | 7.65% | 4.34% | 212/115/108 | +1.35 pt [+0.21, +2.77] * | +0.90 pt [+0.14, +1.86] * | 67.0% | +21.0% |
| `fsmn` (no padding) | 8.56% | 4.74% | 254/122/111 | +2.27 pt [+0.57, +4.37] * | +1.30 pt [+0.32, +2.56] * | 62.6% | +26.1% |
| `energy-db15-pad0.1-sil0.3` (most drastic) | 15.58% | 11.89% | 275/522/89 | +9.28 pt [+6.01, +13.13] * | +8.45 pt [+5.23, +12.11] * | 53.5% | +37.1% |

\* 95% CI excludes 0 (significantly worse than `full`). Kept audio is the speech only, without the 150 ms splice gaps.

Per-method grid summary (all files): Silero, 30 variants, WER 6.15% to 8.56%, 7 under full, 6 significantly worse; FSMN, 4 variants, 6.07% to 8.56%, 1 under full, 1 significantly worse; energy, 30 variants, 6.15% to 15.58%, 4 under full, 11 significantly worse (all of D = 15 dB, which also leaves 6 to 7 files with no speech detected).

On the 40 raw-annotated files, `full` is 4.05% WER / 2.16% CER. The best variant there is `silero-t0.5-pad0.5-sil0.75` at 3.34% (-0.70 pt, CI [-2.19, +0.75]; CER -0.23 pt, CI [-0.94, +0.50]; not significant, 69.8% of audio kept); only `energy-db15-pad0.1-sil0.3` is significantly different (worse).

Compute: trimming cost per file is 0.2 to 0.3 ms for energy, about 9 ms median for Silero (model, incl. segmentation) and for FSMN, against about 55 ms median ASR per file. By duration bucket, trimming does not pay off under 5 s (net -5% for Silero, -2% for FSMN-pad0.5, +2% for energy) and loses between 5 and 15 s (-11% for both models, +1% for energy); it pays only above 15 s (+17% Silero, +27% FSMN, +5% energy). Overall net gain is +4% to +17% for the gentle variants and +21% to +37% for the drastic ones.

**Observations**
- No variant beats full audio significantly. The best ones (padding 0.5 s) sit 0.1 to 0.25 pt under `full`, with CIs that comfortably include 0; that is noise at 5688 words.
- Quality loss is monotonic with how much is cut: wider padding and longer min silence recover WER. Errors from aggressive cuts are mostly **deletions** (clipped words: `silero-t0.5-pad0.1-sil0.3` 115 vs 68 for full; energy 15 dB 522), with substitutions growing second; insertions stay flat (about 90 to 110), so trimming does not remove hallucinations in silences here.
- Large padding (0.5 s) makes all three methods safe but then they keep 78% (FSMN), 82% (Silero) and 96% (energy) of the audio, so the speed gain is small and is mostly lost on short dictations.
- The files that regress most (e.g. `20261125-085206`, `20260626-135147`) are repeated for all three methods: a short hesitation or an overlapping restart gets cut or merged differently.
- The earlier finding that long dictations drift into English on cut audio was not reproduced as a gain: trimming raw audio did not lower WER on the long files either.

**Decision rule outcome:** no variant is significantly better than full audio in WER or in CER (paired bootstrap on both), and several settings are significantly worse in both. Silence trimming is not kept for quality; the in-app trimming task is cancelled (at most a speed option for dictations over 15 s, with padding of 0.5 s or more, worth +17% to +27% on that bucket).

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

Silence trimming: `python3 make_manifest_annotated.py` (writes `manifest_annotated.json`), then `swift build --package-path fluidbench -c release` and `./fluidbench/.build/release/trimbench manifest_annotated.json results/raw/trim` (about 25 min, downloads the Silero and FSMN models on first run), then `.venv-onnx/bin/python bench_trim.py > report.md`.

OpenWhispr and Oriloq results come from `bench_openwhispr.py` and `bench_oriloq.py`, which need those apps running.
