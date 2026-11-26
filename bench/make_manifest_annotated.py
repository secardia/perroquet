"""Build manifest_annotated.json from a Validated_Recordings folder.

Usage: python make_manifest_annotated.py [recordings folder]
Schema: manifest.json's {id, path, duration, ref} plus annotated_on_raw.
"""

import json
import sys
from datetime import datetime
from pathlib import Path
from typing import TypedDict

ROOT = Path(__file__).parent
DEFAULT_SRC = (
    Path.home()
    / "Library/Application Support/Perroquet/FineTuningDataset/Validated_Recordings"
)
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
RAW_ANNOTATION_START = datetime(2026, 11, 25).timestamp()


class Row(TypedDict):
    id: str
    path: str
    duration: float
    ref: str
    annotated_on_raw: bool


rows: list[Row] = []
for d in sorted(SRC.iterdir()):
    info, ref_file = d / "infos.json", d / "transcription.txt"
    audio = next((d / n for n in ("audio.flac", "audio.wav") if (d / n).exists()), None)
    if audio is None or not info.exists() or not ref_file.exists():
        continue
    ref = ref_file.read_text().strip()
    if not ref:
        continue
    rows.append(
        {
            "id": d.name,
            "path": str(audio.resolve()),
            "duration": float(json.loads(info.read_text())["duration"]),
            "ref": ref,
            "annotated_on_raw": ref_file.stat().st_mtime >= RAW_ANNOTATION_START,
        }
    )

rows.sort(key=lambda r: r["duration"])
(ROOT / "manifest_annotated.json").write_text(
    json.dumps(rows, ensure_ascii=False, indent=1)
)
print(
    f"{len(rows)} recordings, {sum(r['duration'] for r in rows) / 60:.1f} min, "
    f"{sum(r['annotated_on_raw'] for r in rows)} annotated on raw"
)
