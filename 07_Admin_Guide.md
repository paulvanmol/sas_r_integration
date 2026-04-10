# Administrator Guide: Enabling PROC R in SAS Viya
## SAS Viya Stable 2026.03 and later

---

## Overview

SAS Viya Stable 2026.03 introduces PROC R, a native SAS procedure that
allows R code to be executed within a SAS Compute Server session.

Because PROC R enables execution of external open-source code, it is not
available by default. An administrator must explicitly configure R external
language integration in the SAS Viya deployment.

Enabling PROC R requires:
1. Installing R in the SAS Viya environment via sas-pyconfig
2. Making R visible to SAS Compute Server processes
3. Allowing external language execution under SAS Viya security controls
4. Installing required R packages centrally
5. Controlling access via compute contexts and authorization

> PROC R does not have a standalone on/off SAS option. Availability is
> determined by deployment configuration, not a single toggle. There is
> no `PROCR_ENABLED` option.

---

## Step 1 – Install R Using the SAS Configurator for Open Source

The SAS Configurator for Open Source (`sas-pyconfig`) is the only supported
method for installing R for SAS Compute in Viya. It builds R from source,
installs packages, and writes everything to a shared Persistent Volume (PVC).

### 1a. Locate deployment assets

On the deployment host, identify the `site-config` directory:

```
$deploy/site-config/
```

### 1b. Enable R in change-configuration.yaml

Edit:

```
$deploy/site-config/sas-pyconfig/change-configuration.yaml
```

Ensure the following settings are present:

```yaml
global:
  enabled: true
  r_enabled: true
```

Optionally specify R profiles if your environment uses them.

### 1c. Specify packages to install

Copy the example R configuration directory:

```bash
cp -r $deploy/sas-bases/examples/sas-open-source-config/r \
      $deploy/site-config/sas-open-source-config/
```

Edit the package list in the patch section:

```yaml
patch:
  r-packages:
    - mmrm
    - survival
    - survminer
    - ggplot2
    - dplyr
    - broom
    - nlme
    - haven
    - gt
```

> `mmrm` and `survminer` are not part of base R and must be installed
> explicitly. Without them, demo code falls back to `nlme::lme` and
> base R graphics respectively.

### 1d. Run the sas-pyconfig job

```bash
kubectl create job sas-pyconfig-r-install \
  --from=cronjob/sas-pyconfig \
  -n <your-namespace>

# Monitor progress
kubectl logs -f job/sas-pyconfig-r-install -n <your-namespace>
```

The job builds R from source, installs packages, and writes the result
to the shared PVC used by SAS Compute pods.

---

## Step 2 – Make R Visible to the Compute Server

After sas-pyconfig completes, R must be visible to SAS Compute Server pods.
In most deployments this is handled automatically. If not, verify the
following environment variables are set in the compute pod:

```bash
R_HOME
PATH          # must include R/bin
LD_LIBRARY_PATH  # must include R/lib
```

If variables are missing, update the compute server deployment via
`site-config` overlays as documented by SAS.

> Do not hard-code paths unless required — path locations are
> deployment-dependent and may change between Viya releases.

---

## Step 3 – Understand How PROC R Becomes Available

PROC R becomes available automatically when:

- R external language integration is configured
- R is present and visible to the compute server
- The compute context allows external language execution

There is no SAS option such as `PROCR_ENABLED`. The procedure is
registered and licensed as part of Base SAS once the prerequisites above
are met.

The `RLANG` system option is associated with PROC IML's R integration and
is not documented as a prerequisite for PROC R. It does not need to be
set explicitly for PROC R to function.

---

## Step 4 – Verify the Installation

Log in to SAS Studio and run:

```sas
/* Verify R is callable from SAS */
proc r;
  submit;
    cat("R version:", R.version.string, "\n")
    cat("R_HOME:   ", Sys.getenv("R_HOME"), "\n")
  endsubmit;
run;
```

Expected behavior:
- No errors in the SAS log
- R version string printed
- `NOTE: R initialized.` appears in the log on first call

To check which R installation is active from the SAS side:

```sas
%let rpath = %sysget(PROC_RPATH);
%put NOTE: PROC_RPATH = &rpath.;
```

---

## Step 5 – Install Additional R Packages

### Option A – Via sas-pyconfig (recommended for production)

