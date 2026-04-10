/*===========================================================================
  PROC R Integration — Clinical Programming Hands-On Practice
  SAS Viya Stable 2026.03
  
  Case Study: Pharmacokinetic & Lab Safety Analysis — Study STUDY-2024-001
  Drug: DrugX_100mg vs Placebo  |  N=60 subjects  |  6 visits
  
  Sections:
    0. Prerequisites & Environment Check
    1. Setup — Create Synthetic ADaM Datasets (ADLB + ADTTE)
    2. Exercise A — Data Transfer: sd2df() and df2sd()
    3. Exercise B — Macro Variables: symget() and symput()
    4. Exercise C — Graphics: rplot() and renderImage()
    5. Exercise D — Mixed Model: PROC R (lme4) vs PROC MIXED
    6. Exercise E — Survival Analysis: PROC R (survival) vs PROC LIFETEST
    7. Exercise F — Store Final Results Back as SAS Datasets
    
  Prerequisites:
    - SAS Viya Stable 2026.03+ with PROC R enabled
    - R packages: lme4, broom.mixed, survival, survminer, ggplot2, dplyr
    - Instructor: verify PROC R is enabled before the session (see Appendix)
    
  NOTE: Column names arrive in R as UPPERCASE from SAS.
        R is case-sensitive. Use names(df) <- tolower(names(df)) or
        names(df) <- toupper(names(df)) for consistency.
        Always restore to UPPERCASE before df2sd() for SAS convention.
===========================================================================*/


/*---------------------------------------------------------------------------
  SECTION 0 — PREREQUISITES & ENVIRONMENT CHECK
  Run this first. Confirm PROC R is available before continuing.
---------------------------------------------------------------------------*/

/* 0.1 Check PROC R is enabled (should print R version to log) */
proc r restart;
  submit;
    cat("=== R Environment Check ===\n")
    print(R.version.string)
    cat("Available packages:\n")
    pkgs <- c("lme4","broom.mixed","survival","survminer","ggplot2","dplyr")
    installed <- pkgs %in% rownames(installed.packages())
    print(data.frame(Package=pkgs, Installed=installed))
  endsubmit;
run;

/*
  EXPECTED LOG OUTPUT:
  === R Environment Check ===
  [1] "R version 4.x.x (....)"
  Available packages:
    Package  Installed
  1    lme4      TRUE
  2 broom.mixed  TRUE
  ...
  
  If PROC R is not enabled, ask the administrator to:
    1. Set PROC_RPATH and PROC_M2PATH environment variables
    2. Add to compute server autoexec:
         lockdown enable_ams=R;
         lockdown enable_ams=SOCKET;
*/

/* 0.2 Set libname for output (adjust path to your environment) */
%let outlib  = WORK;          /* Change to a permanent libname if desired   */
%let drug    = DrugX_100mg;   /* Treatment name macro variable               */
%let placebo = Placebo;       /* Control arm                                  */
%let study   = STUDY-2024-001;


/*---------------------------------------------------------------------------
  SECTION 1 — SETUP: CREATE SYNTHETIC ADaM DATASETS
  
  Creates two ADaM-like datasets in WORK:
    WORK.ADLB  — Alanine Aminotransferase (ALT) lab data, 6 visits
    WORK.ADTTE — Time-to-first-adverse-event, one row per subject
  
  These simulate a small clinical trial: 30 subjects per arm, 6 visits.
  Real studies would read from a permanent libname.
---------------------------------------------------------------------------*/

/* 1.1 Create ADLB — longitudinal lab safety data */
data work.adlb;
  call streaminit(42);                    /* reproducible random seed */
  length USUBJID $12 TRTP $20 PARAMCD $8 PARAM $40 AVISIT $20;
  
  do subj = 1 to 60;
    USUBJID  = cats("SUBJ-", put(subj, z3.));
    TRTP     = ifc(subj <= 30, "&drug", "&placebo");
    PARAMCD  = "ALT";
    PARAM    = "Alanine Aminotransferase (U/L)";
    STUDYID  = "&study";
    
    /* Baseline value: drug arm slightly higher at baseline */
    base_mean = ifc(subj <= 30, 32, 28);
    BASE      = round(base_mean + rand("Normal", 0, 5), 1);
    if BASE < 10 then BASE = 10;
    ABLFL     = "Y";
    
    do visit = 0 to 5;
      AVISITN  = visit;
      AVISIT   = cats("Week ", put(visit * 4, best.));
      if visit = 0 then AVISIT = "Baseline";
      
      /* Drug arm shows transient ALT increase, resolves by week 16 */
      if subj <= 30 then
        trt_effect = 8 * exp(-0.3 * visit) * (visit > 0);
      else
        trt_effect = 0;
      
      AVAL = round(BASE + trt_effect + rand("Normal", 0, 4), 1);
      if AVAL < 5 then AVAL = 5;
      
      CHG  = round(AVAL - BASE, 1);
      ABLFL = ifc(visit = 0, "Y", " ");
      
      output;
    end;
  end;
  
  drop subj visit base_mean trt_effect;
run;

proc sort data=work.adlb; by USUBJID AVISITN; run;

