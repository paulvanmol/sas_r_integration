/*=============================================================================
  DEMO 4 (BONUS): Polyglot Pipeline – SAS + Python + R
  Case Study: SAS & R Integration for Clinical Programmers
  Inspired by: The SAS Viya Guide – github.com/Criptic/The-SAS-Viya-Guide

  Workflow:
    Step 1 (SAS)    – Clean ADLB data, descriptive summaries
    Step 2 (Python) – Feature engineering + sklearn regression model
    Step 3 (R)      – ggplot2 visualizations of model results

  Prerequisites:
    - PROC PYTHON configured and enabled; numpy, pandas, sklearn installed
    - PROC R configured and enabled; ggplot2, dplyr, scales installed
    - SAS Viya Stable 2026.03+

  This pattern is useful when:
    - Python has the best ML/feature engineering ecosystem
    - R has the best visualization or specialized stats packages
    - SAS owns the data and the audit trail
=============================================================================*/

/*=============================================================================
  STEP 1: SAS – Prepare and summarize ADLB data
=============================================================================*/

/* Use sashelp.class as a stand-in for a clinical dataset in this demo.
   In a real study this would be your ADaM ADLB or ADEFF dataset.        */
data work.adeff_clean;
  set sashelp.class;
  where weight is not missing
    and height is not missing
    and age    is not missing;
  /* Simulate a treatment response variable */
  call streaminit(42);
  response = round(weight * 0.8 + rand("normal") * 5, 0.1);
  label response = "Simulated Efficacy Response";
run;

proc means data=work.adeff_clean n mean std min max;
  class sex;
  var weight height age response;
  title "Step 1 (SAS): Descriptive Statistics by Sex";
run;

proc freq data=work.adeff_clean;
  tables sex / nocum;
  title "Step 1 (SAS): Subject Count by Sex";
run;
title;

/*=============================================================================
  STEP 2: Python – Feature engineering and sklearn linear model
=============================================================================*/

proc python;
submit;
import pandas as pd
import numpy  as np
from sklearn.linear_model    import LinearRegression
from sklearn.model_selection  import train_test_split
from sklearn.metrics          import r2_score, mean_absolute_error
from sklearn.preprocessing    import StandardScaler

# Pull SAS dataset into pandas
# Normalise all column names to lowercase immediately after sd2df()
# to avoid case sensitivity issues regardless of dataset origin.
df = SAS.sd2df("work.adeff_clean")
df.columns = df.columns.str.lower()
print(f"Columns: {list(df.columns)}")

# Feature engineering (all column refs lowercase)
df["bmi"]     = df["weight"] / (df["height"] * 0.0254) ** 2
df["age_sq"]  = df["age"] ** 2
df = pd.get_dummies(df, columns=["sex"], drop_first=True)
df.columns = [c.replace(" ", "_") for c in df.columns]

# sex dummy column will be sex_M or sex_F depending on reference level
sex_col  = next((c for c in df.columns if c.lower().startswith("sex_")), None)
FEATURES = [c for c in ["weight","height","age","bmi","age_sq", sex_col]
            if c and c in df.columns]
TARGET   = "response"

X, y = df[FEATURES], df[TARGET]
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.3, random_state=42
)

scaler  = StandardScaler()
X_train = scaler.fit_transform(X_train)
X_test  = scaler.transform(X_test)

model = LinearRegression()
model.fit(X_train, y_train)
y_pred = model.predict(X_test)

r2  = r2_score(y_test, y_pred)
mae = mean_absolute_error(y_test, y_pred)
print(f"R²  : {r2:.3f}  |  MAE : {mae:.2f}")

# Pass metrics to SAS macro variables
SAS.symput("py_r2",  str(round(r2,  3)))
SAS.symput("py_mae", str(round(mae, 2)))

# Reconstruct sex label for the results dataframe
results = pd.DataFrame({
    "Actual"   : y_test.values,
    "Predicted": y_pred,
    "Residual" : y_pred - y_test.values,
    "Sex"      : np.where(df.loc[y_test.index, sex_col] == 1,
                          "M", "F") if sex_col else "Unknown"
})

