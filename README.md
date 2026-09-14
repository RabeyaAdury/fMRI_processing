# Task-fMRI GLM and Residual Time-Series Generation

## Overview

This Bash workflow uses AFNI to perform task-based fMRI GLM analysis and generate residual time series for downstream functional connectivity analysis.

I adapted this workflow for a preclinical sensory-stimulation fMRI paradigm and automated the processing of task regressors, nuisance regressors, motion parameters, censoring, and subject-level outputs.

## Main Processing Steps

- Model task-related BOLD responses using `3dDeconvolve`
- Regress CSF and motion-related nuisance signals
- Apply motion/time-point censoring
- Generate beta coefficient and statistical maps
- Generate residual fMRI time series for functional connectivity analysis
- Optionally calculate percent-signal-change, ALFF/fALFF, and multiscale entropy outputs

## Requirements

- AFNI
- Bash/Linux
- Preprocessed and scaled fMRI data
- Motion regressors
- CSF nuisance regressor
- Task timing file

## Notes

This workflow was adapted for my research analyses. Study-specific paths, identifiers, and data are not included in the public repository. Parameters such as the stimulation model and censoring intervals should be modified for other datasets or experimental paradigms.