/* 1.2 Create ADTTE — time-to-first adverse event */
data work.adtte;
  call streaminit(99);
  length USUBJID $12 TRTP $20 PARAMCD $8 PARAM $40;
  
  do subj = 1 to 60;
    USUBJID = cats("SUBJ-", put(subj, z3.));
    TRTP    = ifc(subj <= 30, "&drug", "&placebo");
    PARAMCD = "TTFAE";
    PARAM   = "Time to First Adverse Event";
    STUDYID = "&study";
    
    /* Drug arm has shorter time-to-event (more events) */
    if subj <= 30 then
      AVAL = round(rand("Exponential", 1/80) * 100 + 10, 1);
    else
      AVAL = round(rand("Exponential", 1/120) * 100 + 10, 1);
    
    if AVAL > 168 then do; AVAL = 168; CNSR = 1; end;
    else CNSR = 0;
    
    output;
  end;
  drop subj;
run;

/* 1.3 Quick check */
title "ADLB: first 12 rows";
proc print data=work.adlb(obs=12); 
  var USUBJID TRTP PARAMCD AVISIT AVISITN BASE AVAL CHG ABLFL;
run;

title "ADTTE: first 10 rows";
proc print data=work.adtte(obs=10);
  var USUBJID TRTP PARAMCD AVAL CNSR;
run;
title;


/*---------------------------------------------------------------------------
  SECTION 2 — EXERCISE A: DATA TRANSFER — sd2df() and df2sd()
  
  Goal: Import ADLB into R, compute summary statistics, export back to SAS.
  
  Key concept:
    - SAS column names arrive in R as UPPERCASE
    - R is case-sensitive — decide on a convention and apply it immediately
    - Restore UPPERCASE before df2sd() so SAS downstream code works
---------------------------------------------------------------------------*/

/* Exercise A.1 — Basic import and column name inspection */
proc r;
  submit;
    df <- sd2df("work.adlb")
    
    cat("=== Column names as received from SAS ===\n")
    print(names(df))
    cat("\nDimensions:", nrow(df), "rows x", ncol(df), "cols\n")
    cat("\nFirst 3 rows:\n")
    print(head(df[, c("USUBJID","TRTP","AVISIT","AVAL","CHG")], 3))
  endsubmit;
run;

/*
  EXPECTED: Column names are UPPERCASE as stored in SAS:
  [1] "USUBJID" "TRTP" "PARAMCD" "PARAM" "STUDYID" "BASE" "ABLFL"
      "AVISITN" "AVISIT" "AVAL" "CHG"
*/


/* Exercise A.2 — Convert to lowercase for R processing, summarise, restore */
proc r;
  submit;
    library(dplyr)
    df <- sd2df("work.adlb")
    
    # BEST PRACTICE: lowercase immediately for idiomatic R code
    names(df) <- tolower(names(df))
    
    # Now use lowercase names freely in R 
    bl <- df[df$ablfl == "Y", ]     
    
    summary_stats <- df %>%
      group_by(trtp, avisit, avisitn) %>%
      summarise(
        n        = n(),
        mean_chg = round(mean(chg, na.rm = TRUE), 2),
        sd_chg   = round(sd(chg,   na.rm = TRUE), 2),
        min_chg  = min(chg,  na.rm = TRUE),
        max_chg  = max(chg,  na.rm = TRUE),
        .groups  = "drop"
      ) %>%
      arrange(trtp, avisitn)
    
    cat("=== Summary Statistics ===\n")
    print(summary_stats)
    # return variables back to uppercase before df2sd() method    
    names(summary_stats) <- toupper(names(summary_stats))
    df2sd(summary_stats, "r_summary_a")
  endsubmit;
run;

title "Exercise A — R Summary Stats (imported back from R via df2sd)";
proc print data=work.r_summary_a noobs;
  var TRTP AVISIT AVISITN N MEAN_CHG SD_CHG MIN_CHG MAX_CHG;
  format MEAN_CHG SD_CHG 8.2;
run;
title;

/*
  >> YOUR TURN:
     1. Modify the dplyr pipeline above to also compute the median change.
     2. Filter to only PARAMCD = "ALT" before summarising (it already is,
        but add the filter explicitly for good practice).
     3. Change the round() to 3 decimal places.
*/


/*---------------------------------------------------------------------------
  SECTION 3 — EXERCISE B: MACRO VARIABLES — symget() and symput()
  
  Goal: Pass study parameters into R via SAS macro variables,
        compute scalar results in R, and retrieve them back in SAS.
---------------------------------------------------------------------------*/

/* B.1 — Pass macro variables INTO R with symget() */
proc r;
  submit;
    # Read SAS macro variables into R — always returns character string 
    drug    <- symget("drug")
    placebo <- symget("placebo")
    study   <- symget("study")
    
    cat("Study  :", study,   "\n")
    cat("Drug   :", drug,    "\n")
    cat("Control:", placebo, "\n")
    
    # Use them in data operations 
    df <- sd2df("work.adlb")
    names(df) <- tolower(names(df))
    
    drug_rows <- nrow(df[df$trtp == drug, ])
    ctrl_rows <- nrow(df[df$trtp == placebo, ])
    
    cat("\nRows for", drug,    ":", drug_rows, "\n")
    cat("Rows for", placebo, ":", ctrl_rows, "\n")
  endsubmit;
