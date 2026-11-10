#!/usr/bin/env Rscript

# Preserve UTF-8 paths and corpus labels on Windows.
if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "Chinese_China.utf8"))

# RQ3 audit for the frozen last3_left specification.
# 1) verifies matched rows, 2) obtains emotion-specific focal contrasts with
#    coefficient-based 95% CIs, and 3) bootstraps text-cluster prediction loss.

suppressPackageStartupMessages({
  library(mgcv)
})

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1]]), mustWork = TRUE)
project_root <- normalizePath(file.path(dirname(script_path), "../.."), mustWork = TRUE)
result_dir <- file.path(project_root, "results/review/esd_mean_log_last3_left_pos-relative")
out_dir <- result_dir
set.seed(20260724)

responses <- c(
  duration = "log_word_duration_sec",
  f0 = "f0_peak_deviation",
  intensity = "intensity_peak_deviation"
)
stem <- function(response, model) {
  file.path(
    result_dir,
    paste0(
      "esd_mean_log_last3_left_none_position-relative_duration-tone-yes_word-random-yes_",
      response, "_", model, "_freml.rds"
    )
  )
}

shared_paths <- vapply(responses, stem, character(1), model = "shared")
moderated_paths <- vapply(responses, stem, character(1), model = "moderated")
if (any(!file.exists(c(shared_paths, moderated_paths)))) {
  stop("Expected final shared/moderated RDS files are missing in ", result_dir)
}

newdata_at <- function(data, predictor, value, emotion) {
  out <- data[1, , drop = FALSE]
  out <- out[rep(1, length(value)), , drop = FALSE]
  out[["emotion"]] <- factor(emotion, levels = levels(data$emotion))
  out[["char_count"]] <- factor(
    names(which.max(table(data$char_count))), levels = levels(data$char_count)
  )
  out[["content_function"]] <- factor(
    levels(data$content_function)[1], levels = levels(data$content_function)
  )
  out[["lexical_tone"]] <- factor(
    levels(data$lexical_tone)[1], levels = levels(data$lexical_tone)
  )
  out[["log_frequency"]] <- median(data$log_frequency, na.rm = TRUE)
  out[["relative_position"]] <- 0.5
  out[["source_speaker_id"]] <- factor(
    levels(data$source_speaker_id)[1], levels = levels(data$source_speaker_id)
  )
  out[["text_id"]] <- factor(levels(data$text_id)[1], levels = levels(data$text_id))
  out[["word"]] <- factor(levels(data$word)[1], levels = levels(data$word))
  out[[predictor]] <- value
  out
}

term_columns <- function(model, predictor, emotion, moderated) {
  cn <- colnames(predict(model, newdata = model$model[1, , drop = FALSE], type = "lpmatrix"))
  if (moderated) {
    prefix <- if (predictor == "surprisal") "s(surprisal):emotion" else "s(contextual_fit):emotion"
    keep <- startsWith(cn, paste0(prefix, emotion, "."))
  } else {
    prefix <- if (predictor == "surprisal") "s(surprisal)" else "s(contextual_fit)"
    keep <- startsWith(cn, paste0(prefix, "."))
  }
  which(keep)
}

contrast_one <- function(model, predictor, emotion, moderated) {
  data <- model$model
  q <- quantile(data[[predictor]], c(.10, .90), na.rm = TRUE)
  nd <- newdata_at(data, predictor, q, emotion)
  X <- predict(model, newdata = nd, type = "lpmatrix")
  cols <- term_columns(model, predictor, emotion, moderated)
  if (!length(cols)) stop("Could not identify focal smooth columns for ", predictor, " / ", emotion)
  L <- X[2, cols, drop = FALSE] - X[1, cols, drop = FALSE]
  beta <- coef(model)[cols]
  V <- vcov(model)[cols, cols, drop = FALSE]
  estimate <- as.numeric(L %*% beta)
  se <- sqrt(max(0, as.numeric(L %*% V %*% t(L))))
  data.frame(
    response = as.character(model$formula[[2]]),
    model = if (moderated) "emotion_specific" else "shared",
    predictor = predictor,
    emotion = emotion,
    x_low = unname(q[[1]]), x_high = unname(q[[2]]),
    contrast = estimate, se = se,
    lower = estimate - 1.96 * se, upper = estimate + 1.96 * se,
    stringsAsFactors = FALSE
  )
}

