
/*Macro Variables*/

/*from SAS to R: symget*/
/*from R to SAS: symput, submit(%let)*/


%let origin1=Europe;
%put &=origin1;

proc r;
    submit;
    origin1=symget("origin1") 
    print(origin1) 
    origin2='Asia'
    symput('origin2',origin2) 
    endsubmit;
run;

/*showing R macrovariable*/
%put &=origin2;

%let origin1=Europe;
%put &=origin1;


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

proc r;
    submit;
    df=sd2df('sashelp.cars(where=(origin="&origin1"))') 
    df2sd(df,"cars_europe")
    show(df,count=10) 
    endsubmit;
run;

/*attempt to print origin1 variable*/
proc r restart;
    submit;
    print(origin1)
    endsubmit;
run; 
proc r terminate;
run; 

/*transfer data between SAS and R Hardcoded*/
proc r; 
    submit;
    library(tidyverse)
    carsdf <- sd2df("sashelp.cars")
    carsAudi <- carsdf %>% filter(Make == "Audi")
    df2sd(carsAudi, "AUDI", "WORK")
    endsubmit;
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
avg_msrp <- round(avg_msrp, 2)   # keep 2 decimals
symput("AvgPrice", avg_msrp)
 
df2sd(mycars, "filtered_cars", "WORK")
endsubmit;
run;
 
/* SAS: use the macro variable created in R */
%put Average MSRP from R = &AvgPrice;
 
proc print data=filtered_cars(obs=5);
title "First 5 &Make Cars (Avg MSRP = &AvgPrice)";
run;
