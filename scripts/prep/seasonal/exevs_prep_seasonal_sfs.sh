#!/bin/bash

#set -x
echo "VDATE=$VDATE"
echo "MAX_LEAD=$MAX_LEAD"
echo "SFS_SRC_ROOT=$SFS_SRC_ROOT"
echo "SFS_LEAD_MONTHLY_CLIMO_DIR=$SFS_LEAD_MONTHLY_CLIMO_DIR"
echo "MODELNAME=$MODELNAME"

echo "BEGIN: $(basename ${BASH_SOURCE[0]})"

DATA=${DATA:-${DATAROOT:?}/${jobid:?}}
mkdir -p "$DATA"
cd "$DATA"

# Helper for error exit whether or not prod_util is loaded
die() {
    if command -v err_exit >/dev/null 2>&1; then
        err_exit "$1"
    else
        echo "$1"
        exit 1
    fi
}

# Inputs supplied by driver/job wrapper
SFS_SRC_ROOT=${SFS_SRC_ROOT:-""}
VDATE=${VDATE:-""}
MAX_LEAD=${MAX_LEAD:-11}
COMOUT=${COMOUT:-""}
SFS_LEAD_MONTHLY_CLIMO_DIR=${SFS_LEAD_MONTHLY_CLIMO_DIR:-""}
FIXevs=${FIXevs:-${HOMEevs}/fix}

echo "COMOUT: $COMOUT VDATE: $VDATE MAX_LEAD: $MAX_LEAD SFS_SRC_ROOT: $SFS_SRC_ROOT"

if [ -z "$SFS_SRC_ROOT" ] || [ -z "$COMOUT" ] || [ -z "$VDATE" ] || [ -z "$RUN" ] || [ -z "$MODELNAME" ]; then
    die "ERROR: SFS_SRC_ROOT, COMOUT, VDATE, RUN, and MODELNAME must be set."
fi

# Defensive normalization in case VDATE arrives as YYYYMMDD
if [[ "$VDATE" =~ ^[0-9]{6}([0-9]{2})?$ ]]; then
    VDATE="${VDATE:0:6}"
else
    die "ERROR: VDATE must be in YYYYMM or YYYYMMDD format (got: '${VDATE}')."
fi

# Base output directories for verification month VDATE
BASE_OUT="${COMOUT}/${RUN}.${VDATE}/${MODELNAME}"
ENS_DIR="${BASE_OUT}/ens"
FIX_CLIMO_DIR="${FIXevs}/climos/seasonal/${MODELNAME}"

mkdir -p "$BASE_OUT" "$ENS_DIR"

echo "DEBUG SFS_SRC_ROOT=$SFS_SRC_ROOT"
echo "DEBUG BASE_OUT=$BASE_OUT"
echo "DEBUG COMOUT=$COMOUT"
echo "DEBUG VDATE=$VDATE"
echo "DEBUG MAX_LEAD=$MAX_LEAD"
echo "DEBUG RUN=$RUN"
echo "DEBUG DATA=$DATA"