run;


/* B.2 — Compute in R, send results BACK to SAS with symput() */
proc r;
  submit;
    library(dplyr)
    df <- sd2df("work.adlb")
    names(df) <- tolower(names(df))
    
    # Compute summary scalars 
    n_subjects  <- length(unique(df$usubjid))
    n_drug      <- length(unique(df$usubjid[df$trtp == symget("drug")]))
    n_placebo   <- length(unique(df$usubjid[df$trtp == symget("placebo")]))
    
    mean_pk_alt <- round(
      mean(df$aval[df$trtp == symget("drug") & df$ablfl != "Y"],
           na.rm = TRUE), 2)
    
    max_chg     <- round(max(df$chg, na.rm = TRUE), 2)
    
    # symput() — value MUST be a character string 
    symput("r_n_total",   as.character(n_subjects))
    symput("r_n_drug",    as.character(n_drug))
    symput("r_n_placebo", as.character(n_placebo))
    symput("r_mean_alt",  as.character(mean_pk_alt))
    symput("r_max_chg",   as.character(max_chg))
  endsubmit;
run;

/* B.3 — Use R-derived macro variables in SAS */
%put === Results returned from R ===;
%put Total subjects : &r_n_total;
%put Drug arm (N)   : &r_n_drug;
%put Placebo arm (N): &r_n_placebo;
%put Mean ALT (drug): &r_mean_alt;
%put Max CHG        : &r_max_chg;

title "Study &study — Enrollment Summary";
footnote "R-computed statistics: N=&r_n_total | Drug N=&r_n_drug | Placebo N=&r_n_placebo";
footnote2 "Mean post-baseline ALT (&drug): &r_mean_alt U/L  |  Max CHG from BL: &r_max_chg";
proc report data=work.r_summary_a nowd;
  column TRTP AVISIT N MEAN_CHG SD_CHG;
  define TRTP    / group "Treatment";
  define AVISIT  / group "Visit";
  define N       / analysis sum "N";
  define MEAN_CHG / analysis mean "Mean CHG" format=8.2;
  define SD_CHG  / analysis mean "SD CHG"   format=8.2;
run;
title; footnote; footnote2;

/*
  >> YOUR TURN:
     1. Add a symput() call to send the p-value from a t-test on CHG
        at Week 20: t.test(chg ~ trtp, data=df[df$avisitn==5,])$p.value
     2. Use the p-value macro variable in a title statement below.
*/


/*---------------------------------------------------------------------------
  SECTION 4 — EXERCISE C: GRAPHICS — rplot() and renderImage()
  
  Goal: Create a mean profile plot and a box plot in R,
        display them in SAS Studio Results pane.
  
  NOTE: After tolower(), use lowercase names in ggplot2 aesthetics.
        After toupper(), you can also filter with UPPERCASE.
---------------------------------------------------------------------------*/

/* C.1 — Mean ALT change over visits (ggplot2 via rplot) */
proc r;
  submit;
    library(ggplot2)
    library(dplyr)
    
    df <- sd2df("work.adlb")
    # lowercase for ggplot2 
    names(df) <- tolower(names(df))    
    
    # Summarise for mean profile 
    # exclude baseline CHG=0 
    profile <- df %>%
      filter(avisitn > 0) %>%         
      group_by(trtp, avisitn, avisit) %>%
      summarise(mean_chg = mean(chg, na.rm=TRUE),
                se_chg   = sd(chg, na.rm=TRUE) / sqrt(n()),
                .groups  = "drop")
    
    p1 <- ggplot(profile,
                 aes(x=avisitn, y=mean_chg,
                     color=trtp, group=trtp)) +
      geom_line(linewidth=1.2) +
      geom_point(size=3) +
      geom_errorbar(aes(ymin=mean_chg - se_chg,
                        ymax=mean_chg + se_chg),
                    width=0.3, alpha=0.6) +
      geom_hline(yintercept=0, linetype="dashed", color="grey60") +
      scale_color_manual(values=c("#1B2A5E","#E8631A")) +
      scale_x_continuous(breaks=1:5,
        labels=c("Wk 4","Wk 8","Wk 12","Wk 16","Wk 20")) +
      labs(title    = "Mean Change from Baseline in ALT",
           subtitle = paste("Study:", symget("study")),
           x        = "Visit",
           y        = "Mean Change from Baseline (U/L)",
           color    = "Treatment") +
      theme_bw(base_size=12) +
      theme(legend.position="bottom")
    # display in SAS Studio Results pane 
    rplot(p1)    
    
    # Also save to SAS WORK directory for renderImage() demo 
    # full_path <- paste0(sas$workpath, "myplot.png")
    # wk <- symget("SASWORKLOCATION")
    ggplot2::ggsave(paste0(sas$worklocation, "alt_profile.png"),
                    plot=p1, width=8, height=5, dpi=150)
    symput("r_plot_path", paste0(sas$worklocation, "alt_profile.png"))
  endsubmit;
run;
%put Plot saved to: &r_plot_path;


