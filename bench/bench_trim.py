"""Score the trimbench output: WER/CER per variant vs full audio, with a paired bootstrap.

Three scorings of the same transcripts:
- normalized: lowercase, no punctuation (harness.normalize), the usual ASR metric;
- strict: raw text, punctuation marks are tokens of their own, case and punctuation count as full errors;
- lax: the strict alignment, but an error that only differs by case or punctuation weighs 0.5.

Usage: python bench_trim.py [results dir (default results/raw/trim)]
Prints markdown tables to stdout.
"""

import json
import re
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path

import jiwer
import numpy as np
from harness import normalize

ROOT = Path(__file__).parent
RESAMPLES, SEED = 2000, 0
SPLICE_GAP_S = 0.15
METHODS = ("silero", "fsmn", "energy")
MINOR_WEIGHT = 0.5
STRICT_KEYS = ("wer_strict", "cer_strict", "wer_lax", "cer_lax")


def strict_tokens(text: str) -> list[str]:
    """Words and punctuation marks as separate tokens, case kept."""
    return re.findall(r"\w+|[^\w\s]", unicodedata.normalize("NFC", text.replace("’", "'")))


def is_punct(token: str) -> bool:
    return not re.search(r"\w", token)


def minor_sub(r: str, h: str) -> bool:
    """A substitution that only changes case or punctuation."""
    return r.lower() == h.lower() or (is_punct(r) and is_punct(h))


def strict_and_lax(ref: list[str], hyp: list[str]) -> tuple[int, float]:
    """(strict errors, lax errors) of hyp against ref, from one Levenshtein alignment over the tokens."""
    if not hyp:
        return len(ref), sum(MINOR_WEIGHT if is_punct(t) else 1 for t in ref)
    # jiwer splits on spaces: tokens never contain one, chars are mapped to a placeholder.
    enc = lambda ts: " ".join(t if t != " " else "\u2581" for t in ts)
    out = jiwer.process_words(enc(ref), enc(hyp))
    r, h = out.references[0], out.hypotheses[0]
    strict, lax = 0, 0.0
    for c in out.alignments[0]:
        if c.type == "equal":
            continue
        if c.type == "substitute":
            for a, b in zip(r[c.ref_start_idx : c.ref_end_idx], h[c.hyp_start_idx : c.hyp_end_idx]):
                strict += 1
                lax += MINOR_WEIGHT if minor_sub(a, b) else 1
        else:
            span = r[c.ref_start_idx : c.ref_end_idx] if c.type == "delete" else h[c.hyp_start_idx : c.hyp_end_idx]
            for t in span:
                strict += 1
                lax += MINOR_WEIGHT if is_punct(t) else 1
    return strict, lax


def strict_scores(ref_text: str, hyp_text: str) -> tuple[dict[str, float], dict[str, int]]:
    """Strict and lax word and character errors, with their reference sizes."""
    ref_words, hyp_words = strict_tokens(ref_text), strict_tokens(hyp_text)
    ref_chars = list(unicodedata.normalize("NFC", ref_text.strip().replace("’", "'")))
    hyp_chars = list(unicodedata.normalize("NFC", hyp_text.strip().replace("’", "'")))
    ws, wl = strict_and_lax(ref_words, hyp_words)
    cs, cl = strict_and_lax(ref_chars, hyp_chars)
    errs = {"wer_strict": ws, "wer_lax": wl, "cer_strict": cs, "cer_lax": cl}
    refs = {"wer_strict": len(ref_words), "wer_lax": len(ref_words), "cer_strict": len(ref_chars), "cer_lax": len(ref_chars)}
    return errs, refs


@dataclass
class FileScore:
    """One file transcribed by one variant: word and character error counts against its reference."""

    sub: int
    dele: int
    ins: int
    wref: int
    cerr: int
    cref: int
    trim: float
    hyp: str
    ref: str
    duration: float
    kept: float
    segments: int
    time: float
    raw: bool
    errs: dict[str, float]
    refs: dict[str, int]

    @property
    def werr(self) -> int:
        return self.sub + self.dele + self.ins


def speech_only_kept(row: dict) -> float:
    """kept_s without the 150 ms splice gaps (older result files counted them)."""
    if row["segments"] == 0:
        return 0.0
    if row.get("speech_only_kept"):
        return row["kept_s"]
    return row["kept_s"] - SPLICE_GAP_S * (row["segments"] - 1)


