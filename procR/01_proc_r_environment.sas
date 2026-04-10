* Understanding which R environment is currently in use;
%let rpath = %sysget(PROC_RPATH);
%put PROC_RPATH = &rpath.;

proc r;
submit;
# installed.packages() returns a matrix — convert to data frame
pkgs <- as.data.frame(
    installed.packages()[, c("Package", "Version", "Priority", "Depends", "Imports", "License", "NeedsCompilation")],
    stringsAsFactors = FALSE,
    row.names = FALSE
)

# Tidy up: replace NA with empty string so SAS handles it cleanly
pkgs[is.na(pkgs)] <- ""

# Flag which packages are currently loaded in this session
pkgs$Loaded <- ifelse(pkgs$Package %in% loadedNamespaces(), "Yes", "No")

# Sort alphabetically
pkgs <- pkgs[order(pkgs$Package), ]

# Summary to log
cat("Total packages found:", nrow(pkgs), "\n")
cat("Packages loaded in session:", sum(pkgs$Loaded == "Yes"), "\n")

# Push to SAS WORK library
df2sd(pkgs, "r_packages", "work")
endsubmit;
run;