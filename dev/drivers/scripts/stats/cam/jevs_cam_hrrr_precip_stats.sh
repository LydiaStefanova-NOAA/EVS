#PBS -S /bin/bash
#PBS -N jevs_cam_hrrr_precip_stats
#PBS -j oe
#PBS -S /bin/bash
#PBS -q dev
#PBS -A VERF-DEV
#PBS -l walltime=02:00:00
#PBS -l place=vscatter:exclhost,select=1:ncpus=128:ompthreads=1:mem=256GB
#PBS -l debug=true

set -x
export model=evs
export machine=WCOSS2

# ECF Settings
export SENDMAIL=YES
export SENDECF=YES
export SENDCOM=YES
export KEEPDATA=YES
export SENDDBN=NO
export SENDDBN_NTC=
export job=${PBS_JOBNAME:-jevs_cam_hrrr_precip_stats}
export jobid=$job.${PBS_JOBID:-$$}
export SITE=$(cat /etc/cluster_name)
export USE_CFP=YES
export nproc=128

# General Verification Settings
export NET="evs"
export STEP="stats"
export COMPONENT="cam"
export RUN="atmos"
export VERIF_CASE="precip"
export MODELNAME="hrrr"

# EVS Settings
export HOMEevs="/lfs/h2/emc/vpppg/noscrub/$USER/EVS"
export HOMEevs=${HOMEevs:-${PACKAGEROOT}/evs.${evs_ver}}
export config=$HOMEevs/parm/evs_config/cam/config.evs.prod.${STEP}.${COMPONENT}.${RUN}.${VERIF_CASE}.${MODELNAME}

# Load Modules
source $HOMEevs/versions/run.ver
module reset
module load prod_envir/${prod_envir_ver}
source $HOMEevs/dev/modulefiles/$COMPONENT/${COMPONENT}_${STEP}.sh
evs_ver_2d=$(echo $evs_ver | cut -d'.' -f1-2)

# Developer Settings
export envir=prod
export DATAROOT=/lfs/h2/emc/stmp/$USER/evs_test/$envir/tmp
export COMIN=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/$evs_ver_2d
export COMOUT=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/$evs_ver_2d/$STEP/$COMPONENT
export vhr=${vhr:-${vhr}}
export MAILTO="andrew.benjamin@noaa.gov,marcel.caron@noaa.gov"

# Job Settings and Run
. ${HOMEevs}/jobs/JEVS_CAM_STATS
