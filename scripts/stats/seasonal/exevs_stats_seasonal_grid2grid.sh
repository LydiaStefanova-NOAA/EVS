#!/bin/bash
# Program Name: exevs_stats_seasonal_grid2grid.sh
# Author(s)/Contact(s): Lydia Stefanova
# Creation date: 11/4/2026
# Abstract: Launched by jobs/JEVS_STATS_SEASONAL
#           calculates grid-to-grid verification for SFS forecasts

set -x
exec </dev/null

echo
echo "===== RUNNING GRID-TO-GRID STATS VERIFICATION ====="
echo "STEP=$STEP"
echo "VERIF_TYPE=$VERIF_TYPE"

die() {
    echo "$1" >&2
    if command -v err_exit >/dev/null 2>&1; then
        SENDECF=NO err_exit "$1" || true
    fi
    exit 1
}

if [[ "${VDATE:-}" =~ ^[0-9]{6}([0-9]{2})?$ ]]; then
    export VDATE="${VDATE:0:6}"
else
    die "ERROR: VDATE must be set in YYYYMM or YYYYMMDD format (got: '${VDATE:-}')."
fi

export MAX_LEAD=${MAX_LEAD:-11}
export USE_CFP=${USE_CFP:-YES}
export nproc=${nproc:-1}
export config=${config:-${PARMevs}/evs_config/${COMPONENT}/config.evs.${COMPONENT}.${MODELNAME}}

[ -f "$config" ] || die "ERROR: Required EVS config file not found: '${config}'."
source "$config"

[ "${NVARS:-0}" -ge 1 ] || die "ERROR: NVARS must be >= 1 in ${config}."

export FCST_GRID_STAT_INPUT_DIR=${COMIN}
export OBS_GRID_STAT_INPUT_DIR=${COMIN}
export FCST_CLIMO_DIR=${MONTHLY_CLIMATOLOGY_ROOT}/${MODELNAME}
export GRID_STAT_OUTPUT_DIR=${COMOUT}/${MODELNAME}.${VDATE}
mkdir -p "$GRID_STAT_OUTPUT_DIR" "${DATA}/jobs" "${DATA}/logs" || die "ERROR: Failed to create output/job/log directories."

CMDFILE="${DATA}/cmdfile"
: > "$CMDFILE"

valid_sec=$(date -u -d "${VDATE}01 00:00:00" +%s)
task_count=0

for i in $(seq 1 "$NVARS"); do
    var_id_ref="VAR${i}_ID"
    fstream_ref="VAR${i}_FCST_STREAM"
    fvar_ref="VAR${i}_FCST_VAR"
    flev_ref="VAR${i}_FCST_LEVEL"
    oname_ref="VAR${i}_OBS_NAME"
    opref_ref="VAR${i}_OBS_PREFIX"
    ovar_ref="VAR${i}_OBS_VAR"
    olev_ref="VAR${i}_OBS_LEVEL"
    oclev_ref="VAR${i}_OBS_CLIMO_LEVEL"

    VAR_ID="${!var_id_ref:-}"
    FCST_STREAM="${!fstream_ref:-}"
    FCST_VAR="${!fvar_ref:-}"
    FCST_LEVEL="${!flev_ref:-}"
    OBSNAME="${!oname_ref:-}"
    OBS_PREFIX="${!opref_ref:-}"
    OBS_VAR="${!ovar_ref:-}"
    OBS_LEVEL="${!olev_ref:-}"
    OBS_CLIMO_LEVEL="${!oclev_ref:-}"

    if [ -z "$VAR_ID" ] || [ -z "$FCST_STREAM" ] || [ -z "$FCST_VAR" ] || [ -z "$FCST_LEVEL" ] || \
       [ -z "$OBSNAME" ] || [ -z "$OBS_PREFIX" ] || [ -z "$OBS_VAR" ] || [ -z "$OBS_LEVEL" ] || [ -z "$OBS_CLIMO_LEVEL" ]; then
        die "ERROR: Incomplete VAR${i}_* definition in ${config}."
    fi

    OBS_CLIMO_DIR="${MONTHLY_CLIMATOLOGY_ROOT}/${OBSNAME}"

    # Observation file for VDATE must exist
    obs_file="${COMIN}/${RUN}.${VDATE}/obs/${OBSNAME}/${OBS_PREFIX}_${VDATE}.nc"
    [ -f "$obs_file" ] || die "ERROR: Required observation file not found: ${obs_file}"

    for lead in $(seq 0 "$MAX_LEAD"); do
        LEAD_PAD=$(printf "%02d" "$lead")
        LEAD_SEQ="${lead}m"
        INIT_VDATE=$(date -d "${VDATE}01 -${lead} month" +"%Y%m")

        init_sec=$(date -u -d "${INIT_VDATE}01 00:00:00" +%s)
        lead_hours=$(( (valid_sec - init_sec) / 3600 ))
        LEAD_HHMMSS=$(printf "%02d0000" "$lead_hours")

        fcst_file="${COMIN}/${RUN}.${VDATE}/${MODELNAME}/ens/${FCST_STREAM}.monthly.${INIT_VDATE}0100.${VDATE}.grib.t00z.ensmean.nc"
        if [ ! -f "$fcst_file" ]; then
            echo "WARNING: Forecast file not found for ${VAR_ID} lead ${LEAD_PAD} (${fcst_file}). Skipping."
            continue
        fi

        task_id="${VAR_ID}_lead${LEAD_PAD}"
        task_script="${DATA}/jobs/run_${task_id}.sh"
        task_log="${DATA}/logs/run_${task_id}.log"

        cat << EOF > "$task_script"