/* C.2 — Box plots of CHG at each visit */
proc r;
  submit;
    library(ggplot2)
    df <- sd2df("work.adlb")
    names(df) <- tolower(names(df))
    
    p2 <- ggplot(df[df$avisitn > 0, ],
                 aes(x=avisit, y=chg, fill=trtp)) +
      geom_boxplot(alpha=0.75, outlier.shape=21) +
      scale_fill_manual(values=c("#007B87","#E8631A")) +
      geom_hline(yintercept=0, linetype="dashed", color="grey50") +
      labs(title    = "Distribution of ALT Change from Baseline",
           subtitle = "By Visit and Treatment Group",
           x        = "Visit",
           y        = "Change from Baseline (U/L)",
           fill     = "Treatment") +
      theme_bw(base_size=11) +
      theme(legend.position="bottom",
            axis.text.x=element_text(angle=25, hjust=1))
    
    rplot(p2)
  endsubmit;
run;


/* C.3 — renderImage() demo: re-display the saved PNG */
proc r;
  submit;
    img <- symget("r_plot_path")
    if (file.exists(img)) {
      cat("Re-displaying saved plot via renderImage():\n", img, "\n")
      renderImage(img)
    } else {
      cat("File not found:", img, "\n")
    }
  endsubmit;
run;

/*
  >> YOUR TURN:
     1. Add a facet_wrap(~paramcd) to p2 (only ALT here, but shows pattern).
     2. Change the color palette to use hex codes from your company style guide.
     3. Save p2 as an SVG file and use renderImage() to display it.
*/


/*---------------------------------------------------------------------------
  SECTION 5 — EXERCISE D: MIXED MODEL — PROC R (lme4) vs PROC MIXED
  
  Goal: Fit a repeated-measures mixed model in both SAS and R,
        compare the fixed-effect estimates using PROC COMPARE.
  
  Model: CHG = TRTP AVISIT TRTP*AVISIT BASE  (+ random intercept per subject)
---------------------------------------------------------------------------*/

/* D.1 — Prepare analysis dataset (post-baseline only) */
data work.adlb_chg;
  set work.adlb;
  where ABLFL ne "Y" and AVISITN > 0;
run;

/* D.2 — SAS reference: PROC MIXED */
proc mixed data=work.adlb_chg;
  class USUBJID AVISIT TRTP;
  model CHG = TRTP AVISIT TRTP*AVISIT BASE / solution;
  repeated AVISIT / subject=USUBJID type=UN;
  lsmeans TRTP*AVISIT / diff cl;
  ods output SolutionF=work.sas_fixed_effects
             LSMeans  =work.sas_lsmeans;
run;

title "SAS PROC MIXED — Fixed Effects";
proc print data=work.sas_fixed_effects noobs;
  var Effect TRTP AVISIT Estimate StdErr tValue Probt;
  format Estimate StdErr tValue 8.4;
run;
title;


/* D.3 — R equivalent: lme4 via PROC R */
proc r;
  submit;
    library(lme4)
    library(broom.mixed)
    library(dplyr)
    library(nlme)
    
    df <- sd2df("work.adlb_chg")
    names(df) <- tolower(names(df))
    
    # Convert character variables to factors (SAS sends as character) 
    df$trtp   <- as.factor(df$trtp)
    df$avisit <- as.factor(df$avisit)
    
    # Fit mixed model — REML for parameter estimates 
    m <- lme(chg ~ trtp * avisit + base ,
              random = ~ 1 | usubjid,
              data = df,
              na.action=na.omit)
    
    # Tidy fixed effects into a data frame
    fixed_ef <- tidy(m, effects="fixed", conf.int=TRUE)
    
    cat("=== lme Fixed Effects ===\n")
    show(fixed_ef,
         title = "lme Fixed Effects",
         count = 30)
    
    cat("\nModel summary:\n")
    cat("  AIC :", AIC(m), "\n")
    cat("  BIC :", BIC(m), "\n")
    cat("  Nobs:", nobs(m), "\n")
    
    # Compute simple per-visit means for comparison 
    visit_means <- df %>%
      group_by(trtp, avisit) %>%
      summarise(r_mean_chg = round(mean(chg, na.rm=TRUE), 4),
                r_n        = n(),
                .groups    = "drop")
    
    # Export both back to SAS 
    names(fixed_ef)   <- toupper(names(fixed_ef))
    names(visit_means) <- toupper(names(visit_means))
    df2sd(fixed_ef,    "work.r_fixed_effects")
    df2sd(visit_means, "work.r_visit_means")
    
    # Store model fit stats in macro variables 
    symput("r_aic", as.character(round(AIC(m), 2)))
    symput("r_bic", as.character(round(BIC(m), 2)))
    symput("r_nobs", as.character(nobs(m)))
  endsubmit;
run;

%put lme4 model: AIC=&r_aic  BIC=&r_bic  N=&r_nobs;

title "R lme4 Fixed Effects (exported via df2sd)";
proc print data=work.r_fixed_effects noobs;
  var TERM ESTIMATE STD_ERROR STATISTIC P_VALUE CONF_LOW CONF_HIGH;
  format ESTIMATE STD_ERROR STATISTIC 8.4;
run;
title;


/* D.4 — Compare key estimates visually */
title "Visit Means: R lme4 vs PROC MIXED";
proc report data=work.r_visit_means nowd;
  column TRTP AVISIT R_MEAN_CHG R_N;
  define TRTP      / group  "Treatment";
  define AVISIT    / group  "Visit";
  define R_MEAN_CHG / analysis mean "R Mean CHG" format=8.4;
  define R_N       / analysis sum   "N";
