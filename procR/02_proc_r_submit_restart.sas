proc r;
    submit;
    print ('Hello from R - inside SAS') 
    endsubmit;
run;

proc r;
submit;
y <- "Hi!"
my_function <- function() {
  print("Inside the function")
}
endsubmit;
run;

proc r;
submit;
my_function()
print(paste("y =", y))
endsubmit;
run;

proc r restart;
submit;
x <- "New variable x is created"
print(paste("x =", x))
# References to function, variable from previous PROC R call
my_function()
print(paste("y =", y))
endsubmit;
run;

proc r terminate;
submit;
# Reference to variable defined in previous PROC R call
print(paste("x =", x))
x <- "Updating the value for x"
print(paste("x =", x))
# Redefining a function called my_function
my_function <- function() {
  print("Inside the proc step")
}
endsubmit;
run;

proc r;
submit;
print(paste("x =", x))
my_function()
endsubmit;
run;