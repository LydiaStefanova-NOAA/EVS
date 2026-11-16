#!/bin/bash
# Program Name: exevs_prep_seasonal_obs.sh
# Abstract: Launched by jobs/JEVS_PREP_SEASONAL
#           Stages monthly observations and climatologies into $DATA, computes
#           monthly anomalies and realized tercile categories, and copies
#           products to $COMOUT via cpfs when SENDCOM=YES.

set -x
exec </dev/null

echo "BEGIN: $(basename ${BASH_SOURCE[0]})"
echo "VDATE=$VDATE"
echo "OBS_SRC_ROOT=$OBS_SRC_ROOT"
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

OBS_SRC_ROOT=${OBS_SRC_ROOT:-""}
COMOUT=${COMOUT:-""}
VDATE=${VDATE:-""}
SENDCOM=${SENDCOM:-YES}
FIXevs=${FIXevs:-${HOMEevs}/fix}
USHevs=${USHevs:-${HOMEevs}/ush}
PARMevs=${PARMevs:-${HOMEevs}/parm}
config=${config:-${PARMevs}/evs_config/${COMPONENT:-seasonal}/config.evs.${COMPONENT:-seasonal}.${MODELNAME:-sfs_b2}}

if [ -z "$OBS_SRC_ROOT" ] || [ -z "$COMOUT" ] || [ -z "$VDATE" ] || [ -z "$RUN" ]; then
    die "ERROR: OBS_SRC_ROOT, COMOUT, VDATE, and RUN must all be set."
fi

if ! [[ "$VDATE" =~ ^[0-9]{6}$ ]]; then
    die "ERROR: VDATE must be in YYYYMM format (got: '${VDATE}')."
fi

[ -f "$config" ] || die "ERROR: Required EVS config file not found: '${config}'."
source "$config"

[ "${NVARS:-0}" -ge 1 ] || die "ERROR: NVARS must be >= 1 in ${config}."

OBS_CAT_PY="${USHevs}/seasonal/calc_obs_terciles.py"
[ -f "$OBS_CAT_PY" ] || die "ERROR: Required utility script not found: '${OBS_CAT_PY}'."

# Deduplicate (OBS_NAME, OBS_PREFIX) pairs and collect required OBS_VARs per file
OBS_TARGETS=()
declare -A TARGET_OBS_NAME
declare -A TARGET_OBS_PREFIX
declare -A TARGET_OBS_VARS

for i in $(seq 1 "$NVARS"); do
    oname_ref="VAR${i}_OBS_NAME"
    opref_ref="VAR${i}_OBS_PREFIX"
    ovar_ref="VAR${i}_OBS_VAR"

    oname="${!oname_ref:-}"
    opref="${!opref_ref:-}"
    ovar="${!ovar_ref:-}"

    [ -n "$oname" ] && [ -n "$opref" ] && [ -n "$ovar" ] \
        || die "ERROR: VAR${i}_OBS_NAME, VAR${i}_OBS_PREFIX, and VAR${i}_OBS_VAR must be set in ${config}."

    key="${oname}::${opref}"
    if [ -z "${TARGET_OBS_NAME[$key]:-}" ]; then
        OBS_TARGETS+=("$key")
        TARGET_OBS_NAME["$key"]="$oname"
        TARGET_OBS_PREFIX["$key"]="$opref"
        TARGET_OBS_VARS["$key"]="$ovar"
    elif [[ ! " ${TARGET_OBS_VARS[$key]} " =~ " ${ovar} " ]]; then
        TARGET_OBS_VARS["$key"]="${TARGET_OBS_VARS[$key]} ${ovar}"
    fi
done

VMONTH="${VDATE:4:2}"

