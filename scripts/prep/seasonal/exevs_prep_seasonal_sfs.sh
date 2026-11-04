#!/bin/bash

#set -x
echo "INITYEAR=$INITYEAR"
echo "INITMONTH=$INITMONTH"
echo "SFS_SRC_ROOT=$SFS_SRC_ROOT"
echo "SFS_LEAD_MONTHLY_CLIMO_DIR=$SFS_LEAD_MONTHLY_CLIMO_DIR"
echo "MODELNAME=$MODELNAME"

echo "BEGIN: $(basename ${BASH_SOURCE[0]})"

DATA=${DATA:-${DATAROOT:?}/${jobid:?}}
mkdir -p "$DATA"
cd $DATA

# Inputs supplied by driver/job wrapper
SFS_SRC_ROOT=${SFS_SRC_ROOT:-""}
INITYEAR=${INITYEAR:-""}
INITMONTH=${INITMONTH:-""}
COMOUT=${COMOUT:-""}
SFS_LEAD_MONTHLY_CLIMO_DIR=${SFS_LEAD_MONTHLY_CLIMO_DIR:-""}

echo "COMOUT: $COMOUT INITMONTH: $INITMONTH SFS_SRC_ROOT: $SFS_SRC_ROOT"

if [ -z "$SFS_SRC_ROOT" ] || [ -z "$COMOUT" ] || [ -z "$INITMONTH" ] || [ -z "$INITYEAR" ] ; then
    err_exit "ERROR: SFS_SRC_ROOT, COMOUT, and INITMONTH must be set."
fi

# Base input directories for monthly forecast
BASE_IN=${SFS_SRC_ROOT}/init_${INITMONTH}/${INITYEAR}

# Base output directories for monthly forecast
BASE_OUT=${COMOUT}/${RUN}.${INITYEAR}${INITMONTH}/$MODELNAME
mkdir -p $BASE_OUT

# Copy forecast data into the seasonal EVS prep layout
if [ -d "$BASE_IN" ]; then
    echo "Copying SFS forecast files from $BASE_IN to ${BASE_OUT}"
    cp -r "${BASE_IN}/." "${BASE_OUT}/"
else
    echo "WARNING: SFS source directory not found: ${BASE_IN}"
fi

# Validate lead-dependent monthly climatology directory
if [ -d "${SFS_LEAD_MONTHLY_CLIMO_DIR}" ]; then
    echo "Found SFS lead-dependent monthly climatology directory: ${SFS_LEAD_MONTHLY_CLIMO_DIR}"
else
    echo "WARNING: SFS lead-dependent monthly climatology directory not found: ${SFS_LEAD_MONTHLY_CLIMO_DIR}"
fi

echo "DEBUG SFS_SRC_ROOT=$SFS_SRC_ROOT"
echo "DEBUG BASE_OUT=$BASE_OUT"
echo "DEBUG COMOUT=$COMOUT"
echo "DEBUG INITMONTH=$INITYEAR"
echo "DEBUG INITMONTH=$INITMONTH"
echo "DEBUG RUN=$RUN"
echo "DEBUG DATA=$DATA"

# ==============================================================================
# Calculate Ensemble Mean and Stdev (Explicit Paths, No Wildcards in Loop)
# ==============================================================================
ENS_DIR="${BASE_OUT}/ens"
mkdir -p "$ENS_DIR"

# Scratch directory for parallel NetCDF conversion
TMP_NC_DIR="${DATA}/tmp_ens_nc_$$"
mkdir -p "$TMP_NC_DIR"

# SFS forecasts have 31 members
NUM_MEMBERS=31

# Get the exact filenames from mem000 to determine valid leads without date math
if [ -d "${BASE_OUT}/mem000" ]; then
    # Grab the literal filenames for both instantaneous and accumulated products
    EXACT_FILENAMES=$(cd "${BASE_OUT}/mem000" && ls inst.monthly.*.grb2 acc.monthly.*.grb2 2>/dev/null)

    for EXACT_FILENAME in $EXACT_FILENAMES; do
        echo "Processing ensemble stats for ${EXACT_FILENAME}..."
        
        stem="${EXACT_FILENAME%.grb2}"
        
        # 1. Build the list of member files explicitly
        MEMBER_FILES=()
        for (( i=0; i<NUM_MEMBERS; i++ )); do
            mem_dir=$(printf "mem%03d" "$i")
            mem_file="${BASE_OUT}/${mem_dir}/${EXACT_FILENAME}"
            
            if [ -f "${mem_file}" ]; then
                MEMBER_FILES+=("${mem_file}")
            else
                echo "WARNING: Missing expected file: ${mem_file}"
            fi
        done
        
        # 2. Halt processing for this specific lead if any member is missing
        if [ "${#MEMBER_FILES[@]}" -eq "${NUM_MEMBERS}" ]; then
            tmp_ncs=()
            
            # Parallel conversion to NetCDF in RAM/scratch to bypass CDO GRIB2 limitations
            for mem_file in "${MEMBER_FILES[@]}"; do
                mname=$(basename "$(dirname "$mem_file")") # e.g., mem000
                tmp_nc="${TMP_NC_DIR}/${mname}_${EXACT_FILENAME}.nc"
                
                wgrib2 "$mem_file" -netcdf "$tmp_nc" >/dev/null 2>&1 &
                tmp_ncs+=("$tmp_nc")
            done
            wait # Wait for all 31 wgrib2 background jobs to finish
            
            out_mean="${ENS_DIR}/${stem}.ensmean.nc"
            out_std="${ENS_DIR}/${stem}.ensstd.nc"
            
            # 3. CDO computes ensemble mean and standard deviation
            cdo -s -O ensmean "${tmp_ncs[@]}" "${out_mean}"
            cdo -s -O ensstd  "${tmp_ncs[@]}" "${out_std}"
            
            # 4. Clean up temporary NetCDF slice files
            rm -f "${tmp_ncs[@]}"
            
            echo "SUCCESS: Created ${out_mean} and ${out_std}"
        else
            echo "ERROR: Found ${#MEMBER_FILES[@]}/${NUM_MEMBERS} members for ${EXACT_FILENAME}. Skipping to prevent skewed statistics."
        fi
    done
else
    echo "WARNING: ${BASE_OUT}/mem000 not found. Cannot determine file list for ensemble statistics."
fi

# Clean up temporary NetCDF directory entirely
rm -rf "$TMP_NC_DIR"
