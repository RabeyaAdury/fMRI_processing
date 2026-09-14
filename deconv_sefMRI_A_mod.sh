#!/bin/bash
set -e

#Runs Deconvolution, specifically set for the mouse heat paradigm

#PSC_bool="yes"
conn_bool="yes"
#ALFF_bool="no"
#MSE_bool="no"
gen_error_msg="Usage: [-h] [-z] [-a] [-m] -c"
while getopts "hzamc:" opt; do
    case ${opt} in
        h|\? ) echo "$gen_error_msg"; exit 0;;
        z ) #Percent signal change
            PSC_bool="yes";;
        a ) # Amplitude of low frequency fluctuations
            ALFF_bool="yes";;
        c ) #Give censor mean 1D file, necessary unless ALFF is being calculated
            censor=`readlink -ev $OPTARG`;;
        m ) #Calculate multi-scale entropy (Default is 5 levels of scale)
            MSE_bool="yes";;
    esac
done
shift $((OPTIND -1))

if [ $# -lt 4 ]; then echo "Not enough inputs"; exit 1; fi


epi_scaled=`readlink -ev $1` #Scaled EPI
motion_demean=`readlink -ev $2` #Motion mean 1D file
motion_deriv=`readlink -ev $3`
CSF=`readlink -ev $4`
stim_file=`readlink -ev $5` #Stimulation paradigm
prefix=`readlink -f $6`
echo "DEBUG: epi_scaled=$1"
echo "DEBUG: motion_demean=$2" 
echo "DEBUG: motion_deriv=$3"
echo "DEBUG: CSF=$4"
echo "DEBUG: stim_file=$5"
echo "DEBUG: prefix=$6"

out_dir=${prefix%/*}
echo "out_dir is $out_dir"
cp $0 $out_dir
here=`pwd`
my_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" #location of this script
#Basis function suggestions:
#https://afni.nimh.nih.gov/pub/dist/doc/misc/Decon/2007_0504_basis_funcs.html
if [ "$PSC_bool" == "yes" ]; then
    label="PSC"
    #stim_func='TENT(0,76,20)' #TENT functions spanning from 0 to 76s after start of stim. 
    stim_func='TENT(0,60,11)' 
    echo "*************************************"
    #echo "WARNING: TENT(0,76,20) is being used"
    echo "WARNING: $stim_func is being used, to be consistent with BLOCK 60s function"
    echo "this will not be appropriate for other stim paradigms"
    echo "*************************************"
    # "The BLOCK curve lasts about 15.8 seconds longer than the stimulus duration"
else
    label="BOLD"
    stim_func='BLOCK(60,1)' #60 second blocks at each stim time, peak amplitude of 1
    echo " stim_func is $stim_func"
fi

if [ "$ALFF_bool" == "yes" ]; then
    echo "Not censoring for ALFF"
else
    censor_opt="-censor $censor"
    x1D_censor_opt="-x1D_uncensored ${prefix}_nocensor_xmat.1D"
fi
# using 1deval to compute RMS for each timepoint from motion parameters file
1deval -a ${prefix}_motion_demean.1D[0] -b ${prefix}_motion_demean.1D[1] -c ${prefix}_motion_demean.1D[2] -d ${prefix}_motion_demean.1D[3] -e ${prefix}_motion_demean.1D[4] -f ${prefix}_motion_demean.1D[5] -expr 'sqrt((a*a + b*b + c*c + d*d + e*e + f*f)/6)'> ${prefix}_motion_demean_rms.1D


#===================== Deconvolution ====================
	#-force_TR 2 \ (only needed this when registration occured before deconvolution)
cd $out_dir
3dDeconvolve \
    -input $epi_scaled $censor_opt \
	-polort A \
    -ortvec $CSF CSF \
    -ortvec $motion_demean mot_demean \
    -ortvec $motion_deriv mot_deriv \
	-num_stimts 2 \
	-stim_times 1 $stim_file $stim_func -stim_label 1 $label \
    -stim_file 2 ${prefix}_motion_demean_rms.1D -stim_base 2 -stim_label 2 rms_motion \
    -CENSORTR 41-55 101-115 161-175 221-235 281-295 \
	-tout -fout	-rout \
    -x1D ${prefix}_xmat.1D $x1D_censor_opt \
    -xjpeg ${prefix}_xmat.jpg \
    -fitts ${prefix}_fitts.nii.gz \
    -errts ${prefix}_errts.nii.gz \
    -bucket ${prefix}_stats_epispace.nii.gz

    # -CENSORTR 41-55 101-115 161-175 221-235 281-295 \ used for BLOCk (60,1) function. PSC function is extended 0 to 76
    #-stim_file 2 ${prefix}_motion_demean.1D'[0]' -stim_base 2 -stim_label 2 roll  \
    #-stim_file 4 ${prefix}_motion_demean.1D'[2]' -stim_base 4 -stim_label 4 yaw   \
    

#Extract Bcoef and Tstat images
if [ "$PSC_bool" == "yes" ]; then
    # TENT functions affect here too
    for ia in {0..10}; do
        ib=$(( (ia+1)*2 ))
        3dbucket ${prefix}_stats_epispace.nii.gz[${ib}] \
            -prefix ${prefix}_PSC_Bcoef${ia}.nii.gz
    done
else
    3dbucket ${prefix}_stats_epispace.nii.gz[2] \
        -prefix ${prefix}_BOLD_Bcoef.nii.gz
    3dbucket ${prefix}_stats_epispace.nii.gz[3] \
        -prefix ${prefix}_BOLD_Tstat.nii.gz
fi


if [ "$ALFF_bool" == "yes" ]; then
    # Calculate ALFF maps
    3dRSFC -prefix ${prefix} -nodetrend 0.01 0.1 \
        ${prefix}_errts.nii.gz

    # Convert filtereed timeseries to nifti
    3dAFNItoNIFTI -prefix ${prefix}_errts_filtered.nii.gz ${prefix}_LFF+orig
    # Convert ALFF anf fALFF maps to nifti
    3dAFNItoNIFTI -prefix ${prefix}_ALFF.nii.gz ${prefix}_ALFF+orig
    3dAFNItoNIFTI -prefix ${prefix}_fALFF.nii.gz ${prefix}_fALFF+orig
fi

if [ "$MSE_bool" == "yes" ]; then
    3dMSE -prefix ${prefix}_mse.nii.gz ${prefix}_errts.nii.gz
    for i in {0..4}; do
        3dbucket -prefix ${prefix}_mse${i}.nii.gz ${prefix}_mse.nii.gz[${i}]
    done
fi

#3ddeconvolve structure for connectivity

#-polort should be >= 0
# -ortvec $motion 6 used for sefmri, rsfmri uses 12

if [ "$conn_bool" == "yes" ]; then

    # we can use either 3dDeconvolve or 3ddTproject, but as we don't need to construct GLM, 3dTproject does the job. 
    # I have both 3dDeconvolve and 3dTproject 
    #for connectivity analysis, only 6 degree of motion is regressed out
    #the output conn_errts.nii.gz will be called in Mondo_sefMRI_A_mod.sh "Run Task Connectivity" block
    #do i use censorTrs?
    ##============= 3dDeconvolve option===================##
    3dDeconvolve \
    -input $epi_scaled $censor_opt \
	-polort A \
    -ortvec $CSF CSF \
    -ortvec $motion_demean mot_demean \
    -ortvec $motion_deriv mot_deriv \
	-num_stimts 0 \
    -tout -fout	-rout \
    -x1D ${prefix}_conn_xmat.1D $x1D_censor_opt \
    -xjpeg ${prefix}_conn_xmat.jpg \
    -fitts ${prefix}_conn_fitts.nii.gz \
    -errts ${prefix}_conn_errts.nii.gz \
    -bucket ${prefix}_conn_stats_epispace.nii.gz
    ##============= 3dTproject option===================##

    # bandpass filter
    #3dTproject \
    #-input $epi_scaled $censor_opt \
    #-polort A \
    #-bandpass 0.009 0.12 \
    #-ortvec $motion mot_demean \
    #-errts ${prefix}_conn_errts.nii.gz \
else
    echo "--- Skipping Task Connectivity ---"
 
fi

cd $here

exit 0
