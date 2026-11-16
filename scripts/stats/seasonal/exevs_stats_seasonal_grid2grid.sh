#!/bin/bash
# Program Name: exevs_stats_seasonal_grid2grid.sh
# Author(s)/Contact(s): Lydia Stefanova
# Creation date: 11/4/2026
# Abstract: Launched by jobs/JEVS_STATS_SEASONAL
#           calculates grid-to-grid verification for SFS forecasts

set -x

echo
echo "===== RUNNING GRID-TO-GRID STATS VERIFICATION ====="
echo "STEP=$STEP"
echo "VERIF_TYPE=$VERIF_TYPE"

# Normalize VDATE to YYYYMM (accepts YYYYMM or YYYYMMDD)
if [[ "${VDATE:-}" =~ ^[0-9]{6}([0-9]{2})?$ ]]; then
    export VDATE="${VDATE:0:6}"
else
    err_exit "ERROR: VDATE must be set in YYYYMM or YYYYMMDD format (got: '${VDATE:-}')."
fi

export MAX_LEAD=${MAX_LEAD:-11}

echo "VDATE=$VDATE"
echo "MAX_LEAD=$MAX_LEAD"
echo "MODELNAME=$MODELNAME"
echo "MONTHLY_CLIMATOLOGY_ROOT=$MONTHLY_CLIMATOLOGY_ROOT"
echo "COMIN=$COMIN"
echo "COMOUT=$COMOUT"

export OBSNAME="CORe"
export VARNAME="HGT500"

export FCST_GRID_STAT_INPUT_DIR=${COMIN}
export OBS_GRID_STAT_INPUT_DIR=${COMIN}
export FCST_CLIMO_DIR=${MONTHLY_CLIMATOLOGY_ROOT}/${MODELNAME}
export OBS_CLIMO_DIR=${MONTHLY_CLIMATOLOGY_ROOT}/${OBSNAME}

export GRID_STAT_OUTPUT_DIR=${COMOUT}/${MODELNAME}.${VDATE}
mkdir -p "$GRID_STAT_OUTPUT_DIR"

valid_sec=$(date -u -d "${VDATE}01 00:00:00" +%s)

for lead in $(seq 0 "$MAX_LEAD"); do
    export LEAD_PAD=$(printf "%02d" "$lead")
    export LEAD_SEQ="${lead}m"
    INIT_VDATE=$(date -d "${VDATE}01 -${lead} month" +"%Y%m")

    init_sec=$(date -u -d "${INIT_VDATE}01 00:00:00" +%s)
    lead_hours=$(( (valid_sec - init_sec) / 3600 ))
    export LEAD_HHMMSS=$(printf "%02d0000" "$lead_hours")

    fcst_file="${COMIN}/${RUN}.${VDATE}/${MODELNAME}/ens/inst.monthly.${INIT_VDATE}0100.${VDATE}.grib.t00z.ensmean.nc"
    if [ ! -f "$fcst_file" ]; then
        echo "WARNING: Forecast file not found for lead ${LEAD_PAD} (${fcst_file}). Skipping."
        continue
    fi

    echo "Running METplus GridStat for VDATE=${VDATE}, INIT=${INIT_VDATE}, LEAD=${LEAD_PAD} (${LEAD_SEQ}, ${LEAD_HHMMSS})..."
    run_metplus.py -c ${PARMevs}/metplus_config/stats/seasonal/grid2grid/sfs_deterministic.conf
    export err=$?; err_chk
done
