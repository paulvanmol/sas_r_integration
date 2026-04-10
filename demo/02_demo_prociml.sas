/*=============================================================================
  DEMO 1: PROC IML SUBMIT/R
  Case Study: SAS & R Integration for Clinical Programmers
  Approach: Classic PROC IML with SUBMIT/R block
  Requires: RLANG option enabled, R installed on compute server
=============================================================================*/

/* ---- 0. Setup ----------------------------------------------------------- */
/*options rlang; */  /* must be enabled in sasv9.cfg or by admin */

/* Create sample ADaM-like lab data (ADLB subset for HbA1c) */
data work.adlb;
  call streaminit(42);
  length usubjid $10 trt01p $20 avisit $10 paramcd $8;
  do i = 1 to 60;
    usubjid = cats("SUBJ-", put(i, z3.));
    trt01p  = ifc(i <= 30, "DRUG A", "PLACEBO");
    base    = round(8 + rand("normal") * 0.8, 0.1);
    do j = 1 to 4;
      avisit = cats("WEEK", put(j*4, z2.));
      /* Drug A reduces HbA1c more than placebo */
      chg = round(
              (ifc(trt01p="DRUG A", -0.8, -0.2)) * j/4
              + rand("normal") * 0.4,
              0.01);
      output;
    end;
  end;
  drop i j;
run;

/* ---- 1. Exploratory plot via R ----------------------------------------- */
proc iml;
  /* Read data into IML matrices */
  use work.adlb;
  read all var {base chg} into X;
  read all var {trt01p}   into trt;
  close work.adlb;

  base = X[,1];
  chg  = X[,2];

  /* Export to R */
  call ExportMatrixToR(base, "base");
  call ExportMatrixToR(chg,  "chg");
  call ExportMatrixToR(trt,  "trt");

  /* Run R: scatter plot of baseline vs change */
  submit / R;
    library(ggplot2)
    df <- data.frame(base = as.numeric(base),
                     chg  = as.numeric(chg),
                     trt  = as.character(trt))
    p <- ggplot(df, aes(x = base, y = chg, color = trt)) +
           geom_point(alpha = 0.6, size = 2) +
           geom_smooth(method = "lm", se = TRUE) +
           labs(title  = "Baseline HbA1c vs Change from Baseline",
                x      = "Baseline HbA1c (%)",
                y      = "Change from Baseline (%)",
                color  = "Treatment") +
           theme_bw()
    ggsave("iml_baseline_vs_change.png", p, width = 6, height = 4, dpi = 150)
    cat("Plot saved.\n")
  endsubmit;

  /* ---- 2. Simple linear model in R, retrieve coefficients -------------- */
  submit / R;
    fit   <- lm(chg ~ base + trt)
    coefs <- as.numeric(coef(fit))
    names(coefs) <- names(coef(fit))
    cat("R lm coefficients:\n")
    print(coefs)
  endsubmit;

  call ImportMatrixFromR(coefs, "coefs");
  print "Linear model coefficients from R:" coefs;

  /* ---- 3. Pass a macro variable value into R --------------------------- */
  /* Resolve macro variable to IML scalar, then export */
  %let alpha = 0.05;
  alpha_val = &alpha.;
  call ExportMatrixToR(alpha_val, "alpha_val");

  submit / R;
    cat("Significance level passed from SAS macro: alpha =", alpha_val, "\n")
    pval <- summary(fit)$coefficients["trtPLACEBO", "Pr(>|t|)"]
    cat("p-value for treatment effect:", round(pval, 4), "\n")
    sig  <- as.numeric(pval < alpha_val)
  endsubmit;

  call ImportMatrixFromR(sig, "sig");
  if sig = 1 then
    print "Treatment effect is statistically significant at alpha = &alpha.";
  else
    print "Treatment effect is NOT significant at alpha = &alpha.";

  /* ---- 4. Write R results back to a SAS dataset ----------------------- */
  submit / R;
    result_df <- data.frame(
      param    = names(coef(fit)),
      estimate = as.numeric(coef(fit)),
      se       = summary(fit)$coefficients[, "Std. Error"],
      pvalue   = summary(fit)$coefficients[, "Pr(>|t|)"]
    )
  endsubmit;

  /* Import each column as a matrix */
  call importMatrixFromR(param, "result_df$param");
  call ImportMatrixFromR(estimates, "result_df$estimate");
  call ImportMatrixFromR(se_vals,   "result_df$se");
  call ImportMatrixFromR(pvals,     "result_df$pvalue");

  /* Create output dataset */
  create work.iml_r_results
    var {param estimates se_vals pvals};
  append;
  close work.iml_r_results;

quit;

/* ---- 5. Display results ------------------------------------------------ */
proc print data=work.iml_r_results label noobs;
  title "Linear Model Results from R (via PROC IML SUBMIT/R)";
  label estimates = "Estimates"
        se_vals   = "Std Error"
        pvals     = "p-value";
  format estimates se_vals 8.4 pvals pvalue6.4;
run;
title;

/*=============================================================================
  NOTE: PROC IML SUBMIT/R is the established approach for SAS 9.4 and Viya.
  Key limitation: only matrices/vectors transfer; no direct data frame support.
  For full dataset transfer, use PROC R (Viya 2026.03) instead.
=============================================================================*/
