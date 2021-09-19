#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

mkdir -p "${WARDEN_SSL_DIR}/certs"

CERTIFICATE_DOMAIN_LIST=
for (( i = 0; i < ${#WARDEN_PARAMS[@]} * 2; i+=2 )); do
  [[ ${CERTIFICATE_DOMAIN_LIST} ]] && CERTIFICATE_DOMAIN_LIST+=" "
  CERTIFICATE_DOMAIN_LIST+="${WARDEN_PARAMS[i/2]}"
  CERTIFICATE_DOMAIN_LIST+=" *.${WARDEN_PARAMS[i/2]}"
done

CERTIFICATE_NAME="${WARDEN_PARAMS[0]}"

echo "==> Generating private key certificate"
mkcert \
 -key-file "${WARDEN_SSL_DIR}/certs/${CERTIFICATE_NAME}.key.pem" \
 -cert-file "${WARDEN_SSL_DIR}/certs/${CERTIFICATE_NAME}.crt.pem" \
 ${CERTIFICATE_DOMAIN_LIST}


if [[ "$(cd "${WARDEN_HOME_DIR}" && docker-compose -p warden -f "${WARDEN_DIR}/docker/docker-compose.yml" ps -q traefik)" ]]
then
  echo "==> Updating traefik"
  "${WARDEN_DIR}/bin/warden" svc up traefik
  "${WARDEN_DIR}/bin/warden" svc restart traefik
fi
