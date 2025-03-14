#! /usr/bin/env bash

source "${USHgfs}/preamble.sh"

###############################################################
echo "Begin Cleanup ${DATAROOT}!"

# Remove DATAoutput from the forecast model run
# TODO: Handle this better
DATAfcst="${DATAROOT}/${RUN}fcst.${PDY:-}${cyc}"
if [[ -d "${DATAfcst}" ]]; then rm -rf "${DATAfcst}"; fi
#DATAefcs="${DATAROOT}/${RUN}efcs???${PDY:-}${cyc}"
rm -rf "${DATAROOT}/${RUN}efcs"*"${PDY:-}${cyc}"

# In XML, DATAROOT is defined as:
#DATAROOT="${STMP}/RUNDIRS/${PSLOT}/${RUN}.${PDY}${cyc}"
# cleanup is only executed after the entire cycle is successfully completed.
# removing DATAROOT should be possible if that is the case.
rm -rf "${DATAROOT}"

echo "Cleanup ${DATAROOT} completed!"
###############################################################

if [[ "${CLEANUP_COM:-YES}" == NO ]] ; then
    exit 0
fi

###############################################################
# Clean up previous cycles; various depths

# Step back every assim_freq hours and remove old rotating directories
# for successful cycles (defaults from 24h to 120h).
# Retain files needed by Fit2Obs
last_date=$(date --utc +%Y%m%d%H -d "${PDY} ${cyc} -${RMOLDEND:-24} hours")
first_date=$(date --utc +%Y%m%d%H -d "${PDY} ${cyc} -${RMOLDSTD:-120} hours")
last_rtofs=$(date --utc +%Y%m%d%H -d "${PDY} ${cyc} -${RMOLDRTOFS:-48} hours")
function remove_files() {
    local directory=$1
    shift
    if [[ ! -d ${directory} ]]; then
        echo "No directory ${directory} to remove files from, skiping"
        return
    fi
    local find_exclude_string=""
    for exclude in "$@"; do
        find_exclude_string+="${find_exclude_string} -name ${exclude} -or"
    done
    # Chop off any trailing or
    find_exclude_string="${find_exclude_string[*]/%-or}"
    # Remove all regular files that do not match
    # shellcheck disable=SC2086
    find "${directory}" -type f -not \( ${find_exclude_string} \) -delete
    # Remove all symlinks that do not match
    # shellcheck disable=SC2086
    find "${directory}" -type l -not \( ${find_exclude_string} \) -delete
    # Remove any empty directories
    find "${directory}" -type d -empty -delete
}

for (( current_date=first_date; current_date <= last_date; \
  current_date=$(date --utc +%Y%m%d%H -d "${current_date:0:8} ${current_date:8:2} +${assim_freq} hours") )); do
    current_PDY="${current_date:0:8}"
    current_cyc="${current_date:8:2}"
    rtofs_dir="${ROTDIR}/rtofs.${current_PDY}"
    rocotolog="${EXPDIR}/logs/${current_date}.log"
    if [[ -f "${rocotolog}" ]]; then
        # TODO: This needs to be revamped to not look at the rocoto log.
        # shellcheck disable=SC2312
        if [[ $(tail -n 1 "${rocotolog}") =~ "This cycle is complete: Success" ]]; then
            YMD="${current_PDY}" HH="${current_cyc}" declare_from_tmpl \
                COMOUT_TOP:COM_TOP_TMPL
            if [[ -d "${COMOUT_TOP}" ]]; then
                IFS=", " read -r -a exclude_list <<< "${exclude_string:-}"
                remove_files "${COMOUT_TOP}" "${exclude_list[@]:-}"
            fi
            if [[ -d "${rtofs_dir}" ]] && (( current_date < last_rtofs )); then rm -rf "${rtofs_dir}" ; fi
        fi
    fi

    # Remove mdl gfsmos directory
    if [[ "${RUN}" == "gfs" ]]; then
        mos_dir="${ROTDIR}/gfsmos.${current_PDY}"
        if [[ -d "${mos_dir}" ]] && (( current_date < CDATE_MOS )); then rm -rf "${mos_dir}" ; fi
    fi
done

# Remove archived gaussian files used for Fit2Obs in $VFYARC that are
# $FHMAX_FITS plus a delta before $CDATE. Touch existing archived
# gaussian files to prevent the files from being removed by automatic
# scrubber present on some machines.

if [[ "${RUN}" == "gfs" ]]; then
    fhmax=$((FHMAX_FITS + 36))
    RDATE=$(date --utc +%Y%m%d%H -d "${PDY} ${cyc} -${fhmax} hours")
    verify_dir="${ROTDIR}/vrfyarch/${RUN}.${RDATE:0:8}"
    [[ -d ${verify_dir} ]] && rm -rf "${verify_dir}"

    touch_date=$(date --utc +%Y%m%d%H -d "${PDY} ${cyc} -${FHMAX_FITS} hours")
    while (( touch_date < "${PDY}${cyc}" )); do
        touch_PDY="${touch_date:0:8}"
        touch_cyc="${touch_date:8:2}"
        touch_dir="${ROTDIR}/vrfyarch/${RUN}.${touch_PDY}/${touch_cyc}"
        [[ -d ${touch_dir} ]] && touch "${touch_dir}"/*
        touch_date=$(date --utc +%Y%m%d%H -d "${touch_PDY} ${touch_cyc} +6 hours")
    done
fi

# Remove $RUN.$rPDY for the older of GDATE or RDATE
GDATE=$(date --utc +%Y%m%d%H -d "${PDY} ${cyc} -${RMOLDSTD:-120} hours")
RDATE=$(date --utc +%Y%m%d%H -d "${PDY} ${cyc} -${FHMAX_GFS} hours")
if (( GDATE < RDATE )); then
    RDATE=${GDATE}
fi
deletion_target="${ROTDIR}/${RUN}.${RDATE:0:8}"
if [[ -d ${deletion_target} ]]; then rm -rf "${deletion_target}"; fi
