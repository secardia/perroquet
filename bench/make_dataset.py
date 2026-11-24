"""Pick a duration-stratified sample of recordings and convert them to 16 kHz mono WAV.

Usage: python make_dataset.py <recordings folder>
"""

import json
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent
SRC = Path(sys.argv[1])
OUT = ROOT / "data"
OUT.mkdir(exist_ok=True)
BUCKETS = [(0, 5, 40), (5, 15, 50), (15, 30, 30), (30, 60, 20), (60, 1e9, 10)]

rows = []
for d in sorted(SRC.iterdir()):
    info = d / "infos.json"
    if not info.exists():
        continue
    audio = next((d / n for n in ("audio.wav", "audio.flac") if (d / n).exists()), None)
    if audio is None:
        continue
    rows.append(
        (
            d.name,
            audio,
            json.loads(info.read_text())["duration"],
            (d / "transcription.txt").read_text().strip(),
        )
    )

random.seed(42)
manifest: list[dict] = []
for lo, hi, n in BUCKETS:
    pool = [r for r in rows if lo <= r[2] < hi and r[3]]
    for name, audio, dur, ref in random.sample(pool, min(n, len(pool))):
        wav = OUT / f"{name}.wav"
        subprocess.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-y",
                "-i",
                str(audio),
                "-ac",
                "1",
                "-ar",
                "16000",
                "-sample_fmt",
                "s16",
                str(wav),
            ],
            check=True,
        )
        manifest.append(
            {"id": name, "path": str(wav.resolve()), "duration": dur, "ref": ref}
        )

manifest.sort(key=lambda m: m["duration"])
(ROOT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
print(
    len(manifest), "files,", round(sum(m["duration"] for m in manifest) / 60, 1), "min"
)