# Scratch directory for parallel NetCDF conversion
TMP_NC_DIR="${DATA}/tmp_ens_nc_$$"
mkdir -p "$TMP_NC_DIR"

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

    # SFS forecasts have 31 members starting in 2026; earlier years have 11
    if [ "$INIT_YEAR" -ge 2026 ]; then
        NUM_MEMBERS=31
    else
        NUM_MEMBERS=11
    fi

    BASE_IN="${SFS_SRC_ROOT}/init_${INIT_MONTH}/${INIT_YEAR}"

    # --------------------------------------------------------------------------
    # 1. Stage lead-dependent monthly climatology file
    # --------------------------------------------------------------------------
    CLIMO_FILENAME="sfs_init${INIT_MONTH}_clim_1991-2020_lead${LEAD_PAD}.nc"
    CLIMO_SRC=""
    for candidate in \
        "${SFS_LEAD_MONTHLY_CLIMO_DIR}/init_${INIT_MONTH}/climatology_1991-2020/${CLIMO_FILENAME}" \
        "${SFS_SRC_ROOT}/init_${INIT_MONTH}/climatology_1991-2020/${CLIMO_FILENAME}" \
        "${SFS_LEAD_MONTHLY_CLIMO_DIR}/${CLIMO_FILENAME}" \
        "${FIX_CLIMO_DIR}/${CLIMO_FILENAME}"; do
        if [ -f "$candidate" ]; then
            CLIMO_SRC="$candidate"
            break
        fi
    done

    CLIMO_LOCAL=""
    if [ -n "$CLIMO_SRC" ]; then
        CLIMO_LOCAL="${BASE_OUT}/${CLIMO_FILENAME}"
        echo "Staging climatology file: ${CLIMO_SRC}"

        if [ "$(readlink -f "$CLIMO_SRC")" != "$(readlink -f "$CLIMO_LOCAL")" ]; then
            cp -p "$CLIMO_SRC" "$CLIMO_LOCAL"
        fi

        fix_climo_target="${FIX_CLIMO_DIR}/${CLIMO_FILENAME}"
        if [ ! -f "$fix_climo_target" ]; then
            if mkdir -p "$FIX_CLIMO_DIR" 2>/dev/null && [ -w "$FIX_CLIMO_DIR" ]; then
                cp -p "$CLIMO_SRC" "$fix_climo_target"
            else
                echo "WARNING: ${FIX_CLIMO_DIR} is not writable; skipped copying ${CLIMO_FILENAME} to FIXevs."
            fi
        fi
    else
        echo "WARNING: Climatology file not found for init_${INIT_MONTH} lead ${LEAD_PAD} (${CLIMO_FILENAME})."
    fi

    # --------------------------------------------------------------------------
    # 2. Check source forecast directory and discover files valid for VDATE
    # --------------------------------------------------------------------------
    if [ ! -d "${BASE_IN}/mem000" ]; then
        echo "WARNING: Source directory not found: ${BASE_IN}/mem000. Skipping lead ${LEAD_PAD}."
        continue
    fi

    EXACT_FILENAMES=$(cd "${BASE_IN}/mem000" && ls inst.monthly.*.${VDATE}.*.grb2 acc.monthly.*.${VDATE}.*.grb2 2>/dev/null)

    if [ -z "$EXACT_FILENAMES" ]; then
        echo "WARNING: No GRIB2 files valid for VDATE=${VDATE} found in ${BASE_IN}/mem000. Skipping lead ${LEAD_PAD}."
        continue
    fi

    # --------------------------------------------------------------------------
    # 3. Copy member GRIB2 files for VDATE and compute ensemble statistics
    # --------------------------------------------------------------------------
    for EXACT_FILENAME in $EXACT_FILENAMES; do
        echo "Processing ${EXACT_FILENAME} (lead ${LEAD_PAD}, ${NUM_MEMBERS} members)..."

        stem="${EXACT_FILENAME%.grb2}"

        MEMBER_FILES=()
        for (( i=0; i<NUM_MEMBERS; i++ )); do
            mem_dir=$(printf "mem%03d" "$i")
            src_mem_file="${BASE_IN}/${mem_dir}/${EXACT_FILENAME}"
            dst_mem_dir="${BASE_OUT}/${mem_dir}"
            dst_mem_file="${dst_mem_dir}/${EXACT_FILENAME}"

            if [ -f "${src_mem_file}" ]; then
                mkdir -p "${dst_mem_dir}"
                cp -p "${src_mem_file}" "${dst_mem_file}"
                MEMBER_FILES+=("${dst_mem_file}")
            else
                echo "WARNING: Missing expected file: ${src_mem_file}"
            fi
        done

        if [ "${#MEMBER_FILES[@]}" -eq "${NUM_MEMBERS}" ]; then
            tmp_ncs=()

            # Parallel conversion to NetCDF in scratch to bypass CDO GRIB2 limitations
            for mem_file in "${MEMBER_FILES[@]}"; do
                mname=$(basename "$(dirname "$mem_file")")
                tmp_nc="${TMP_NC_DIR}/lead${LEAD_PAD}_${mname}_${EXACT_FILENAME}.nc"

                wgrib2 "$mem_file" -netcdf "$tmp_nc" >/dev/null 2>&1 &
                tmp_ncs+=("$tmp_nc")
            done
            wait

            out_mean="${ENS_DIR}/${stem}.ensmean.nc"
            out_std="${ENS_DIR}/${stem}.ensstd.nc"
            out_anom="${ENS_DIR}/${stem}.ensanom.nc"

            # Ensemble mean and standard deviation
            cdo -s -O ensmean "${tmp_ncs[@]}" "${out_mean}"
            cdo -s -O ensstd  "${tmp_ncs[@]}" "${out_std}"
            echo "SUCCESS: Created ${out_mean} and ${out_std}"

            # Ensemble anomaly relative to lead-dependent climatology
            if [ -n "$CLIMO_LOCAL" ] && [ -f "$CLIMO_LOCAL" ]; then
                mean_vars=$(cdo -s showname "${out_mean}" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')
                clim_vars=$(cdo -s showname "${CLIMO_LOCAL}" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')

                sel_mean_list=()
                sel_clim_list=()
                chname_list=()

                # Match either <var> directly or <var>_mean in the climatology file
                for v in $mean_vars; do
                    if echo "$clim_vars" | grep -qx "$v"; then
                        sel_mean_list+=("$v")
                        sel_clim_list+=("$v")
                    elif echo "$clim_vars" | grep -qx "${v}_mean"; then
                        sel_mean_list+=("$v")
                        sel_clim_list+=("${v}_mean")
                        chname_list+=("${v}_mean,${v}")
                    fi
                done

                if [ "${#sel_mean_list[@]}" -gt 0 ]; then
                    sel_mean=$(IFS=,; echo "${sel_mean_list[*]}")
                    sel_clim=$(IFS=,; echo "${sel_clim_list[*]}")
                    chname_arg=$(IFS=,; echo "${chname_list[*]}")

                    if [ -n "$chname_arg" ]; then
                        cdo_cmd=(cdo -s -O sub -selname,"${sel_mean}" "${out_mean}" -chname,"${chname_arg}" -selname,"${sel_clim}" "${CLIMO_LOCAL}" "${out_anom}")
                    else
                        cdo_cmd=(cdo -s -O sub -selname,"${sel_mean}" "${out_mean}" -selname,"${sel_clim}" "${CLIMO_LOCAL}" "${out_anom}")
                    fi

                    if "${cdo_cmd[@]}"; then
                        echo "SUCCESS: Created ${out_anom} (vars: ${sel_mean} <- ${sel_clim})"
                    else
                        echo "WARNING: cdo sub failed for ${out_anom} (check grid/time alignment between ${out_mean} and ${CLIMO_LOCAL})."
                    fi
                else
                    echo "WARNING: No matching variable names between ${out_mean} (${mean_vars//$'\n'/ }) and ${CLIMO_LOCAL} (${clim_vars//$'\n'/ }). Skipping ensanom."
                fi
            fi

            rm -f "${tmp_ncs[@]}"
        else
            echo "WARNING: Found ${#MEMBER_FILES[@]}/${NUM_MEMBERS} members for ${EXACT_FILENAME} (lead ${LEAD_PAD}). Skipping ensemble stats for this file."
        fi
    done
done

# Clean up temporary NetCDF directory entirely
rm -rf "$TMP_NC_DIR"

echo "END: $(basename ${BASH_SOURCE[0]})"
