proc r;
submit;
library(ggplot2)

df <- data.frame(
  category = rep(c("A", "B", "C", "D"), each = 25),
  value = c(rnorm(25, 10, 2),
            rnorm(25, 15, 3),
            rnorm(25, 12, 2.5),
            rnorm(25, 18, 4))
)

p <- ggplot(df, aes(x = category, y = value, fill = category)) +
  geom_boxplot(alpha = 0.7) +
  theme_minimal() +
  labs(title = "Distribution by Category",
       x = "Category",
       y = "Value") +
  scale_fill_brewer(palette = "Set2")

rplot(p, filename = "boxplot_demo.png")
endsubmit;
run;