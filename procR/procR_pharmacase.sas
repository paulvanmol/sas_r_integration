
libname adam "/srv/nfs/kubedata/compute-landingzone/sbxpav/r_integration/adam";
/*Step 1 – Prepare analysis dataset in SAS*/
data adam_dlt;
  set adam.adsl;
  where saffl = "Y";
run;
/*Step 2 – Pass SAS data to R using PROC R*/
proc r;
   submit;
      # SAS automatically provides the table
      dlt=sd2df('work.adam_dlt')
      show(dlt)
   endsubmit;
run;