def score_file(row: dict, ref: str, hyp: str) -> FileScore:
    words = jiwer.process_words(ref, hyp) if hyp else None
    chars = jiwer.process_characters(ref, hyp) if hyp else None
    n_words = len(ref.split())
    errs, refs = strict_scores(row["ref"], row["hyp"])
    return FileScore(
        sub=words.substitutions if words else 0,
        dele=words.deletions if words else n_words,
        ins=words.insertions if words else 0,
        wref=n_words,
        cerr=chars.substitutions + chars.deletions + chars.insertions
        if chars
        else len(ref),
        cref=len(ref),
        trim=row.get("vad_time", 0.0) + row.get("splice_time", 0.0),
        hyp=row["hyp"],
        ref=row["ref"],
        duration=row["duration"],
        kept=speech_only_kept(row),
        segments=row["segments"],
        time=row["time"],
        raw=row.get("annotated_on_raw", False),
        errs=errs,
        refs=refs,
    )


def per_file(rows: list[dict]) -> dict[str, FileScore]:
    """id -> scores, skipping empty normalized references (same rule as harness.save)."""
    out = {}
    for row in rows:
        ref = normalize(row["ref"])
        if ref:
            out[row["id"]] = score_file(row, ref, normalize(row["hyp"]))
    return out


def bootstrap(
    var: list[FileScore], full: list[FileScore]
) -> dict[str, tuple[float, float, float]]:
    """Paired bootstrap over files (same resamples for both metrics): metric(variant) - metric(full)."""
    idx = np.random.default_rng(SEED).integers(0, len(full), (RESAMPLES, len(full)))
    out = {}
    metrics = [
        ("wer", lambda f: f.werr, lambda f: f.wref),
        ("cer", lambda f: f.cerr, lambda f: f.cref),
    ] + [(k, lambda f, k=k: f.errs[k], lambda f, k=k: f.refs[k]) for k in STRICT_KEYS]
    for kind, err, ref in metrics:
        ve, fe = np.array([err(f) for f in var]), np.array([err(f) for f in full])
        refs = np.array([ref(f) for f in full])
        deltas = (ve[idx].sum(1) - fe[idx].sum(1)) / refs[idx].sum(1)
        lo, hi = np.percentile(deltas, [2.5, 97.5])
        out[kind] = ((ve.sum() - fe.sum()) / refs.sum(), lo, hi)
    return out


def median_ms(xs) -> float:
    return float(np.median(xs)) * 1000


def summarize(files: list[FileScore], full: list[FileScore]) -> dict:
    boot = bootstrap(files, full)
    full_time = sum(f.time for f in full)
    net = [g.time - f.time - f.trim for f, g in zip(files, full)]
    return {
        "sub": sum(f.sub for f in files),
        "del": sum(f.dele for f in files),
        "ins": sum(f.ins for f in files),
        "trim_total": sum(f.trim for f in files),
        "trim_med": median_ms([f.trim for f in files]),
        "net_total": sum(net),
        "net_pct": sum(net) / full_time,
        "net_med": median_ms(net),
        "asr_med": median_ms([f.time for f in files]),
        "asr_pct": sum(f.time for f in files) / full_time,
        "wer": sum(f.werr for f in files) / sum(f.wref for f in files),
        "cer": sum(f.cerr for f in files) / sum(f.cref for f in files),
        **{k: sum(f.errs[k] for f in files) / sum(f.refs[k] for f in files) for k in STRICT_KEYS},
        "boot": boot,
        "sig": {k: lo > 0 or hi < 0 for k, (_, lo, hi) in boot.items()},
        "kept": sum(f.kept for f in files) / sum(f.duration for f in files),
        "nospeech": sum(f.segments == 0 for f in files),
        "time": sum(f.time for f in files),
    }


def delta_cell(boot: tuple[float, float, float], significant: bool) -> str:
    d, lo, hi = boot
    return f"{d * 100:+.2f} pt [{lo * 100:+.2f}, {hi * 100:+.2f}]{' *' if significant else ''}"


