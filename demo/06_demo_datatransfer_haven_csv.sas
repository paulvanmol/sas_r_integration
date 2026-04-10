/*=============================================================================
  DEMO 5: Reading SAS datasets in R with haven + CSV round-trip
  Case Study: SAS & R Integration for Clinical Programmers

  Demonstrates:
    - Reading a .sas7bdat file directly in R using haven::read_sas()
    - Passing SAS macro variables to R with symget()
    - Writing R results to CSV in the SAS WORK directory
    - Importing the CSV back into SAS with PROC IMPORT
    - options validvarname=v7 to handle column names from CSV

  Requires:
    - haven package installed in the R environment
    - ADSL dataset at &path./adam/adsl.sas7bdat
=============================================================================*/

%let path     = /srv/nfs/kubedata/compute-landingzone/sbxpav/r_integration;
%let workpath = %sysfunc(pathname(work));

proc r;
  submit;
    library(haven)
    library(dplyr)

    # Read macro variables from SAS
    # Note: symget() returns the value; no $ prefix needed on the macro name
    path     <- symget("path")
    workpath <- symget("workpath")

    # Build the full path to the SAS dataset
    # paste0() avoids the unwanted space that paste() adds by default
    adsl_path <- paste0(path, "/adam/adsl.sas7bdat")
    cat("Reading:", adsl_path, "\n")

    adsl <- read_sas(adsl_path)

    # haven preserves SAS variable names as-is (typically uppercase)
    cat("Rows:", nrow(adsl), "| Cols:", ncol(adsl), "\n")
    cat("Columns:", paste(names(adsl)[1:10], collapse = ", "), "...\n")

    # ---- Exploratory plot: Age by treatment arm --------------------------
    # rplot() renders directly in SAS Results — no ggsave needed
    # Use quote() to defer evaluation so rplot() receives the expression
    rplot(quote(
      boxplot(AGE ~ TRT01A,
              data = adsl,
              main = "Age Distribution by Treatment Arm",
              xlab = "Treatment Arm",
              ylab = "Age",
              col  = c("#0072B2","#E69F00","#009E73"))
    ))

    # ---- Summary statistics by treatment arm ----------------------------
    summary_stats <- adsl %>%
      group_by(TRT01A) %>%
      summarise(
        N       = n(),
        AGE_MEAN = round(mean(AGE, na.rm = TRUE), 1),
        AGE_SD   = round(sd(AGE,   na.rm = TRUE), 1),
        AGE_MIN  = min(AGE, na.rm = TRUE),
        AGE_MAX  = max(AGE, na.rm = TRUE),
        .groups  = "drop"
      )

    show(summary_stats, title = "Age Summary by Treatment Arm")

    # ---- Write to CSV in SAS WORK directory -----------------------------
    # paste0() ensures no space between workpath and filename
    csv_path <- paste0(workpath, "/summary_stats.csv")
    write.csv(summary_stats, csv_path, row.names = FALSE)
    cat("CSV written to:", csv_path, "\n")

    # Pass the path back to SAS for use in PROC IMPORT
    symput("csv_path", csv_path)
  endsubmit;
run;

/*=============================================================================
  Import the CSV back into SAS
  options validvarname=v7 converts any non-standard column name characters
  (dots, spaces) to underscores, matching standard SAS variable naming rules.
  This is important because write.csv() may produce names like "AGE.MEAN"
  which are not valid SAS v7 variable names without this option.
=============================================================================*/

options validvarname=v7;

proc import
  datafile = "&csv_path."
  out      = work.summary_stats
  dbms     = csv
  replace;
  getnames = yes;
run;

/* Reset to default after import */
options validvarname=upcase;

proc print data=work.summary_stats noobs label;
  title "Age Summary by Treatment Arm (imported from R via CSV)";
run;
title;

/*=============================================================================
  Visualize in SAS using the imported summary data
=============================================================================*/

ods graphics on;

proc sgplot data=work.summary_stats;
  title "Mean Age by Treatment Arm";
  vbar trt01a / response = age_mean
                datalabel
                fillattrs = (color="#0072B2");
  yaxis label = "Mean Age (years)";
  xaxis label = "Treatment Arm";
run;

ods graphics off;
title;

/*=============================================================================
  Notes on the CSV round-trip approach vs df2sd():

  CSV via write.csv() + PROC IMPORT:
    + Works without any PROC R callback (useful for standalone R scripts)
    + Compatible with haven::read_sas() workflow
    + No parquet $32767 length issue for numeric columns
    - Character columns still need validvarname=v7 for name handling
    - Numeric precision may be affected by CSV text representation
    - Requires a shared filesystem path visible to both R and SAS

  df2sd() + sas_length_stmt() DATA step:
    + Stays entirely within the PROC R session
    + Handles all types cleanly
    - Parquet intermediate requires the two-step length fix for char columns

  For reading existing SAS datasets in R, haven::read_sas() is the
  standard approach when working outside of a PROC R session.
  Inside PROC R, sd2df() is simpler and avoids filesystem paths.
=============================================================================*/
