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

if [ -n "${PBS_O_WORKDIR:-}" ]; then
    cd "$PBS_O_WORKDIR"
fi

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
export OBSNAME="GHCNCAMS CMAP CORe"
export PREP_TYPE=obs

# Normalize externally supplied VDATE (accepts YYYYMM or YYYYMMDD; otherwise J-job derives from PDY)
if [ -n "${VDATE:-}" ]; then
    if [[ "$VDATE" =~ ^[0-9]{6}([0-9]{2})?$ ]]; then
        export VDATE="${VDATE:0:6}"
    else
        echo "ERROR: VDATE must be in YYYYMM or YYYYMMDD format (got: '${VDATE}')."
        exit 1
    fi
fi

# Source root for monthly observation files
export OBS_SRC_ROOT=${OBS_SRC_ROOT:-"/lfs/h2/emc/vpppg/noscrub/lydia.b.stefanova/sfs-ver-dev/SFS_VERIF_DATA/verifying_truths"}

# Fix/climo roots for monthly obs climatology
export FIXevs=${FIXevs:-$HOMEevs/fix}
export GHCNCAMS_CLIMO_DIR=${GHCNCAMS_CLIMO_DIR:-$FIXevs/climos/seasonal/GHCNCAMS}
export CMAP_CLIMO_DIR=${CMAP_CLIMO_DIR:-$FIXevs/climos/seasonal/CMAP}
export CORe_CLIMO_DIR=${CORe_CLIMO_DIR:-$FIXevs/climos/seasonal/CORe}
export OISSTv2_CLIMO_DIR=${OISSTv2_CLIMO_DIR:-$FIXevs/climos/seasonal/OISSTv2}

export COMOUT=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/${evs_ver_2d}/$STEP/$COMPONENT/$RUN

# Use shared config to specify scope
export MODELNAME=sfs_b2
export config=${config:-$HOMEevs/parm/evs_config/${COMPONENT}/config.evs.${COMPONENT}.${MODELNAME}}

source $HOMEevs/dev/drivers/set_MAILTO.sh

# Call executable job script
$HOMEevs/jobs/JEVS_PREP_SEASONAL

######################################################################
# Purpose: This job and task scripts work together to retrieve the
#          monthly observation datasets for seasonal prep and
#          copy them into the prep directory.
######################################################################
