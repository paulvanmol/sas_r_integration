/*=============================================================================
  DEMO 3: PROC R (NEW – SAS Viya Stable 2026.03)
  Case Study: SAS & R Integration for Clinical Programmers
  References:
    SAS Help Center – Overview: PROC R
    The SAS Viya Guide – github.com/Criptic/The-SAS-Viya-Guide

  PROC R Statement Options:
    proc r;            – start / reuse existing R subprocess
    proc r restart;    – start a fresh R session (clears all R objects)
    proc r terminate;  – shut down R subprocess and release resources
    proc r inFile=ref; – execute an external R script file

  Callback Methods (case-sensitive, all available inside SUBMIT block):
  ┌──────────────────────────────────────────────────────────────────────┐
  │  Data Transfer                                                       │
  │    sd2df("dataset", "libname")   SAS dataset → R data frame         │
  │    → always follow with: names(df) <- toupper(names(df))            │
  │    df2sd(df, "dataset", "lib")   R data frame → SAS dataset         │
  │                                                                      │
  │  Macro Variables                                                     │
  │    symget("macvar")              Read SAS macro variable             │
  │    symput("macvar", "value")     Write value → SAS macro variable    │
  │    submit("sas code")            Execute SAS code from R             │
  │                                                                      │
  │  SAS Functions                                                       │
  │    sasfnc("funcname" <, args>)   Call any SAS function               │
  │                                                                      │
  │  Output / Display                                                    │
  │    rplot(obj <, filename="f.png">)  Render plot in Results window    │
  │    renderImage("full/path.png")     Render saved image in Results    │
  │    show(obj, title=, count=)        Display R object in Results      │
  │                                                                      │
  │  Session                                                             │
  │    sas$workpath                  Path to SAS WORK directory          │
  └──────────────────────────────────────────────────────────────────────┘
=============================================================================*/

/*=============================================================================
  SECTION 0: Environment Check
  Best practice: always verify which R is active before running analyses.
=============================================================================*/

/* Check which R installation PROC R is using */
%let rpath = %sysget(PROC_RPATH);
%put NOTE: PROC_RPATH = &rpath.;

/* Verify R is reachable and list available packages */
proc r;
  submit;
    cat("R version:", R.version.string, "\n")
    cat("R_HOME:   ", Sys.getenv("R_HOME"), "\n")

    # ------------------------------------------------------------------
    # Helper 1: trim character columns to their actual max content width.
    # This controls what df2sd() sees, but the parquet intermediate format
    # still produces $32767 in SAS. Use sas_length_stmt() (Helper 2) to
    # fix lengths on the SAS side after df2sd().
    #
    # Usage: df <- trim_char_widths(df)
    #        df <- trim_char_widths(df, min_width = 8)
    # ------------------------------------------------------------------
    trim_char_widths <- function(df, min_width = 1L) {
      char_cols <- sapply(df, is.character)
      df[char_cols] <- lapply(df[char_cols], function(col) {
        max_len <- max(nchar(col, type = "bytes", allowNA = TRUE,
                             keepNA = FALSE), na.rm = TRUE)
        max_len <- max(max_len, min_width, na.rm = TRUE)
        substr(col, 1L, max_len)
      })
      df
    }

    # ------------------------------------------------------------------
    # Helper 2: generate a SAS LENGTH statement string from a data frame.
    # Write it to a SAS macro variable with symput(), then use it in a
    # DATA step to re-stamp column widths after df2sd().
    #
    # Pattern:
    #   df  <- trim_char_widths(df)
    #   symput("my_lengths", sas_length_stmt(df))
    #   df2sd(df, "raw_ds", "work")
    #   -- back in SAS --
    #   data work.final_ds; &my_lengths. set work.raw_ds; run;
    # ------------------------------------------------------------------
    sas_length_stmt <- function(df, min_width = 1L) {
      char_cols <- names(df)[sapply(df, is.character)]
      if (length(char_cols) == 0) return("")
      parts <- sapply(char_cols, function(col) {
        max_len <- max(nchar(df[[col]], type = "bytes"), na.rm = TRUE)
        max_len <- max(max_len, min_width, na.rm = TRUE)
        paste0(col, " $", max_len)
      })
      paste("length", paste(parts, collapse = " "), ";")
    }

    # Build a tidy inventory of installed packages
    pkgs <- as.data.frame(
      installed.packages()[, c("Package","Version","Priority",
                               "Depends","Imports","License")],
      stringsAsFactors = FALSE,
      row.names        = FALSE
    )
    pkgs[is.na(pkgs)] <- ""
    pkgs$Loaded <- ifelse(pkgs$Package %in% loadedNamespaces(), "Yes", "No")
    pkgs        <- pkgs[order(pkgs$Package), ]

    cat("Total packages installed:", nrow(pkgs), "\n")
    cat("Packages loaded in session:", sum(pkgs$Loaded == "Yes"), "\n")

    pkgs <- trim_char_widths(pkgs, min_width = 1)

    # Build a LENGTH statement string for SAS so the DATA step
    # can re-stamp correct column widths after df2sd() / parquet transfer.
    # The parquet engine always produces $32767 for character columns;
    # this is the only reliable way to fix lengths on the SAS side.
    char_cols  <- names(pkgs)[sapply(pkgs, is.character)]
    len_parts  <- sapply(char_cols, function(col) {
      max_len <- max(nchar(pkgs[[col]], type = "bytes"), na.rm = TRUE)
      max_len <- max(max_len, 1L)
      paste0(col, " $", max_len)
    })
    len_stmt <- paste("length", paste(len_parts, collapse = " "), ";")
    symput("r_pkg_lengths", len_stmt)

    df2sd(pkgs, "r_packages_raw", "work")
    cat("Lengths macro: ", len_stmt, "\n")
  endsubmit;
