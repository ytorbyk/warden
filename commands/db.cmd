#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

WARDEN_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${WARDEN_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${WARDEN_DB:-1} -eq 0 ]]; then
  fatal "Database environment is not used (WARDEN_DB=0)."
fi

if (( ${#WARDEN_PARAMS[@]} == 0 )) || [[ "${WARDEN_PARAMS[0]}" == "help" ]]; then
  warden db --help || exit $? && exit $?
fi

## load connection information for the mysql service
DB_CONTAINER=$(warden env ps -q db)
if [[ ! ${DB_CONTAINER} ]]; then
    fatal "No container found for db service."
fi

eval "$(
    docker container inspect ${DB_CONTAINER} --format '
        {{- range .Config.Env }}{{with split . "=" -}}
            {{- index . 0 }}='\''{{ range $i, $v := . }}{{ if $i }}{{ $v }}{{ end }}{{ end }}'\''{{println}}
        {{- end }}{{ end -}}
    ' | grep "^MYSQL_"
)"

## sub-command execution
case "${WARDEN_PARAMS[0]}" in
    connect)
        "${WARDEN_DIR}/bin/warden" env exec db \
            mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --database="${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}" "$@"
        ;;
    create)
        "${WARDEN_DIR}/bin/warden" env exec db \
            mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}\`" "$@" \
            && echo "'${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}' DB created if it did not exist"
        ;;
    drop)
        "${WARDEN_DIR}/bin/warden" env exec -T db \
            mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}\`" "$@" \
            && echo "'${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}' DB dropped if it existed"
        ;;
    cleanup)
        "${WARDEN_DIR}/bin/warden" env exec -T db \
            mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}\`" \
        && "${WARDEN_DIR}/bin/warden" env exec db \
           mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}\`" \
        && echo "'${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}' DB was re-created"
        ;;
    import)
        LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`/DEFINER=CURRENT_USER/g' \
            | LC_ALL=C sed -E '/\@\@(GLOBAL\.GTID_PURGED|SESSION\.SQL_LOG_BIN)/d' \
            | "${WARDEN_DIR}/bin/warden" env exec -T db \
            mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --database="${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}" "$@"
        ;;
    restore)
        pv ${WARDEN_PARAMS[1]} \
            | gunzip -c \
            | LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*[^*]*\*/\*/g' \
            | LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*[^*]*PROCEDURE/PROCEDURE/g' \
            | LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*[^*]*FUNCTION/FUNCTION/g' \
            | LC_ALL=C sed -E 's/ROW_FORMAT=FIXED//g' \
            | LC_ALL=C sed -E '/\@\@(GLOBAL\.GTID_PURGED|SESSION\.SQL_LOG_BIN)/d' \
            | "${WARDEN_DIR}/bin/warden" env exec -T db \
            mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --database="${WARDEN_PARAMS[2]:-${MYSQL_DATABASE}}" "$@"
        ;;
    dump)
        "${WARDEN_DIR}/bin/warden" env exec -T db \
            mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD}" "${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}}" "$@"
        ;;
    backup)
        "${WARDEN_DIR}/bin/warden" env exec -T db \
            mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD}" "${WARDEN_PARAMS[2]:-${MYSQL_DATABASE}}" \
            --single-transaction --quick --add-drop-table --routines=true \
            | LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*[^*]*\*/\*/g' \
            | LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*[^*]*PROCEDURE/PROCEDURE/g' \
            | LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*[^*]*FUNCTION/FUNCTION/g' \
            | LC_ALL=C sed -E 's/ROW_FORMAT=FIXED//g' \
            | LC_ALL=C sed -E '/\@\@(GLOBAL\.GTID_PURGED|SESSION\.SQL_LOG_BIN)/d' \
            | gzip -9 --force \
            > "${WARDEN_PARAMS[1]:-${MYSQL_DATABASE}.sql.gz}"
        ;;
    *)
        fatal "The command \"${WARDEN_PARAMS[0]}\" does not exist. Please use --help for usage."
        ;;
esac
