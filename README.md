# Semantic relevance and Mandarin acoustic realization

Selected analysis code and example derived features accompanying the manuscript *Semantic relevance predicts the acoustic realization of words in Mandarin speech*.

## Contents
- `scripts/esd/`: archived main modeling, metric-merging, and emotion-audit scripts from the study.
- `data/example_features.csv`: 5,000 genuine derived word records sampled uniformly without replacement from 127,509 records using pandas random_state=20261110. This example does not reproduce full-sample manuscript estimates.
- `data/data_dictionary.csv`: original feature names and storage types.
- `results/`: full-sample summaries of acoustic-context controls, repeated-context sensitivity analyses, and text-held-out validation. These are archived results, not estimates from the example sample.

## Use
R with mgcv is required for modeling; the merging script uses Python. See `scripts/esd/README.md` for archived options and expected full-data layout. Run `Rscript scripts/esd/run_esd_models.R --help` for arguments. Original default paths expect `results/full/esd_metric_master/esd_jieba_gamm_input_all_metrics.csv`; place the complete feature table there for a full analysis. The bundled sample may be copied there for demonstration only. Alternatively specify the example directly:

```bash
Rscript scripts/esd/run_esd_models.R --input data/example_features.csv --output-dir results/example_run
```

Small example fits can fail if factor levels are insufficient.

This selection does not include raw audio, model weights, complete extraction configurations, or all supplementary model-fitting scripts. It is a partial code/data release, not a complete reconstruction of the entire study pipeline. Published summaries include analyses beyond the archived main runner.

## Data source and reuse
Source recordings: Emotional Speech Dataset (ESD), https://github.com/HLTSingapore/Emotional-Speech-Data . Consult the creators for original access and license conditions. Feature records include corpus transcripts and pseudonymous speaker/utterance identifiers. No raw recordings are redistributed. No additional blanket license over third-party corpus materials is asserted here.
