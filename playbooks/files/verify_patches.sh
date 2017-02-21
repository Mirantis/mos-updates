#!/bin/bash

APT_CONF=${1:-$APT_CONF}
APT_CONF=${APT_CONF:-"/root/mos_mu/apt/apt.conf"}
PATCHES_DIR=${2:-$PATCHES_DIR}
PATCHES_DIR=${PATCHES_DIR:?"PATCHES_DIR is undefined!"}
VERIFICATION_DIR=${3:-$VERIFICATION_DIR}
VERIFICATION_DIR=${VERIFICATION_DIR:?"VERIFICATION_DIR is undefined!"}
PKG_VER_FOR_VERIFICATION=${4:-$PKG_VER_FOR_VERIFICATION}
PKG_VER_FOR_VERIFICATION=${PKG_VER_FOR_VERIFICATION:?"PKG_VER_FOR_VERIFICATION is undefined!"}
IGNORE_APPLIED_PATCHES=${5:-$IGNORE_APPLIED_PATCHES}
IGNORE_APPLIED_PATCHES=${IGNORE_APPLIED_PATCHES:-"False"}
KEEP_PKGS=${KEEP_PKGS:-$5}


# Get patackage name from patch
# Global vars:
#   OUT - Error or Warning messages
#   PKG - Package name
get_pkg_name_from_patch()
{
    OUT=""
    PKG=""
    local RET=0
    local PATCH=${1:?"Please specify patch's filename"}
    local FILES=$(awk '/\+\+\+/ {print $2}' "${PATCH}")
    # Get Package name and make sure that all affect the only one package
    for FILE in ${FILES}; do
        [ -e "${FILE}" ] || {
            OUT+="[WARN]   ${FILE} skipped since it is absent";
            continue; }
        PACK=$(dpkg -S "${FILE}")
        PACK=$(echo -e "${PACK}" | awk '{print $1}')
        PACK=${PACK/\:/}
        [ -z "${PKG}" ] && {
            PKG="${PACK}";
            continue; }
        [[ "${PACK}" != "${PKG}" ]] && {
            (( RET |= 1 ));
            OUT+="[ERROR]  Affect more than one package: ${PKG} != ${PACK} (${FILE})"; }
    done
    return "${RET}"
}

cd "${PATCHES_DIR}" &>/dev/null || exit 0

HOLD_PKGS=$(apt-mark showhold)

RET=0
# Check patches
PATCHES=$(find . -type f -name "*.patch" |sort)
for PATCH in ${PATCHES}; do
    cd "${PATCHES_DIR}" || exit 2
    echo -e "\n-------- ${PATCH}"
    get_pkg_name_from_patch "${PATCH}"
    RS=$?
    [ -z "${OUT}" ] ||
        echo -e "${OUT}"
    (( RS != 0 ))  && {
        (( RET |= 1 ));
        continue; }
    # Whether package is installed on this node
    [ -z "${PKG}" ] &&
        continue
    # Whether this package should be keeped
    echo "${KEEP_PKGS} ${HOLD_PKGS}" | grep ${PKG} &>/dev/null  && {
        echo "[SKIP]   ${PKG} is on hold";
        continue; }

    # Download new version and extract it
    PKG_PATH=${VERIFICATION_DIR}/${PKG}
    POLICY=$(apt-cache -c "${APT_CONF}" policy "${PKG}") || exit 2
    VERS_ORIG=$(echo -e "${POLICY}" | grep "${PKG_VER_FOR_VERIFICATION}" | awk '{print $2}')
    VERS=${VERS_ORIG/\:/\%3a}
    VERS_PATH=${PKG_PATH}/${VERS}
    PKG_NAME="${PKG}_${VERS}_all.deb"

    [ -d "${VERS_PATH}" ] || mkdir -p "${VERS_PATH}"
    cd "${VERS_PATH}" || exit 2
    [ -e "${PKG_NAME}" ] ||
        apt-get -q -c "${APT_CONF}" download "${PKG}" &>/dev/null || {
            echo "[ERROR]  Failed to download ${PKG}";
            (( RET |= 2));
            continue; }
    [ -d "usr" ] ||
        ar p "${PKG_NAME}" data.tar.xz | tar xJ || {
            echo "[ERROR]  Failed to unpack ${PKG}";
            (( RET |= 2));
            continue; }

    # Verify patch applying
    cd "${PKG_PATH}" ||
        { exit 2
        echo "[ERROR]  Failed to enter to the folder ${PKG_PATH}";}

    cp -f "${PATCHES_DIR}/${PATCH}" .
    PATCH_FILENAME=${PATCH##*/}
    PATCH_OUT=$(patch -p1 -Nu -r- -d "${VERS}" < "${PATCH_FILENAME}")
    RES=$?
    echo -e "${PATCH_OUT}"
    if (( RES != 0 )); then
        if [ "${IGNORE_APPLIED_PATCHES,,}" != "true" ]; then
            PATCH_RES=$(grep -E "Skipping|ignored" <<< "${PATCH_OUT}")
            if [ -n "${PATCH_RES}" ]; then
                echo "[ERROR]  Failed to apply ${PATCH}"
                (( RET |= 4))
                continue
            fi
        fi
        # FIXME: Need to be tested and modified !?
        # Only the following lines should present in output:
        #    patching file usr/lib/python2.7/dist-packages/......
        #    Reversed (or previously applied) patch detected!  Skipping patch.
        #    2 out of 2 hunks ignored
        PATCH_RES=$(grep -Ev "patching|Skipping|ignored" <<< "${PATCH_OUT}")
        if [ -n "${PATCH_RES}" ]; then
            echo "[ERROR]  Failed to apply ${PATCH}"
            (( RET |= 8))
            continue
        fi
    fi
    echo "[OK]     ${PKG} is customized successfully"
done

if (( (RET & 4) == 4 )); then
    echo ""
    echo "Some patches look as already applied."
    echo "Please make sure that these patches were included in MU"
    echo "If you sure that it is, you can use the following flag:"
    echo ' {"ignore_applied_patches":true}'
    echo "for ignoring these patches."
fi
if (( (RET & 8) == 8 )); then
    echo ""
    echo "Some patches failed to apply."
    echo "Please resolve this issue:"
    echo " 1. Go on the failed nodes in 'verification' folder"
    echo " 2. Handle the issue with patch applying."
    echo " 3. Copy this patch  to 'patches' folder"
    echo ' 4. use -e {"use_current_customizations":false} for skipping'
    echo "    verification and using of gathered customizations."
fi

exit "${RET}"
