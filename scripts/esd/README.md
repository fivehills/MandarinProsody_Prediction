# Canonical ESD analysis

This directory contains the two maintained modeling entry points for the ESD
paper.

## Main GAMM

`run_esd_models.R` fits the three paper responses:

- log word duration;
- F0 peak deviation;
- intensity peak deviation.

The default run is the frozen paper specification: mean-token surprisal on the
log scale, final-three-layer left-context contextual fit, relative word
position, and speaker, text, and word random intercepts.

```bash
Rscript scripts/esd/run_esd_models.R
```

Alternative registered metrics remain available for robustness analyses:

```bash
Rscript scripts/esd/run_esd_models.R --list-metrics
Rscript scripts/esd/run_esd_models.R \
  --surprisal sum \
  --transform none \
  --semantic l10_left
```

The unified input is:

`results/full/esd_metric_master/esd_jieba_gamm_input_all_metrics.csv`

The metric master also contains Qwen2.5-0.5B features:

- `qwen25_sum_surprisal_bits`
- `qwen25_mean_token_surprisal_bits`
- `semantic_relevance_qwen25_last3_left`
- `semantic_relevance_qwen25_last3_whole_inclusive`
- `semantic_relevance_qwen25_l16_18_left_context` (Qwen2.5 layers 16--18)

They can be selected in the GAMM runner with `--surprisal qwen_mean` or
`--surprisal qwen_sum`, and `--semantic qwen_last3_left` or
`--semantic qwen_last3_whole`.

Rebuild it after recomputing language features:

```bash
python scripts/esd/build_esd_metric_master.py
```

## Emotion-mapping audit

`audit_esd_rq3.R` reads the shared and emotion-specific models from the frozen
main run. It verifies matched rows, estimates emotion-specific focal
contrasts, and evaluates prediction loss with a text-cluster bootstrap.

```bash
Rscript scripts/esd/audit_esd_rq3.R
```

Historical linear models, Model2Vec pilots, and superseded plotting scripts
were removed so they cannot be mistaken for the paper analysis.
