#!/bin/bash

#set -x
echo "INITMONTH=$INITMONTH"
echo "INITYEAR=$INITYEAR"

echo "BEGIN: $(basename ${BASH_SOURCE[0]})"

DATA=${DATA:-${DATAROOT:?}/${jobid:?}}
cd $DATA


# Inputs supplied by driver/job wrapper
OBS_SRC_ROOT=${OBS_SRC_ROOT:-""}
COMOUT=${COMOUT:-""}
INITMONTH=${INITMONTH:-""}
INITYEAR=${INITYEAR:-""}

echo "COMOUT: $COMOUT INITMONTH: $INITMONTH INITYEAR: $INITYEAR OBS_SRC_ROOT: $OBS_SRC_ROOT"

if [ -z "$OBS_SRC_ROOT" ] || [ -z "$COMOUT" ] || [ -z "$INITMONTH" ] || [ -z "$INITYEAR" ] ; then
    echo "ERROR: OBS_SRC_ROOT, COMOUT, INITMONTH, and INITYEAR must be set."
    exit 1
#    err_exit "OBS_SRC_ROOT, COMOUT, INITMONTH, and INITYEAR must be set."
fi

# Base output directories for monthly obs
BASE_OUT=${COMOUT}/${RUN}.${INITYEAR}${INITMONTH}
mkdir -p $BASE_OUT/obs
mkdir -p $BASE_OUT/fcst


echo "DEBUG OBS_SRC_ROOT=$OBS_SRC_ROOT"
echo "DEBUG BASE_OUT=$BASE_OUT"
echo "DEBUG COMOUT=$COMOUT"
echo "DEBUG INITMONTH=$INITMONTH"
echo "DEBUG INITYEAR=$INITYEAR"
echo "DEBUG RUN=$RUN"
echo "DEBUG DATA=$DATA"

# Create per-source output directories
for obs in GHCNCAMS CMAP CORE ; do
    mkdir -p ${BASE_OUT}/obs/${obs}
done

# Copy each obs source into the expected EVS prep layout
#
# -------------------------------------------------------------
# 1. GHCNCAMS and CMAP (Path: <OBS>/monthly/)
# -------------------------------------------------------------
for obs in GHCNCAMS CMAP; do
    src_dir="${OBS_SRC_ROOT}/${obs}/monthly"
    dest_dir="${BASE_OUT}/obs/${obs}"

    found=0
    for file in "${src_dir}"/*"${INITYEAR}${INITMONTH}"*.nc; do
        if [ -f "$file" ]; then
            mkdir -p "$dest_dir"
            echo "Copying $(basename "$file") -> $dest_dir"
            cp "$file" "$dest_dir/"
            found=1
        fi
    done

    if [ "$found" -eq 0 ]; then
        echo "WARNING: no file found for ${INITYEAR}${INITMONTH} in $src_dir"
    fi
done

# -------------------------------------------------------------
# 2. CORE (Path: CORE/<VARIABLE>/monthly/)
# -------------------------------------------------------------
for var_path in "${OBS_SRC_ROOT}/CORE"/*/; do
    var_name="$(basename "$var_path")"
    src_dir="${var_path}monthly"
    dest_dir="${BASE_OUT}/obs/CORE/${var_name}"

    found=0
    for file in "${src_dir}"/*"${INITYEAR}${INITMONTH}"*.nc; do
        if [ -f "$file" ]; then
            mkdir -p "$dest_dir"
            echo "Copying CORE/${var_name}/$(basename "$file") -> $dest_dir"
            cp "$file" "$dest_dir/"
            found=1
        fi
    done

    if [ "$found" -eq 0 ]; then
        echo "WARNING: no file found for ${INITYEAR}${INITMONTH} in $src_dir"
    fi
done


# Optional: validate monthly climatology files are present
# These will be used by later seasonal stats jobs
for climo in \
    "${GHCN_CAMS_CLIMO_DIR}" \
    "${CMAP_CLIMO_DIR}" \
    "${CORE_CLIMO_DIR}" \
    "${OISST_CLIMO_DIR}"
do
    if [ -d "$climo/climatology" ]; then
        echo "Found climatology directory: $climo/climatology"
    else
        echo "WARNING: climatology directory not found: $climo/climatology"
    fi
done

echo "END: $(basename ${BASH_SOURCE[0]})"
