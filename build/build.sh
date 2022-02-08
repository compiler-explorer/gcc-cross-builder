#!/bin/bash

set -exuo pipefail

ROOT=$(pwd)

ARCHITECTURE=$1
VERSION=$2

BASEVERSION=${VERSION}
if echo "${VERSION}" | grep 'trunk'; then
    VERSION=${VERSION}-$(date +%Y%m%d)
    LAST_REVISION="${4}"
else
    LAST_REVISION="ignore"
fi

OUTPUT=/home/gcc-user/${ARCHITECTURE}-gcc-${VERSION}.tar.xz
STAGING_DIR=/opt/compiler-explorer/${ARCHITECTURE}/gcc-${VERSION}
export CT_PREFIX=${STAGING_DIR}

ARG3=${3:-}
FULLNAME=${ARCHITECTURE}-gcc-${VERSION}
if [[ $ARG3 =~ s3:// ]]; then
    S3OUTPUT=$ARG3
else
    S3OUTPUT=""
    if [[ -d "${ARG3}" ]]; then
        OUTPUT="${ARG3}/${FULLNAME}.tar.xz"
    else
        OUTPUT=${3-/home/gcc-user/${FULLNAME}.tar.xz}
    fi
fi

CONFIG_FILE=${ARCHITECTURE}-${BASEVERSION}.config
for version in latest 1.24.0 1.23.0 1.22.0; do
    if [[ -f ${version}/${CONFIG_FILE} ]]; then
        CONFIG_FILE=${version}/${CONFIG_FILE}
        CT=${ROOT}/crosstool-ng-$version/ct-ng
        if [[ ! -x ${CT} ]]; then
            # installed version rather than ct-ng configured with --enable-local
            CT=${ROOT}/crosstool-ng-$version/bin/ct-ng
            if [[ ! -x ${CT} ]]; then
                echo "ct-ng $CT is either not found or not executable, also checked ${ROOT}/crosstool-ng-$version/ct-ng"
                exit 1
            fi
        fi
        break
    fi
done

REVISION="$(date +%s)"  # make up a revision every time

echo "ce-build-revision:${REVISION}"
echo "ce-build-output:${OUTPUT}"

if [[ "${REVISION}" == "${LAST_REVISION}" ]]; then
    echo "ce-build-status:SKIPPED"
    exit
fi


cp "${CONFIG_FILE}" .config
${CT} oldconfig
# oldconfig will restore mirror urls, so as a workaround until
# https://github.com/crosstool-ng/crosstool-ng/issues/1609 gets
# fixed we have to update the mirror url after calling oldconfig
sed -i -r 's|CT_ISL_MIRRORS=".*"|CT_ISL_MIRRORS="https://libisl.sourceforge.io/"|g' .config
${CT} "build.$(nproc)"

export XZ_DEFAULTS="-T 0"
tar Jcf "${OUTPUT}" -C "${STAGING_DIR}"/.. "gcc-${VERSION}"

if [[ -n "${S3OUTPUT}" ]]; then
    aws s3 cp --storage-class REDUCED_REDUNDANCY "${OUTPUT}" "${S3OUTPUT}"
fi

echo "ce-build-status:OK"
