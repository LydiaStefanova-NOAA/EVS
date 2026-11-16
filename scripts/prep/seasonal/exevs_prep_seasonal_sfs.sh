#!/bin/bash

#set -x
exec </dev/null

echo "VDATE=$VDATE"
echo "MAX_LEAD=$MAX_LEAD"
echo "SFS_SRC_ROOT=$SFS_SRC_ROOT"
echo "SFS_LEAD_MONTHLY_CLIMO_DIR=$SFS_LEAD_MONTHLY_CLIMO_DIR"
echo "MODELNAME=$MODELNAME"
echo "config=${config:-}"

echo "BEGIN: $(basename ${BASH_SOURCE[0]})"

export OMP_NUM_THREADS=1
MAX_BG_JOBS=${nproc:-4}

DATA=${DATA:-${DATAROOT:?}/${jobid:?}}
mkdir -p "$DATA"
cd "$DATA" || exit 1

die() {
    echo "$1" >&2
    if command -v err_exit >/dev/null 2>&1; then
        SENDECF=NO err_exit "$1" || true
    fi
    exit 1
}

throttle_bg() {
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_BG_JOBS" ]; do
        sleep 0.2
    done
}

SFS_SRC_ROOT=${SFS_SRC_ROOT:-""}
SFS_LEAD_MONTHLY_CLIMO_DIR=${SFS_LEAD_MONTHLY_CLIMO_DIR:-""}
VDATE=${VDATE:-""}
MAX_LEAD=${MAX_LEAD:-11}
COMOUT=${COMOUT:-""}
FIXevs=${FIXevs:-${HOMEevs}/fix}
config=${config:-${HOMEevs}/parm/evs_config/${COMPONENT:-seasonal}/config.evs.${COMPONENT:-seasonal}.${MODELNAME}}

if [ -z "$SFS_SRC_ROOT" ] || [ -z "$SFS_LEAD_MONTHLY_CLIMO_DIR" ] || [ -z "$COMOUT" ] || [ -z "$VDATE" ] || [ -z "$RUN" ] || [ -z "$MODELNAME" ]; then
    die "ERROR: SFS_SRC_ROOT, SFS_LEAD_MONTHLY_CLIMO_DIR, COMOUT, VDATE, RUN, and MODELNAME must all be set."
fi

if ! [[ "$VDATE" =~ ^[0-9]{6}$ ]]; then
    die "ERROR: VDATE must be in YYYYMM format (got: '${VDATE}')."
fi

[ -f "$config" ] || die "ERROR: Required EVS config file not found: '${config}'."
source "$config"

[ "${NVARS:-0}" -ge 1 ] || die "ERROR: NVARS must be >= 1 in ${config}."

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

BASE_OUT="${COMOUT}/${RUN}.${VDATE}/${MODELNAME}"
ENS_DIR="${BASE_OUT}/ens"
FIX_CLIMO_DIR="${FIXevs}/climos/seasonal/${MODELNAME}"
mkdir -p "$BASE_OUT" "$ENS_DIR" || die "ERROR: Failed to create output directories under ${BASE_OUT}."

TMP_NC_DIR="${DATA}/tmp_ens_nc_$$"
mkdir -p "$TMP_NC_DIR" || die "ERROR: Failed to create scratch directory ${TMP_NC_DIR}."

# Helper Python script to compute tercile probabilities & dominant category
# Strictly processes the exact list of configured forecast variables passed via argv[4].
PROB_PY="${TMP_NC_DIR}/calc_ens_terciles.py"
cat << 'EOF' > "$PROB_PY"
import sys
import numpy as np
import xarray as xr

out_prob_path = sys.argv[1]
climo_path = sys.argv[2]
mean_path = sys.argv[3]
target_vars = sys.argv[4].split(",")
member_paths = sys.argv[5:]

ds_clim = xr.open_dataset(climo_path)
ds_mean = xr.open_dataset(mean_path)

member_dsets = [xr.open_dataset(p) for p in member_paths]
ds_ens = xr.concat(member_dsets, dim="ens")

out_ds = xr.Dataset(coords=ds_mean.coords)

