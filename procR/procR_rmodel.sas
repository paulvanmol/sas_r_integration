proc r;
submit ;
   Class <-sd2df("sashelp.class","Class")
   show("Class")
   Model <- lm(Weight ~ Height, data=Class, na.action="na.exclude")
   summary(Model)
   rmodel <- as.data.frame(coef(summary(Model)))
   rmodel$Term <- rownames(rmodel)
   rownames(rmodel) <- NULL
   df2sd(rmodel, "rmodel","work")
endsubmit;
run; 