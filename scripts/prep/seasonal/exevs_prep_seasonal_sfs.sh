#!/bin/bash
# Program Name: exevs_prep_seasonal_sfs.sh
# Abstract: Launched by jobs/JEVS_PREP_SEASONAL
#           Stages SFS ensemble members and lead-dependent climatologies into $DATA,
#           computes ensemble mean, spread, anomaly, and tercile probabilities,
#           and copies products to $COMOUT via cpfs when SENDCOM=YES.

set -x
exec </dev/null

echo "BEGIN: $(basename ${BASH_SOURCE[0]})"
echo "VDATE=$VDATE"
echo "MAX_LEAD=$MAX_LEAD"
echo "SFS_SRC_ROOT=$SFS_SRC_ROOT"
echo "SFS_LEAD_MONTHLY_CLIMO_DIR=$SFS_LEAD_MONTHLY_CLIMO_DIR"
echo "MODELNAME=$MODELNAME"
echo "config=${config:-}"

export OMP_NUM_THREADS=1

DATA=${DATA:-${DATAROOT:?}/${jobid:?}}
mkdir -p "$DATA"
cd "$DATA" || exit 1

die() {
    echo "$1" >&2
    if command -v err_exit >/dev/null 2>&1; then
        SENDECF=${SENDECF:-NO} err_exit "$1" || true
    fi
    exit 1
}

SFS_SRC_ROOT=${SFS_SRC_ROOT:-""}
SFS_LEAD_MONTHLY_CLIMO_DIR=${SFS_LEAD_MONTHLY_CLIMO_DIR:-""}
VDATE=${VDATE:-""}
MAX_LEAD=${MAX_LEAD:-11}
COMOUT=${COMOUT:-""}
SENDCOM=${SENDCOM:-YES}
USE_CFP=${USE_CFP:-NO}
nproc=${nproc:-1}
FIXevs=${FIXevs:-${HOMEevs}/fix}
USHevs=${USHevs:-${HOMEevs}/ush}
PARMevs=${PARMevs:-${HOMEevs}/parm}
config=${config:-${PARMevs}/evs_config/${COMPONENT:-seasonal}/config.evs.${COMPONENT:-seasonal}.${MODELNAME}}

if [ -z "$SFS_SRC_ROOT" ] || [ -z "$COMOUT" ] || [ -z "$VDATE" ] || [ -z "$RUN" ] || [ -z "$MODELNAME" ]; then
    die "ERROR: SFS_SRC_ROOT, COMOUT, VDATE, RUN, and MODELNAME must all be set."
fi

if ! [[ "$VDATE" =~ ^[0-9]{6}$ ]]; then
    die "ERROR: VDATE must be in YYYYMM format (got: '${VDATE}')."
fi

[ -f "$config" ] || die "ERROR: Required EVS config file not found: '${config}'."
source "$config"

[ "${NVARS:-0}" -ge 1 ] || die "ERROR: NVARS must be >= 1 in ${config}."

CALC_TERCILES_PY="${USHevs}/seasonal/calc_ens_terciles.py"
[ -f "$CALC_TERCILES_PY" ] || die "ERROR: Required utility script not found: '${CALC_TERCILES_PY}'."

# Build unique list of required forecast streams and per-stream variable lists
STREAMS=()
declare -A STREAM_VARS
for i in $(seq 1 "$NVARS"); do
    stream_ref="VAR${i}_FCST_STREAM"
    fvar_ref="VAR${i}_FCST_VAR"
    stream="${!stream_ref:-}"
    fvar="${!fvar_ref:-}"

    [ -n "$stream" ] && [ -n "$fvar" ] || die "ERROR: VAR${i}_FCST_STREAM and VAR${i}_FCST_VAR must be set in ${config}."

    if [[ ! " ${STREAMS[*]} " =~ " ${stream} " ]]; then
        STREAMS+=("$stream")
        STREAM_VARS["$stream"]="$fvar"
    elif [[ ! " ${STREAM_VARS[$stream]} " =~ " ${fvar} " ]]; then
        STREAM_VARS["$stream"]="${STREAM_VARS[$stream]} ${fvar}"
    fi
done

WORK_BASE="${DATA}/out/${RUN}.${VDATE}/${MODELNAME}"
WORK_ENS="${WORK_BASE}/ens"
COM_BASE="${COMOUT}/${RUN}.${VDATE}/${MODELNAME}"
COM_ENS="${COM_BASE}/ens"
FIX_CLIMO_DIR="${FIXevs}/climos/seasonal/${MODELNAME}"
TMP_NC_DIR="${DATA}/tmp_ens_nc"

mkdir -p "$WORK_BASE" "$WORK_ENS" "$TMP_NC_DIR" || die "ERROR: Failed to create working directories under ${DATA}."