#!/bin/bash
exec > "${task_log}" 2>&1
set -x
export OMP_NUM_THREADS=1
export VARNAME="${VAR_ID}"
export FCST_STREAM="${FCST_STREAM}"
export FCST_VAR="${FCST_VAR}"
export FCST_LEVEL="${FCST_LEVEL}"
export OBSNAME="${OBSNAME}"
export OBS_PREFIX="${OBS_PREFIX}"
export OBS_VAR="${OBS_VAR}"
export OBS_LEVEL="${OBS_LEVEL}"
export OBS_CLIMO_LEVEL="${OBS_CLIMO_LEVEL}"
export OBS_CLIMO_DIR="${OBS_CLIMO_DIR}"
export LEAD_PAD="${LEAD_PAD}"
export LEAD_SEQ="${LEAD_SEQ}"
export LEAD_HHMMSS="${LEAD_HHMMSS}"
export METPLUS_OUTPUT_BASE="${DATA}/METplus/output_${task_id}"
run_metplus.py -c ${PARMevs}/metplus_config/stats/seasonal/grid2grid/sfs_deterministic.conf
EOF
        chmod +x "$task_script"
        echo "$task_script" >> "$CMDFILE"
        task_count=$((task_count + 1))
    done
done

[ "$task_count" -gt 0 ] || die "ERROR: No GridStat tasks were generated for VDATE=${VDATE}."

echo "Executing ${task_count} GridStat tasks (USE_CFP=${USE_CFP}, nproc=${nproc})..."
if [ "$USE_CFP" = "YES" ]; then
    mpiexec -n "$nproc" --cpu-bind verbose,core cfp "$CMDFILE"
    export err=$?
else
    ( set -e; bash "$CMDFILE" )
    export err=$?
fi

if [ "$err" -ne 0 ]; then
    echo "ERROR: One or more GridStat tasks failed (exit code ${err}). Checking task logs in ${DATA}/logs/:" >&2
    dumped=0
    for lf in "${DATA}/logs"/run_*.log; do
        [ -f "$lf" ] || continue
        if grep -qE "ERROR|Traceback|CRITICAL" "$lf" 2>/dev/null; then
            echo "===== FAILED TASK LOG: $lf =====" >&2
            cat "$lf" >&2
            dumped=1
        fi
    done
    if [ "$dumped" -eq 0 ]; then
        for lf in "${DATA}/logs"/run_*.log; do
            [ -f "$lf" ] || continue
            echo "===== TASK LOG: $lf =====" >&2
            cat "$lf" >&2
        done
    fi
    err_chk
fi
