#!/bin/bash

PKG=${1?:"Please specify package name."}
APT_CONF=${APT_CONF:-$2}
APT_CONF=${APT_CONF:-"/root/mos_mu/apt/apt.conf"}
CUSTOM_DIR=${CUSTOM_DIR:-$3}
CUSTOM_DIR=${CUSTOM_DIR:?"CUSTOM_DIR is undefined!"}
KEEP_PKGS=${KEEP_PKGS:-$4}

HOLD_PKGS=$(apt-mark showhold)
echo "${KEEP_PKGS} ${HOLD_PKGS}" | grep ${PKG} && exit 100

EXTRACTED_PKG="${CUSTOM_DIR}/${PKG}"

POLICY=$(apt-cache -c "${APT_CONF}" policy "${PKG}") || exit 1
VERS_ORIG=$(echo -e "${POLICY}" | awk '/Installed/ {print $2}')
VERS=${VERS_ORIG/\:/\%3a}

PKG_FILE="${PKG}_${VERS}_all.deb"
CACHED_PKG_FILE="/var/cache/apt/archives/${PKG_FILE}"
ORIG_PKG="${CACHED_PKG_FILE}"

DIFF="${EXTRACTED_PKG}/${PKG}_customization.patch"

# Check if diff already exists
[ -e "${DIFF}" ] && exit 0

[ -d "${EXTRACTED_PKG}/${VERS}" ] || mkdir -p "${EXTRACTED_PKG}/${VERS}"
cd "${EXTRACTED_PKG}/${VERS}"     && rm -rf ./*

if ! [ -e "${CACHED_PKG_FILE}" ]; then
    apt-get -c "${APT_CONF}" download "${PKG}=${VERS_ORIG}" || exit -1
    ORIG_PKG=${PKG_FILE}
fi
ar p "${ORIG_PKG}" data.tar.xz | tar xJ || exit -1

cd "${EXTRACTED_PKG}" || exit -1
RET=0
FILES=$(dpkg -V "${PKG}" |  awk '{if ($2 != "c") print $2}')
for FILE in ${FILES}; do
    file "${FILE}" | grep text &> /dev/null || {
        echo "[WARN] File ${FILE} is not text and will be ignored and might replaced during the update procedure";
        continue; }
    diff -NrU 5 "./${VERS}/${FILE}" "${FILE}" >> "${DIFF}"
    case $? in
        1)
            ;;
        *)
            (( RET |= 1 ))
            ;;
    esac
done

exit  "${RET}"