Add packages to the R package list in `site-config` (Step 1c) and
re-run the configurator job. This ensures:
- Offline availability in air-gapped environments
- Central governance and version control
- Consistent packages across all compute pods

### Option B – Manual installation (advanced / temporary only)

```bash
kubectl exec -it <sas-compute-pod> -n <namespace> -- bash

Rscript -e "install.packages(
  c('mmrm','survival','survminer','ggplot2','dplyr','broom'),
  repos = 'https://cloud.r-project.org',
  lib   = file.path(Sys.getenv('R_HOME'), 'library')
)"
```

Manual installation is not recommended for production or regulated
environments — packages will not persist across pod restarts unless
written to the shared PVC.

### Option C – Air-gapped / offline installation

```bash
# On an internet-connected machine, download source packages
Rscript -e "
  download.packages(
    c('mmrm','survival','survminer','ggplot2','dplyr','broom'),
    destdir = '/tmp/r_packages',
    repos   = 'https://cloud.r-project.org',
    type    = 'source'
  )
"

# Copy to the compute pod and install offline
kubectl cp /tmp/r_packages <pod>:/tmp/r_packages -n <namespace>
kubectl exec -it <pod> -n <namespace> -- \
  Rscript -e "install.packages(
    list.files('/tmp/r_packages', full.names = TRUE),
    repos = NULL, type = 'source'
  )"
```

---

## Step 6 – Access Control

PROC R access is controlled using standard SAS Viya mechanisms.
PROC-level authorization rules for PROC R are not currently documented
by SAS — do not attempt to create capability URIs for PROC R.

### Recommended approach

Create a dedicated Compute Context for R usage and assign only authorized
users or groups to it. Keep other compute contexts R-free.

1. Open SAS Environment Manager → Compute Contexts
2. Create a new context (e.g. `R-Enabled Context`) associated with the
   R-configured launcher
3. Assign the context to an authorized group (e.g. `ClinicalProgrammers`)
4. Leave the default context without R integration

### Additional controls

- Use `LOCKDOWN` settings to restrict filesystem and OS access within
  R-enabled sessions
- Monitor job execution via SAS Environment Manager
- Restrict network access from compute pods in regulated environments

---

## Step 7 – Logging and Monitoring

PROC R activity is logged as part of standard SAS Compute Server logging.
There is no PROC R-specific audit option (`PROCR_AUDIT` does not exist).

To monitor PROC R activity:

- SAS Environment Manager → Monitoring → Compute Sessions
- Kubernetes pod logs: `kubectl logs <sas-compute-pod> -n <namespace>`
- Integrate with the Viya logging and monitoring stack as documented in
  the SAS Viya Platform Operations Guide

---

## Quick Reference

| Item | Purpose |
|------|---------|
| `sas-pyconfig` | Installs R and packages into the shared PVC |
| `change-configuration.yaml` | Enables R via `r_enabled: true` |
| `R_HOME` | Location of R installation (set by sas-pyconfig) |
| Compute Context | Controls which users can execute PROC R |
| `LOCKDOWN` | Controls filesystem / OS access within sessions |
| SAS Environment Manager | Verification, monitoring, access control |

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `ERROR: Procedure R not found` | R not configured or not visible | Re-run sas-pyconfig; verify R_HOME |
| `WARNING: ignoring environment value of R_HOME` | R_HOME set externally, overridden by SAS | Informational only; does not prevent execution |
| Package not found (`no package called 'mmrm'`) | Not installed centrally | Add to sas-pyconfig package list |
| `X11 is not available` | Headless server, no display | Use `png(..., type="cairo")` or `rplot()` |
| First PROC R call is slow | R subprocess startup overhead | Normal; subsequent calls in same session are faster |
| R works in one context, not another | R not configured for that context | Assign R-enabled context to the user |

---

## References

- SAS Help Center – Overview: PROC R (SAS Viya Stable 2026.03)
- SAS Help Center – Configure R Integration Using SAS Configurator for Open Source
- SAS Communities – Introducing PROC R
- SAS Communities – [Installing R for SAS IML in SAS Viya](https://blogs.sas.com/content/iml/2023/01/09/install-r-sas-viya.html)
- SAS Viya Platform Operations Guide – Logging and Monitoring
- The SAS Viya Guide – [github.com/Criptic/The-SAS-Viya-Guide](https://github.com/Criptic/The-SAS-Viya-Guide)
