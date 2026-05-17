#!/usr/bin/env python3
"""Per-seed generalization analysis for the top-3 MLP feature sets.

For each of the three best CL2-test MLPs (by distinct feature set), reads
per-seed metrics and asks: do seeds that rank higher on CL2-test also rank
higher on the aux splits (BDB2020, EGFR, MPro)?

Usage:
    uv run python scripts/seed_generalization.py
    uv run python scripts/seed_generalization.py --models-root /abs/path/to/mlps
    uv run python scripts/seed_generalization.py --top 5
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

MODELS_ROOT_DEFAULT = (
    Path(__file__).resolve().parents[2]
    / "ml-trainer" / "models" / "mlps"
)

AUX_METRICS = [
    ("BDB",  "bdb2020_pearson_r"),
    ("EGFR", "egfr_pearson_r"),
    ("MPro", "mpro_pearson_r"),
]


def spearman_rho(xs: list[float], ys: list[float]) -> float:
    """Spearman rank correlation between two equal-length lists."""
    n = len(xs)
    if n < 2:
        return float("nan")

    def rank(vals):
        order = sorted(range(n), key=lambda i: vals[i])
        r = [0.0] * n
        for rank_idx, orig_idx in enumerate(order):
            r[orig_idx] = rank_idx + 1.0
        return r

    rx = rank(xs)
    ry = rank(ys)
    d2 = sum((rx[i] - ry[i]) ** 2 for i in range(n))
    return 1.0 - 6.0 * d2 / (n * (n * n - 1))


def load_seed_metrics(fp_dir: Path) -> list[dict]:
    """Load per-seed metrics from a fingerprint directory."""
    seeds = []
    for seed_dir in sorted(fp_dir.glob("seed_*")):
        m_path = seed_dir / "metrics.json"
        if not m_path.exists():
            continue
        m = json.loads(m_path.read_text())
        seeds.append({"seed": seed_dir.name, **m})
    return seeds


def load_spec(fp_dir: Path) -> dict:
    spec_path = fp_dir / "spec.json"
    return json.loads(spec_path.read_text()) if spec_path.exists() else {}


def load_corpus(models_root: Path, standard_only: bool = True) -> list[dict]:
    """Return one record per fingerprint with aggregate CL2 and feature info."""
    records = []
    for agg_path in sorted(models_root.glob("*/aggregate.json")):
        fp = agg_path.parent.name
        spec_path = agg_path.parent / "spec.json"
        if not spec_path.exists():
            continue
        spec = json.loads(spec_path.read_text())
        agg = json.loads(agg_path.read_text())
        if standard_only and spec.get("surface_variant", "?") != "standard":
            continue
        feat_ids = frozenset(f["id"].split(".")[-1] for f in spec.get("feature_set", []))
        cl2_mean = agg.get("metrics", {}).get("test_pearson_r_mean")
        if cl2_mean is None:
            continue
        records.append({"fp": fp, "cl2_mean": cl2_mean, "feat_ids": feat_ids, "dir": agg_path.parent})
    return sorted(records, key=lambda r: r["cl2_mean"], reverse=True)


def pick_top_distinct(records: list[dict], n: int) -> list[dict]:
    """Pick the top-n records with mutually distinct feature sets."""
    chosen = []
    for r in records:
        if all(r["feat_ids"] != c["feat_ids"] for c in chosen):
            chosen.append(r)
        if len(chosen) == n:
            break
    return chosen


def print_seed_table(fp: str, seed_rows: list[dict], spec: dict) -> None:
    feat_labels = [f["id"].split(".")[-1] for f in spec.get("feature_set", [])]
    n_feats = len(feat_labels)

    print(f"\n{'═'*72}")
    print(f"  Recipe  {fp}  ({n_feats} features)")
    print(f"  Features: {', '.join(feat_labels)}")
    print(f"{'═'*72}")

    # Sort by CL2 desc, assign rank
    sorted_rows = sorted(seed_rows, key=lambda r: r.get("test_pearson_r", 0.0), reverse=True)
    for rank, row in enumerate(sorted_rows, 1):
        row["_cl2_rank"] = rank

    # Header
    aux_header = "  ".join(f"{'  '.join([label.ljust(7)])}" for label, _ in AUX_METRICS)
    print(f"  {'rank':<5}  {'seed':<9}  {'CL2test':<9}  {aux_header}")
    print(f"  {'-'*4}  {'-'*8}  {'-'*8}  " + "  ".join("-" * 7 for _ in AUX_METRICS))

    for row in sorted_rows:
        aux_vals = "  ".join(
            f"{row.get(key, float('nan')):.4f} " for _, key in AUX_METRICS
        )
        print(f"  {row['_cl2_rank']:<5}  {row['seed']:<9}  {row.get('test_pearson_r', float('nan')):.4f}   {aux_vals}")

    cl2_vals = [r.get("test_pearson_r", 0.0) for r in sorted_rows]
    print()
    for label, key in AUX_METRICS:
        aux_vals_list = [r.get(key, 0.0) for r in sorted_rows]
        rho = spearman_rho(cl2_vals, aux_vals_list)
        print(f"  Spearman rho(CL2, {label:<5}): {rho:+.3f}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--models-root", default=str(MODELS_ROOT_DEFAULT))
    ap.add_argument("--top", type=int, default=3, help="How many distinct recipes to analyze (default: 3)")
    args = ap.parse_args()

    models_root = Path(args.models_root).expanduser()
    if (models_root / "mlps").is_dir():
        models_root = models_root / "mlps"
    if not models_root.exists():
        print(f"models root not found: {models_root}", file=sys.stderr)
        sys.exit(1)

    corpus = load_corpus(models_root)
    top_recipes = pick_top_distinct(corpus, args.top)

    if not top_recipes:
        print("No recipes found.", file=sys.stderr)
        sys.exit(1)

    print(f"\nTop-{args.top} distinct-feature-set recipes (sorted by CL2-test mean)\n")
    for i, r in enumerate(top_recipes, 1):
        print(f"  {i}. {r['fp']}  CL2-mean={r['cl2_mean']:.4f}  n_feats={len(r['feat_ids'])}")

    for recipe in top_recipes:
        seed_rows = load_seed_metrics(recipe["dir"])
        spec = load_spec(recipe["dir"])
        print_seed_table(recipe["fp"], seed_rows, spec)

    print()


if __name__ == "__main__":
    main()
