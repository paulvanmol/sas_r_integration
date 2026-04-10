/*Macro variable Example*/
/*Creating macro Variables from R*/
proc r restart;
submit;
submit("%let mymacrovar=Hi there;")
symput('myvar', "This variable has global scope")
txt <- symget("mymacrovar")
print(txt)
endsubmit;
run;

%put &=mymacrovar;
%put &=myvar;

/*transfer data between SAS and R*/
proc r; 
    submit;
    library(tidyverse)
    carsdf <- sd2df("sashelp.cars")
    carsAudi <- carsdf %>% filter(Make == "Audi")
    df2sd(carsAudi, "AUDI", "WORK")
    endsubmit;
run;

proc contents data=work.audi;
run; 

 
/* R: filter data and create a macro variable */
%let Make = Honda;
proc r;
submit;
library(tidyverse)
 
VMake <- symget("Make")
carsdf <- sd2df("sashelp.cars")
 
mycars <- carsdf %>%
filter(Make == VMake)
 
# Create a macro variable in SAS from R 
avg_msrp <- mean(mycars$MSRP, na.rm = TRUE)
symput("AvgPrice", avg_msrp)
 
df2sd(mycars, "filtered_cars", "WORK")
endsubmit;
run;
 
/* SAS: use the macro variable created in R */
%put Average MSRP from R = &AvgPrice;
 
proc print data=filtered_cars(obs=5);
title "First 5 &Make Cars (Avg MSRP = &AvgPrice)";
run;


