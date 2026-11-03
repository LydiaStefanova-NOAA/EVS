#PBS -N jevs_prep_seasonal_sfs
#PBS -j oe
#PBS -S /bin/bash
#PBS -q "dev"
#PBS -A VERF-DEV
#PBS -l walltime=00:15:00
#PBS -l place=shared,select=1:ncpus=1:mem=20GB
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
export job=${PBS_JOBNAME:-jevs_prep_seasonal_sfs}
export jobid=$job.${PBS_JOBID:-$$}
export TMPDIR=$DATAROOT
export SITE=$(cat /etc/cluster_name)
export KEEPDATA=NO
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
export MODELNAME=sfs
export PREP_TYPE=sfs

#### Below are things to check with Mallory - key words, config

# Origin directory with the SFS-related data
export SFS_SRC_ROOT=${SFS_SRC_ROOT:-"/lfs/h2/emc/vpppg/noscrub/lydia.b.stefanova/sfs-ver-dev/SFS_VERIF_DATA/forecasts"}

# Origin directory with the Fix/climo roots for lead-dependent forecast climatology
# export FIXevs=${FIXevs:-$HOMEevs/fix}
export FIXevs=${FIXevs:-$SFS_SRC_ROOT}
export SFS_LEAD_MONTHLY_CLIMO_DIR=${SFS_LEAD_MONTHLY_CLIMO_DIR:-$FIXevs/seasonal/sfs}

#  

export COMOUT=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/${evs_ver_2d}/$STEP/$COMPONENT/$RUN

# If you have a seasonal config file, uncomment this
#export config_inst=$HOMEevs/parm/evs_config/seasonal/config.evs.prep.seasonal.sfsinst.conf
#export config_inst=$HOMEevs/parm/evs_config/seasonal/config.evs.prep.seasonal.sfsacc.conf

source $HOMEevs/dev/drivers/set_MAILTO.sh

# Call executable job script
$HOMEevs/jobs/JEVS_PREP_SEASONAL

######################################################################
# Purpose: This job and task scripts work together to retrieve the
#          SFS ensemble forecast files for seasonal prep and
#          copy them into the prep directory.
######################################################################
