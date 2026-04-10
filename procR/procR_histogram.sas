proc r; 
    submit;
    library(tidyverse)
    carsdf <- sd2df("sashelp.cars")
    carsAudi <- carsdf %>% filter(Make == "Audi")
    df2sd(carsAudi, "AUDI", "WORK");
    endsubmit;
run;
 
proc print data=work.audi;
run;
proc r;
    submit;
    library(ggplot2)
 
    p <- ggplot(carsdf, aes(x = MPG_Highway)) +
    geom_histogram(binwidth = 2, fill = "#69b3a2",
    color = "#1f3552", alpha = 0.8) +
    labs(
        title = "Distribution of Highway MPG",
        x = "Highway MPG",
        y = "Count"
        ) +
    theme_minimal(base_size = 14) +
    theme(
    plot.title = element_text(hjust = 0.5, face = "bold"),
    axis.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
)
 
    rplot(p);
    endsubmit;
run;