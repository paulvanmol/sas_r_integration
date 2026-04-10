/*=============================================================================
  DEMO 2: R Runner Custom Step (SAS Studio Viya)
  Case Study: SAS & R Integration for Clinical Programmers
  Approach: R Runner custom step by Sundaresh Sankaran / Samiul Haque
            github.com/SundareshSankaran/r-runner
  Requires: SAS Viya 2023.08+, Python + rpy2 configured via sas-pyconfig,
            R Runner custom step installed in SAS Studio

  rpy2 version note:
    pandas2ri.activate() was deprecated in rpy2 >= 3.5.
    Use rpy2.robjects.conversion.localconverter() with
    rpy2.robjects.pandas2ri.converter instead.
=============================================================================*/

/*
  NOTE FOR INSTRUCTORS:
  R Runner is a low-code Custom Step used in SAS Studio Flows.
  In a flow, you drag the "R Runner" step onto the canvas, connect an input
  dataset port, paste R code in the snippet text area, and connect an output
  dataset port. The step handles all data conversion automatically.

  The PROC PYTHON block below shows what R Runner generates internally so
  programmers understand what is happening under the hood.
  In practice, users interact with the GUI — not this code directly.
*/

/* ---- 0. Create sample data --------------------------------------------- */
data work.adlb;
  call streaminit(42);
  length usubjid $10 trt01p $20 avisit $10 paramcd $8;
  do i = 1 to 60;
    usubjid = cats("SUBJ-", put(i, z3.));
    trt01p  = ifc(i <= 30, "DRUG A", "PLACEBO");
    base    = round(8 + rand("normal") * 0.8, 0.1);
    paramcd = "HBA1C";
    do j = 1 to 4;
      avisit = cats("WEEK", put(j*4, z2.));
      chg    = round(
                 (ifc(trt01p="DRUG A", -0.8, -0.2)) * j/4
                 + rand("normal") * 0.4,
                 0.01);
      output;
    end;
  end;
  drop i j;
run;

/*=============================================================================
  SECTION 1: What R Runner generates internally
  Key corrections vs older rpy2 examples:
    - Do NOT use pandas2ri.activate() — deprecated in rpy2 >= 3.5
    - Use localconverter(pandas2ri.converter) context manager instead
    - Do NOT use saspy.SASsession() inside proc python — you are already
      inside a SAS session; use SAS.sd2df() / SAS.df2sd() directly
=============================================================================*/

proc python;
submit;
import rpy2.robjects as ro
from rpy2.robjects        import pandas2ri
from rpy2.robjects.conversion import localconverter

# ---- Pull SAS dataset into pandas using the SAS. callback ----------------
# Normalise column names to lowercase immediately after sd2df() —
# SAS variable name case depends on dataset origin (user datasets are
# typically lowercase; SAS-supplied datasets like sashelp.* may be mixed).
r_input_table = SAS.sd2df("work.adlb")
r_input_table.columns = r_input_table.columns.str.upper()
print(f"Rows from SAS: {len(r_input_table)}, Cols: {list(r_input_table.columns)}")

# ---- Convert pandas DataFrame to R data frame ----------------------------
# Use localconverter (rpy2 >= 3.5) instead of the deprecated activate()
with localconverter(pandas2ri.converter):
    r_df = ro.conversion.py2rpy(r_input_table)

# Make the data frame available in the R global environment
ro.globalenv["r_input_table"] = r_df

# ---- Run R code via ro.r() -----------------------------------------------
r_code = """
library(ggplot2)
library(dplyr)

# Summarize mean change by treatment and visit
summary_df <- r_input_table |>
  group_by(TRT01P, AVISIT) |>
  summarise(
    n        = n(),
    mean_chg = round(mean(CHG, na.rm = TRUE), 3),
    sd_chg   = round(sd(CHG,  na.rm = TRUE), 3),
    .groups  = "drop"
  )

# Boxplot
p <- ggplot(r_input_table, aes(x = AVISIT, y = CHG, fill = TRT01P)) +
       geom_boxplot(alpha = 0.7) +
       labs(title = "HbA1c Change from Baseline by Visit",
            x     = "Visit",
            y     = "Change from Baseline (%)",
            fill  = "Treatment") +
       theme_bw() +
       theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave("rrunner_boxplot.png", p, width = 7, height = 5, dpi = 150)
cat("Boxplot saved.\n")
"""
ro.r(r_code)

# ---- Retrieve R data frame and convert back to pandas --------------------
summary_df_r = ro.globalenv["summary_df"]

with localconverter(pandas2ri.converter):
    summary_df_pd = ro.conversion.rpy2py(summary_df_r)

print(summary_df_pd)

# ---- Write result back to SAS using SAS.df2sd() --------------------------
SAS.df2sd(summary_df_pd, "rrunner_summary")
print("Written to work.rrunner_summary")

endsubmit;
run;

/* ---- Display the result written back by R Runner ----------------------- */
proc print data=work.rrunner_summary label noobs;
  title "Mean HbA1c Change by Visit (R Runner output via PROC PYTHON + rpy2)";
  label mean_chg = "Mean Change"
        sd_chg   = "Std Dev";
  format mean_chg sd_chg 8.3;
run;
title;

/*=============================================================================
  SECTION 2: R Runner in SAS Studio Flows (GUI usage)

  In the actual R Runner Custom Step you do NOT write any of the above code.
  The step provides a GUI with these parameters:

    Input port  (SAS dataset)  → automatically converted to r_input_table
    R Snippet   (text area)    → paste your R code here, reference r_input_table
    R dataframe to output      → name of the R data frame to write back
    Output port (SAS dataset)  → receives the named R data frame

  Example R snippet you would paste into the step UI:
  ─────────────────────────────────────────────────────
    library(dplyr)
    summary_df <- r_input_table |>
      group_by(TRT01P, AVISIT) |>
      summarise(mean_chg = round(mean(CHG, na.rm=TRUE), 3), .groups="drop")
  ─────────────────────────────────────────────────────
  Then set "R dataframe to output" = summary_df
  and connect the output port to work.rrunner_summary.

  The step handles all rpy2 conversion internally.
=============================================================================*/

/*=============================================================================
  R Runner Summary:
  + Great for SAS Studio Flow users (drag-and-drop, no code needed)
  + Full SAS dataset passes to R as a data frame automatically
  + Output R data frame written back to SAS dataset automatically
  - Requires Python + rpy2 (three-language stack: SAS → Python → R)
  - rpy2 >= 3.5: use localconverter(), NOT the deprecated activate()
  - Community tool (not officially supported by SAS Institute)
  - Limited macro variable exchange compared to PROC R
  - More complex admin setup than PROC IML or PROC R
  - For new projects on Viya 2026.03+, prefer PROC R instead
=============================================================================*/