run;
title;

/*
  >> YOUR TURN:
     1. Add lmerControl(optimizer="bobyqa") to the lmer() call to test
        convergence robustness.
     2. Try REML=FALSE and compare AIC values — use symput() to store both
        and report the difference in a %put statement.
     3. Change the random effect to (1 + avisitn | usubjid) (random slope).
        How does the AIC change?
*/
/*=============================================================================
  SECTION 5 — EXERCISE D: MIXED MODEL
  PROC R (lme4 / nlme fallback) vs PROC MIXED
  Goal: Fit a repeated-measures mixed model in both SAS and R,
        compare the fixed-effect estimates using PROC COMPARE.
  Model: CHG = TRTP AVISIT TRTP*AVISIT BASE (+ random intercept per subject)

  Fixes applied vs original exercise code:
    - lme4 / broom.mixed fallback to nlme::lme + broom (both ship with base R)
    - df2sd() uses separate dataset/libname arguments, not dot-notation
    - names(df) <- toupper() (not tolower) for consistent uppercase refs
    - _raw + sas_length_stmt() + proc delete for $32767 fix
    - R comments use # not /* */
    - dot in column name STD.ERROR → STD_ERROR (validvarname=v7 handled)
    - proc print var list updated to match actual column names
=============================================================================*/

/*=============================================================================
  D.1 — Prepare analysis dataset (post-baseline only)
=============================================================================*/

data work.adlb_chg;
  set work.adlb;
  where ABLFL ne "Y" and AVISITN > 0;
run;

/*=============================================================================
  D.2 — SAS reference: PROC MIXED
=============================================================================*/

proc mixed data=work.adlb_chg;
  class USUBJID AVISIT TRTP;
  model CHG = TRTP AVISIT TRTP*AVISIT BASE / solution ddfm=kr;
  repeated AVISIT / subject=USUBJID type=UN;
  lsmeans TRTP*AVISIT / diff cl;
  ods output SolutionF = work.sas_fixed_effects
             LSMeans   = work.sas_lsmeans;
run;

title "SAS PROC MIXED — Fixed Effects";
proc print data=work.sas_fixed_effects noobs;
  var Effect TRTP AVISIT Estimate StdErr tValue Probt;
  format Estimate StdErr tValue 8.4;
run;
title;

/*=============================================================================
  D.3 — R equivalent: lme4 preferred, nlme::lme fallback
=============================================================================*/

options validvarname=v7;   /* converts dots in col names to underscores */

proc r;
  submit;
    library(dplyr)

    # Helper: generate SAS LENGTH statement from a data frame
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

    # Pull dataset and normalise column names to uppercase
    df <- sd2df("adlb_chg", "work")
    names(df) <- toupper(names(df))

    # Convert character variables to factors
    df$TRTP    <- as.factor(df$TRTP)
    df$AVISIT  <- as.factor(df$AVISIT)
    df$USUBJID <- as.factor(df$USUBJID)

    # ---- Fit mixed model: lme4 preferred, nlme fallback -----------------
    if (requireNamespace("lme4", quietly = TRUE) &&
        requireNamespace("broom.mixed", quietly = TRUE)) {

      library(lme4)
      library(broom.mixed)
      cat("Fitting model using: lme4::lmer\n")

      m <- lmer(CHG ~ TRTP * AVISIT + BASE + (1 | USUBJID),
                data    = df,
                REML    = TRUE,
                control = lmerControl(optimizer = "bobyqa"))

      fixed_ef <- tidy(m, effects = "fixed", conf.int = TRUE)
      # rename to avoid dots in column names (SAS validvarname=v7 handles
      # them but explicit rename is cleaner)
      names(fixed_ef) <- gsub("\\.", "_", toupper(names(fixed_ef)))

      aic_val  <- round(AIC(m),  2)
      bic_val  <- round(BIC(m),  2)
      nobs_val <- nobs(m)
      cat("Model fitted using: lme4 (REML)\n")

    } else {
      # Fallback: nlme::lme — ships with every R installation
      cat("NOTE: lme4 or broom.mixed not installed – falling back to nlme::lme\n")
      cat("Ask your SAS administrator to install lme4 and broom.mixed.\n")
      library(nlme)

      m <- lme(fixed     = CHG ~ TRTP * AVISIT + BASE,
               random    = ~ 1 | USUBJID,
               data      = df,
               na.action = na.omit,
               method    = "REML")

      coef_tbl <- as.data.frame(summary(m)$tTable)
      fixed_ef <- data.frame(
        EFFECT    = rownames(coef_tbl),
        ESTIMATE  = round(coef_tbl[["Value"]],          4),
        STD_ERROR = round(coef_tbl[["Std.Error"]],      4),
        DF        = round(coef_tbl[["DF"]],             1),
        STATISTIC = round(coef_tbl[["t-value"]],        4),
        P_VALUE   = round(coef_tbl[["p-value"]],        4),
        stringsAsFactors = FALSE
      )

      aic_val  <- round(AIC(m),  2)
      bic_val  <- round(BIC(m),  2)
      nobs_val <- nrow(df[complete.cases(df[, c("CHG","BASE")]), ])
      cat("Model fitted using: nlme::lme (REML)\n")
    }

    cat("\nModel fit statistics:\n")
    cat("  AIC :", aic_val,  "\n")
    cat("  BIC :", bic_val,  "\n")
    cat("  Nobs:", nobs_val, "\n")

    show(fixed_ef, title = "Mixed Model Fixed Effects", count = 30)

    # Store model fit stats in SAS macro variables
    symput("r_aic",  as.character(aic_val))
    symput("r_bic",  as.character(bic_val))
    symput("r_nobs", as.character(nobs_val))

    # ---- Per-visit means for comparison ---------------------------------
    visit_means <- df %>%
      group_by(TRTP, AVISIT) %>%
      summarise(
        R_MEAN_CHG = round(mean(CHG, na.rm = TRUE), 4),
        R_N        = n(),
        .groups    = "drop"
      ) %>%
      as.data.frame()

    # ---- Export to SAS with length fix ----------------------------------
    symput("r_fe_lengths",  sas_length_stmt(fixed_ef))
    symput("r_vm_lengths",  sas_length_stmt(visit_means))

    df2sd(fixed_ef,   "r_fixed_effects_raw", "work")
    df2sd(visit_means,"r_visit_means_raw",   "work")
    cat("Results written to work.*_raw datasets\n")
  endsubmit;