run;

/* Re-stamp correct character lengths — parquet engine always produces $32767.
   R wrote the correct LENGTH statement into &r_pkg_lengths. via symput().   */
data work.r_packages;
  &r_pkg_lengths.
  set work.r_packages_raw;
run;

proc delete data=work.r_packages_raw; run;

proc print data=work.r_packages(obs=20) noobs;
  title "Installed R Packages (first 20)";
  var Package Version Loaded;
run;
title;

/*=============================================================================
  SECTION 1: Create ADaM-like Sample Data
=============================================================================*/

data work.adlb;
  call streaminit(42);
  length usubjid $10 trt01p $20 avisit $10 paramcd $8;
  do i = 1 to 80;
    usubjid = cats("SUBJ-", put(i, z3.));
    trt01p  = ifc(i <= 40, "DRUG A", "PLACEBO");
    base    = round(8 + rand("normal") * 0.8, 0.1);
    paramcd = "HBA1C";
    do j = 1 to 4;
      avisit = cats("WEEK", put(j*4, z2.));
      chg    = round(
                 (ifc(trt01p="DRUG A", -0.9, -0.2)) * j/4
                 + rand("normal") * 0.4,
                 0.01);
      output;
    end;
  end;
  drop i j;
run;

data work.adtte;
  call streaminit(99);
  length usubjid $10 trt01p $20 paramcd $8;
  do i = 1 to 80;
    usubjid = cats("SUBJ-", put(i, z3.));
    trt01p  = ifc(i <= 40, "DRUG A", "PLACEBO");
    paramcd = "OS";
    aval    = round(rand("exponential") *
                    ifc(trt01p="DRUG A", 18, 12), 0.1);
    cnsr    = ifc(aval > 24, 1, 0);
    aval    = min(aval, 24);
    output;
  end;
  drop i;
run;

/*=============================================================================
  SECTION 2: Data Transfer – sd2df() and df2sd()
  sd2df("dataset", "libname")  pulls a SAS dataset into R as a data frame.
  df2sd(df, "dataset", "lib")  pushes an R data frame back to SAS.
  Note: libname is a separate third argument, not dot-notation.
=============================================================================*/

