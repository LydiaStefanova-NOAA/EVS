#!/bin/bash
# Program Name: exevs_stats_seasonal_grid2grid.sh
# Author(s)/Contact(s): Lydia Stefanova
# Creation date: 11/4/2026
# Abstract: Launched by jobs/JEVS_STATS_SEASONAL 
#           calculates grid-to-grid verification for SFS forecasts 

set -x

echo
echo "===== RUNNING GRID-TO-GRID STATS VERIFICATION  ====="
echo $STEP
echo $VERIF_CASE

# These are the environmental variables that the parm/metplus_config/seasonal/*.conf scripts need
#
echo MODELNAME $MODELNAME
echo MONTHLY_CLIMATOLOGY_ROOT $MONTHLY_CLIMATOLOGY_ROOT
echo COMIN $COMIN
echo COMOUT $COMOUT

export FCST_GRID_STAT_INPUT_DIR=${COMIN}/atmos.${INITYEAR}${INITMONTH}/${MODELNAME}/ens
export OBS_GRID_STAT_INPUT_DIR=${COMIN}/atmos.${INITYEAR}${INITMONTH}/obs/CORE/HGT500
export FCST_CLIMO_DIR=${MONTHLY_CLIMATOLOGY_ROOT}/${MODELNAME}/init_${INITMONTH}
export OBS_CLIMO_DIR=${MONTHLY_CLIMATOLOGY_ROOT}/CORE
export OUTPUT_BASE=${COMOUT}
export GRID_STAT_OUTPUT_DIR=${COMOUT}/${MODELNAME}.${VDATE}


# Source config
#echo $config
run_metplus.py -c ${PARMevs}/metplus_config/stats/seasonal/grid2grid/sfs_rmse_ensmean_lead00.conf


export err=$?; err_chk

# Set up directories
mkdir -p ${VERIF_TYPE}_$STEP
echo mkdir -p ${VERIF_TYPE}_$STEP
export err=$?; err_chk

