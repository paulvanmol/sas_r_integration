proc r restart ;
submit;
install.packages("metamicrobiomeR")
library("metamicrobiomeR")
endrsubmit; 
run; 
proc r;
submit; 
installed.packages()[,c('Package','Version')]
installed.packages()
ip <- installed.packages()
data.frame(
  Package = ip[, "Package"],
  Version = ip[, "Version"],
  row.names = NULL
)
head(ip)
"ggplot2" %in% installed.packages()[, "Package"]
#install multiple packages 
Packages <- c("knitr","rmarkdown","installr","haven","readr","yaml","tidyverse")
#install.packages(Packages)
#load multiple packages
lapply(Packages, library, character.only = TRUE)
endsubmit;
run; 