run;

options validvarname=upcase;   /* reset after import */

/* Re-stamp correct character lengths, drop raw datasets */
data work.r_fixed_effects;
  &r_fe_lengths.
  set work.r_fixed_effects_raw;
run;
proc delete data=work.r_fixed_effects_raw; run;

data work.r_visit_means;
  &r_vm_lengths.
  set work.r_visit_means_raw;
run;
proc delete data=work.r_visit_means_raw; run;

%put NOTE: lme4/nlme model — AIC=&r_aic.  BIC=&r_bic.  N=&r_nobs.;

title "R Mixed Model Fixed Effects (exported via df2sd)";
proc print data=work.r_fixed_effects noobs;
  format _numeric_ 8.4;
run;
title;

/*=============================================================================
  D.4 — Compare key estimates: R visit means vs SAS PROC MIXED lsmeans
=============================================================================*/

title "Visit Means: R Mixed Model";
proc report data=work.r_visit_means nowd;
  column TRTP AVISIT R_MEAN_CHG R_N;
  define TRTP      / group    "Treatment";
  define AVISIT    / group    "Visit";
  define R_MEAN_CHG / analysis mean "R Mean CHG" format=8.4;
  define R_N        / analysis sum  "N";
run;
title;

/*=============================================================================
  >> YOUR TURN:

  1. lmerControl(optimizer="bobyqa") is already included in the lme4 path.
     Try changing it to optimizer="Nelder_Mead" — does the model still
     converge? Use symput() to store a convergence flag and report it
     with %put.

  2. Compare REML vs ML estimation. Store both AIC values and report
     the difference with %put.

     If using lme4::lmer:
       m_reml <- lmer(..., REML = TRUE)
       m_ml   <- lmer(..., REML = FALSE)

     If using nlme::lme (fallback):
       m_reml <- lme(..., method = "REML")
       m_ml   <- lme(..., method = "ML")

     Then store and compare:
       symput("r_aic_reml", as.character(round(AIC(m_reml), 2)))
       symput("r_aic_ml",   as.character(round(AIC(m_ml),   2)))

     In SAS:
       %put AIC difference (REML - ML) = %sysevalf(&r_aic_reml. - &r_aic_ml.);

     Note: REML and ML are not directly comparable via AIC — use ML
     when comparing models with different fixed effects, REML for
     comparing models with different random effects.

  3. Add a random slope for visit (numeric visit variable required).

     If using lme4::lmer:
       lmer(CHG ~ TRTP * AVISIT + BASE + (1 + AVISITN | USUBJID), ...)

     If using nlme::lme (fallback):
       lme(fixed  = CHG ~ TRTP * AVISIT + BASE,
           random = ~ 1 + AVISITN | USUBJID, ...)

     How does AIC change? Does the model converge without bobyqa?
=============================================================================*/

/*=============================================================================
  SECTION 6 — EXERCISE E: SURVIVAL ANALYSIS
  PROC R (survival + survminer) vs PROC LIFETEST
  Goal: Kaplan-Meier analysis on ADTTE, compare KM tables,
        render a KM plot with risk table in SAS Studio.

  Fixes applied vs original exercise code:
    - survminer fallback using base R survival plot (type="cairo" for headless)
    - df2sd() uses separate dataset/libname arguments, not dot-notation
    - names(df) <- toupper() applied after sd2df()
    - _raw dataset + sas_length_stmt() pattern for $32767 fix
    - proc delete for _raw dataset
    - R comments use # not / * * /
    - df2sd() target name without "work." prefix
=============================================================================*/

%let study = STUDY001;

/*=============================================================================
  E.1 — SAS reference: PROC LIFETEST
=============================================================================*/

proc lifetest data=work.adtte
  plots   = survival(atrisk)
  timelist= (28 56 84 112 140 168);
  time AVAL * CNSR(1);
  strata TRTP;
  ods output ProductLimitEstimates = work.sas_km_estimates
             Quartiles             = work.sas_km_quartiles;
