* include script example for SAS Server;
%let path=/srv/nfs/kubedata/compute-landingzone/sbxpav/sas_r_integration; 
/* Inline path — resolved from macro variable */
proc r infile="&path./procR/my_script.r";
  submit;
    my_function()
    print(paste("y =", y))
  endsubmit;
run;

/* Filename fileref — same macro variable */
filename script "&path./procR/my_script.r";

proc r infile=script;
  submit;
    my_function()
    print(paste("y =", y))
  endsubmit;
run;

filename script clear;

/* SAS Content — username still hardcoded by design (personal folder) */
/*
filename script filesrvc folderpath="/Users/&sysuserid./My Folder/Courses"
                          name="my_script.r";
proc r infile=script;
  submit;
    my_function()
    print(paste("y =", y))
  endsubmit;
run;
filename script clear;
*/