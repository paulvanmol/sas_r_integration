proc iml;
/* Comparison of matrix operations in IML and R */
print "----------  SAS/IML Results  -----------------";
x = 1:3;                                 /* vector of sequence 1,2,3 */
m = {1 2 3, 4 5 6, 7 8 9};               /* 3 x 3 matrix */
q = m * t(x);                            /* matrix multiplication */
print q;
print "-------------  R Results  --------------------";
submit / R;
  rx <- matrix( 1:3, nrow=1)             # vector of sequence 1,2,3
  rm <- matrix( 1:9, nrow=3, byrow=TRUE) # 3 x 3 matrix
  rq <- rm %*% t(rx)                     # matrix multiplication
  print(rq)
endsubmit;


call ExportDataSetToR("Sashelp.Class", "df" );
submit / R;
   names(df)
endsubmit;
quit;