run;

title "SAS KM Quartiles by Treatment";
proc print data=work.sas_km_quartiles noobs;
  var TRTP Percent Estimate LowerLimit UpperLimit;
  format Estimate LowerLimit UpperLimit 8.1;
run;
title;

/*=============================================================================
  E.2 — R equivalent: survival + survminer via PROC R
  Preferred:  survminer ggsurvplot() rendered via rplot()
  Fallback:   base R plot() with type="cairo" (headless server, no X11)
=============================================================================*/

proc r;
  submit;
    library(survival)
    library(dplyr)

    # Helper: generate SAS LENGTH statement from a data frame
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

    # Pull ADTTE from SAS and normalise column names to uppercase
    df <- sd2df("adtte", "work")
    names(df) <- toupper(names(df))

    # Kaplan-Meier fit
    fit <- survfit(Surv(AVAL, 1 - CNSR) ~ TRTP, data = df)

    cat("=== KM Summary ===\n")
    print(summary(fit)$table)

    # Log-rank test
    lr_test <- survdiff(Surv(AVAL, 1 - CNSR) ~ TRTP, data = df)
    p_val   <- round(1 - pchisq(lr_test$chisq, df = 1), 4)
    symput("r_km_pval", as.character(p_val))
    cat("\nLog-rank p-value:", p_val, "\n")

    # Read study macro variable for plot title
    study <- symget("study")

    # ---- KM plot: survminer preferred, base R fallback ------------------
    if (requireNamespace("survminer", quietly = TRUE)) {
      library(survminer)
      km_plot <- ggsurvplot(fit,
        data              = df,
        risk.table        = TRUE,
        pval              = TRUE,
        conf.int          = TRUE,
        palette           = c("#1B2A5E","#E8631A"),
        title             = paste("Kaplan-Meier: Time to First AE —", study),
        xlab              = "Time (Days)",
        ylab              = "Event-Free Probability",
        legend.title      = "Treatment",
        risk.table.height = 0.28,
        ggtheme           = theme_bw()
      )
      rplot(km_plot, filename = "km_plot_exercise_e.png")
      cat("KM plot rendered using: survminer\n")

    } else {
      # Fallback: base R survival plot — type="cairo" required on headless server
      cat("NOTE: survminer not installed – using base R plot\n")
      cat("Ask your SAS administrator to install survminer.\n")
      plot_path <- paste0(sas$workpath, "km_plot_exercise_e.png")
      png(plot_path, width = 900, height = 650, type = "cairo")
      plot(fit,
           col   = c("#1B2A5E","#E8631A"),
           lwd   = 2,
           xlab  = "Time (Days)",
           ylab  = "Event-Free Probability",
           main  = paste("Kaplan-Meier: Time to First AE —", study),
           mark.time = TRUE)
      legend("topright",
             legend = levels(factor(df$TRTP)),
             col    = c("#1B2A5E","#E8631A"),
             lwd    = 2,
             bty    = "n")
      dev.off()
      renderImage(plot_path)
      cat("KM plot rendered using: base R survival\n")
    }

    # ---- Export KM table at key timepoints to SAS -----------------------
    # as.numeric() guards against NULL/NaN when all events occur before
    # the requested timepoints, which causes round() to fail
    km_sum  <- summary(fit, times = c(28, 56, 84, 112, 140, 168),
                       extend = TRUE)   # extend=TRUE fills NA beyond last time
    km_tbl  <- data.frame(
      STRATA  = as.character(km_sum$strata),
      TIME    = as.numeric(km_sum$time),
      N_RISK  = as.integer(km_sum$n.risk),
      N_EVENT = as.integer(km_sum$n.event),
      SURV    = round(as.numeric(km_sum$surv),  4),
      LOWER   = round(as.numeric(km_sum$lower), 4),
      UPPER   = round(as.numeric(km_sum$upper), 4),
      stringsAsFactors = FALSE
    )

    show(km_tbl, title = "R KM Table at Key Timepoints")

    # Apply length fix before df2sd (parquet engine produces $32767 otherwise)
    symput("r_km_lengths", sas_length_stmt(km_tbl))
    df2sd(km_tbl, "r_km_table_raw", "work")
    cat("KM table written to work.r_km_table_raw\n")
  endsubmit;
run;

/* Re-stamp correct character lengths, then drop the raw dataset */
data work.r_km_table;
  &r_km_lengths.
  set work.r_km_table_raw;
run;

proc delete data=work.r_km_table_raw; run;

%put NOTE: KM Log-rank p-value (from R) = &r_km_pval.;

title "R KM Table at Key Timepoints (exported via df2sd)";
proc print data=work.r_km_table noobs;
  var STRATA TIME N_RISK N_EVENT SURV LOWER UPPER;
  format SURV LOWER UPPER 8.3;
run;
title;

