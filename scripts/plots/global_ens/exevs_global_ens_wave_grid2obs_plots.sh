#!/bin/bash
################################################################################
# Name of Script: exevs_global_ens_wave_grid2obs_plots.sh                       
# Deanna Spindler / Deanna.Spindler@noaa.gov                                    
# Purpose of Script: Run the grid2obs plots for any global wave model           
#                    (deterministic and ensemble: GEFS-Wave, GFS-Wave, NWPS)    
#                                                                               
# Usage:                                                                        
#  Parameters: None                                                             
#  Input files:                                                                 
#     evs.stats.gefs.wave.grid2obs.vYYYYMMDD.stat                               
#  Output files:                                                                
#     evs.plots.global_ens.wave.grid2obs.last31days.vYYYYMMDD.tar               
#     evs.plots.global_ens.wave.grid2obs.last90days.vYYYYMMDD.tar               
#  User controllable options: None                                              
################################################################################

set -x 

#############################
## grid2obs wave model plots 
#############################

cd $DATA
echo "Starting grid2obs_plots for ${MODELNAME}_${RUN}"

echo ' '
echo ' ******************************************'
echo " *** ${MODELNAME}-${RUN} grid2obs plots ***"
echo ' ******************************************'
echo ' '
echo "Starting at : `date`"
echo '-------------'
echo ' '

############################
# get the model .stat files 
############################
echo ' '
echo 'Copying *.stat files :'
echo '-----------------------------'

mkdir -p ${DATA}/stats

plot_start_date=${PDYm90}
plot_end_date=${VDATE}

theDate=${plot_start_date}
while (( ${theDate} <= ${plot_end_date} )); do
  EVSINstats=${COMIN}/stats/${COMPONENT}/${MODELNAME}.${theDate}
  if [[ -s ${EVSINstats}/evs.stats.${MODELNAME}.${RUN}.${VERIF_CASE}.v${theDate}.stat ]]; then
      cp -v ${EVSINstats}/evs.stats.${MODELNAME}.${RUN}.${VERIF_CASE}.v${theDate}.stat ${DATA}/stats/.
  else
      echo "WARNING: DOES NOT EXIST ${EVSINstats}/evs.stats.${MODELNAME}.${RUN}.${VERIF_CASE}.v${theDate}.stat"
  fi
  theDate=$($NDATE +24 ${theDate}${vhr} | cut -c 1-8)
done

####################
# quick error check 
####################
nc=`ls ${DATA}/stats/evs*stat | wc -l | awk '{print $1}'`
echo " Found ${nc} ${DATA}/stats/evs*stat file for ${VDATE} "
if [ "${nc}" != '0' ]
then
  echo "Successfully copied the GEFS-Wave *.stat file for ${VDATE}"
else
  echo ' '
  echo '**************************************** '
  echo '*** ERROR : NO GEFS-Wave *.stat FILE *** '
  echo "             for ${VDATE} "
  echo '**************************************** '
  echo ' '
  err_exit "Did not copy the GEFS-Wave *.stat file for ${VDATE}"
fi

#################################
# Make the command files for cfp 
#################################

## time_series
${USHevs}/${COMPONENT}/evs_wave_timeseries.sh
export err=$?; err_chk

## lead_averages
${USHevs}/${COMPONENT}/evs_wave_leadaverages.sh
export err=$?; err_chk

chmod 775 plot_all_${MODELNAME}_${RUN}_g2o_plots.sh

###########################################
# Run the command files for the PAST31DAYS 
###########################################
if [ ${run_mpi} = 'yes' ] ; then
  mpiexec -np 36 --cpu-bind verbose,core --depth=3 cfp plot_all_${MODELNAME}_${RUN}_g2o_plots.sh
  export err=$?; err_chk
else
  echo "not running mpiexec"
  plot_all_${MODELNAME}_${RUN}_g2o_plots.sh
  export err=$?; err_chk
fi

###########################################
# Cat the plotting log files
###########################################
log_dir=$DATA
log_file_count=$(find $log_dir/*.out -type f |wc -l)
if [[ $log_file_count -ne 0 ]]; then
    for log_file in $log_dir/*.out; do
        echo "Start: $log_file"
        cat $log_file
        echo "End: $log_file"
    done
fi

#######################
# Gather all the files 
#######################
periods='PAST31DAYS PAST90DAYS'
if [ $gather = yes ] ; then
  echo "copying all images into one directory"
  for FILE in ${DATA}/wave/*png ; do
      if [ -s $FILE ]; then
          cp -v $FILE ${DATA}/sfcshp/.  ## lead_average plots
      fi
  done
  nc=$(ls ${DATA}/sfcshp/*png | wc -l | awk '{print $1}')
  echo "copied $nc plots"
  for period in ${periods} ; do
    period_lower=$(echo ${period,,})
    if [ ${period} = 'PAST31DAYS' ] ; then
      period_out='last31days'
    elif [ ${period} = 'PAST90DAYS' ] ; then
      period_out='last90days'
    fi
    # check to see if the plots are there
    nc=$(ls ${DATA}/sfcshp/*${period_lower}*.png | wc -l | awk '{print $1}')
    echo " Found ${nc} ${DATA}/plots/*${period_lower}*.png files for ${VDATE} "
    if [ "${nc}" != '0' ]
    then
      echo "Found ${nc} ${period_lower} plots for ${VDATE}"
    else
      echo ' '
      echo '**************************************** '
      echo '*** ERROR : NO ${period} PLOTS  *** '
      echo "    found for ${VDATE} "
      echo '**************************************** '
      echo ' '
      err_exit "Did not find any ${period} plots for ${VDATE}"
    fi
    
    # tar and copy them to the final destination
    if [ "${nc}" > '0' ] ; then
      cd ${DATA}/sfcshp
      tar -cvf evs.${STEP}.${COMPONENT}.${RUN}.${VERIF_CASE}.${period_out}.v${VDATE}.tar evs.*${period_lower}*.png
    fi
    if [ $SENDCOM="YES" ] ; then
        if [ -s evs.${STEP}.${COMPONENT}.${RUN}.${VERIF_CASE}.${period_out}.v${VDATE}.tar ]; then
            cp -v evs.${STEP}.${COMPONENT}.${RUN}.${VERIF_CASE}.${period_out}.v${VDATE}.tar ${COMOUTplots}/.
        fi
    fi
    if [ $SENDDBN = YES ]; then
      $DBNROOT/bin/dbn_alert MODEL EVS_RZDM $job ${COMOUTplots}/evs.${STEP}.${COMPONENT}.${RUN}.${VERIF_CASE}.${period_out}.v${VDATE}.tar
    fi
  done
else  
  echo "not copying the plots"
fi

# --------------------------------------------------------------------------- #
# Ending output                                                                

echo ' '
echo "Ending at : `date`"
echo ' '
echo " *** End of ${MODELNAME}-${RUN} grid2obs stat *** "
echo ' '

# End of GEFS-Wave grid2obs plots script ------------------------------------- #
