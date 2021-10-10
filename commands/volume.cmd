#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

WARDEN_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${WARDEN_ENV_PATH}" || exit $?

if (( ${#WARDEN_PARAMS[@]} == 0 )) || [[ "${WARDEN_PARAMS[0]}" == "help" ]]; then
  warden volume --help || exit $? && exit $?
fi

if [[ -f "${WARDEN_HOME_DIR}/.env" ]]; then
  eval "$(cat "${WARDEN_HOME_DIR}/.env" | sed 's/\r$//g' | grep "^WARDEN_VOLUMES_")"
fi
export WARDEN_VOLUMES_FOLDER="${WARDEN_VOLUMES_FOLDER:-"$HOME"}"

YEL='\033[1;33m' # Yellow
NC='\033[0m'     # No Color

## sub-command execution
case "${WARDEN_PARAMS[0]}" in
    export)
        VOLUME_NAME="${WARDEN_ENV_NAME}_${WARDEN_PARAMS[1]:-"dbdata"}" \
        && VOLUME_ARCHIVE="${WARDEN_PARAMS[2]:-"${VOLUME_NAME}-$(date +'%Y.%m.%d-%H.%M.%S').tar.gz"}" \
        && docker run -v ${VOLUME_NAME}:/volume --rm --log-driver none \
            loomchild/volume-backup backup -c pigz - | pv -b -t -r -N "Export [${VOLUME_NAME}]" > ${WARDEN_VOLUMES_FOLDER}/${VOLUME_ARCHIVE} \
        && printf "Volume ${YEL}${VOLUME_NAME}${NC} is exported to ${YEL}${WARDEN_VOLUMES_FOLDER}/${VOLUME_ARCHIVE}${NC}\n"
        ;;
    import)
        if [[ -f "${WARDEN_VOLUMES_FOLDER}/${WARDEN_PARAMS[1]:-}" ]]; then
            VOLUME_NAME="${WARDEN_ENV_NAME}_${WARDEN_PARAMS[2]:-"dbdata"}" \
            && VOLUME_ARCHIVE="${WARDEN_PARAMS[1]:-}" \
            && pv -w 80 -N "Import [${VOLUME_NAME}]" ${WARDEN_VOLUMES_FOLDER}/${VOLUME_ARCHIVE} | \
                docker run -i -v ${VOLUME_NAME}:/volume --rm loomchild/volume-backup restore -c pigz -f - \
            && printf "Data in ${YEL}${VOLUME_NAME}${NC} volume is replaced with data from ${YEL}${WARDEN_VOLUMES_FOLDER}/${VOLUME_ARCHIVE}${NC}\n"
        else
            fatal "Archive '${WARDEN_VOLUMES_FOLDER}/${WARDEN_PARAMS[2]:-}' is not found."
        fi
        ;;
    list)
        docker volume ls --format "{{title .Name}}" -f name="^${WARDEN_ENV_NAME}"
        ;;
    *)
        fatal "The command \"${WARDEN_PARAMS[0]}\" does not exist. Please use --help for usage."
        ;;
esac