/* ---- 2a. SAS → R with sd2df ------------------------------------------- */
/*
  NOTE: sd2df() returns column names exactly as stored in the SAS dataset.
  User-created datasets (data step) are typically lowercase; SAS-supplied
  datasets (sashelp.*) and some others may be mixed case.
  Always normalise immediately after sd2df() to avoid column-not-found errors:
    In R:      names(df) <- toupper(names(df))
    In Python: df.columns = df.columns.str.lower()  (or .str.upper())
*/
proc r;
  submit;
    df <- sd2df("adlb", "work")
    names(df) <- toupper(names(df))   # normalise to uppercase
    cat("Rows:", nrow(df), "| Cols:", ncol(df), "\n")
    str(df)
  endsubmit;
run;

/* ---- 2b. R → SAS with df2sd ------------------------------------------- */
proc r;
  submit;
    library(dplyr)
    df <- sd2df("adlb", "work")
    names(df) <- toupper(names(df))

    summary_df <- df |>
      group_by(TRT01P, AVISIT) |>
      summarise(
        N        = n(),
        MEAN_CHG = round(mean(CHG, na.rm = TRUE), 4),
        SD_CHG   = round(sd(CHG,  na.rm = TRUE), 4),
        MIN_CHG  = round(min(CHG, na.rm = TRUE), 4),
        MAX_CHG  = round(max(CHG, na.rm = TRUE), 4),
        .groups  = "drop"
      )

    # Display in Results window
    show(summary_df, title = "HbA1c Summary by Treatment and Visit")

    summary_df <- trim_char_widths(summary_df)
    symput("r_summary_lengths", sas_length_stmt(summary_df))
    df2sd(summary_df, "r_summary_raw", "work")
    cat("Written to work.r_summary_raw\n")
  endsubmit;
run;

data work.r_summary;
  &r_summary_lengths.
  set work.r_summary_raw;
run;

proc delete data=work.r_summary_raw; run;

proc print data=work.r_summary label noobs;
  title "Descriptive Statistics from R (via df2sd)";
  format mean_chg sd_chg min_chg max_chg 8.4;
run;
title;

/*=============================================================================
  SECTION 3: Macro Variable Exchange
  symget("macvar")          – read SAS macro variable into R at runtime
  symput("macvar", "value") – write R value back to SAS macro variable
  submit("sas code")        – execute SAS code (e.g. %let) from within R
  sasfnc("func" <, args>)   – call a SAS function from R
=============================================================================*/

%let study_id  = STUDY001;
%let endpoint  = HBA1C;
%let alpha     = 0.05;
%let cutoff_wk = WEEK16;

/* ---- 3a. symget() – read macro variables in R ------------------------- */
proc r;
  submit;
    study_id  <- symget("study_id")
    endpoint  <- symget("endpoint")
    alpha_val <- as.numeric(symget("alpha"))
    cutoff_wk <- symget("cutoff_wk")

    cat("Study:", study_id, "| Endpoint:", endpoint,
        "| Alpha:", alpha_val, "| Visit:", cutoff_wk, "\n")

    df      <- sd2df("adlb", "work")
    names(df) <- toupper(names(df))
    df_wk16 <- df[df$AVISIT == cutoff_wk & df$PARAMCD == endpoint, ]
    cat("Rows at", cutoff_wk, ":", nrow(df_wk16), "\n")

    t_result <- t.test(CHG ~ TRT01P, data = df_wk16,
                       conf.level = 1 - alpha_val)
    print(t_result)
  endsubmit;
run;

/* ---- 3b. symput() – write R results back to SAS ----------------------- */
proc r;
  submit;
    df    <- sd2df("adlb", "work")
    names(df) <- toupper(names(df))
    df_wk <- df[df$AVISIT == "WEEK16" & df$PARAMCD == "HBA1C", ]
    t_res <- t.test(CHG ~ TRT01P, data = df_wk)

    pval     <- round(t_res$p.value, 4)
    tstat    <- round(t_res$statistic[["t"]], 4)
    diff_est <- round(diff(t_res$estimate), 4)

    symput("r_pvalue",   as.character(pval))
    symput("r_tstat",    as.character(tstat))
    symput("r_diff_est", as.character(diff_est))

    cat("p-value:", pval, "| t-stat:", tstat,
        "| mean diff:", diff_est, "\n")
  endsubmit;
