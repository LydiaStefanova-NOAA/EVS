#PBS -N jevs_prep_seasonal_sfs
#PBS -j oe
#PBS -S /bin/bash
#PBS -q "dev"
#PBS -A VERF-DEV
#PBS -l walltime=00:15:00
#PBS -l place=shared,select=1:ncpus=1:mem=20GB
#PBS -l debug=true

#set -x #lbs temporarily commented out

####################################################################
# STANDARD PREAMBLE
####################################################################
export model=evs
cd $PBS_O_WORKDIR
export HOMEevs=/lfs/h2/emc/vpppg/noscrub/$USER/EVS

####################################################################
# Specify step, component, modelname, verif_type
####################################################################
export STEP=prep
export COMPONENT=seasonal
export RUN=atmos
export MODELNAME=sfs_b2
export PREP_TYPE=sfs

######################################################################
# Set job name based on step, component, modelname, verif_type
######################################################################
export job=${PBS_JOBNAME:-jevs_${STEP}_${COMPONENT}_${PREP_TYPE}}
export jobid=$job.${PBS_JOBID:-$$}

######################################################################
# Source standard scripts, load modules
######################################################################
source $HOMEevs/versions/run.ver
module reset
module load prod_envir/${prod_envir_ver}
source $HOMEevs/dev/modulefiles/seasonal/seasonal_prep.sh
evs_ver_2d=$(echo $evs_ver | cut -d'.' -f1-2)

######################################################################
# Export environment variables to pass on to JEVS_${STEP^^}_${COMPONENT^^}
######################################################################
export envir=prod
export KEEPDATA=NO
export SITE=$(cat /etc/cluster_name)
export SENDMAIL=YES

export DATAROOT=/lfs/h2/emc/stmp/$USER/evs_test/$envir/tmp
export TMPDIR=$DATAROOT

export USER=$USER
export ACCOUNT=VERF-DEV
export QUEUE=dev
export QUEUESHARED=dev_shared
export QUEUESERV=dev_transfer
export PARTITION_BATCH=
export nproc=1
export vhr=00
export NET=evs

########################################################################
# Paths required for this task
########################################################################
export COMOUT=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/${evs_ver_2d}/$STEP/$COMPONENT/$RUN
export FIXevs=${FIXevs:-$HOMEevs/fix}

###### Since the incoming data is currently not on dcom, point to my personal directory ####################
# RESOLVE DETAILS LATER
###################################################################################################
export SFS_SRC_ROOT="/lfs/h2/emc/vpppg/noscrub/lydia.b.stefanova/sfs-ver-dev/SFS_VERIF_DATA/forecasts/${MODELNAME:-sfs_b2}"
export SFS_LEAD_MONTHLY_CLIMO_DIR="${FIXevs}/climos/seasonal/${MODELNAME}"

################ If a seasonal config file, uncomment this #############################################
# export config_inst=$HOMEevs/parm/evs_config/${COMPONENT}/config.evs.${STEP}.${COMPONENT}.${PREP_TYPE}.conf

source $HOMEevs/dev/drivers/set_MAILTO.sh

# Call executable job script
echo calling $HOMEevs/jobs/JEVS_${STEP^^}_${COMPONENT^^}
$HOMEevs/jobs/JEVS_${STEP^^}_${COMPONENT^^}

######################################################################
# Purpose: This job and task scripts work together to retrieve the
#          SFS ensemble forecast files for seasonal prep and
#          copy them into the prep directory.
######################################################################
