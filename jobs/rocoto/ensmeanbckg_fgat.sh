#!/bin/ksh -x
###############################################################
# Source FV3GFS workflow modules
. $HOMEgfs/ush/load_fv3gfs_modules.sh
status=$?
[[ $status -ne 0 ]] && exit $status

###############################################################
# Source relevant configs
configs="base anal"
for config in $configs; do
    . $EXPDIR/config.${config}
    status=$?
    [[ $status -ne 0 ]] && exit $status
done

# Source machine runtime environment
. $BASE_ENV/${machine}.env anal 
status=$?
[[ $status -ne 0 ]] && exit $status
###############################################################
#  Set environment.
export VERBOSE=${VERBOSE:-"YES"}
if [ $VERBOSE = "YES" ]; then
   echo $(date) EXECUTING $0 $* >&2
   set -x
fi

#  Directories.
pwd=$(pwd)
export NWPROD=${NWPROD:-$pwd}
export HOMEgfs=${HOMEgfs:-$NWPROD}
export HOMEjedi=${HOMEjedi:-$HOMEgfs/sorc/jedi.fd/}
export DATA=${DATA:-${DATAROOT}/ensmean.$$}
export COMIN=${COMIN:-$pwd}
export COMIN_OBS=${COMIN_OBS:-$COMIN}
export COMIN_GES=${COMIN_GES:-$COMIN}
export COMIN_GES_ENS=${COMIN_GES_ENS:-$COMIN_GES}
export COMIN_GES_OBS=${COMIN_GES_OBS:-$COMIN_GES}
export COMOUT=${COMOUT:-$COMIN}
export JEDIUSH=${JEDIUSH:-$HOMEgfs/ush/JEDI/}
#export MEANEXECDIR=${MEANEXECDIR:-/scratch1/BMC/gsd-fv3-dev/MAPP_2018/pagowski/exec_bo/}
export MEANEXECDIR=${MEANEXECDIR:-$HOMEgfs/exec/}

# Base variables
CDATE=${CDATE:-"2001010100"}
CDUMP=${CDUMP:-"gdas"}
GDUMP=${GDUMP:-"gdas"}
export CASE=${CASE:-"C96"}
export nlevs=${nlevs:-64}


# Derived base variables
ADATE=$($NDATE +$assim_freq $CDATE)
PDY=$(echo $CDATE | cut -c1-8)
cyc=$(echo $CDATE | cut -c9-10)
aPDY=$(echo $ADATE | cut -c1-8)
acyc=$(echo $ADATE | cut -c9-10)

ADATEm3=$($NDATE -${assim_freq_half} $ADATE)
ADATEp3=$($NDATE ${assim_freq_half} $ADATE)


# Utilities
export NCP=${NCP:-"/bin/cp"}
export NMV=${NMV:-"/bin/mv"}
export NLN=${NLN:-"/bin/ln -sf"}
export ERRSCRIPT=${ERRSCRIPT:-'eval [[ $err = 0 ]]'}

export analdir=${analdir-$ROTDIR/enkfgdas.${PDY}/${cyc}/}

mkdir -p $DATA && cd $DATA

# source modules
#source $HOMEgfs/sorc/gsi.fd/modulefiles/modulefile.ProdGSI.hera
source /apps/lmod/7.7.18/init/ksh
#module use -a /scratch1/NCEPDEV/da/Daniel.Holdaway/opt/modulefiles
#module load apps/jedi/intel-19.0.5.281
#module use -a /scratch1/NCEPDEV/jcsda/Ryan.Honeyager/jedi/modules/
#module load jedi-stack/intel-impi-18.0.5
#module list

. ${HOMEjedi}/jedi_module_base.hera
module load nco ncview ncl netcdf
module list
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${HOMEjedi}/lib/" 

# link executables to working directory
$NLN $MEANEXECDIR/calc_ensmean_fv3.x ./calc_ensmean_fv3.x

cat > ensmean.nml <<EOF
&ensmean_nml
varnames =  'sphum','bc1','bc2','oc1','oc2','sulf','dust1','dust2','dust3','dust4','dust5','seas1','seas2','seas3','seas4','seas5'
/
EOF

bkgfreq=${FGAT3D_freq}
if [ ${FGAT3D} == "TRUE" -a  ${FGAT3D_onlyCenter} != "TRUE" ]; then
   bkgtimest=${ADATEm3}
   bkgtimeed=${ADATEp3}
else
   bkgtimest=${ADATE}
   bkgtimeed=${ADATE}
fi

