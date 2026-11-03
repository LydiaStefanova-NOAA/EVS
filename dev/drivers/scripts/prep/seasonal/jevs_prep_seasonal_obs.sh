#PBS -N jevs_prep_seasonal_obs
#PBS -j oe
#PBS -S /bin/bash
#PBS -q "dev"
#PBS -A VERF-DEV
#PBS -l walltime=00:10:00
#PBS -l place=shared,select=1:ncpus=1:mem=5GB
#PBS -l debug=true

#set -x

export model=evs

cd $PBS_O_WORKDIR

export HOMEevs=/lfs/h2/emc/vpppg/noscrub/$USER/EVS

source $HOMEevs/versions/run.ver
module reset
module load prod_envir/${prod_envir_ver}
source $HOMEevs/dev/modulefiles/seasonal/seasonal_prep.sh

evs_ver_2d=$(echo $evs_ver | cut -d'.' -f1-2)

export envir=prod
export DATAROOT=/lfs/h2/emc/stmp/$USER/evs_test/$envir/tmp
export job=${PBS_JOBNAME:-jevs_prep_seasonal_obs}
export jobid=$job.${PBS_JOBID:-$$}
export TMPDIR=$DATAROOT
export SITE=$(cat /etc/cluster_name)
export KEEPDATA=YES
export SENDMAIL=YES

export USER=$USER
export ACCOUNT=VERF-DEV
export QUEUE=dev
export QUEUESHARED=dev_shared
export QUEUESERV=dev_transfer
export PARTITION_BATCH=
export nproc=1
export vhr=00
export NET=evs
export STEP=prep
export COMPONENT=seasonal
export RUN=atmos
export OBSNAME="GHCN CMAP CORE"
export PREP_TYPE=obs

# This is where you will pass the source roots for the observation files
export OBS_SRC_ROOT=${OBS_SRC_ROOT:-"/lfs/h2/emc/vpppg/noscrub/lydia.b.stefanova/sfs-ver-dev/SFS_VERIF_DATA/verifying_truths"}

# FUTURE Fix/climo roots for monthly obs climatology
#export FIXevs=${FIXevs:-$HOMEevs/fix}
#export GHCN_CAMS_CLIMO_DIR=${GHCN_CAMS_CLIMO_DIR:-$FIXevs/seasonal/GHCN}
#export CMAP_CLIMO_DIR=${CMAP_CLIMO_DIR:-$FIXevs/seasonal/CMAP}
#export CORE_CLIMO_DIR=${CORE_CLIMO_DIR:-$FIXevs/seasonal/CORE}
#export OISST_CLIMO_DIR=${OISST_CLIMO_DIR:-$FIXevs/seasonal/OISST}

# TEMPORARY Fix/climo roots for monthly obs climatology
export FIXevs=${FIXevs:-$OBS_SRC_ROOT}
export GHCN_CAMS_CLIMO_DIR=${GHCN_CAMS_CLIMO_DIR:-$FIXevs/GHCNCAMS/}
export CMAP_CLIMO_DIR=${CMAP_CLIMO_DIR:-$FIXevs/CMAP/}
export CORE_CLIMO_DIR=${CORE_CLIMO_DIR:-$FIXevs/CORE/}
export OISST_CLIMO_DIR=${OISST_CLIMO_DIR:-$FIXevs/OISST/}




export COMOUT=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/${evs_ver_2d}/$STEP/$COMPONENT/$RUN

# Once I have a seasonal config file, uncomment this
# export config=$HOMEevs/parm/evs_config/seasonal/config.evs.seasonal.obs.prep

source $HOMEevs/dev/drivers/set_MAILTO.sh

# Call executable job script
$HOMEevs/jobs/JEVS_PREP_SEASONAL

######################################################################
# Purpose: This job and task scripts work together to retrieve the
#          monthly observation datasets for seasonal prep and
#          copy them into the prep directory.
######################################################################
