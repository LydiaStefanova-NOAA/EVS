#!/bin/bash

#set -x
echo "VDATE=$VDATE"
echo "OBSNAME=$OBSNAME"
echo "OBS_SRC_ROOT=$OBS_SRC_ROOT"

echo "BEGIN: $(basename ${BASH_SOURCE[0]})"

DATA=${DATA:-${DATAROOT:?}/${jobid:?}}
mkdir -p "$DATA"
cd "$DATA"

# Inputs supplied by driver/job wrapper
OBS_SRC_ROOT=${OBS_SRC_ROOT:-""}
COMOUT=${COMOUT:-""}
VDATE=${VDATE:-""}
OBSNAME=${OBSNAME:-"GHCNCAMS CMAP CORe"}
FIXevs=${FIXevs:-${HOMEevs}/fix}

echo "COMOUT: $COMOUT VDATE: $VDATE OBS_SRC_ROOT: $OBS_SRC_ROOT"

if [ -z "$OBS_SRC_ROOT" ] || [ -z "$COMOUT" ] || [ -z "$VDATE" ] || [ -z "$RUN" ]; then
    if command -v err_exit >/dev/null 2>&1; then
        err_exit "ERROR: OBS_SRC_ROOT, COMOUT, VDATE, and RUN must be set."
    else
        echo "ERROR: OBS_SRC_ROOT, COMOUT, VDATE, and RUN must be set."
        exit 1
    fi
fi

# Defensive normalization in case VDATE arrives as YYYYMMDD
if [[ "$VDATE" =~ ^[0-9]{6}([0-9]{2})?$ ]]; then
    VDATE="${VDATE:0:6}"
else
    if command -v err_exit >/dev/null 2>&1; then
        err_exit "ERROR: VDATE must be in YYYYMM or YYYYMMDD format (got: '${VDATE}')."
    else
        echo "ERROR: VDATE must be in YYYYMM or YYYYMMDD format (got: '${VDATE}')."
        exit 1
    fi
fi

VMONTH="${VDATE:4:2}"
BASE_OUT="${COMOUT}/${RUN}.${VDATE}"

echo "DEBUG OBS_SRC_ROOT=$OBS_SRC_ROOT"
echo "DEBUG BASE_OUT=$BASE_OUT"
echo "DEBUG COMOUT=$COMOUT"
echo "DEBUG VDATE=$VDATE"
echo "DEBUG VMONTH=$VMONTH"
echo "DEBUG OBSNAME=$OBSNAME"
echo "DEBUG RUN=$RUN"
echo "DEBUG DATA=$DATA"