run;

%put NOTE: R t-test p-value  = &r_pvalue.;
%put NOTE: R t-statistic     = &r_tstat.;
%put NOTE: R mean difference = &r_diff_est.;

%if %sysevalf(&r_pvalue. < &alpha.) %then %do;
  %put NOTE: Significant at alpha=&alpha. (p=&r_pvalue.).;
%end;
%else %do;
  %put NOTE: Not significant at alpha=&alpha. (p=&r_pvalue.).;
%end;

/* ---- 3c. submit() and sasfnc() ---------------------------------------- */
proc r;
  submit;
    df   <- sd2df("adlb", "work")
    names(df) <- toupper(names(df))
    nobs <- nrow(df)

    # submit() executes SAS code from within R
    submit(paste0("%let r_nobs=", nobs, ";"))
    cat("Submitted %let r_nobs =", nobs, "\n")

    # sasfnc() calls a SAS function – remove the %sysfunc() wrapper
    today_sas <- sasfnc("today")
    cat("SAS TODAY() =", today_sas, "\n")

    # Check if a libref exists
    work_exists <- sasfnc("exist", "work", "LIBREF")
    cat("WORK libref exists:", work_exists, "\n")
  endsubmit;
run;

%put NOTE: N from R = &r_nobs.;

/*=============================================================================
  SECTION 4: Visualization
  rplot(obj)                       – render R plot object in Results window
  rplot(obj, filename="name.png")  – render and also save to file
  renderImage("full/path.png")     – render a previously saved image
  sas$workpath                     – path to the SAS WORK directory
=============================================================================*/

proc r;
  submit;
    library(ggplot2)
    df <- sd2df("adlb", "work")
    names(df) <- toupper(names(df))

    p <- ggplot(df, aes(x = AVISIT, y = CHG, fill = TRT01P)) +
           geom_boxplot(alpha = 0.7) +
           scale_fill_manual(values = c("DRUG A"  = "#0072B2",
                                        "PLACEBO" = "#E69F00")) +
           labs(title = "HbA1c Change from Baseline by Visit",
                x     = "Visit",
                y     = "Change from Baseline (%)",
                fill  = "Treatment") +
           theme_bw() +
           theme(axis.text.x = element_text(angle = 45, hjust = 1))

    # rplot renders directly in Results; optional filename saves a copy
    rplot(p, filename = "boxplot_hba1c.png")

    # renderImage can display any previously saved PNG/JPG/SVG
    plot_path <- paste0(sas$workpath, "boxplot_hba1c.png")
    renderImage(plot_path)
  endsubmit;
run;

/*=============================================================================
  SECTION 5: Running an External R Script (inFile=)
  Useful when R code is already maintained separately or stored in SAS Content.
=============================================================================*/

/* Store a small R script in WORK for demo purposes */
data _null_;
  file "%sysfunc(pathname(work))/explore_adlb.r";
  put 'df <- sd2df("adlb", "work")';
  put 'names(df) <- toupper(names(df))';
  put 'cat("External script: rows =", nrow(df), "\n")';
  put 'show(head(df, 5), title = "First 5 rows of ADLB")';
run;

filename rscript "%sysfunc(pathname(work))/explore_adlb.r";

/* Execute the external script via inFile= */
proc r inFile=rscript;
  submit;
  endsubmit;
run;

filename rscript clear;

/* SAS Content example (commented out – requires SAS Viya content service):
filename rscript filesrvc
  folderPath='/Users/youruser/My Folder/R-Scripts'
  filename='explore_adlb.r';
proc r inFile=rscript;
  submit;
  endsubmit;
run;
*/