/*=============================================================================
  >> YOUR TURN:

  1. Extract and report median survival time per arm.
     The summary table uses the strata label format "TRTP=<value>".
     Use symget() to read the treatment name dynamically rather than
     hard-coding it:

       trt_levels <- levels(factor(df$TRTP))
       for (trt in trt_levels) {
         key <- paste0("TRTP=", trt)
         med <- as.character(summary(fit)$table[key, "median"])
         symput(paste0("r_median_", gsub("[^A-Za-z0-9]", "_", trt)), med)
       }

     Then in SAS:
       %put NOTE: Median survival — &r_median_DrugX_100mg. days (Drug),
                                    &r_median_Placebo. days (Placebo);

  2. Change the plot colours in the survminer path.
     The palette argument accepts hex codes or named R colours:
       palette = c("#2C7BB6", "#D7191C")
     In the base R fallback path, update the col= argument to match:
       col = c("#2C7BB6", "#D7191C")
     Keep both paths in sync so output looks consistent regardless of
     which package is installed.

  3. Add a restricted mean survival time (RMST) calculation.
     survRM2 may not be installed — use requireNamespace() and provide
     a fallback message, consistent with the pattern used in this demo:

       if (requireNamespace("survRM2", quietly = TRUE)) {
         library(survRM2)
         # tau = analysis time horizon in days (e.g. 168 = 24 weeks)
         rmst_result <- rmst2(df$AVAL, 1 - df$CNSR,
                              arm = as.integer(df$TRTP == "DrugX_100mg"),
                              tau = 168)
         cat("RMST difference (Drug - Placebo):",
             round(rmst_result$unadjusted.result[1, 1], 2), "days\n")
         symput("r_rmst_diff",
                as.character(round(rmst_result$unadjusted.result[1, 1], 2)))
       } else {
         cat("NOTE: survRM2 not installed – ask your administrator.\n")
       }

     Then in SAS:
       %put NOTE: RMST difference = &r_rmst_diff. days;
=============================================================================*/


/*---------------------------------------------------------------------------
  SECTION 7 — EXERCISE F: STORE FINAL RESULTS AS SAS DATASETS
  
  Goal: Combine R and SAS model results into a permanent comparison table,
        add source metadata, and store as a proper SAS dataset.
---------------------------------------------------------------------------*/

/* F.1 — Build combined model comparison dataset */
data work.model_comparison;
  length SOURCE $20 MODEL $40 TERM $60;
  set work.r_fixed_effects (in=from_r);
  if from_r then do;
    SOURCE   = "R-lme4";
    MODEL    = "lmer (REML)";
    AIC_VAL  = input("&r_aic", best.);
    BIC_VAL  = input("&r_bic", best.);
  end;
  RUN_DATE = today();
  STUDY_ID = "&study";
  format RUN_DATE date9.;
run;

/* F.2 — Save comparison to permanent location (WORK here; change if needed) */
data &outlib..proc_r_model_results;
  set work.model_comparison;
run;

/* F.3 — Also save the KM table */
data &outlib..proc_r_km_results;
  set work.r_km_table;
  RUN_DATE = today();
  STUDY_ID = "&study";
  format RUN_DATE date9.;
run;

/* F.4 — Final summary report */
title1 "PROC R Integration — Final Results Summary";
title2 "Study: &study  |  Drug: &drug  |  N=&r_n_total subjects";
footnote "Source: R lme4 (AIC=&r_aic) + PROC LIFETEST | Log-rank p=&r_km_pval";

proc report data=&outlib..proc_r_model_results nowd;
  column SOURCE MODEL TERM ESTIMATE P_VALUE;
  define SOURCE    / group  "Source"    width=12;
  define MODEL     / group  "Model"     width=14;
  define TERM      / display "Effect"   width=30;
  define ESTIMATE  / display "Estimate" format=8.4 width=10;
  define P_VALUE   / display "p-value"  format=8.4 width=10;
  where TERM ne "(Intercept)";
run;

title; footnote;

/* F.5 — Validate datasets exist and print contents */
proc contents data=&outlib..proc_r_model_results; run;
proc contents data=&outlib..proc_r_km_results;    run;

/*
  >> FINAL CHALLENGE:
     Combine EXERCISE D and E into a single PROC R call:
       - Fit lme4 mixed model
       - Fit KM survival model
       - Render both plots with rplot()
       - Export both result tables with df2sd()
       - Pass 3 macro variables back (AIC, log-rank p-value, N)
     
     This demonstrates the persistent subprocess — all objects
     remain available across SUBMIT blocks in the same session.
*/


/*===========================================================================
  APPENDIX — ADMINISTRATOR REFERENCE
  
  If PROC R gives "PROC R procedure not found" or "ERROR: External
  language R is not enabled":
  
  1. Verify environment variables are set (SAS Environment Manager):
       PROC_RPATH  = /path/to/R/bin/R
       PROC_M2PATH = /opt/sas/viya/home/.../SAS.R
  
  2. Add to Compute Server autoexec_code:
       lockdown enable_ams=R;
       lockdown enable_ams=SOCKET;
  
  3. Install required R packages (once, on the server):
       install.packages(c("R6","arrow","haven","plotly","svglite",
                          "lme4","broom.mixed","survival","survminer",
                          "ggplot2","dplyr"),
                        lib="/shared/Rlibs")
  
  4. Set shared library path in SAS autoexec:
       options set=R_LIBS_USER="/shared/Rlibs";
  
  5. Restart Compute Server session and re-run Section 0.
===========================================================================*/