# ==============================================================================
# Process Each Configured Observation Target in $DATA, Publish via cpfs
# ==============================================================================
for key in "${OBS_TARGETS[@]}"; do
    obs="${TARGET_OBS_NAME[$key]}"
    prefix="${TARGET_OBS_PREFIX[$key]}"
    req_vars="${TARGET_OBS_VARS[$key]}"

    echo "------------------------------------------------------------------------------"
    echo "Processing ${obs} (${prefix}_${VDATE}.nc, vars: ${req_vars})"

    src_dir="${OBS_SRC_ROOT}/${obs}/monthly"
    work_dir="${DATA}/out/${RUN}.${VDATE}/obs/${obs}"
    com_dir="${COMOUT}/${RUN}.${VDATE}/obs/${obs}"
    fix_climo_dir="${FIXevs}/climos/seasonal/${obs}"
    mkdir -p "$work_dir" || die "ERROR: Failed to create ${work_dir}."

    obs_basename="${prefix}_${VDATE}.nc"
    src_obs_file="${src_dir}/${obs_basename}"
    work_obs_file="${work_dir}/${obs_basename}"
    if [ ! -f "$work_obs_file" ]; then
        cpreq "$src_obs_file" "$work_obs_file"
    fi

    climo_var="${obs}_CLIMO_DIR"
    configured_climo_dir="${!climo_var:-}"

    # Read-only lookup: prefer $FIXevs, then configured/archive climo directory
    CLIMO_SRC=""
    for search_dir in \
        "${fix_climo_dir}" \
        "${configured_climo_dir}" \
        "${OBS_SRC_ROOT}/${obs}/climatology_1991-2020" \
        "${OBS_SRC_ROOT}/${obs}"; do
        [ -n "$search_dir" ] && [ -d "$search_dir" ] || continue

        for candidate in \
            "${search_dir}/${prefix}_clim_${VMONTH}.nc" \
            "${search_dir}/${obs}_all_clim_${VMONTH}.nc" \
            "${search_dir}/${obs}_clim_${VMONTH}.nc"; do
            if [ -f "$candidate" ]; then
                CLIMO_SRC="$candidate"
                break 2
            fi
        done
    done

    [ -n "$CLIMO_SRC" ] || die "ERROR: Required climatology file not found for ${obs_basename} (VMONTH=${VMONTH})."

    climo_basename=$(basename "$CLIMO_SRC")
    CLIMO_LOCAL="${work_dir}/${climo_basename}"
    if [ ! -f "$CLIMO_LOCAL" ]; then
        cpreq "$CLIMO_SRC" "$CLIMO_LOCAL"
    fi

    stem="${obs_basename%.nc}"
    out_anom="${work_dir}/${stem}.anom.nc"
    out_cat="${work_dir}/${stem}.cat.nc"

    obs_vars=$(cdo -s showname "$work_obs_file" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')
    clim_vars=$(cdo -s showname "$CLIMO_LOCAL" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')

    sel_obs_list=()
    sel_clim_list=()
    chname_list=()
    req_var_csv=()

    for v in $req_vars; do
        echo "$obs_vars"  | grep -qx "$v"        || die "ERROR: Configured variable '${v}' missing from ${work_obs_file}."
        echo "$clim_vars" | grep -qx "${v}_mean" || die "ERROR: Missing '${v}_mean' in ${CLIMO_LOCAL}."
        echo "$clim_vars" | grep -qx "${v}_p33"  || die "ERROR: Missing '${v}_p33' in ${CLIMO_LOCAL}."
        echo "$clim_vars" | grep -qx "${v}_p67"  || die "ERROR: Missing '${v}_p67' in ${CLIMO_LOCAL}."

        sel_obs_list+=("$v")
        sel_clim_list+=("${v}_mean")
        chname_list+=("${v}_mean,${v}")
        req_var_csv+=("$v")
    done

    sel_obs=$(IFS=,; echo "${sel_obs_list[*]}")
    sel_clim=$(IFS=,; echo "${sel_clim_list[*]}")
    chname_arg=$(IFS=,; echo "${chname_list[*]}")
    target_vars_arg=$(IFS=,; echo "${req_var_csv[*]}")

    clim_ntime=$(cdo -s ntime "$CLIMO_LOCAL" 2>/dev/null | tr -d ' ')
    if [ "$clim_ntime" = "12" ]; then
        cdo_op="ymonsub"
    else
        cdo_op="sub"
    fi

    cdo -s -O "$cdo_op" -selname,"${sel_obs}" "$work_obs_file" -chname,"${chname_arg}" -selname,"${sel_clim}" "$CLIMO_LOCAL" "$out_anom"
    export err=$?; err_chk
    echo "SUCCESS: Created ${out_anom} using cdo ${cdo_op} (vars: ${sel_obs})"

    cat_out=$(python3 "$OBS_CAT_PY" "$out_cat" "$CLIMO_LOCAL" "$work_obs_file" "$((10#$VMONTH))" "${target_vars_arg}" 2>&1)
    export err=$?
    if [ "$err" -ne 0 ] || [ ! -s "$out_cat" ]; then
        die "ERROR: Observation tercile category calculation failed for ${out_cat}: ${cat_out}"
    fi
    echo "SUCCESS: Created ${out_cat} (vars: ${cat_out})"

    if [ "$SENDCOM" = "YES" ]; then
        mkdir -p "$com_dir" || die "ERROR: Failed to create ${com_dir}."
        cpfs "$CLIMO_LOCAL"    "${com_dir}/${climo_basename}"
        cpfs "$work_obs_file"  "${com_dir}/${obs_basename}"
        cpfs "$out_anom"       "${com_dir}/${stem}.anom.nc"
        cpfs "$out_cat"        "${com_dir}/${stem}.cat.nc"
    fi
done

echo "END: $(basename ${BASH_SOURCE[0]})"