/*=============================================================================
  SECTION 6: MMRM Model Comparison (SAS PROC MIXED vs R mmrm)
  Clinical use case: independent QC of primary efficacy model
=============================================================================*/

/* ---- 6a. SAS PROC MIXED (reference / primary model) ------------------- */
proc mixed data=work.adlb;
  class usubjid trt01p avisit(ref="WEEK04");
  model chg = base trt01p avisit trt01p*avisit / ddfm=kr solution;
  repeated avisit / subject=usubjid type=un;
  lsmeans trt01p*avisit / diff cl alpha=0.05;
  ods output lsmeans=work.sas_lsmeans
             solutionf=work.sas_fixed_effects;
run;

/* ---- 6b. R mixed model (independent QC model) -------------------------
   Preferred: mmrm package (Kenward-Roger, unstructured covariance)
   Fallback:  nlme::lme (always available in base R)
   In a locked-down Viya environment, ask your admin to install mmrm.
   The fallback produces comparable fixed-effect estimates for QC purposes.
-------------------------------------------------------------------- */
proc r restart;
  submit;
    # Redefine helper after restart (proc r restart clears all R objects)
    trim_char_widths <- function(df, min_width = 1L) {
      char_cols <- sapply(df, is.character)
      df[char_cols] <- lapply(df[char_cols], function(col) {
        max_len <- max(nchar(col, type = "bytes", allowNA = TRUE,
                             keepNA = FALSE), na.rm = TRUE)
        max_len <- max(max_len, min_width, na.rm = TRUE)
        substr(col, 1L, max_len)
      })
      df
    }

    df <- sd2df("adlb", "work")
    names(df) <- toupper(names(df))
    df$AVISIT  <- factor(df$AVISIT,
                          levels = c("WEEK04","WEEK08","WEEK12","WEEK16"))
    df$TRT01P  <- factor(df$TRT01P,  levels = c("DRUG A","PLACEBO"))
    df$USUBJID <- factor(df$USUBJID)

    if (requireNamespace("mmrm", quietly = TRUE)) {
      # --- preferred path: mmrm with Kenward-Roger ----------------------
      library(mmrm)
      fit <- mmrm(
        formula = CHG ~ BASE + TRT01P + AVISIT + TRT01P:AVISIT +
                  us(AVISIT | USUBJID),
        data    = df,
        method  = "Kenward-Roger"
      )
      fe       <- as.data.frame(summary(fit)$coefficients)
      fe$PARAM <- rownames(fe)
      names(fe) <- c("R_ESTIMATE","R_SE","R_DF","R_TVALUE","R_PVALUE","PARAM")
      fe <- fe[, c("PARAM","R_ESTIMATE","R_SE","R_DF","R_TVALUE","R_PVALUE")]
      cat("Model fitted using: mmrm (Kenward-Roger)\n")

    } else {
      # --- fallback path: nlme::lme (ships with base R) -----------------
      cat("NOTE: mmrm not installed – falling back to nlme::lme\n")
      cat("Ask your SAS administrator to install the mmrm package.\n")
      library(nlme)
      fit <- lme(
        fixed  = CHG ~ BASE + TRT01P + AVISIT + TRT01P:AVISIT,
        random = ~ 1 | USUBJID,
        data   = df,
        na.action = na.omit
      )
      coef_tbl  <- summary(fit)$tTable
      fe        <- as.data.frame(coef_tbl)
      fe$PARAM  <- rownames(fe)
      # Align column names to the same schema as the mmrm path
      names(fe) <- c("R_ESTIMATE","R_SE","R_DF","R_TVALUE","R_PVALUE","PARAM")
      fe <- fe[, c("PARAM","R_ESTIMATE","R_SE","R_DF","R_TVALUE","R_PVALUE")]
      cat("Model fitted using: nlme::lme\n")
    }

    show(fe, title = "R Mixed Model Fixed Effects")
    fe <- trim_char_widths(fe)
    symput("r_mmrm_lengths", sas_length_stmt(fe))
    df2sd(fe, "r_mmrm_fe_raw", "work")
    cat("Results written to work.r_mmrm_fe_raw\n")
  endsubmit;
