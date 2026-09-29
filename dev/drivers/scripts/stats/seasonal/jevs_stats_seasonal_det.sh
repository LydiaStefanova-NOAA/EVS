#!/bin/bash
#PBS -N jevs_stats_seasonal_det
#PBS -j oe
#PBS -S /bin/bash
#PBS -q dev
#PBS -A VERF-DEV
#PBS -l walltime=00:30:00
#PBS -l place=shared,select=1:ncpus=1:mem=50GB
#PBS -l debug=true

set -x

cd "${PBS_O_WORKDIR:-$(pwd)}"

export model=evs
export HOMEevs="${HOMEevs:-/lfs/h2/emc/vpppg/noscrub/${USER}/EVS}"

export SENDCOM=YES
export SENDMAIL=YES
export KEEPDATA=NO
export job="${PBS_JOBNAME:-jevs_stats_seasonal_det}"
export jobid="${job}.${PBS_JOBID:-$$}"
export SITE="$(cat /etc/cluster_name 2>/dev/null || echo unknown)"
export vhr="${vhr:-00}"

source "${HOMEevs}/versions/run.ver" || true
module reset || true

source "${HOMEevs}/dev/modulefiles/seasonal/seasonal_stats.sh"

export envir="${envir:-prod}"
export NET="${NET:-evs}"
export STEP="${STEP:-stats}"
export COMPONENT="${COMPONENT:-seasonal}"
export RUN="${RUN:-det}"

export DATAROOT="${DATAROOT:-/lfs/h2/emc/stmp/${USER}/evs_test/${envir}/tmp}"
export TMPDIR="${TMPDIR:-${DATAROOT}}"

export COMIN="${COMIN:-/lfs/h2/emc/vpppg/noscrub/${USER}/${NET}/prod}"
export COMOUT="${COMOUT:-/lfs/h2/emc/vpppg/noscrub/${USER}/${NET}/prod/${STEP}/${COMPONENT}/${RUN}}"

mkdir -p "${DATAROOT}" "${COMOUT}"

source "${HOMEevs}/dev/drivers/set_MAILTO.sh" || true

"${HOMEevs}/jobs/JEVS_STATS_SEASONAL"
