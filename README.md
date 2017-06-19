# GEAM

Code to extract and mask genetic data (Genetics Extract And Mask, GEAM)

Designed to enable genetic data in various formats to have variables and samples extracted and re-indexed for sharing with collaborators.

**WARNING** Code is bespoke for a particular project with a particular data management structure. Email epzcar@bristol.ac.uk for more info.

## Files

### 1. `getSampleForSet.pl`

### 2. `job_header.txt`

Is the PBS job scheduler header for the queue submission. This requests resources on the cluster for running the extraction.

### 3. `runBGEN.sh`

Code to use Perl scripts to extract data from dosage BGEN files.

### 4. `runPLINK.sh`

Code to use Perl scripts to extract data from PLINK files.

## Set-up files

Add in fill path for a withdrawn consent list to `getSampleForSet.pl`.
