"""Corpus-derived performance table with a parquet-backed cache.

Two corpora are supported, keyed by the council manifest's ``corpus`` field:

- ``mlps`` (default) — flat ``models/mlps/<fingerprint>/aggregate.json``.
- ``gnns`` — nested ``models/gnns/<config>_<variant>/<fingerprint>/aggregate.json``
  with a different aggregate schema (``metrics[k] = {mean, std, n}``
  instead of ``{key}_mean / {key}_std``).

The dashboard's "performance tile" reads ml-trainer's *corpus* directly
rather than a single council session's ``runs.jsonl``. Recomputing on
every render scans hundreds of small JSON files, so we materialize one
row per fingerprint into a parquet cache at
``models_root/<family>/.perf_cache.parquet`` and only rebuild when an
aggregate has been touched since the last write.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pandas as pd

CACHE_FILENAME = ".perf_cache.parquet"


def _read_json(path: Path) -> dict[str, Any] | None:
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def _flatten_mlp(fp_dir: Path) -> dict[str, Any] | None:
    """One row per fingerprint for the MLP corpus."""
    aggregate = _read_json(fp_dir / "aggregate.json")
    spec = _read_json(fp_dir / "spec.json")
    if aggregate is None:
        return None
    spec = spec or {}
    model = spec.get("model") or {}
    train = spec.get("train") or {}
    metrics = aggregate.get("metrics") or {}
    feature_ids = [f.get("id") for f in spec.get("feature_set", []) if f.get("id")]
    hidden = model.get("hidden")
    if isinstance(hidden, list):
        hidden_repr = "x".join(str(h) for h in hidden)
    else:
        hidden_repr = str(hidden) if hidden is not None else ""
    return {
        "fingerprint": aggregate.get("fingerprint", fp_dir.name),
        "surface": spec.get("surface_variant"),
        "model_family": model.get("family"),
        "hidden": hidden_repr,
        "num_layers": model.get("num_layers"),
        "dropout": model.get("dropout"),
        "lr": train.get("lr"),
        "n_features": len(feature_ids),
        "feature_ids": ",".join(feature_ids),
        "n_seeds": aggregate.get("n_seeds"),
        "n_seeds_succeeded": aggregate.get("n_seeds_succeeded"),
        "test_pearson_r_mean": metrics.get("test_pearson_r_mean"),
        "test_pearson_r_std": metrics.get("test_pearson_r_std"),
        "test_rmse_mean": metrics.get("test_rmse_mean"),
        "val_pearson_r_mean": metrics.get("val_pearson_r_mean"),
        "bdb2020_pearson_r_mean": metrics.get("bdb2020_pearson_r_mean"),
        "egfr_pearson_r_mean": metrics.get("egfr_pearson_r_mean"),
        "mpro_pearson_r_mean": metrics.get("mpro_pearson_r_mean"),
        "trained_at": aggregate.get("trained_at"),
    }


def _gnn_metric(aggregate_metrics: dict[str, Any], key: str, field: str) -> float | None:
    """Pull ``metrics[key][field]`` from a GNN aggregate. Returns ``None`` if absent."""
    entry = aggregate_metrics.get(key)
    if isinstance(entry, dict):
        v = entry.get(field)
        return float(v) if isinstance(v, (int, float)) else None
    return None


def _flatten_gnn(fp_dir: Path) -> dict[str, Any] | None:
    """One row per fingerprint for the GNN corpus.

    GNN spec.json has a different schema (``config``, ``hparams``, ``extras``
    with channel lists) and the aggregate stores metrics as
    ``{mean, std, n}`` per key rather than ``{key}_mean`` / ``{key}_std``.
    The output row shape mirrors :func:`_flatten_mlp` so the API + frontend
    consume both without branching.
    """
    aggregate = _read_json(fp_dir / "aggregate.json")
    spec = _read_json(fp_dir / "spec.json")
    if aggregate is None:
        return None
    spec = spec or {}
    hparams = spec.get("hparams") or {}
    extras = spec.get("extras") or {}
    metrics = aggregate.get("metrics") or {}

    # Channel taxonomy: synthesize "<substrate>:<channel>" pills so the
    # frontend's FeatureChipList renders something meaningful per recipe.
    feature_ids: list[str] = []
    substrate = extras.get("substrate") or ""
    for ch in extras.get("vertex_channels", []) or []:
        feature_ids.append(f"vtx:{ch}")
    for ch in extras.get("triangle_channels", []) or []:
        feature_ids.append(f"tri:{ch}")
    for ch in extras.get("vv_edge_channels", []) or []:
        feature_ids.append(f"vve:{ch}")
    for ch in extras.get("tt_edge_channels", []) or []:
        feature_ids.append(f"tte:{ch}")

    hidden = hparams.get("hidden")
    hidden_repr = str(hidden) if hidden is not None else ""

    return {
        "fingerprint": aggregate.get("fingerprint", fp_dir.name),
        "surface": extras.get("surface_variant"),
        "model_family": substrate,  # tri_gnn-like family is implied; substrate is the user-facing axis
        "hidden": hidden_repr,
        "num_layers": hparams.get("num_layers"),
        "dropout": hparams.get("dropout"),
        "lr": hparams.get("lr"),
        "n_features": len(feature_ids),
        "feature_ids": ",".join(feature_ids),
        "n_seeds": aggregate.get("n_seeds"),
        "n_seeds_succeeded": aggregate.get("n_seeds"),  # GNN aggregate omits a separate "succeeded" count
        "test_pearson_r_mean": _gnn_metric(metrics, "test_pearson_r", "mean"),
        "test_pearson_r_std": _gnn_metric(metrics, "test_pearson_r", "std"),
        "test_rmse_mean": _gnn_metric(metrics, "test_rmse", "mean"),
        "val_pearson_r_mean": _gnn_metric(metrics, "val_pearson_r", "mean"),
        "bdb2020_pearson_r_mean": _gnn_metric(metrics, "bdb2020_pearson_r", "mean"),
        "egfr_pearson_r_mean": _gnn_metric(metrics, "egfr_pearson_r", "mean"),
        "mpro_pearson_r_mean": _gnn_metric(metrics, "mpro_pearson_r", "mean"),
        "trained_at": aggregate.get("completed_at"),
    }


def _corpus_dir(models_root: Path, family: str) -> Path:
    # No fallback to the parent or to a sibling family — a missing
    # subdir must yield an empty corpus, not a cross-family scan that
    # mis-flattens aggregates against the wrong schema.
    return models_root / family


def _index_mtime(corpus_dir: Path) -> float:
    """Mtime of ``_index.json`` — touched by ml-trainer after every training run."""
    idx = corpus_dir / "_index.json"
    return idx.stat().st_mtime if idx.exists() else 0.0


def _build_dataframe(corpus_dir: Path, family: str) -> pd.DataFrame:
    """Walk the corpus dir; layout depends on family.

    - ``mlps``: ``<corpus_dir>/<fingerprint>/aggregate.json`` (one level).
    - ``gnns``: ``<corpus_dir>/<config>_<variant>/<fingerprint>/aggregate.json``
      (two levels). The intermediate config dir groups all HP variants of the
      same recipe.
    """
    rows: list[dict[str, Any]] = []
    if family == "gnns":
        for cfg_dir in sorted(corpus_dir.iterdir()):
            if not cfg_dir.is_dir() or cfg_dir.name.startswith("."):
                continue
            for fp_dir in sorted(cfg_dir.iterdir()):
                if not fp_dir.is_dir() or fp_dir.name.startswith("."):
                    continue
                row = _flatten_gnn(fp_dir)
                if row is not None:
                    rows.append(row)
    else:
        for fp_dir in sorted(corpus_dir.iterdir()):
            if not fp_dir.is_dir() or fp_dir.name.startswith("."):
                continue
            row = _flatten_mlp(fp_dir)
            if row is not None:
                rows.append(row)
    return pd.DataFrame(rows)


def load_performance(
    models_root: Path,
    *,
    family: str = "mlps",
    rebuild: bool = False,
) -> pd.DataFrame:
    """Return the performance DataFrame, refreshing parquet if stale."""
    corpus_dir = _corpus_dir(models_root, family)
    if not corpus_dir.exists():
        return pd.DataFrame()

    cache_path = corpus_dir / CACHE_FILENAME
    needs_rebuild = rebuild or not cache_path.exists()
    if not needs_rebuild:
        cache_mtime = cache_path.stat().st_mtime
        if _index_mtime(corpus_dir) > cache_mtime:
            needs_rebuild = True

    if needs_rebuild:
        df = _build_dataframe(corpus_dir, family)
        if not df.empty:
            df.to_parquet(cache_path, index=False)
        return df
    return pd.read_parquet(cache_path)


def performance_payload(
    models_root: Path,
    *,
    family: str = "mlps",
    sort: str = "test_pearson_r_mean",
    ascending: bool = False,
    limit: int | None = None,
) -> dict[str, Any]:
    """JSON-friendly payload for the frontend (rows + small metadata)."""
    df = load_performance(models_root, family=family)
    if df.empty:
        return {
            "rows": [],
            "n_total": 0,
            "sort": sort,
            "ascending": ascending,
            "family": family,
        }

    if sort in df.columns:
        df = df.sort_values(sort, ascending=ascending, na_position="last")

    n_total = len(df)
    if limit is not None and limit > 0:
        df = df.head(limit)

    return {
        "rows": df.where(pd.notna(df), None).to_dict(orient="records"),
        "n_total": int(n_total),
        "sort": sort,
        "ascending": ascending,
        "family": family,
    }