# ==============================================================================
# Loop over forecast leads (0 .. MAX_LEAD) valid for VDATE
# ==============================================================================
for lead in $(seq 0 "$MAX_LEAD"); do
    LEAD_PAD=$(printf "%02d" "$lead")
    INIT_VDATE=$(date -d "${VDATE}01 -${lead} month" +"%Y%m")
    INIT_YEAR="${INIT_VDATE:0:4}"
    INIT_MONTH="${INIT_VDATE:4:2}"

    echo "------------------------------------------------------------------------------"
    echo "Lead ${LEAD_PAD}: VDATE=${VDATE} <- INIT=${INIT_VDATE} (init_${INIT_MONTH}/${INIT_YEAR})"

    if [ "$INIT_YEAR" -ge 2026 ]; then
        NUM_MEMBERS=31
    else
        NUM_MEMBERS=11
    fi

    BASE_IN="${SFS_SRC_ROOT}/init_${INIT_MONTH}/${INIT_YEAR}"

    # 1. Check whether this lead's forecast initialization exists in archive
    if [ ! -d "${BASE_IN}/mem000" ]; then
        echo "WARNING: Source directory not found: ${BASE_IN}/mem000. Skipping lead ${LEAD_PAD}."
        continue
    fi

    first_stream="${STREAMS[0]}"
    if ! ls "${BASE_IN}/mem000/${first_stream}.monthly."*".${VDATE}."*".grb2" >/dev/null 2>&1; then
        echo "WARNING: No GRIB2 files valid for VDATE=${VDATE} found in ${BASE_IN}/mem000. Skipping lead ${LEAD_PAD}."
        continue
    fi

    # 2. Require and stage lead-dependent monthly climatology into $DATA (never write to $FIXevs)
    CLIMO_FILENAME="${MODELNAME}_init${INIT_MONTH}_clim_1991-2020_lead${LEAD_PAD}.nc"
    FIX_CLIMO_FILE="${FIX_CLIMO_DIR}/${CLIMO_FILENAME}"
    ARCHIVE_CLIMO_FILE="${SFS_LEAD_MONTHLY_CLIMO_DIR}/init_${INIT_MONTH}/climatology_1991-2020/${CLIMO_FILENAME}"

    if [ -f "$FIX_CLIMO_FILE" ]; then
        CLIMO_SRC="$FIX_CLIMO_FILE"
    elif [ -n "$SFS_LEAD_MONTHLY_CLIMO_DIR" ] && [ -f "$ARCHIVE_CLIMO_FILE" ]; then
        CLIMO_SRC="$ARCHIVE_CLIMO_FILE"
    else
        die "ERROR: Required climatology file not found at '${FIX_CLIMO_FILE}' or '${ARCHIVE_CLIMO_FILE}'."
    fi

    CLIMO_LOCAL="${WORK_BASE}/${CLIMO_FILENAME}"
    echo "Staging climatology file into DATA: ${CLIMO_SRC}"
    cpreq "$CLIMO_SRC" "$CLIMO_LOCAL"

    if [ "$SENDCOM" = "YES" ]; then
        mkdir -p "$COM_BASE" || die "ERROR: Failed to create ${COM_BASE}."
        cpfs "$CLIMO_LOCAL" "${COM_BASE}/${CLIMO_FILENAME}"
    fi

    clim_vars=$(cdo -s showname "${CLIMO_LOCAL}" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')

    # 3. Process each configured forecast stream (inst, acc, ...)
    for stream in "${STREAMS[@]}"; do
        req_vars="${STREAM_VARS[$stream]}"
        EXACT_FILENAME=$(cd "${BASE_IN}/mem000" && ls "${stream}.monthly."*".${VDATE}."*".grb2" 2>/dev/null)
        [ -n "$EXACT_FILENAME" ] || die "ERROR: Required stream '${stream}' GRIB2 file missing in ${BASE_IN}/mem000 for VDATE=${VDATE}."
        [ -f "${BASE_IN}/mem000/${EXACT_FILENAME}" ] || die "ERROR: Expected single file for stream '${stream}' and VDATE=${VDATE}, got: ${EXACT_FILENAME}"

        echo "Processing ${EXACT_FILENAME} (lead ${LEAD_PAD}, ${NUM_MEMBERS} members, vars: ${req_vars})..."
        stem="${EXACT_FILENAME%.grb2}"

        MEMBER_FILES=()
        tmp_ncs=()
        tmp_errs=()
        CMDFILE_WGRIB2="${DATA}/cmdfile_wgrib2"
        : > "$CMDFILE_WGRIB2"

        for (( i=0; i<NUM_MEMBERS; i++ )); do
            mem_dir=$(printf "mem%03d" "$i")
            src_mem_file="${BASE_IN}/${mem_dir}/${EXACT_FILENAME}"
            work_mem_dir="${WORK_BASE}/${mem_dir}"
            work_mem_file="${work_mem_dir}/${EXACT_FILENAME}"

            mkdir -p "${work_mem_dir}" || die "ERROR: Failed to create ${work_mem_dir}."
            cpreq "${src_mem_file}" "${work_mem_file}"
            MEMBER_FILES+=("${work_mem_file}")

            if [ "$SENDCOM" = "YES" ]; then
                mkdir -p "${COM_BASE}/${mem_dir}" || die "ERROR: Failed to create ${COM_BASE}/${mem_dir}."
                cpfs "${work_mem_file}" "${COM_BASE}/${mem_dir}/${EXACT_FILENAME}"
            fi

            tmp_nc="${TMP_NC_DIR}/lead${LEAD_PAD}_${mem_dir}_${EXACT_FILENAME}.nc"
            tmp_err="${TMP_NC_DIR}/lead${LEAD_PAD}_${mem_dir}_${EXACT_FILENAME}.err"
            tmp_ncs+=("$tmp_nc")
            tmp_errs+=("$tmp_err")

            echo "wgrib2 \"${work_mem_file}\" -netcdf \"${tmp_nc}\" >\"${tmp_err}\" 2>&1" >> "$CMDFILE_WGRIB2"
        done

        # Execute wgrib2 conversions via CFP (when USE_CFP=YES and nproc>1) or foreground loop (no background &)
        if [ "$USE_CFP" = "YES" ] && [ "$nproc" -gt 1 ]; then
            mpiexec -n "$nproc" --cpu-bind verbose,core cfp "$CMDFILE_WGRIB2"
            export err=$?; err_chk
        else
            while IFS= read -r cmd; do
                eval "$cmd"
                export err=$?; err_chk
            done < "$CMDFILE_WGRIB2"
        fi

        for idx in "${!tmp_ncs[@]}"; do
            if [ ! -s "${tmp_ncs[$idx]}" ]; then
                cat "${tmp_errs[$idx]}" >&2 2>/dev/null
                die "ERROR: wgrib2 conversion failed for ${MEMBER_FILES[$idx]}."
            fi
        done
        rm -f "${tmp_errs[@]}"

        out_mean="${WORK_ENS}/${stem}.ensmean.nc"
        out_std="${WORK_ENS}/${stem}.ensstd.nc"
        out_anom="${WORK_ENS}/${stem}.ensanom.nc"
        out_prob="${WORK_ENS}/${stem}.ensprob.nc"

        cdo -s -O ensmean "${tmp_ncs[@]}" "${out_mean}"
        export err=$?; err_chk
        cdo -s -O ensstd  "${tmp_ncs[@]}" "${out_std}"
        export err=$?; err_chk
        echo "SUCCESS: Created ${out_mean} and ${out_std}"

        mean_vars=$(cdo -s showname "${out_mean}" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')

        sel_mean_list=()
        sel_clim_list=()
        chname_list=()
        req_var_csv=()

        for v in $req_vars; do
            echo "$mean_vars" | grep -qx "$v" || die "ERROR: Configured variable '${v}' missing from ${out_mean}."
            echo "$clim_vars" | grep -qx "${v}_mean" || die "ERROR: Missing '${v}_mean' in ${CLIMO_LOCAL}."
            echo "$clim_vars" | grep -qx "${v}_p33"  || die "ERROR: Missing '${v}_p33' in ${CLIMO_LOCAL}."
            echo "$clim_vars" | grep -qx "${v}_p67"  || die "ERROR: Missing '${v}_p67' in ${CLIMO_LOCAL}."

            sel_mean_list+=("$v")
            sel_clim_list+=("${v}_mean")
            chname_list+=("${v}_mean,${v}")
            req_var_csv+=("$v")
        done

        sel_mean=$(IFS=,; echo "${sel_mean_list[*]}")
        sel_clim=$(IFS=,; echo "${sel_clim_list[*]}")
        chname_arg=$(IFS=,; echo "${chname_list[*]}")
        target_vars_arg=$(IFS=,; echo "${req_var_csv[*]}")

        cdo -s -O sub -selname,"${sel_mean}" "${out_mean}" -chname,"${chname_arg}" -selname,"${sel_clim}" "${CLIMO_LOCAL}" "${out_anom}"
        export err=$?; err_chk
        echo "SUCCESS: Created ${out_anom} (vars: ${sel_mean})"

        prob_out=$(python3 "$CALC_TERCILES_PY" "${out_prob}" "${CLIMO_LOCAL}" "${out_mean}" "${target_vars_arg}" "${tmp_ncs[@]}" 2>&1)
        export err=$?
        if [ "$err" -ne 0 ] || [ ! -s "${out_prob}" ]; then
            die "ERROR: Tercile probability calculation failed for ${out_prob}: ${prob_out}"
        fi
        echo "SUCCESS: Created ${out_prob} (vars: ${prob_out})"

        if [ "$SENDCOM" = "YES" ]; then
            mkdir -p "$COM_ENS" || die "ERROR: Failed to create ${COM_ENS}."
            cpfs "${out_mean}" "${COM_ENS}/${stem}.ensmean.nc"
            cpfs "${out_std}"  "${COM_ENS}/${stem}.ensstd.nc"
            cpfs "${out_anom}" "${COM_ENS}/${stem}.ensanom.nc"
            cpfs "${out_prob}" "${COM_ENS}/${stem}.ensprob.nc"
        fi

        rm -f "${tmp_ncs[@]}"
    done
done

echo "END: $(basename ${BASH_SOURCE[0]})"