run;

/* ---- 6c. Side-by-side comparison --------------------------------------- */

/* Re-stamp correct lengths from the macro variable R wrote via symput() */
data work.r_mmrm_fe;
  &r_mmrm_lengths.
  set work.r_mmrm_fe_raw;
run;

proc delete data=work.r_mmrm_fe_raw; run;

data work.sas_fe_clean;
  set work.sas_fixed_effects;
  length param $50;
  param = strip(effect);
  rename estimate = sas_estimate
         stderr   = sas_se
         probt    = sas_pvalue;
  keep param estimate stderr probt;
run;

proc sql;
  create table work.model_comparison as
  select
    coalesce(s.param, r.param) as param length=50,
    s.sas_estimate,
    r.r_estimate,
    s.sas_se,
    r.r_se,
    s.sas_pvalue,
    r.r_pvalue,
    abs(s.sas_estimate - r.r_estimate) as abs_diff_est,
    case
      when abs(s.sas_estimate - r.r_estimate) > 0.001 then "REVIEW"
      else "OK"
    end as qc_status length=6
  from work.sas_fe_clean s
  full join work.r_mmrm_fe r
    on upcase(s.param) = upcase(r.param)
  order by param;
quit;

proc print data=work.model_comparison label noobs;
  title "MMRM Model Comparison: SAS PROC MIXED vs R mmrm";
  label sas_estimate = "SAS Estimate"
        r_estimate   = "R Estimate"
        abs_diff_est = "Abs Diff"
        qc_status    = "QC Status";
  format sas_estimate r_estimate sas_se r_se 8.4
         sas_pvalue r_pvalue pvalue6.4
         abs_diff_est 8.6;
run;
title;

/*=============================================================================
  SECTION 7: Kaplan-Meier with R survival / survminer
  survival ships with base R; survminer may need admin installation.
  Fallback produces the KM plot using base R graphics if survminer is absent.
=============================================================================*/

proc r;
  submit;
    library(survival)

    df        <- sd2df("adtte", "work")
    names(df) <- toupper(names(df))
    df        <- df[df$PARAMCD == "OS", ]
    df$TRT01P <- factor(df$TRT01P, levels = c("DRUG A","PLACEBO"))

    fit <- survfit(Surv(AVAL, CNSR == 0) ~ TRT01P, data = df)

    # Log-rank test → SAS macro variable (works regardless of survminer)
    lr_test <- survdiff(Surv(AVAL, CNSR == 0) ~ TRT01P, data = df)
    lr_pval <- round(1 - pchisq(lr_test$chisq, df = 1), 4)
    symput("r_logrank_p", as.character(lr_pval))
    cat("Log-rank p-value:", lr_pval, "\n")

    if (requireNamespace("survminer", quietly = TRUE)) {
      # --- preferred path: survminer ------------------------------------
      library(survminer)
      p <- ggsurvplot(fit,
             data       = df,
             pval       = TRUE,
             conf.int   = TRUE,
             risk.table = TRUE,
             palette    = c("#0072B2","#E69F00"),
             title      = "Overall Survival by Treatment (PROC R)",
             xlab       = "Time (months)",
             ylab       = "Survival Probability")
      rplot(p, filename = "km_plot_procr.png")

      med_df        <- as.data.frame(surv_median(fit))
      med_df$STRATA <- gsub("TRT01P=", "", rownames(med_df))
      names(med_df) <- c("MEDIAN","LOWER_95","UPPER_95","STRATA")
      med_df        <- med_df[, c("STRATA","MEDIAN","LOWER_95","UPPER_95")]
      cat("KM plot rendered using: survminer\n")

    } else {
      # --- fallback path: base R plot (headless server, no X11) ----------
      cat("NOTE: survminer not installed – using base R plot\n")
      cat("Ask your SAS administrator to install survminer.\n")
      plot_path <- paste0(sas$workpath, "km_plot_procr.png")
      # type="cairo" renders off-screen on headless Linux (no X11 needed)
      png(plot_path, width = 800, height = 600, type = "cairo")
      plot(fit, col = c("#0072B2","#E69F00"), lwd = 2,
           xlab = "Time (months)", ylab = "Survival Probability",
           main = "Overall Survival by Treatment (PROC R)")
      legend("topright", levels(df$TRT01P),
             col = c("#0072B2","#E69F00"), lwd = 2)
      dev.off()
      renderImage(plot_path)

      # Extract median survival from survfit summary
      s         <- summary(fit)$table
      med_df    <- as.data.frame(s[, c("median","0.95LCL","0.95UCL")])
      med_df$STRATA <- gsub("TRT01P=", "", rownames(med_df))
      names(med_df) <- c("MEDIAN","LOWER_95","UPPER_95","STRATA")
      med_df        <- med_df[, c("STRATA","MEDIAN","LOWER_95","UPPER_95")]
    }

    show(med_df, title = "Median Overall Survival")
    med_df <- trim_char_widths(med_df)
    symput("r_km_lengths", sas_length_stmt(med_df))
    df2sd(med_df, "r_km_median_raw", "work")
  endsubmit;