matched_rows <- lapply(names(responses), function(label) {
  shared <- readRDS(shared_paths[[label]])
  moderated <- readRDS(moderated_paths[[label]])
  sdat <- shared$model
  mdat <- moderated$model
  data.frame(
    response = responses[[label]],
    shared_rows = nrow(sdat), moderated_rows = nrow(mdat),
    same_n = nrow(sdat) == nrow(mdat),
    same_response = identical(sdat[[responses[[label]]]], mdat[[responses[[label]]]]),
    shared_texts = length(unique(sdat$text_id)),
    moderated_texts = length(unique(mdat$text_id)),
    shared_words = length(unique(sdat$word)),
    moderated_words = length(unique(mdat$word)),
    stringsAsFactors = FALSE
  )
})
matched_rows <- do.call(rbind, matched_rows)
write.csv(matched_rows, file.path(out_dir, "rq3_same_rows.csv"), row.names = FALSE)

contrast_rows <- list()
boot_rows <- list()
for (label in names(responses)) {
  response <- responses[[label]]
  shared <- readRDS(shared_paths[[label]])
  moderated <- readRDS(moderated_paths[[label]])
  emotions <- levels(shared$model$emotion)
  for (model_pair in list(shared = list(m = shared, moderated = FALSE),
                          emotion_specific = list(m = moderated, moderated = TRUE))) {
    for (predictor in c("surprisal", "contextual_fit")) {
      for (emotion in emotions) {
        contrast_rows[[length(contrast_rows) + 1L]] <- contrast_one(
          model_pair$m, predictor, emotion, model_pair$moderated
        )
      }
    }
  }

  # Cluster bootstrap: fixed-effect predictions are evaluated with all
  # speaker/text/word random effects excluded, then text clusters are resampled.
  dat <- shared$model
  pred_shared <- as.numeric(predict(
    shared, newdata = dat,
    exclude = c("s(source_speaker_id)", "s(text_id)", "s(word)")
  ))
  pred_moderated <- as.numeric(predict(
    moderated, newdata = dat,
    exclude = c("s(source_speaker_id)", "s(text_id)", "s(word)")
  ))
  text_key <- as.character(dat$text_id)
  text_ids <- unique(text_key)
  per_text <- do.call(rbind, lapply(text_ids, function(text_id) {
    rows <- text_key == text_id
    y <- dat[[response]][rows]
    data.frame(
      text_id = text_id,
      n = sum(rows),
      mse_shared = mean((y - pred_shared[rows])^2),
      mse_moderated = mean((y - pred_moderated[rows])^2),
      moderated_minus_shared = mean((y - pred_moderated[rows])^2) -
        mean((y - pred_shared[rows])^2)
    )
  }))
  B <- 2000L
  boot <- numeric(B)
  for (b in seq_len(B)) {
    sampled <- sample(seq_len(nrow(per_text)), replace = TRUE)
    boot[[b]] <- weighted.mean(
      per_text$moderated_minus_shared[sampled],
      per_text$n[sampled]
    )
  }
  boot_rows[[length(boot_rows) + 1L]] <- data.frame(
    response = response,
    texts = nrow(per_text),
    observed_mse_shared = weighted.mean(per_text$mse_shared, per_text$n),
    observed_mse_moderated = weighted.mean(per_text$mse_moderated, per_text$n),
    observed_moderated_minus_shared = weighted.mean(
      per_text$moderated_minus_shared, per_text$n
    ),
    bootstrap_lower = quantile(boot, .025),
    bootstrap_median = quantile(boot, .5),
    bootstrap_upper = quantile(boot, .975),
    bootstrap_p_moderated_better = mean(boot < 0),
    stringsAsFactors = FALSE
  )
}

contrast_rows <- do.call(rbind, contrast_rows)
boot_rows <- do.call(rbind, boot_rows)
write.csv(contrast_rows, file.path(out_dir, "rq3_emotion_specific_contrasts.csv"), row.names = FALSE)
write.csv(boot_rows, file.path(out_dir, "rq3_text_cluster_bootstrap.csv"), row.names = FALSE)
writeLines(capture.output({
  cat("RQ3 audit: matched rows\n")
  print(matched_rows, row.names = FALSE)
  cat("\nRQ3 audit: emotion-specific 10-90 contrasts with coefficient-based 95% CIs\n")
  print(contrast_rows, row.names = FALSE)
  cat("\nRQ3 audit: text-cluster bootstrap of fixed-effect MSE difference\n")
  print(boot_rows, row.names = FALSE)
}), file.path(out_dir, "rq3_audit_summary.txt"))

cat("wrote RQ3 audit outputs to ", out_dir, "\n", sep = "")
