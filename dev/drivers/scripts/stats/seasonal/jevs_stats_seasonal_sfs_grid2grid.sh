#PBS -N jevs_stats_seasonal_sfs_grid2grid
#PBS -j oe
#PBS -S /bin/bash
#PBS -q "dev"
#PBS -A VERF-DEV
#PBS -l walltime=00:20:00
#PBS -l place=vscatter:shared,select=1:ncpus=66:ompthreads=1:mem=70GB
#PBS -l debug=true

#set -x

export model=evs

cd $PBS_O_WORKDIR

export HOMEevs=/lfs/h2/emc/vpppg/noscrub/$USER/EVS

export job=${PBS_JOBNAME:-jevs_stats_seasonal_sfs_grid2grid}
export jobid=$job.${PBS_JOBID:-$$}

source $HOMEevs/versions/run.ver
module reset
module load prod_envir/${prod_envir_ver}
source $HOMEevs/dev/modulefiles/seasonal/seasonal_stats.sh   

evs_ver_2d=$(echo $evs_ver | cut -d'.' -f1-2)


export USER=$USER
export envir=prod
export KEEPDATA=NO
export DATAROOT=/lfs/h2/emc/stmp/$USER/evs_test/$envir/tmp
export ACCOUNT=VERF-DEV
export QUEUE=dev
export QUEUESHARED=dev_shared  # Question: where is this used in scripts
export QUEUESERV=dev_transfer  # Question: where is this used in scripts
export PARTITION_BATCH=
export nproc=66           # Note: Edit to reflect how many processes (matches how many jobs are created, and matches ncpus)
export USE_CFP=YES        # Note: ???
export vhr=00             # Note: placeholder, not really used, but has to be there
export NET=evs
export STEP=stats
export COMPONENT=seasonal # SEASONAL
export RUN=atmos
export MODELNAME=sfs         
export VERIF_CASE=grid2grid

export COMOUT=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/${evs_ver_2d}/$STEP/$COMPONENT
export COMIN=/lfs/h2/emc/vpppg/noscrub/$USER/$NET/${evs_ver_2d}/prep/$COMPONENT/$RUN

export config=$HOMEevs/parm/evs_config/seasonal/config.evs.seasonal.sfs.grid2grid.stats

# Call executable job script
$HOMEevs/jobs/JEVS_STATS_SEASONAL


######################################################################
# Purpose: The job and task scripts work together to generate the
#          seasonal verification grid-to-grid statistics for the SFS model
#          and create the stat files in the databases.
######################################################################
