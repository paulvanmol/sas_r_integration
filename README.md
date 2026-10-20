# SAS & R Integration – Clinical Programmer Case Study
## SAS Viya Stable 2026.03

### Contents
| File | Description |
|------|-------------|
| `01_Presentation.md` | Full slide-by-slide presentation (14 slides) |
| `02_Demo_ProcIML.sas` | Demo 1 – PROC IML SUBMIT/R (classic approach) |
| `03_Demo_RRunner.sas` | Demo 2 – R Runner Custom Step equivalent code |
| `04_Demo_ProcR.sas` | Demo 3 – PROC R (new, Viya Stable 2026.03) |
| `05_Demo_Polyglot.sas` | Demo 4 – Polyglot pipeline: SAS + Python + R |
| `06_Demo_Haven_CSV.sas` | Demo 5 – Reading SAS datasets with haven + CSV round-trip |
| `07_Admin_Guide.md` | Administrator guide: enabling PROC R in SAS Viya |
| `08_ProcR_Pitfalls.md` | Common PROC R pitfalls and fixes |

### Scenario
A clinical programmer at a pharma company receives ADaM-ready data (ADLB, ADTTE)
and needs to:
1. Explore lab data in R (ggplot2 visualizations)
2. Fit a Mixed Model for Repeated Measures (MMRM) in both SAS and R
3. Compare model results side-by-side
4. Store final estimates back as a SAS dataset for TFL production

### R Packages Used
- `nlme`, `mmrm` – mixed models
- `survival`, `survminer` – Kaplan-Meier / Cox
- `ggplot2` – visualization
- `haven` – SAS dataset I/O (for standalone R context)

### PROC R Callback Methods (Viya 2026.03)
| Callback | Direction | Purpose |
|----------|-----------|---------|
| `sd2df("lib.ds")` | SAS → R | Import SAS dataset as R data frame |
| `df2sd(df, "lib.ds")` | R → SAS | Export R data frame to SAS dataset |
| `symget("macvar")` | SAS → R | Read SAS macro variable |
| `symput("macvar","val")` | R → SAS | Write value to SAS macro variable |
| `submit("sas code")` | R → SAS | Execute SAS code from R |
| `sasfnc("func"<,args>)` | R → SAS | Call a SAS function |
| `rplot(obj)` | R → Results | Render R plot in Results window |
| `renderImage("path")` | R → Results | Render saved image in Results window |
| `show(obj,title=,count=)` | R → Results | Display R object in Results window |