for var in target_vars:
    if var not in ds_mean:
        sys.stderr.write(f"ERROR: Configured variable '{var}' missing from forecast {mean_path}\n")
        sys.exit(1)

    p33_key = f"{var}_p33"
    p67_key = f"{var}_p67"
    if p33_key not in ds_clim or p67_key not in ds_clim:
        sys.stderr.write(f"ERROR: Missing '{p33_key}' and/or '{p67_key}' in {climo_path}\n")
        sys.exit(1)

    ens_vals = ds_ens[var].values
    p33_vals = ds_clim[p33_key].values
    p67_vals = ds_clim[p67_key].values

    if ens_vals.shape[1:] != p33_vals.shape or ens_vals.shape[1:] != p67_vals.shape:
        sys.stderr.write(
            f"ERROR: Shape mismatch for '{var}': forecast slice {ens_vals.shape[1:]} vs "
            f"climo {p33_vals.shape} / {p67_vals.shape}\n"
        )
        sys.exit(1)

    pb = np.mean(ens_vals < p33_vals[np.newaxis, ...], axis=0).astype(np.float32)
    pa = np.mean(ens_vals > p67_vals[np.newaxis, ...], axis=0).astype(np.float32)
    pn = np.clip(1.0 - (pb + pa), 0.0, 1.0).astype(np.float32)

    dom_cat = np.full(pb.shape, 2, dtype=np.float32)
    dom_cat[(pb > pn) & (pb >= pa)] = 1
    dom_cat[(pa > pn) & (pa > pb)] = 3

    nan_mask = np.isnan(ens_vals[0])
    pb[nan_mask] = np.nan
    pn[nan_mask] = np.nan
    pa[nan_mask] = np.nan
    dom_cat[nan_mask] = np.nan

    dims = ds_mean[var].dims
    out_ds[f"{var}_prob_below"] = xr.DataArray(pb, dims=dims, attrs={"long_name": f"{var} probability below normal", "units": "1"})
    out_ds[f"{var}_prob_near"]  = xr.DataArray(pn, dims=dims, attrs={"long_name": f"{var} probability near normal", "units": "1"})
    out_ds[f"{var}_prob_above"] = xr.DataArray(pa, dims=dims, attrs={"long_name": f"{var} probability above normal", "units": "1"})
    out_ds[f"{var}_dom_cat"]    = xr.DataArray(dom_cat, dims=dims, attrs={"long_name": f"{var} dominant tercile category (1=below,2=near,3=above)", "units": "1"})

for d in member_dsets:
    d.close()
ds_clim.close()
ds_mean.close()

