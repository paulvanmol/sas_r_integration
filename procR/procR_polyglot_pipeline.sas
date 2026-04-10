/*************************************************************
   Polyglot pipeline - sashelp.cars
   SAS Procedures, Python (sklearn) & R (ggplot2)
   Prerequisites:
     - Proc Python needs to be configured and enabled +
        numpy, pandas and sklearn need to be installed
     - Proc R needs to be configured and eanabled +
        ggplot2, dplyr and scales need to be installed
*************************************************************/
* Step 1: SAS - clean and summarise sashelp.cars;
data work.cars_clean;
  set sashelp.cars;
  where MSRP is not missing
    and Horsepower is not missing
    and EngineSize is not missing
    and MPG_City is not missing
    and MPG_Highway is not missing
    and Weight is not missing;
run;

proc means data=work.cars_clean N MEAN STD MIN MAX;
  class Origin;
  var MSRP Horsepower EngineSize;
run;

proc freq data=work.cars_clean;
  tables Origin / noCum;
run;


* Step 2: Proc Python - feature engineering + sklearn model;
proc python;
submit;
import pandas as pd
import numpy  as np
from sklearn.linear_model    import LinearRegression
from sklearn.model_selection  import train_test_split
from sklearn.metrics          import r2_score, mean_absolute_error
from sklearn.preprocessing    import StandardScaler

# Pull SAS dataset directly into a Pandas DataFrame
df = SAS.sd2df("work.cars_clean")

# Feature engineering
df["MPG_Combined"]  = (df["MPG_City"] + df["MPG_Highway"]) / 2
df["PowerToWeight"] =  df["Horsepower"] / df["Weight"]
df = pd.get_dummies(df, columns=["Origin"], drop_first=True)
df.columns = [c.replace(" ", "_") for c in df.columns]

FEATURES = ["Horsepower", "EngineSize", "MPG_Combined",
            "PowerToWeight", "Weight", "Origin_Europe", "Origin_USA"]
TARGET = "MSRP"
X, y = df[FEATURES], df[TARGET]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)
scaler  = StandardScaler()
X_train = scaler.fit_transform(X_train)
X_test  = scaler.transform(X_test)

model = LinearRegression()
model.fit(X_train, y_train)
y_pred = model.predict(X_test)

r2  = r2_score(y_test, y_pred)
mae = mean_absolute_error(y_test, y_pred)
print(f"R²  : {r2:.3f}  |  MAE : ${mae:,.0f}")

# Save model metrics to SAS macro variables
SAS.symput("py_r2",  str(round(r2,  3)))
SAS.symput("py_mae", str(int(round(mae, 0))))

# Reconstruct origin label from one-hot columns
origin_raw = df.loc[y_test.index]
results = pd.DataFrame({
    "Actual"   : y_test.values,
    "Predicted": y_pred,
    "Origin"   : np.where(
        origin_raw["Origin_Europe"] == 1, "Europe",
        np.where(origin_raw["Origin_USA"] == 1, "USA", "Asia")
    )
})

# Write predictions back to SAS WORK library
SAS.df2sd(results, "cars_preds")

endsubmit;
run;

* Verify metrics and preview predictions;
title "Model R² = &py_r2.  |  MAE = $&py_mae.";
proc print data=work.cars_preds(obs=10);
run;


* Step 3: Proc R - ggplot2 visualisations;
proc r;
submit;
library(ggplot2)
library(dplyr)
library(scales)

# Pull predictions dataset and macro metrics directly from SAS
preds   <- sd2df("cars_preds", "work")
r2_val  <- symget("py_r2")
mae_val <- symget("py_mae")

preds <- preds |> mutate(Residual = Predicted - Actual)

subtitle_txt <- paste0(
    "Linear regression  |  R² = ", r2_val,
    "  |  MAE = $", format(as.integer(mae_val), big.mark = ",")
)

# Plot 1: predicted vs actual, faceted by origin
p1 <- ggplot(preds, aes(x = Actual, y = Predicted, colour = Residual)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "#888780", linewidth = 0.5) +
    geom_point(alpha = 0.75, size = 2.2) +
    scale_colour_gradient2(low = "#185FA5", mid = "#D3D1C7", high = "#D85A30", midpoint = 0, name = "Residual ($)") +
    scale_x_continuous(labels = dollar_format()) +
    scale_y_continuous(labels = dollar_format()) +
    facet_wrap(vars(Origin), ncol = 3) +
    labs(title = "Predicted vs actual MSRP by origin", subtitle = subtitle_txt, x = "Actual MSRP", y = "Predicted MSRP") +
    theme_minimal(base_size = 12) +
    theme(strip.text = element_text(face = "bold"), legend.position = "bottom", panel.grid.minor = element_blank())

# Render directly to SAS Studio Results panel
rplot(p1, filename = "cars_predicted_vs_actual.png")

# Plot 2: residual distribution by origin
p2 <- ggplot(preds, aes(x = Residual, fill = Origin)) +
    geom_histogram(bins = 25, colour = "white", alpha = 0.85) +
    scale_fill_manual(values = c(Asia = "#534AB7", Europe = "#1D9E75", USA = "#D85A30")) +
    scale_x_continuous(labels = dollar_format()) +
    facet_wrap(vars(Origin)) +
    labs(title = "Residual distribution by origin", x = "Predicted − actual MSRP", y = "Count") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "none")

rplot(p2, filename = "cars_residuals.png")

# Bonus: show summary stats table in Results
summary_tbl <- preds |>
    group_by(Origin) |>
    summarise(
        N = n(),
        Mean_Actual = round(mean(Actual),    0),
        Mean_Pred = round(mean(Predicted), 0),
        MAE_Origin = round(mean(abs(Residual)), 0),
        .groups = "drop")

show(summary_tbl, title = "Per-origin model performance")

endsubmit;
run;