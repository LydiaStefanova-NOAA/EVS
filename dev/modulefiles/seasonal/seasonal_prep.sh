#!/bin/bash
# modulefile-style environment setup for EVS seasonal prep step
# sourced by driver scripts before running jobs/JEVS_PREP_SEASONAL

set -euo pipefail
set -x

# If available, these versions should be supplied by versions/run.ver.
# Keep defaults so this template is still usable in dev/test.
: "${prod_envir_ver:=2.0.0}"
: "${met_ver:=12.0.1}"
: "${metplus_ver:=6.0.0}"

# Some platforms do not support 'module reset' in non-login shells;
# keep it, but fail-soft if needed.
module reset || true

# Core environment expected by existing EVS components
module load prod_envir/"${prod_envir_ver}" || true
module load met/"${met_ver}" || true
module load metplus/"${metplus_ver}" || true

# Optional tools commonly used in prep workflows
module load nco || true
module load cdo || true
module load wgrib2 || true
module load python || true

module list || true

# EVS component identity
export NET="${NET:-evs}"
export STEP="${STEP:-prep}"
export COMPONENT="${COMPONENT:-seasonal}"

# Driver should set RUN=det|ens; set a safe default.
export RUN="${RUN:-det}"

# Repo roots (HOMEevs usually exported by driver script)
: "${HOMEevs:?HOMEevs must be set before sourcing seasonal_prep.sh}"

# Component paths
export PARMseasonal="${HOMEevs}/parm/evs_config/seasonal"
export USHseasonal="${HOMEevs}/ush/seasonal"
export SCRIPTseasonal="${HOMEevs}/scripts/seasonal/prep"

# Runtime/config convenience variables
export EVS_CONFIG_DIR="${EVS_CONFIG_DIR:-${PARMseasonal}}"
export EVS_COMMON_CONF="${EVS_COMMON_CONF:-${PARMseasonal}/seasonal_common.conf}"
export EVS_RUN_CONF="${EVS_RUN_CONF:-${PARMseasonal}/seasonal_${RUN}.conf}"

# Typical output paths; driver can override
export DATAROOT="${DATAROOT:-/tmp/${USER}/evs/${NET}/tmp}"
export COMROOT="${COMROOT:-/tmp/${USER}/evs/com}"
export COMIN="${COMIN:-${COMROOT}/in/${NET}}"
export COMOUT="${COMOUT:-${COMROOT}/out/${NET}/${STEP}/${COMPONENT}/${RUN}}"

mkdir -p "${DATAROOT}" "${COMOUT}"

echo "Loaded seasonal prep environment:"
echo "  NET=${NET}"
echo "  STEP=${STEP}"
echo "  COMPONENT=${COMPONENT}"
echo "  RUN=${RUN}"
echo "  EVS_COMMON_CONF=${EVS_COMMON_CONF}"
echo "  EVS_RUN_CONF=${EVS_RUN_CONF}"