# Write predictions back to SAS
SAS.df2sd(results, "adeff_preds")
print(f"Predictions written to work.adeff_preds ({len(results)} rows)")

endsubmit;
run;

/* Verify metrics and preview predictions */
title "Step 2 (Python): Model R² = &py_r2.  |  MAE = &py_mae.";
proc print data=work.adeff_preds(obs=10) noobs; run;
title;

/*=============================================================================
  STEP 3: R – ggplot2 visualizations of model results
  Demonstrates reading Python-produced SAS datasets and SAS macro variables
  directly in R, then rendering plots back into the SAS Results window.
=============================================================================*/

proc r;
submit;
library(ggplot2)
library(dplyr)
library(scales)

# Helper: trim character columns to actual content width before df2sd()
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

# Pull predictions dataset from SAS (produced by Python in Step 2)
preds <- sd2df("adeff_preds", "work")
names(preds) <- toupper(names(preds))

# Read Python model metrics from SAS macro variables
r2_val  <- symget("py_r2")
mae_val <- symget("py_mae")

subtitle_txt <- paste0(
  "Linear regression  |  R\u00b2 = ", r2_val,
  "  |  MAE = ", mae_val
)

# ---- Plot 1: Predicted vs Actual, coloured by residual, faceted by sex ----
p1 <- ggplot(preds, aes(x = ACTUAL, y = PREDICTED, colour = RESIDUAL)) +
  geom_abline(slope = 1, intercept = 0,
              linetype = "dashed", colour = "#888780", linewidth = 0.5) +
  geom_point(alpha = 0.8, size = 3) +
  scale_colour_gradient2(low  = "#185FA5", mid  = "#D3D1C7",
                         high = "#D85A30", midpoint = 0,
                         name = "Residual") +
  facet_wrap(vars(SEX), ncol = 2) +
  labs(title    = "Predicted vs Actual Response by Sex",
       subtitle = subtitle_txt,
       x        = "Actual Response",
       y        = "Predicted Response") +
  theme_minimal(base_size = 12) +
  theme(strip.text       = element_text(face = "bold"),
        legend.position  = "bottom",
        panel.grid.minor = element_blank())

# Render directly in SAS Studio Results panel; also save a copy
rplot(p1, filename = "polyglot_predicted_vs_actual.png")

# ---- Plot 2: Residual distribution by sex --------------------------------
p2 <- ggplot(preds, aes(x = RESIDUAL, fill = SEX)) +
  geom_histogram(bins = 15, colour = "white", alpha = 0.85) +
  scale_fill_manual(values = c(F = "#534AB7", M = "#D85A30")) +
  facet_wrap(vars(SEX)) +
  labs(title = "Residual Distribution by Sex",
       x     = "Predicted \u2212 Actual",
       y     = "Count") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none")

rplot(p2, filename = "polyglot_residuals.png")

# ---- Summary table in Results -------------------------------------------
summary_tbl <- preds |>
  group_by(SEX) |>
  summarise(
    N           = n(),
    Mean_Actual = round(mean(ACTUAL),         2),
    Mean_Pred   = round(mean(PREDICTED),      2),
    MAE_Group   = round(mean(abs(RESIDUAL)),  2),
    .groups     = "drop"
  )

show(summary_tbl, title = "Per-sex model performance")

# Write summary back to SAS for potential TFL use
summary_tbl <- trim_char_widths(summary_tbl)
df2sd(summary_tbl, "r_model_summary", "work")
cat("Summary written to work.r_model_summary\n")

endsubmit;
run;

proc print data=work.r_model_summary label noobs;
  title "Step 3 (R): Per-sex Model Performance Summary";
run;
title;

/* Release R resources */
proc r terminate;
run;

/*=============================================================================
  END OF DEMO 4 – Polyglot Pipeline

  Key takeaways:
  - SAS, Python, and R share the same session and WORK library
  - Python uses SAS.sd2df() / SAS.df2sd() / SAS.symput() (SAS. prefix)
  - R uses sd2df() / df2sd() / symput() (no prefix needed)
  - Data flows: SAS dataset → Python (pandas) → SAS dataset → R (data frame)
  - Macro variables flow freely across all three languages
  - Each language contributes its strength to a single auditable workflow
=============================================================================*/