out_ds.to_netcdf(out_prob_path, format="NETCDF3_64BIT")
print(" ".join(target_vars))
EOF

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

    # 2. Require and stage lead-dependent monthly climatology
    CLIMO_FILENAME="${MODELNAME}_init${INIT_MONTH}_clim_1991-2020_lead${LEAD_PAD}.nc"
    PRIMARY_CLIMO="${SFS_LEAD_MONTHLY_CLIMO_DIR}/init_${INIT_MONTH}/climatology_1991-2020/${CLIMO_FILENAME}"
    FIX_CLIMO_TARGET="${FIX_CLIMO_DIR}/${CLIMO_FILENAME}"

    if [ -f "$PRIMARY_CLIMO" ]; then
        CLIMO_SRC="$PRIMARY_CLIMO"
    elif [ -f "$FIX_CLIMO_TARGET" ]; then
        CLIMO_SRC="$FIX_CLIMO_TARGET"
    else
        die "ERROR: Required climatology file not found at '${PRIMARY_CLIMO}' or '${FIX_CLIMO_TARGET}'."
    fi

    CLIMO_LOCAL="${BASE_OUT}/${CLIMO_FILENAME}"
    echo "Staging climatology file: ${CLIMO_SRC}"
    if [ "$(readlink -f "$CLIMO_SRC")" != "$(readlink -f "$CLIMO_LOCAL")" ]; then
        cp -p "$CLIMO_SRC" "$CLIMO_LOCAL" || die "ERROR: Failed to copy ${CLIMO_SRC} to ${CLIMO_LOCAL}."
    fi

    if [ ! -f "$FIX_CLIMO_TARGET" ]; then
        mkdir -p "$FIX_CLIMO_DIR" || die "ERROR: Failed to create ${FIX_CLIMO_DIR}."
        cp -p "$CLIMO_SRC" "$FIX_CLIMO_TARGET" || die "ERROR: Failed to stage ${CLIMO_FILENAME} into ${FIX_CLIMO_DIR}."
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
        for (( i=0; i<NUM_MEMBERS; i++ )); do
            mem_dir=$(printf "mem%03d" "$i")
            src_mem_file="${BASE_IN}/${mem_dir}/${EXACT_FILENAME}"
            dst_mem_dir="${BASE_OUT}/${mem_dir}"
            dst_mem_file="${dst_mem_dir}/${EXACT_FILENAME}"

            [ -f "${src_mem_file}" ] || die "ERROR: Missing expected member file: ${src_mem_file}"
            mkdir -p "${dst_mem_dir}" || die "ERROR: Failed to create ${dst_mem_dir}."
            cp -p "${src_mem_file}" "${dst_mem_file}" || die "ERROR: Failed to copy ${src_mem_file} to ${dst_mem_file}."
            MEMBER_FILES+=("${dst_mem_file}")
        done

        tmp_ncs=()
        tmp_errs=()
        for mem_file in "${MEMBER_FILES[@]}"; do
            throttle_bg
            mname=$(basename "$(dirname "$mem_file")")
            tmp_nc="${TMP_NC_DIR}/lead${LEAD_PAD}_${mname}_${EXACT_FILENAME}.nc"
            tmp_err="${TMP_NC_DIR}/lead${LEAD_PAD}_${mname}_${EXACT_FILENAME}.err"

            wgrib2 "$mem_file" -netcdf "$tmp_nc" >"$tmp_err" 2>&1 &
            tmp_ncs+=("$tmp_nc")
            tmp_errs+=("$tmp_err")
        done
        wait

        for idx in "${!tmp_ncs[@]}"; do
            if [ ! -s "${tmp_ncs[$idx]}" ]; then
                cat "${tmp_errs[$idx]}" >&2 2>/dev/null
                die "ERROR: wgrib2 conversion failed for ${MEMBER_FILES[$idx]}."
            fi
        done
        rm -f "${tmp_errs[@]}"

        out_mean="${ENS_DIR}/${stem}.ensmean.nc"
        out_std="${ENS_DIR}/${stem}.ensstd.nc"
        out_anom="${ENS_DIR}/${stem}.ensanom.nc"
        out_prob="${ENS_DIR}/${stem}.ensprob.nc"

        cdo -s -O ensmean "${tmp_ncs[@]}" "${out_mean}" || die "ERROR: cdo ensmean failed for ${out_mean}."
        cdo -s -O ensstd  "${tmp_ncs[@]}" "${out_std}"  || die "ERROR: cdo ensstd failed for ${out_std}."
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

        cdo -s -O sub -selname,"${sel_mean}" "${out_mean}" -chname,"${chname_arg}" -selname,"${sel_clim}" "${CLIMO_LOCAL}" "${out_anom}" \
            || die "ERROR: cdo sub failed when creating ${out_anom}."
        echo "SUCCESS: Created ${out_anom} (vars: ${sel_mean})"

        prob_out=$(python3 "$PROB_PY" "${out_prob}" "${CLIMO_LOCAL}" "${out_mean}" "${target_vars_arg}" "${tmp_ncs[@]}" 2>&1) \
            || die "ERROR: Tercile probability calculation failed for ${out_prob}: ${prob_out}"
        [ -s "${out_prob}" ] || die "ERROR: Expected probability output ${out_prob} was not created or is empty."
        echo "SUCCESS: Created ${out_prob} (vars: ${prob_out})"

        rm -f "${tmp_ncs[@]}"
    done
done

rm -rf "$TMP_NC_DIR"
echo "END: $(basename ${BASH_SOURCE[0]})"