def table(
    title: str, names: list[str], data: dict[str, dict[str, FileScore]], subset
) -> None:
    ids = [i for i, f in data["full"].items() if subset(f)]
    full = [data["full"][i] for i in ids]
    stats = {n: summarize([data[n][i] for i in ids], full) for n in names}
    print(
        f"\n### {title} ({len(ids)} files, {sum(f.wref for f in full)} reference words)\n"
    )
    print("(* = 95% CI excludes 0)\n")
    print(
        "| Variant | WER | CER | S/D/I | ΔWER vs full [95% CI] | ΔCER vs full [95% CI] | Kept audio | No speech |"
    )
    print("|---|---|---|---|---|---|---|---|")
    ranked = sorted(names, key=lambda n: (stats[n]["wer"], stats[n]["cer"]))
    for n in ranked:
        s = stats[n]
        print(
            f"| {n} | {s['wer']:.2%} | {s['cer']:.2%} | {s['sub']}/{s['del']}/{s['ins']} "
            f"| {delta_cell(s['boot']['wer'], s['sig']['wer'])} | {delta_cell(s['boot']['cer'], s['sig']['cer'])} "
            f"| {s['kept']:.1%} | {s['nospeech']} |"
        )
    print("\nStrict (case and punctuation count) and lax (a case or punctuation error weighs 0.5):\n")
    print(
        "| Variant | WER strict | ΔWER strict [95% CI] | WER lax | ΔWER lax [95% CI] "
        "| CER strict | ΔCER strict [95% CI] | CER lax | ΔCER lax [95% CI] |"
    )
    print("|---|---|---|---|---|---|---|---|---|")
    for n in sorted(names, key=lambda n: stats[n]["wer_lax"]):
        s = stats[n]
        cells = [f"{s[k]:.2%} | {delta_cell(s['boot'][k], s['sig'][k])}" for k in ("wer_strict", "wer_lax", "cer_strict", "cer_lax")]
        print(f"| {n} | " + " | ".join(cells) + " |")
    print(
        "\n| Variant | ASR total (% of full) | ASR median/file | Trim cost total | Trim median/file "
        "| Net gain total (% of full) | Net median/file |"
    )
    print("|---|---|---|---|---|---|---|")
    for n in ranked:
        s = stats[n]
        print(
            f"| {n} | {s['time']:.1f} s ({s['asr_pct']:.0%}) | {s['asr_med']:.0f} ms "
            f"| {s['trim_total']:.2f} s | {s['trim_med']:.1f} ms "
            f"| {s['net_total']:+.1f} s ({s['net_pct']:+.1%}) | {s['net_med']:+.0f} ms |"
        )


def buckets(names: list[str], data: dict[str, dict[str, FileScore]]) -> None:
    print("\n### ASR time and net gain by duration bucket (all files)\n")
    print("| Variant | < 5 s | 5-15 s | > 15 s |")
    print("|---|---|---|---|")
    edges = [(0, 5), (5, 15), (15, float("inf"))]
    for n in names:
        cells = []
        for lo, hi in edges:
            ids = [i for i, f in data["full"].items() if lo <= f.duration < hi]
            full_t = sum(data["full"][i].time for i in ids)
            if not ids or full_t == 0:
                cells.append("-")
                continue
            asr = sum(data[n][i].time for i in ids)
            net = full_t - asr - sum(data[n][i].trim for i in ids)
            cells.append(f"{asr / full_t:.0%} ASR, net {net / full_t:+.0%}")
        print(f"| {n} | " + " | ".join(cells) + " |")


def show(label: str, variant: str, data: dict[str, dict[str, FileScore]], key) -> None:
    full = data["full"]
    ids = sorted(full, key=lambda i: key(data[variant][i], full[i]), reverse=True)[:5]
    print(f"\n#### {label}\n")
    print("| id | duration | ref | full hyp | variant hyp |")
    print("|---|---|---|---|---|")
    for i in ids:
        print(
            f"| {i[:15]} | {full[i].duration:.1f} s | {full[i].ref} | {full[i].hyp} | {data[variant][i].hyp} |"
        )


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results/raw/trim"
    data = {
        p.stem: per_file(json.loads(p.read_text())) for p in sorted(src.glob("*.json"))
    }
    names = sorted(data)
    table("All files", names, data, lambda f: True)
    table("Annotated on raw only", names, data, lambda f: f.raw)

    ids = list(data["full"])
    full = [data["full"][i] for i in ids]
    stats = {n: summarize([data[n][i] for i in ids], full) for n in names}
    best = {
        m: min(
            (n for n in names if n.split("-")[0] == m),
            key=lambda n: (stats[n]["wer"], stats[n]["cer"]),
        )
        for m in METHODS
    }
    print(f"\nBest per method (all files): {best}")
    padded = [n for n in names if n.startswith("full-sil")]
    buckets(["full", *padded, *best.values()], data)
    top = min(
        (n for n in names if n != "full"),
        key=lambda n: (stats[n]["wer"], stats[n]["cer"]),
    )
    show(
        f"Largest divergences, {top} vs full",
        top,
        data,
        lambda v, f: abs(v.werr - f.werr),
    )
    for n in best.values():
        show(f"Worst regressions of {n} vs full", n, data, lambda v, f: v.werr - f.werr)


if __name__ == "__main__":
    main()