# ==============================================================================
# Stage Monthly Observations, Climatologies, and Compute Anomalies
# ==============================================================================
for obs in $OBSNAME; do
    echo "------------------------------------------------------------------------------"
    echo "Processing observation dataset: ${obs} (VDATE=${VDATE})"

    src_dir="${OBS_SRC_ROOT}/${obs}/monthly"
    dest_dir="${BASE_OUT}/obs/${obs}"
    fix_climo_dir="${FIXevs}/climos/seasonal/${obs}"
    mkdir -p "$dest_dir"

    # --------------------------------------------------------------------------
    # 1. Locate and stage climatology file for this obs dataset and VMONTH
    # --------------------------------------------------------------------------
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
            "${search_dir}"/*all*clim*_"${VMONTH}".nc \
            "${search_dir}"/*clim*_"${VMONTH}".nc \
            "${search_dir}"/*clim*"${VMONTH}"*.nc \
            "${search_dir}"/*clim*.nc; do
            if [ -f "$candidate" ]; then
                CLIMO_SRC="$candidate"
                break 2
            fi
        done
    done

    CLIMO_LOCAL=""
    if [ -n "$CLIMO_SRC" ]; then
        climo_basename=$(basename "$CLIMO_SRC")
        CLIMO_LOCAL="${dest_dir}/${climo_basename}"
        echo "Staging climatology file: ${CLIMO_SRC} -> ${dest_dir}/"

        if [ "$(readlink -f "$CLIMO_SRC")" != "$(readlink -f "$CLIMO_LOCAL")" ]; then
            cp -p "$CLIMO_SRC" "$CLIMO_LOCAL"
        fi

        fix_climo_target="${fix_climo_dir}/${climo_basename}"
        if [ ! -f "$fix_climo_target" ]; then
            if mkdir -p "$fix_climo_dir" 2>/dev/null && [ -w "$fix_climo_dir" ]; then
                cp -p "$CLIMO_SRC" "$fix_climo_target"
            else
                echo "WARNING: ${fix_climo_dir} is not writable; skipped copying ${climo_basename} to FIXevs."
            fi
        fi
    else
        echo "WARNING: No climatology file found for ${obs} (VMONTH=${VMONTH})."
    fi

    # --------------------------------------------------------------------------
    # 2. Copy monthly observation file(s) for VDATE and compute anomalies
    # --------------------------------------------------------------------------
    if [ ! -d "$src_dir" ]; then
        echo "WARNING: Source directory not found: $src_dir"
        continue
    fi

    found=0
    for file in "${src_dir}"/*"${VDATE}"*.nc; do
        [ -f "$file" ] || continue
        obs_basename=$(basename "$file")

        # Skip pre-existing anomaly or climo files if present in source
        case "$obs_basename" in
            *.anom.nc|*clim*) continue ;;
        esac

        dst_obs_file="${dest_dir}/${obs_basename}"
        echo "Copying ${obs_basename} -> ${dest_dir}/"
        cp -p "$file" "$dst_obs_file"
        found=1

        # Compute monthly anomaly if climatology is available
        if [ -n "$CLIMO_LOCAL" ] && [ -f "$CLIMO_LOCAL" ]; then
            stem="${obs_basename%.nc}"
            out_anom="${dest_dir}/${stem}.anom.nc"

            obs_vars=$(cdo -s showname "$dst_obs_file" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')
            clim_vars=$(cdo -s showname "$CLIMO_LOCAL" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')

            sel_obs_list=()
            sel_clim_list=()
            chname_list=()

            # Match either <var> directly or <var>_mean in the climatology file
            for v in $obs_vars; do
                if echo "$clim_vars" | grep -qx "$v"; then
                    sel_obs_list+=("$v")
                    sel_clim_list+=("$v")
                elif echo "$clim_vars" | grep -qx "${v}_mean"; then
                    sel_obs_list+=("$v")
                    sel_clim_list+=("${v}_mean")
                    chname_list+=("${v}_mean,${v}")
                fi
            done

            if [ "${#sel_obs_list[@]}" -gt 0 ]; then
                sel_obs=$(IFS=,; echo "${sel_obs_list[*]}")
                sel_clim=$(IFS=,; echo "${sel_clim_list[*]}")
                chname_arg=$(IFS=,; echo "${chname_list[*]}")

                clim_ntime=$(cdo -s ntime "$CLIMO_LOCAL" 2>/dev/null | tr -d ' ')
                if [ "$clim_ntime" = "12" ]; then
                    cdo_op="ymonsub"
                else
                    cdo_op="sub"
                fi

                if [ -n "$chname_arg" ]; then
                    cdo_cmd=(cdo -s -O "$cdo_op" -selname,"${sel_obs}" "$dst_obs_file" -chname,"${chname_arg}" -selname,"${sel_clim}" "$CLIMO_LOCAL" "$out_anom")
                else
                    cdo_cmd=(cdo -s -O "$cdo_op" -selname,"${sel_obs}" "$dst_obs_file" -selname,"${sel_clim}" "$CLIMO_LOCAL" "$out_anom")
                fi

                if "${cdo_cmd[@]}"; then
                    echo "SUCCESS: Created ${out_anom} using cdo ${cdo_op} (vars: ${sel_obs} <- ${sel_clim})"
                else
                    echo "WARNING: cdo ${cdo_op} failed for ${out_anom} (check grid/time alignment between ${dst_obs_file} and ${CLIMO_LOCAL})."
                fi
            else
                echo "WARNING: No matching variable names between ${dst_obs_file} (${obs_vars//$'\n'/ }) and ${CLIMO_LOCAL} (${clim_vars//$'\n'/ }). Skipping anomaly."
            fi
        fi
    done

    if [ "$found" -eq 0 ]; then
        echo "WARNING: No observation file found for VDATE=${VDATE} in $src_dir"
    fi
done

echo "END: $(basename ${BASH_SOURCE[0]})"