run;

%put NOTE: Log-rank p-value from R = &r_logrank_p.;

data work.r_km_median;
  &r_km_lengths.
  set work.r_km_median_raw;
run;

proc delete data=work.r_km_median_raw; run;

proc print data=work.r_km_median label noobs;
  title "Median Overall Survival (R survminer via PROC R)";
  label strata   = "Treatment"
        median   = "Median (months)"
        lower_95 = "95% CI Lower"
        upper_95 = "95% CI Upper";
  format median lower_95 upper_95 8.1;
run;
title;

/*=============================================================================
  SECTION 8: Store Final Results to Permanent SAS Library
=============================================================================*/

/* In a real study, point to your study results library:
   libname results "/clinical/study001/adam/results";
   For this demo we write directly to WORK.                               */

data work.mmrm_estimates;
  set work.r_mmrm_fe;
  length source $10 run_dttm $20;
  source   = "R mmrm";
  run_dttm = put(datetime(), datetime20.);
run;

data work.km_median_os;
  set work.r_km_median;
  length source $10 run_dttm $20;
  source   = "R survminer";
  run_dttm = put(datetime(), datetime20.);
run;

data work.model_qc_comparison;
  set work.model_comparison;
  length run_dttm $20;
  run_dttm = put(datetime(), datetime20.);
run;

proc contents data=work.mmrm_estimates varnum; run;
proc contents data=work.km_median_os   varnum; run;

%put NOTE: All R results stored as SAS datasets.;

/* Release R resources when fully done */
proc r terminate;
run;

/*=============================================================================
  END OF DEMO 3 – PROC R

  PROC R Statement Options:
    proc r;             reuse existing R subprocess (shared session)
    proc r restart;     fresh R session – clears all R objects
    proc r terminate;   shut down R subprocess, release resources
    proc r inFile=ref;  execute an external .r script file

  Callback Quick Reference (case-sensitive):
  ┌──────────────────────────────────────────────────────────────────────┐
  │  sd2df("ds", "lib")          SAS dataset → R data frame             │
  │  df2sd(df, "ds", "lib")      R data frame → SAS dataset             │
  │    → call trim_char_widths(df) first to avoid $32767 columns        │
  │  symget("macvar")            Read SAS macro variable                 │
  │  symput("macvar", "value")   Write value → SAS macro variable        │
  │  submit("sas code")          Execute SAS code from R                 │
  │  sasfnc("func" <, args>)     Call a SAS function                     │
  │  rplot(obj <, filename=f>)   Render plot in Results window           │
  │  renderImage("path.png")     Render saved image in Results           │
  │  show(obj, title=, count=)   Display R object in Results             │
  │  sas$workpath                Path to SAS WORK directory              │
  └──────────────────────────────────────────────────────────────────────┘
=============================================================================*/
