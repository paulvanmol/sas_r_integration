library(survival)
library(survminer)

 trt_arm <- symget("trt_arm")        # receive from SAS macro var

 adtte   <- sd2df("work.adtte")
 sub     <- adtte[adtte$TRT01P == trt_arm, ]

 km_fit  <- survfit(Surv(AVAL, CNSR==0) ~ 1, data=sub)
 med_os  <- surv_median(km_fit)$median

 symput("r_median_os", as.character(med_os))   # return to SAS

 df2sd(data.frame(TRT01P=trt_arm, MedianOS=med_os),
       "work.km_from_script")