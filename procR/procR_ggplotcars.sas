/*df2sd(df, "sas_dataset")*/
/*Transfers an R data frame to a SAS data set.
Example	Converts the mtcars dataframe into a data set in work.cars_r (work is the default library)*/


proc r;
    submit;
mtcars <- sd2df("sashelp.cars")
names(mtcars)

rplot(quote(plot(mtcars$MPG_City, mtcars$Weight,
                 main = "MPG vs Weight",
                 xlab = "Weight (1000 lbs)",
                 ylab = "Miles per Gallon",
                 col = "blue", 
                 pch = 19,
                 cex = 1.5)),
     filename = "cars_scatter.png")



df2sd(mtcars, "cars_r")
endsubmit;
run;
