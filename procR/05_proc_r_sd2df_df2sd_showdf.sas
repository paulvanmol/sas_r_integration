data work.mydata;
  length a 8;
  length b_value 8;
  length var_32 $32;
  var_32 = "x";
  a = 1;
  b_value = 2;
  output;
run;
/*with head(), no show()*/
proc r;
    submit;
    head(df);
    endsubmit;
run;
/*with show()*/
proc r;
submit;
df <- sd2df("mydata", "work");
show(df)
endsubmit;
run; 



proc r; 
    submit;
  rx <- matrix( 1:3, nrow=1)             # vector of sequence 1,2,3
  rm <- matrix( 1:9, nrow=3, byrow=TRUE) # 3 x 3 matrix
  rq <- rm %*% t(rx)                     # matrix multiplication
  print(rq)
  
endsubmit;
run;


proc r; 
submit ;
df <- sd2df("sashelp.class", "df");
show(df)
names(df)
endsubmit;
run; 