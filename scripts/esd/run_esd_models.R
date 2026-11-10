#!/usr/bin/env Rscript

# Preserve UTF-8 paths and corpus labels on Windows.
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "Chinese_China.utf8"))

# Primary ESD analysis: compare configurable surprisal and semantic metrics.
# Models use fREML and identical rows within each response/metric combination.

suppressPackageStartupMessages(library(mgcv))

script_argument <- grep(
  "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)
script_path <- if (length(script_argument)) {
  normalizePath(sub("^--file=", "", script_argument[[1]]), mustWork = TRUE)
} else {
  normalizePath("scripts/esd/run_esd_models.R", mustWork = TRUE)
}
PROJECT_ROOT <- normalizePath(
  file.path(dirname(script_path), "..", ".."), mustWork = TRUE
)
resolve_project_path <- function(path) {
  expanded <- path.expand(path)
  if (grepl("^/", expanded)) expanded else file.path(PROJECT_ROOT, expanded)
}

SURPRISAL_METRICS <- c(
  sum = "gpt2_sum_surprisal_bits",
  mean = "gpt2_mean_token_surprisal_bits",
  qwen_sum = "qwen25_sum_surprisal_bits",
  qwen_mean = "qwen25_mean_token_surprisal_bits"
)
SEMANTIC_METRICS <- c(
  l6_left = "semantic_relevance_gpt2_l6_left_context",
  l8_sentence = "semantic_relevance_gpt2_l8",
  l8_left = "semantic_relevance_gpt2_l8_left_context",
  l10_left = "semantic_relevance_gpt2_l10_left_context",
  l10_whole = "semantic_relevance_gpt2_l10_whole_inclusive",
  l11_left = "semantic_relevance_gpt2_l11_left_context",
  last3_left = "semantic_relevance_gpt2_last3_left",
  last4_left = "semantic_relevance_gpt2_last4_left",
  last3_whole = "semantic_relevance_gpt2_last3_whole_inclusive",
  qwen_last3_left = "semantic_relevance_qwen25_last3_left",
  qwen_last3_whole = "semantic_relevance_qwen25_last3_whole_inclusive",
  qwen_mid3_left = "semantic_relevance_qwen25_l16_18_left_context",
  model2vec_left = "model2vec_left_context_semantic",
  model2vec_whole = "model2vec_whole_inclusive_semantic"
)
RESPONSE_METRICS <- c(
  duration = "log_word_duration_sec",
  f0 = "f0_peak_deviation",
  intensity = "intensity_peak_deviation",
  f0_mean = "word_f0_mean_speaker_z",
  f0_range = "word_f0_range_speaker_z",
  f0_max = "word_max_f0_speaker_z",
  intensity_mean = "word_mean_intensity_speaker_z",
  intensity_max = "word_max_intensity_speaker_z"
)

usage <- function() {
  cat(
    "Usage:\n",
    "  Rscript scripts/esd/run_esd_models.R [options]\n\n",
    "Options:\n",
    "  --surprisal NAME       sum | mean (default: mean)\n",
    "  --semantic NAME        semantic alias (default: last3_left)\n",
    "  --semantic-transform NAME  none | fisher_z (default: none)\n",
    "  --transform NAME       none | log | log1p (default: log)\n",
    "  --position NAME        none | absolute | relative (default: relative)\n",
    "  --duration-tone NAME   no | yes (default: yes)\n",
    "  --word-random NAME     no | yes (default: yes)\n",
    "  --responses NAMES      comma-separated response aliases\n",
    "  --output-dir PATH      optional; auto-generated when omitted\n",
    "  --input PATH           optional unified master CSV override\n",
    "  --list-metrics         print all aliases and exit\n",
    "  --help                 print this help and exit\n\n",
    "Example:\n",
    "  Rscript scripts/esd/run_esd_models.R \\\n",
    "    --surprisal mean --transform log --semantic last3_left \\\n",
    "    --responses duration,f0,intensity\n",
    sep = ""
  )
}

print_metric_registry <- function() {
  cat("Surprisal aliases:\n")
  print(data.frame(alias = names(SURPRISAL_METRICS), column = unname(SURPRISAL_METRICS)),
        row.names = FALSE)
  cat("\nSemantic aliases:\n")
  print(data.frame(alias = names(SEMANTIC_METRICS), column = unname(SEMANTIC_METRICS)),
        row.names = FALSE)
  cat("\nResponse aliases:\n")
  print(data.frame(alias = names(RESPONSE_METRICS), column = unname(RESPONSE_METRICS)),
        row.names = FALSE)
}

cli <- list(
  surprisal = "mean",
  semantic = "last3_left",
  semantic_transform = "none",
  transform = "log",
  position = "relative",
  duration_tone = "yes",
  word_random = "yes",
  responses = "duration,f0,intensity",
  output_dir = NULL,
  input = "results/full/esd_metric_master/esd_jieba_gamm_input_all_metrics.csv"
)
args <- commandArgs(trailingOnly = TRUE)
i <- 1L
while (i <= length(args)) {
  flag <- args[[i]]
  if (flag == "--help") {
    usage()
    quit(save = "no", status = 0)
  }
  if (flag == "--list-metrics") {
    print_metric_registry()
    quit(save = "no", status = 0)
  }
  key <- switch(
    flag,
    "--surprisal" = "surprisal",
    "--semantic" = "semantic",
    "--semantic-transform" = "semantic_transform",
    "--transform" = "transform",
    "--position" = "position",
    "--duration-tone" = "duration_tone",
    "--word-random" = "word_random",
    "--responses" = "responses",
    "--output-dir" = "output_dir",
    "--input" = "input",
    stop("unknown option: ", flag, "\nUse --help for usage.")
  )
  if (i == length(args)) stop("missing value after ", flag)
  cli[[key]] <- args[[i + 1L]]
  i <- i + 2L
}

if (!cli$surprisal %in% names(SURPRISAL_METRICS)) {
  stop("unknown surprisal alias: ", cli$surprisal, "; use --list-metrics")
}
if (!cli$semantic %in% names(SEMANTIC_METRICS)) {
  stop("unknown semantic alias: ", cli$semantic, "; use --list-metrics")
}
if (!cli$semantic_transform %in% c("none", "fisher_z")) {
  stop("--semantic-transform must be one of: none, fisher_z")
}
if (!cli$transform %in% c("none", "log", "log1p")) {
  stop("--transform must be one of: none, log, log1p")
}
if (!cli$position %in% c("none", "absolute", "relative")) {
  stop("--position must be one of: none, absolute, relative")
}
if (!cli$duration_tone %in% c("no", "yes")) {
  stop("--duration-tone must be one of: no, yes")
}
if (!cli$word_random %in% c("no", "yes")) {
  stop("--word-random must be one of: no, yes")
}
response_aliases <- trimws(strsplit(cli$responses, ",", fixed = TRUE)[[1]])
if (!length(response_aliases) || any(!response_aliases %in% names(RESPONSE_METRICS))) {
  stop(
    "unknown response alias in: ", cli$responses,
    "; choose comma-separated duration,f0,intensity"
  )
}

input <- resolve_project_path(cli$input)
surprisal_column <- unname(SURPRISAL_METRICS[[cli$surprisal]])
semantic_column <- unname(SEMANTIC_METRICS[[cli$semantic]])
semantic_transform <- cli$semantic_transform
surprisal_transform <- cli$transform
responses <- unname(RESPONSE_METRICS[response_aliases])
out_dir <- if (is.null(cli$output_dir)) {
  file.path(
    PROJECT_ROOT, "results/review",
    paste(
      "esd", cli$surprisal, cli$transform, cli$semantic,
      paste0("pos-", cli$position), sep = "_"
    )
  )
} else {
  resolve_project_path(cli$output_dir)
}

if (!file.exists(input)) stop("input CSV not found: ", input)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
cat(
  "ESD model configuration\n",
  "  input: ", input, "\n",
  "  output: ", out_dir, "\n",
  "  surprisal: ", cli$surprisal, " -> ", surprisal_column,
  " (", surprisal_transform, ")\n",
  "  semantic: ", cli$semantic, " -> ", semantic_column, "\n",
  "  semantic transform: ", semantic_transform, "\n",
  "  position control: ", cli$position, "\n",
  "  lexical tone in duration model: ", cli$duration_tone, "\n",
  "  word random intercept: ", cli$word_random, "\n",
  "  responses: ", paste(response_aliases, collapse = ", "), "\n",
  sep = ""
)

transform_surprisal <- function(x) {
  if (surprisal_transform == "none") return(x)
  if (surprisal_transform == "log") {
    if (any(x <= 0, na.rm = TRUE)) {
      stop("log surprisal requires strictly positive values")
    }
    return(log(x))
  }
  log1p(x)
}

transform_contextual_fit <- function(x) {
  if (semantic_transform == "none") return(x)
  if (any(x <= -1 | x >= 1, na.rm = TRUE)) {
    stop(
      "Fisher-z requires contextual-fit values strictly inside (-1, 1); ",
      "use --semantic-transform none for a metric containing boundary values"
    )
  }
  atanh(x)
}

k_for <- function(x, maximum = 5L) {
  max(3L, min(maximum, length(unique(x[is.finite(x)]))))
}

model_deviance <- function(model) {
  value <- summary(model)$dev.expl
  if (!length(value) || !is.finite(value[[1]])) NA_real_ else as.numeric(value[[1]])
}

smooth_terms <- function(model, response, model_name, n) {
  tab <- as.data.frame(summary(model)$s.table, check.names = FALSE)
  tab$term <- rownames(tab)
  rownames(tab) <- NULL
  stat_col <- intersect(c("F", "Chi.sq"), names(tab))[[1]]
  p_col <- intersect(c("p-value", "p.value"), names(tab))[[1]]
  data.frame(
    response = response, model = model_name, n = n, term = tab$term,
    edf = tab$edf, ref_df = tab$Ref.df,
    statistic_name = stat_col, statistic = tab[[stat_col]],
    p_value = tab[[p_col]], stringsAsFactors = FALSE
  )
}

newdata <- function(data, predictor, value, emotion) {
  n <- length(value)
  out <- data.frame(
    surprisal = rep(stats::median(data$surprisal), n),
    contextual_fit = rep(stats::median(data$contextual_fit), n),
    log_frequency = rep(stats::median(data$log_frequency), n),
    char_count = factor(
      rep(names(which.max(table(data$char_count))), n),
      levels = levels(data$char_count)
    ),
    relative_position = rep(0.5, n),
    word_id = rep(stats::median(data$word_id), n),
    content_function = factor(
      rep(levels(data$content_function)[1], n),
      levels = levels(data$content_function)
    ),
    lexical_tone = factor(
      rep(levels(data$lexical_tone)[1], n),
      levels = levels(data$lexical_tone)
    ),
    emotion = factor(rep(emotion, n), levels = levels(data$emotion)),
    source_speaker_id = factor(
      rep(levels(data$source_speaker_id)[1], n),
      levels = levels(data$source_speaker_id)
    ),
    text_id = factor(
      rep(levels(data$text_id)[1], n),
      levels = levels(data$text_id)
    ),
    word = factor(
      rep(levels(data$word)[1], n),
      levels = levels(data$word)
    )
  )
  out[[predictor]] <- value
  out
}

partial_contrasts <- function(model, data, response, model_name, predictor) {
  q <- quantile(data[[predictor]], c(.10, .90), na.rm = TRUE)
  rows <- lapply(levels(data$emotion), function(emotion) {
    excluded_random_effects <- c(
      "s(source_speaker_id)", "s(text_id)",
      if (cli$word_random == "yes") "s(word)"
    )
    low <- predict(model, newdata(data, predictor, q[[1]], emotion),
                   exclude = excluded_random_effects)
    high <- predict(model, newdata(data, predictor, q[[2]], emotion),
                    exclude = excluded_random_effects)
    data.frame(
      response = response, model = model_name, predictor = predictor,
      emotion = emotion, x_low = unname(q[[1]]), x_high = unname(q[[2]]),
      high_minus_low = as.numeric(high - low), stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

partial_effect_curve <- function(model, data, predictor, term, n = 200L) {
  limits <- quantile(data[[predictor]], c(.01, .99), na.rm = TRUE)
  values <- seq(limits[[1]], limits[[2]], length.out = n)
  emotion_level <- if ("neutral" %in% levels(data$emotion)) {
    "neutral"
  } else {
    levels(data$emotion)[[1]]
  }
  grid <- newdata(data, predictor, values, emotion_level)
  prediction <- predict(
    model, newdata = grid, type = "terms", terms = term, se.fit = TRUE
  )
  fit <- as.numeric(prediction$fit)
  se <- as.numeric(prediction$se.fit)
  data.frame(
    predictor = predictor,
    x = values,
    partial_effect = fit,
    se = se,
    lower = fit - 1.96 * se,
    upper = fit + 1.96 * se,
    stringsAsFactors = FALSE
  )
}

draw_partial_effect <- function(
  curve, observed, x_label, y_label, title, color, annotation = NULL
) {
  ylim <- range(c(curve$lower, curve$upper), finite = TRUE)
  plot(
    curve$x, curve$partial_effect, type = "n",
    xlab = x_label, ylab = y_label, main = title,
    ylim = ylim, bty = "l", las = 1
  )
  polygon(
    c(curve$x, rev(curve$x)),
    c(curve$lower, rev(curve$upper)),
    col = grDevices::adjustcolor(color, alpha.f = 0.18),
    border = NA
  )
  abline(h = 0, col = "#777777", lty = 2, lwd = 0.8)
  lines(curve$x, curve$partial_effect, col = color, lwd = 2.2)
  rug_values <- observed[
    is.finite(observed) & observed >= min(curve$x) & observed <= max(curve$x)
  ]
  rug(
    rug_values,
    col = grDevices::adjustcolor("#333333", alpha.f = 0.18),
    ticksize = 0.025
  )
  if (!is.null(annotation)) {
    mtext(annotation, side = 1, line = 3.25, cex = 0.62)
  }
}

write_partial_effect_plots <- function(model, data, response, stem, comp, terms) {
  specifications <- list(
    frequency = list(
      predictor = "log_frequency", term = "s(log_frequency)",
      label = "log(word frequency)", color = "#009E73"
    ),
    surprisal = list(
      predictor = "surprisal", term = "s(surprisal)",
      label = "log(surprisal)", color = "#0072B2"
    ),
    contextual_fit = list(
      predictor = "contextual_fit", term = "s(contextual_fit)",
      label = if (semantic_transform == "fisher_z") {
        "Contextual fit (Fisher-z)"
      } else {
        "Contextual fit"
      }, color = "#D55E00"
    )
  )
  curves <- lapply(specifications, function(spec) {
    partial_effect_curve(model, data, spec$predictor, spec$term)
  })
  y_label <- switch(
    response,
    log_word_duration_sec = "log(word duration)",
    f0_peak_deviation = "F0 peak deviation",
    intensity_peak_deviation = "intensity peak deviation",
    word_f0_mean_speaker_z = "speaker-normalized mean F0",
    word_f0_range_speaker_z = "speaker-normalized F0 range",
    word_max_f0_speaker_z = "speaker-normalized maximum F0",
    word_mean_intensity_speaker_z = "speaker-normalized mean intensity",
    word_max_intensity_speaker_z = "speaker-normalized maximum intensity",
    gsub("_", " ", response)
  )
  term_rows <- terms[terms$model == "shared_mapping", , drop = FALSE]
  metric_stats <- list(
    frequency = c(
      p = term_rows$p_value[term_rows$term == "s(log_frequency)"],
      delta_aic = comp$delta_aic_frequency
    ),
    surprisal = c(
      p = term_rows$p_value[term_rows$term == "s(surprisal)"],
      delta_aic = comp$delta_aic_surprisal
    ),
    contextual_fit = c(
      p = term_rows$p_value[term_rows$term == "s(contextual_fit)"],
      delta_aic = comp$delta_aic_contextual_fit
    )
  )
  format_p <- function(p) {
    if (!is.finite(p)) return("p=NA")
    if (p < .001) "p<.001" else paste0("p=", formatC(p, format = "f", digits = 3))
  }
  annotation <- function(name) {
    s <- metric_stats[[name]]
    # Plotmath renders a true Greek capital Delta reliably in PDF output.
    bquote(
      .(format_p(s[["p"]])) ~~ Delta * AIC ==
        .(formatC(s[["delta_aic"]], format = "f", digits = 1))
    )
  }

  for (name in names(specifications)) {
    curve <- curves[[name]]
    write.csv(
      curve,
      file.path(out_dir, paste0(stem, "_partial_", name, ".csv")),
      row.names = FALSE
    )
  }

  draw_panel <- function() {
      par(
      mfrow = c(1, 3), mar = c(5.0, 4.1, 1.5, 0.7),
      oma = c(0, 0, 2.2, 0),
      mgp = c(2.5, 0.75, 0), family = "serif", cex = 0.88
    )
    plot_names <- names(specifications)
    for (i in seq_along(plot_names)) {
      name <- plot_names[[i]]
      spec <- specifications[[name]]
      draw_partial_effect(
        curves[[name]], data[[spec$predictor]], spec$label,
        if (i == 1) y_label else "",
        tools::toTitleCase(gsub("_", " ", name)), spec$color,
        annotation(name)
      )
    }
    mtext(
      paste("Partial Effects on", y_label), outer = TRUE, side = 3,
      line = 0.45, cex = 1.05, font = 2
    )
  }
  grDevices::pdf(
    file.path(out_dir, paste0(stem, "_three_partial_effects.pdf")),
    width = 7.0, height = 2.7, useDingbats = FALSE
  )
  draw_panel()
  grDevices::dev.off()
  grDevices::png(
    file.path(out_dir, paste0(stem, "_three_partial_effects.png")),
    width = 7.0, height = 2.7, units = "in", res = 300
  )
  draw_panel()
  grDevices::dev.off()
}

fit_one <- function(df, response) {
  needed <- c(
    response, surprisal_column, semantic_column,
    "subtlex_ch_log_frequency", "char_interval_count", "item_id", "word_id",
    "content_function", "lexical_tone", "emotion", "participant_id", "text"
  )
  use <- df[complete.cases(df[, needed, drop = FALSE]), , drop = FALSE]
  finite_rows <- (
    is.finite(use[[response]]) &
    is.finite(use[[surprisal_column]]) &
    is.finite(use[[semantic_column]]) &
    is.finite(use$subtlex_ch_log_frequency) &
    is.finite(use$char_interval_count) &
    is.finite(use$word_id)
  )
  use <- use[finite_rows, , drop = FALSE]
  if (nrow(use) < 500 || length(unique(use[[response]])) < 2) return(NULL)

  use$emotion <- droplevels(factor(use$emotion))
  if ("neutral" %in% levels(use$emotion)) use$emotion <- relevel(use$emotion, ref = "neutral")
  use$content_function <- factor(use$content_function)
  use$lexical_tone <- factor(use$lexical_tone)
  use$source_speaker_id <- factor(use$participant_id)
  use$text_id <- factor(use$text)
  use$word <- factor(use$word)
  use$surprisal <- transform_surprisal(use[[surprisal_column]])
  use$contextual_fit <- transform_contextual_fit(use[[semantic_column]])
  use$log_frequency <- use$subtlex_ch_log_frequency
  use$char_count <- factor(use$char_interval_count)
  utterance_max_word_id <- ave(use$word_id, use$item_id, FUN = max)
  use$relative_position <- ifelse(
    utterance_max_word_id <= 1,
    0,
    (use$word_id - 1) / (utterance_max_word_id - 1)
  )

  emotion_term <- if (nlevels(use$emotion) > 1) "emotion +" else ""
  content_function_term <- if (nlevels(use$content_function) > 1) {
    "content_function +"
  } else {
    ""
  }
  lexical_tone_term <- if (nlevels(use$lexical_tone) > 1) {
    "lexical_tone +"
  } else {
    ""
  }

  k_surprisal <- k_for(use$surprisal)
  k_contextual_fit <- k_for(use$contextual_fit)
  k_frequency <- k_for(use$log_frequency)
  position_control <- switch(
    cli$position,
    none = "",
    absolute = paste0("s(word_id, k = ", k_for(use$word_id), ") +"),
    relative = paste0(
      "s(relative_position, k = ", k_for(use$relative_position), ") +"
    )
  )
  lexical_controls <- if (
    response == "log_word_duration_sec" && cli$duration_tone == "no"
  ) {
    content_function_term
  } else {
    paste(content_function_term, lexical_tone_term)
  }
  controls <- paste(
    paste0("s(log_frequency, k = ", k_frequency, ") +"),
    "char_count +",
    paste0(
      position_control, " ",
      lexical_controls
    ),
    "s(source_speaker_id, bs = 're') + s(text_id, bs = 're')",
    if (cli$word_random == "yes") "+ s(word, bs = 're')" else ""
  )
  shared <- as.formula(paste0(
    response, " ~ ", emotion_term, " s(surprisal, k = ", k_surprisal, ") +",
    " s(contextual_fit, k = ", k_contextual_fit, ") + ", controls
  ))
  no_surprisal <- as.formula(paste0(
    response, " ~ ", emotion_term, " s(contextual_fit, k = ", k_contextual_fit, ") + ", controls
  ))
  no_contextual_fit <- as.formula(paste0(
    response, " ~ ", emotion_term, " s(surprisal, k = ", k_surprisal, ") + ", controls
  ))
  no_frequency <- as.formula(paste0(
    response, " ~ ", emotion_term, " s(surprisal, k = ", k_surprisal,
    ") + s(contextual_fit, k = ", k_contextual_fit, ") + ",
    sub("s\\(log_frequency, k = [0-9]+\\) \\+", "", controls)
  ))
  moderated <- if (nlevels(use$emotion) > 1) {
    as.formula(paste0(
      response, " ~ ", emotion_term,
      " s(surprisal, by = emotion, k = ", k_surprisal, ") +",
      " s(contextual_fit, by = emotion, k = ", k_contextual_fit, ") + ", controls
    ))
  } else {
    shared
  }

  fit <- function(formula) bam(
    formula, data = use, family = gaussian(), method = "fREML",
    discrete = TRUE, nthreads = 4, gc.level = 1
  )
  cat("  fitting ", response, ": shared mapping\n", sep = "")
  shared_model <- fit(shared)
  cat("  fitting ", response, ": without surprisal\n", sep = "")
  no_surprisal_model <- fit(no_surprisal)
  cat("  fitting ", response, ": without contextual fit\n", sep = "")
  no_contextual_model <- fit(no_contextual_fit)
  cat("  fitting ", response, ": without frequency\n", sep = "")
  no_frequency_model <- fit(no_frequency)
  cat("  fitting ", response, ": emotion-moderated mapping\n", sep = "")
  moderated_model <- fit(moderated)

  comp <- data.frame(
    response = response, n = nrow(use),
    full_aic = AIC(shared_model),
    no_surprisal_aic = AIC(no_surprisal_model),
    no_contextual_fit_aic = AIC(no_contextual_model),
    no_frequency_aic = AIC(no_frequency_model),
    delta_aic_surprisal = AIC(no_surprisal_model) - AIC(shared_model),
    delta_aic_contextual_fit = AIC(no_contextual_model) - AIC(shared_model),
    delta_aic_frequency = AIC(no_frequency_model) - AIC(shared_model),
    shared_deviance = model_deviance(shared_model),
    no_surprisal_deviance = model_deviance(no_surprisal_model),
    no_contextual_fit_deviance = model_deviance(no_contextual_model),
    delta_deviance_surprisal = model_deviance(shared_model) - model_deviance(no_surprisal_model),
    delta_deviance_contextual_fit = model_deviance(shared_model) - model_deviance(no_contextual_model),
    no_frequency_deviance = model_deviance(no_frequency_model),
    delta_deviance_frequency = model_deviance(shared_model) - model_deviance(no_frequency_model),
    shared_aic = AIC(shared_model), moderated_aic = AIC(moderated_model),
    delta_aic_moderated_minus_shared = AIC(moderated_model) - AIC(shared_model),
    moderated_deviance = model_deviance(moderated_model),
    delta_deviance_moderated = model_deviance(moderated_model) - model_deviance(shared_model),
    stringsAsFactors = FALSE
  )
  terms <- rbind(
    smooth_terms(shared_model, response, "shared_mapping", nrow(use)),
    smooth_terms(moderated_model, response, "emotion_moderated_mapping", nrow(use))
  )
  contrasts <- rbind(
    partial_contrasts(shared_model, use, response, "shared_mapping", "surprisal"),
    partial_contrasts(shared_model, use, response, "shared_mapping", "contextual_fit"),
    partial_contrasts(moderated_model, use, response, "emotion_moderated_mapping", "surprisal"),
    partial_contrasts(moderated_model, use, response, "emotion_moderated_mapping", "contextual_fit")
  )

  stem <- paste(
    "esd", cli$surprisal, cli$transform, cli$semantic,
    cli$semantic_transform, paste0("position-", cli$position),
    paste0("duration-tone-", cli$duration_tone),
    paste0("word-random-", cli$word_random), response,
    sep = "_"
  )
  write_partial_effect_plots(shared_model, use, response, stem, comp, terms)
  saveRDS(shared_model, file.path(out_dir, paste0(stem, "_shared_freml.rds")))
  saveRDS(moderated_model, file.path(out_dir, paste0(stem, "_moderated_freml.rds")))
  writeLines(capture.output({
    cat("Input:", input, "\nResponse:", response, "\nRows:", nrow(use),
        "\nSurprisal column:", surprisal_column,
        "\nSurprisal transform:", surprisal_transform,
        "\nSemantic column:", semantic_column,
        "\nSemantic transform:", semantic_transform,
        "\nPosition control:", cli$position,
        "\nLexical tone in duration model:", cli$duration_tone,
        "\nWord random intercept:", cli$word_random,
        "\nFit method: fREML + discrete=TRUE; AIC differences are descriptive only.\n\n")
    cat("Shared formula:\n"); print(shared)
    cat("\nModerated formula:\n"); print(moderated)
    cat("\nAIC contribution and moderation comparison:\n"); print(comp, row.names = FALSE)
    cat("\nShared summary:\n"); print(summary(shared_model))
    cat("\nModerated summary:\n"); print(summary(moderated_model))
    cat("\nPartial contrasts:\n"); print(contrasts, row.names = FALSE)
  }), file.path(out_dir, paste0(stem, "_summary.txt")))
  list(comparison = comp, terms = terms, contrasts = contrasts)
}

df <- read.csv(input, stringsAsFactors = FALSE, check.names = FALSE)
if ("word_duration_sec" %in% names(df)) {
  df$log_word_duration_sec <- log(df$word_duration_sec)
}
required_input_columns <- unique(c(
  surprisal_column, semantic_column, responses,
  "word_duration_sec", "subtlex_ch_log_frequency", "char_interval_count",
  "item_id", "word_id", "content_function", "lexical_tone", "emotion",
  "participant_id", "text", "word"
))
missing_input_columns <- setdiff(required_input_columns, names(df))
if (length(missing_input_columns)) {
  stop("input CSV is missing column(s): ", paste(missing_input_columns, collapse = ", "))
}
if ("interval_count_match" %in% names(df)) {
  df <- df[tolower(as.character(df$interval_count_match)) == "true", , drop = FALSE]
}
results <- lapply(responses, function(response) {
  if (response %in% names(df)) fit_one(df, response) else NULL
})
results <- Filter(Negate(is.null), results)
if (!length(results)) {
  stop("no model was fitted; check selected responses and complete-case coverage")
}
bind <- function(x) if (length(x)) do.call(rbind, x) else data.frame()
write.csv(bind(lapply(results, `[[`, "comparison")), file.path(out_dir, "esd_model_comparisons.csv"), row.names = FALSE)
write.csv(bind(lapply(results, `[[`, "terms")), file.path(out_dir, "esd_smooth_terms.csv"), row.names = FALSE)
write.csv(bind(lapply(results, `[[`, "contrasts")), file.path(out_dir, "esd_partial_contrasts.csv"), row.names = FALSE)
cat("wrote ESD information-model results to", out_dir, "\n")
print(bind(lapply(results, `[[`, "comparison")), row.names = FALSE)
