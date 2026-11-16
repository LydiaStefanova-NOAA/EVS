#!/bin/bash

#set -x
exec </dev/null

echo "VDATE=$VDATE"
echo "OBS_SRC_ROOT=$OBS_SRC_ROOT"
echo "config=${config:-}"

echo "BEGIN: $(basename ${BASH_SOURCE[0]})"

export OMP_NUM_THREADS=1

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

OBS_SRC_ROOT=${OBS_SRC_ROOT:-""}
COMOUT=${COMOUT:-""}
VDATE=${VDATE:-""}
FIXevs=${FIXevs:-${HOMEevs}/fix}
config=${config:-${HOMEevs}/parm/evs_config/${COMPONENT:-seasonal}/config.evs.${COMPONENT:-seasonal}.${MODELNAME:-sfs_b2}}

if [ -z "$OBS_SRC_ROOT" ] || [ -z "$COMOUT" ] || [ -z "$VDATE" ] || [ -z "$RUN" ]; then
    die "ERROR: OBS_SRC_ROOT, COMOUT, VDATE, and RUN must all be set."
fi

if ! [[ "$VDATE" =~ ^[0-9]{6}$ ]]; then
    die "ERROR: VDATE must be in YYYYMM format (got: '${VDATE}')."
fi

[ -f "$config" ] || die "ERROR: Required EVS config file not found: '${config}'."
source "$config"

[ "${NVARS:-0}" -ge 1 ] || die "ERROR: NVARS must be >= 1 in ${config}."

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
BASE_OUT="${COMOUT}/${RUN}.${VDATE}"

TMP_OBS_DIR="${DATA}/tmp_obs_$$"
mkdir -p "$TMP_OBS_DIR" || die "ERROR: Failed to create scratch directory ${TMP_OBS_DIR}."

OBS_CAT_PY="${TMP_OBS_DIR}/calc_obs_terciles.py"
cat << 'EOF' > "$OBS_CAT_PY"
import sys
import numpy as np
import xarray as xr

out_cat_path = sys.argv[1]
climo_path = sys.argv[2]
obs_path = sys.argv[3]
vmonth = int(sys.argv[4])
target_vars = sys.argv[5].split(",")

ds_clim = xr.open_dataset(climo_path)
ds_obs = xr.open_dataset(obs_path)

out_ds = xr.Dataset(coords=ds_obs.coords)

for var in target_vars:
    if var not in ds_obs:
        sys.stderr.write(f"ERROR: Configured obs variable '{var}' missing from {obs_path}\n")
        sys.exit(1)

    p33_key = f"{var}_p33"
    p67_key = f"{var}_p67"
    if p33_key not in ds_clim or p67_key not in ds_clim:
        sys.stderr.write(f"ERROR: Missing '{p33_key}' and/or '{p67_key}' in {climo_path}\n")
        sys.exit(1)

    obs_vals = ds_obs[var].values
    p33_vals = ds_clim[p33_key].values
    p67_vals = ds_clim[p67_key].values

    if p33_vals.ndim == 3 and p33_vals.shape[0] == 12:
        p33_vals = p33_vals[vmonth - 1]
        p67_vals = p67_vals[vmonth - 1]

    if obs_vals.ndim == 3 and p33_vals.ndim == 2:
        p33_vals = p33_vals[np.newaxis, ...]
        p67_vals = p67_vals[np.newaxis, ...]
    elif obs_vals.ndim == 2 and p33_vals.ndim == 3 and p33_vals.shape[0] == 1:
        p33_vals = p33_vals[0]
        p67_vals = p67_vals[0]

    if obs_vals.shape != p33_vals.shape or obs_vals.shape != p67_vals.shape:
        sys.stderr.write(
            f"ERROR: Shape mismatch for '{var}': obs {obs_vals.shape} vs "
            f"climo {p33_vals.shape} / {p67_vals.shape}\n"
        )
        sys.exit(1)

    invalid = np.isnan(obs_vals) | np.isnan(p33_vals) | np.isnan(p67_vals)

    below = np.where(obs_vals < p33_vals, 1.0, 0.0).astype(np.float32)
    above = np.where(obs_vals > p67_vals, 1.0, 0.0).astype(np.float32)
    near  = np.where((obs_vals >= p33_vals) & (obs_vals <= p67_vals), 1.0, 0.0).astype(np.float32)

    cat = np.full(obs_vals.shape, 2.0, dtype=np.float32)
    cat[obs_vals < p33_vals] = 1.0
    cat[obs_vals > p67_vals] = 3.0

    below[invalid] = np.nan
    near[invalid]  = np.nan
    above[invalid] = np.nan
    cat[invalid]   = np.nan

    dims = ds_obs[var].dims
    out_ds[f"{var}_cat"]   = xr.DataArray(cat, dims=dims, attrs={"long_name": f"{var} realized tercile category (1=below,2=near,3=above)", "units": "1"})
    out_ds[f"{var}_below"] = xr.DataArray(below, dims=dims, attrs={"long_name": f"{var} below-normal indicator", "units": "1"})
    out_ds[f"{var}_near"]  = xr.DataArray(near, dims=dims, attrs={"long_name": f"{var} near-normal indicator", "units": "1"})
    out_ds[f"{var}_above"] = xr.DataArray(above, dims=dims, attrs={"long_name": f"{var} above-normal indicator", "units": "1"})

