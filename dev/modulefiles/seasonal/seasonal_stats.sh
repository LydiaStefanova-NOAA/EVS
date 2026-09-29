#!/bin/bash
# modulefile-style environment setup for EVS seasonal stats step

set -euo pipefail
set -x

: "${prod_envir_ver:=2.0.0}"
: "${met_ver:=12.0.1}"
: "${metplus_ver:=6.0.0}"

module reset || true
module load prod_envir/"${prod_envir_ver}" || true
module load met/"${met_ver}" || true
module load metplus/"${metplus_ver}" || true
module load python || true

module list || true

export NET="${NET:-evs}"
export STEP="${STEP:-stats}"
export COMPONENT="${COMPONENT:-seasonal}"
export RUN="${RUN:-det}"

: "${HOMEevs:?HOMEevs must be set before sourcing seasonal_stats.sh}"

export PARMseasonal="${HOMEevs}/parm/evs_config/seasonal"
export USHseasonal="${HOMEevs}/ush/seasonal"
export SCRIPTseasonal="${HOMEevs}/scripts/seasonal/stats"

export EVS_CONFIG_DIR="${EVS_CONFIG_DIR:-${PARMseasonal}}"
export EVS_COMMON_CONF="${EVS_COMMON_CONF:-${PARMseasonal}/seasonal_common.conf}"
export EVS_RUN_CONF="${EVS_RUN_CONF:-${PARMseasonal}/seasonal_${RUN}.conf}"

export DATAROOT="${DATAROOT:-/tmp/${USER}/evs/${NET}/tmp}"
export COMROOT="${COMROOT:-/tmp/${USER}/evs/com}"
export COMIN="${COMIN:-${COMROOT}/in/${NET}}"
export COMOUT="${COMOUT:-${COMROOT}/out/${NET}/${STEP}/${COMPONENT}/${RUN}}"

mkdir -p "${DATAROOT}" "${COMOUT}"

echo "Loaded seasonal stats environment:"
echo "  NET=${NET}"
echo "  STEP=${STEP}"
echo "  COMPONENT=${COMPONENT}"
echo "  RUN=${RUN}"
echo "  EVS_COMMON_CONF=${EVS_COMMON_CONF}"
echo "  EVS_RUN_CONF=${EVS_RUN_CONF}"
