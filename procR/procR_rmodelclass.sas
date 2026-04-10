proc r;
    submit;

Class <- read.csv(
  "https://support.sas.com/documentation/onlinedoc/viya/exampledatasets/class.csv"
)

Model <- lm(
  Weight ~ Height,
  data = Class,
  na.action = na.exclude
)

rmodel <- as.data.frame(coef(summary(Model)))
rmodel$Term <- rownames(rmodel)
rownames(rmodel) <- NULL
df2sd(rmodel, "rmodel","work")
endsubmit;
run;