ds_clim.close()
ds_obs.close()

out_ds.to_netcdf(out_cat_path, format="NETCDF3_64BIT")
print(" ".join(target_vars))
EOF

# ==============================================================================
# Process Each Configured Observation Target
# ==============================================================================
for key in "${OBS_TARGETS[@]}"; do
    obs="${TARGET_OBS_NAME[$key]}"
    prefix="${TARGET_OBS_PREFIX[$key]}"
    req_vars="${TARGET_OBS_VARS[$key]}"

    echo "------------------------------------------------------------------------------"
    echo "Processing ${obs} (${prefix}_${VDATE}.nc, vars: ${req_vars})"

    src_dir="${OBS_SRC_ROOT}/${obs}/monthly"
    dest_dir="${BASE_OUT}/obs/${obs}"
    fix_climo_dir="${FIXevs}/climos/seasonal/${obs}"
    mkdir -p "$dest_dir" || die "ERROR: Failed to create ${dest_dir}."

    obs_basename="${prefix}_${VDATE}.nc"
    src_obs_file="${src_dir}/${obs_basename}"
    [ -f "$src_obs_file" ] || die "ERROR: Required observation file not found: ${src_obs_file}"

    climo_var="${obs}_CLIMO_DIR"
    configured_climo_dir="${!climo_var:-${fix_climo_dir}}"

    CLIMO_SRC=""
    for search_dir in \
        "${configured_climo_dir}" \
        "${fix_climo_dir}" \
        "${OBS_SRC_ROOT}/${obs}/climatology_1991-2020" \
        "${OBS_SRC_ROOT}/${obs}"; do
        [ -d "$search_dir" ] || continue

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
    CLIMO_LOCAL="${dest_dir}/${climo_basename}"
    if [ "$(readlink -f "$CLIMO_SRC")" != "$(readlink -f "$CLIMO_LOCAL")" ]; then
        cp -p "$CLIMO_SRC" "$CLIMO_LOCAL" || die "ERROR: Failed to copy ${CLIMO_SRC} to ${CLIMO_LOCAL}."
    fi

    fix_climo_target="${fix_climo_dir}/${climo_basename}"
    if [ ! -f "$fix_climo_target" ]; then
        mkdir -p "$fix_climo_dir" || die "ERROR: Failed to create ${fix_climo_dir}."
        cp -p "$CLIMO_SRC" "$fix_climo_target" || die "ERROR: Failed to stage ${climo_basename} into ${fix_climo_dir}."
    fi

    dst_obs_file="${dest_dir}/${obs_basename}"
    cp -p "$src_obs_file" "$dst_obs_file" || die "ERROR: Failed to copy ${src_obs_file} to ${dst_obs_file}."

    stem="${obs_basename%.nc}"
    out_anom="${dest_dir}/${stem}.anom.nc"
    out_cat="${dest_dir}/${stem}.cat.nc"

    obs_vars=$(cdo -s showname "$dst_obs_file" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')
    clim_vars=$(cdo -s showname "$CLIMO_LOCAL" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')

    sel_obs_list=()
    sel_clim_list=()
    chname_list=()
    req_var_csv=()

    for v in $req_vars; do
        echo "$obs_vars"  | grep -qx "$v"         || die "ERROR: Configured variable '${v}' missing from ${dst_obs_file}."
        echo "$clim_vars" | grep -qx "${v}_mean"  || die "ERROR: Missing '${v}_mean' in ${CLIMO_LOCAL}."
        echo "$clim_vars" | grep -qx "${v}_p33"   || die "ERROR: Missing '${v}_p33' in ${CLIMO_LOCAL}."
        echo "$clim_vars" | grep -qx "${v}_p67"   || die "ERROR: Missing '${v}_p67' in ${CLIMO_LOCAL}."

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

    cdo -s -O "$cdo_op" -selname,"${sel_obs}" "$dst_obs_file" -chname,"${chname_arg}" -selname,"${sel_clim}" "$CLIMO_LOCAL" "$out_anom" \
        || die "ERROR: cdo ${cdo_op} failed when creating ${out_anom}."
    echo "SUCCESS: Created ${out_anom} using cdo ${cdo_op} (vars: ${sel_obs})"

    cat_out=$(python3 "$OBS_CAT_PY" "$out_cat" "$CLIMO_LOCAL" "$dst_obs_file" "$((10#$VMONTH))" "${target_vars_arg}" 2>&1) \
        || die "ERROR: Observation tercile category calculation failed for ${out_cat}: ${cat_out}"
    [ -s "$out_cat" ] || die "ERROR: Expected category output ${out_cat} was not created or is empty."
    echo "SUCCESS: Created ${out_cat} (vars: ${cat_out})"
done

rm -rf "$TMP_OBS_DIR"
echo "END: $(basename ${BASH_SOURCE[0]})"
