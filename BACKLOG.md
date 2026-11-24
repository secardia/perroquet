# Backlog

## Transcription engine

- **Model:** [nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), run fully on-device. Pick the fastest runtime on Apple Silicon (benchmark in `bench/`).
- **No LLM rewriting:** no local LLM pass after transcription. Every correction happens at inference time.

## Custom vocabulary

- Let the user add words (names, jargon, acronyms) that are applied **at inference**: biasing during decoding (hotwords / context biasing / boosting the tokens of those words in the TDT decoder's beam search), not a post-correction.
- Check which runtime allows it: hotword support in the decoder, access to the logits of the joint network, beam search vs greedy.
- Measure the latency cost of biasing (beam search is slower than greedy).

## Fragments and latency

- **Fragment cutting:** split the audio into fragments of a few seconds while the user is still talking.
- **Smart cuts:** cut where the voice drops (falling energy, pauses, VAD), never in the middle of a word.
- **Early processing:** transcribe the first fragments of a sentence while it is still being spoken, so only the last fragment is left to process at the end.
- **Stitching:** join the fragments without duplicating or losing words at the boundaries (overlap + alignment on timestamps).
- **Context across fragments:** keep the decoder state or the previous text so the transcription stays consistent from one fragment to the next.
- **Warm model:** keep the model loaded (and warmed up) in memory to avoid the cold start on every dictation; measure the RAM cost of that.
