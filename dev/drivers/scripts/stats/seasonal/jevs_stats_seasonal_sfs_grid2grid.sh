#PBS -N jevs_stats_seasonal_sfs_grid2grid
#PBS -j oe
#PBS -S /bin/bash
#PBS -q "dev"
#PBS -A VERF-DEV
#PBS -l walltime=00:20:00
#PBS -l place=vscatter:shared,select=1:ncpus=1:ompthreads=1:mem=70GB
#PBS -l debug=true

set -x  # lbs temporarily commented out

####################################################################
# STANDARD PREAMBLE
####################################################################
export model=evs
cd $PBS_O_WORKDIR
export HOMEevs=/lfs/h2/emc/vpppg/noscrub/$USER/EVS

#################################################################### 
# Specify run type, EVS step, component, verif_type, modelname
#################################################################### 
export RUN=atmos
export STEP=stats
export COMPONENT=seasonal 
export VERIF_TYPE=grid2grid
export MODELNAME=sfs_b2 

######################################################################
# Set job name based on step, component, modelname, verif_type
######################################################################
export job=${PBS_JOBNAME:-jevs_${STEP}_${COMPONENT}_${MODELNAME}_${VERIF_TYPE}}  
export jobid=$job.${PBS_JOBID:-$$}

######################################################################
# Source standard scripts, load modules
######################################################################
source $HOMEevs/versions/run.ver
module reset
module load prod_envir/${prod_envir_ver}
source $HOMEevs/dev/modulefiles/seasonal/seasonal_stats.sh   
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
export nproc=1           # Note: Edit to reflect how many processes (matches how many jobs are created, and matches ncpus)

export USE_CFP=YES        # Note: This is not there in the Prep script - is it necessary in all stat scripts 
export vhr=00             # Note: placeholder, not really used, but has to be there
export NET=evs

export COMIN=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/${evs_ver_2d}/prep/$COMPONENT/$RUN
export COMOUT=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/${evs_ver_2d}/$STEP/$COMPONENT

############################################################################
# Optional config
############################################################################
echo export config=$HOMEevs/parm/evs_config/${COMPONENT}/config.evs.${STEP}.${COMPONENT}.${MODELNAME}.${VERIF_TYPE}.stats

# Call executable job script
#
echo calling $HOMEevs/jobs/JEVS_${STEP^^}_${COMPONENT^^}
$HOMEevs/jobs/JEVS_${STEP^^}_${COMPONENT^^}

######################################################################
# Purpose: The job and task scripts work together to generate the
#          seasonal verification grid2grid statistics for the SFS model
#          and create the stat files in the databases.
######################################################################
