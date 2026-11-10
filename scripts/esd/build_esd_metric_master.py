#!/usr/bin/env python3
"""Build one ESD modeling CSV containing all available semantic metrics."""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
KEYS = ["item_id", "word_id"]
BASE = ROOT / "results/full/jieba_gpt_language/esd_jieba_gamm_input_intensity.csv"
OUTPUT_DIR = ROOT / "results/full/esd_metric_master"
OUTPUT_CSV = OUTPUT_DIR / "esd_jieba_gamm_input_all_metrics.csv"
OUTPUT_SUMMARY = OUTPUT_DIR / "esd_jieba_gamm_input_all_metrics.summary.json"

SOURCES = {
    ROOT / "results/full/gpt2_l11_left/"
    "esd_jieba_l11_left_gpt_language_features.csv": [
        "semantic_relevance_gpt2_l11_left_context",
    ],
    ROOT / "results/full/gpt2_last3_left/"
    "esd_jieba_last3_left_gpt_language_features.csv": [
        "semantic_relevance_gpt2_last3_left",
    ],
    ROOT / "results/full/gpt2_l6_left_context/"
    "esd_jieba_gamm_input_semantic_relevance_gpt2_l6_left_context.csv": [
        "semantic_relevance_gpt2_l6_left_context",
    ],
    ROOT / "results/full/gpt2_l10_left_context/"
    "esd_jieba_gamm_input_l10_left_context.csv": [
        "semantic_relevance_gpt2_l10_left_context",
        "semantic_relevance_gpt2_l10_whole_inclusive",
    ],
    ROOT / "results/full/gpt2_last3_whole_inclusive_pilot5000/"
    "esd_jieba_last3_whole_inclusive_pilot5000_gpt_language_features.csv": [
        "semantic_relevance_gpt2_last3_whole_inclusive",
    ],
    ROOT / "results/full/model2vec_left_context/"
    "esd_jieba_gamm_input_intensity_with_model2vec_left.csv": [
        "model2vec_left_context_semantic",
    ],
    ROOT / "results/full/model2vec_whole_inclusive/"
    "esd_jieba_gamm_input_l10_whole_inclusive_with_model2vec_whole_inclusive.csv": [
        "model2vec_whole_inclusive_semantic",
    ],
    ROOT / "results/full/qwen25_last3_left/"
    "esd_jieba_qwen25_last3_left_gpt_language_features.csv": [
        "qwen25_sum_surprisal_bits",
        "qwen25_mean_token_surprisal_bits",
        "semantic_relevance_qwen25_last3_left",
    ],
    ROOT / "results/full/qwen25_last3_whole/"
    "esd_jieba_qwen25_last3_whole_gpt_language_features.csv": [
        "semantic_relevance_qwen25_last3_whole_inclusive",
    ],
    ROOT / "results/full/qwen25_l16_18_left/"
    "esd_jieba_qwen25_l16_18_left_gpt_language_features.csv": [
        "semantic_relevance_qwen25_l16_18_left_context",
    ],
}


def indexed(frame: pd.DataFrame, label: str) -> pd.DataFrame:
    if frame.duplicated(KEYS).any():
        raise ValueError(f"{label}: duplicate item_id + word_id keys")
    return frame.set_index(KEYS, drop=False)


def main() -> None:
    base = pd.read_csv(BASE, low_memory=False)
    master = indexed(base, str(BASE))
    base_index = master.index

    for source_path, columns in SOURCES.items():
        source = pd.read_csv(
            source_path,
            usecols=KEYS + ["word"] + columns,
            low_memory=False,
        )
        source = indexed(source, str(source_path))
        if not source.index.equals(base_index):
            missing = len(base_index.difference(source.index))
            extra = len(source.index.difference(base_index))
            raise ValueError(
                f"{source_path}: key/order mismatch; missing={missing}, extra={extra}"
            )
        word_mismatch = (
            master["word"].astype(str).to_numpy()
            != source["word"].astype(str).to_numpy()
        )
        if word_mismatch.any():
            raise ValueError(
                f"{source_path}: {int(word_mismatch.sum())} aligned word mismatches"
            )
        for column in columns:
            master[column] = pd.to_numeric(source[column], errors="coerce").to_numpy()

    master = master.reset_index(drop=True)
    metric_columns = [
        "gpt2_sum_surprisal_bits",
        "gpt2_mean_token_surprisal_bits",
        "semantic_relevance_gpt2_l8",
        "semantic_relevance_gpt2_l8_left_context",
        *[column for columns in SOURCES.values() for column in columns],
    ]
    coverage = {
        column: {
            "finite_rows": int(master[column].notna().sum()),
            "missing_rows": int(master[column].isna().sum()),
        }
        for column in metric_columns
    }

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    master.to_csv(OUTPUT_CSV, index=False)
    OUTPUT_SUMMARY.write_text(
        json.dumps(
            {
                "base_csv": str(BASE.relative_to(ROOT)),
                "output_csv": str(OUTPUT_CSV.relative_to(ROOT)),
                "rows": len(master),
                "unique_item_word_keys": int(
                    master.drop_duplicates(KEYS).shape[0]
                ),
                "metric_columns": metric_columns,
                "coverage": coverage,
                "note": (
                "Left-context metrics are undefined for utterance-initial words. "
                "The last-three-layer whole-inclusive metric is currently "
                    "partial-coverage for the GPT-2 pilot; Qwen last3-whole has "
                    "full coverage. Last3-left metrics have full non-initial-word "
                    "coverage."
                ),
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"wrote {OUTPUT_CSV} ({len(master)} rows)")
    print(f"wrote {OUTPUT_SUMMARY}")


if __name__ == "__main__":
    main()
