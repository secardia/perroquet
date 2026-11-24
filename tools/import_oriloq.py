#!/usr/bin/env python3
"""Import the Oriloq recordings into the Perroquet dataset (one-shot, safe to re-run).

Usage:
    python3 tools/import_oriloq.py [recordings_dir [annotations_dir [dataset_root]]]

Defaults (relative to the repo root): data/oriloq_recordings, data/oriloq_annotations,
~/Library/Application Support/Perroquet/FineTuningDataset.

Each recording folder is copied (sources are never modified) into:
  - Validated_Recordings when annotations/<id>.txt is non-empty; transcription.txt is
    overwritten with the annotation, transcription_raw.txt is left as is.
  - Rejected_Recordings when annotations/<id>.txt exists but is empty.
  - Pending_Recordings otherwise.
An id already present in any of the three folders is skipped.
"""

import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FOLDERS = ("Pending_Recordings", "Validated_Recordings", "Rejected_Recordings")


def destination(annotation: Path) -> str:
    """Return the dataset folder for a recording given its annotation file."""
    if not annotation.is_file():
        return "Pending_Recordings"
    if annotation.read_text(encoding="utf-8").strip():
        return "Validated_Recordings"
    return "Rejected_Recordings"


def import_recordings(
    recordings: Path, annotations: Path, root: Path
) -> dict[str, int]:
    """Copy every not-yet-imported recording into the dataset; return counts per destination."""
    counts = {name: 0 for name in FOLDERS}
    counts["skipped"] = 0
    for source in sorted(p for p in recordings.iterdir() if p.is_dir()):
        id_ = source.name
        if any((root / name / id_).exists() for name in FOLDERS):
            counts["skipped"] += 1
            continue
        annotation = annotations / f"{id_}.txt"
        target_name = destination(annotation)
        target_dir = root / target_name
        target_dir.mkdir(parents=True, exist_ok=True)
        temp = target_dir / f".{id_}.importing"
        if temp.exists():
            shutil.rmtree(temp)
        shutil.copytree(source, temp)
        if target_name == "Validated_Recordings":
            shutil.copyfile(annotation, temp / "transcription.txt")
        temp.rename(target_dir / id_)
        counts[target_name] += 1
    return counts


def main(argv: list[str]) -> int:
    """Parse arguments, run the import and print the summary."""
    recordings = Path(argv[1]) if len(argv) > 1 else REPO / "data" / "oriloq_recordings"
    annotations = (
        Path(argv[2]) if len(argv) > 2 else REPO / "data" / "oriloq_annotations"
    )
    root = (
        Path(argv[3])
        if len(argv) > 3
        else Path.home()
        / "Library"
        / "Application Support"
        / "Perroquet"
        / "FineTuningDataset"
    )
    if not recordings.is_dir():
        print(f"error: recordings folder not found: {recordings}", file=sys.stderr)
        return 1
    counts = import_recordings(recordings, annotations, root)
    for name in FOLDERS:
        print(f"{name}: {counts[name]}")
    print(f"skipped (already imported): {counts['skipped']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
