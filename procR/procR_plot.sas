/*rplot callback method displays R plot in results*/
proc r;
submit;
x <- 1:100
y <- x^2 + rnorm(100, 0, 100)

rplot({
plot(x, y,
     main = "Base R Scatter Plot",
     xlab = "X Values",
     ylab = "Y Values",
     col = "blue",
     pch = 19)

  abline(lm(y ~ x), col = "red", lwd = 2)
})

endsubmit;
run;