bkgtime=${bkgtimest}
while [[ ${bkgtime} -le ${bkgtimeed} ]]; do
    bkgyy=$(echo $bkgtime | cut -c1-4)
    bkgmm=$(echo $bkgtime | cut -c5-6)
    bkgdd=$(echo $bkgtime | cut -c7-8)
    bkghh=$(echo $bkgtime | cut -c9-10)
    bkgymd=${bkgyy}${bkgmm}${bkgdd}

    itile=1
    while [[ $itile -le 6 ]]; do
        $NCP $ROTDIR/enkfgdas.${PDY}/${cyc}/mem001/RESTART/${bkgymd}.${bkghh}0000.fv_tracer.res.tile${itile}.nc.ges restart.ensmean
        chmod u+w restart.ensmean
        nanal=1
        while [[ $nanal -le $NMEM_AERO ]]; do
            charnanal=mem`printf %03i $nanal`
            $NLN $ROTDIR/enkfgdas.${PDY}/${cyc}/${charnanal}/RESTART/${bkgymd}.${bkghh}0000.fv_tracer.res.tile${itile}.nc.ges restart.${charnanal}
            ((nanal=nanal+1))
        done

        srun -n $NMEM_AERO --export=all ./calc_ensmean_fv3.x $NMEM_AERO restart
        err=$?

        if [[ $? != 0 ]]; then
            exit $?
        fi

        if [[ ! -r ${analdir}/ensmean/RESTART/ ]]; then
           mkdir -p ${analdir}/ensmean/RESTART/
        fi

        $NMV restart.ensmean ${analdir}/ensmean/RESTART/${bkgymd}.${bkghh}0000.fv_tracer.res.tile${itile}.nc.ges


        ((itile=itile+1))

        while [[ $nanal -le $NMEM_AERO ]]; do
            charnanal=mem`printf %03i $nanal`
            unlink restart.${charnanal}
            ((nanal=nanal+1))
        done
    done
    bkgtime=$($NDATE ${bkgfreq} $bkgtime)
done

cat > ensmean.nml <<EOF
&ensmean_nml
varnames =  'T','delp'
/
EOF

bkgtime=${bkgtimest}
while [[ ${bkgtime} -le ${bkgtimeed} ]]; do
    bkgyy=$(echo $bkgtime | cut -c1-4)
    bkgmm=$(echo $bkgtime | cut -c5-6)
    bkgdd=$(echo $bkgtime | cut -c7-8)
    bkghh=$(echo $bkgtime | cut -c9-10)
    bkgymd=${bkgyy}${bkgmm}${bkgdd}

    itile=1
    while [[ $itile -le 6 ]]; do
        $NCP $ROTDIR/enkfgdas.${PDY}/${cyc}/mem001/RESTART/${bkgymd}.${bkghh}0000.fv_core.res.tile${itile}.nc.ges restart.ensmean
        chmod u+w restart.ensmean
        nanal=1
        while [[ $nanal -le $NMEM_AERO ]]; do
        charnanal=mem`printf %03i $nanal`
        $NLN $ROTDIR/enkfgdas.${PDY}/${cyc}/$charnanal/RESTART/${bkgymd}.${bkghh}0000.fv_core.res.tile${itile}.nc.ges restart.${charnanal}
        ((nanal=nanal+1))
        done
    
	srun -n $NMEM_AERO --export=all ./calc_ensmean_fv3.x $NMEM_AERO restart
    
	if [[ $? != 0 ]]; then
            exit $?
        fi

        if [[ ! -r ${analdir}/ensmean/RESTART ]]; then
           mkdir -p ${analdir}/ensmean/RESTART
        fi

        $NMV restart.ensmean ${analdir}/ensmean/RESTART/${bkgymd}.${bkghh}0000.fv_core.res.tile${itile}.nc.ges

        if [[ $itile == 1 ]]; then
            $NCP $ROTDIR/enkfgdas.${PDY}/${cyc}/mem001/RESTART/${bkgymd}.${bkghh}0000.coupler.res.ges ${analdir}/ensmean/RESTART/.
            $NCP $ROTDIR/enkfgdas.${PDY}/${cyc}/mem001/RESTART/${bkgymd}.${bkghh}0000.fv_core.res.nc.ges ${analdir}/ensmean/RESTART/.
        fi

        ((itile=itile+1))

        while [[ $nanal -le $NMEM_AERO ]]; do
            charnanal=mem`printf %03i $nanal`
            unlink restart.${charnanal}
            ((nanal=nanal+1))
        done
    done
    bkgtime=$($NDATE ${bkgfreq} $bkgtime)
done

###############################################################
# Postprocessing
cd $pwd
[[ $mkdata = "YES" ]] && rm -rf $DATA

set +x
#VERBOSE="YES"
if [ $VERBOSE = "YES" ]; then
   echo $(date) EXITING $0 with return code $err >&2
fi
exit $err
