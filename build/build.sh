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

CT_NG_VERSIONS=(latest)
for version in "${CT_NG_VERSIONS[@]}"; do
    if [[ -f "${version}/${CONFIG_FILE}" ]]; then
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

# Pick the host base compiler.
# We need to pick one as close as possible to the GCC version being built because of GNAT (Ada).
# It needs a matching compiler to build the runtime. Too old or too recent may cause build errors.

# Kind of heuristic to find a "good" GCC version. Not perfect, but should do the
# work. Starts by checking for a matching version host compiler X.Y.Z, then for
# any X.Y and finally for any X. If nothing matches, then it uses the default
# one (see Dockerfile).
# This works for X.Y.Z but also for "trunk", even if we use latest trunk as the default.
export PATH="/opt/compiler-explorer/gcc-trunk/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/compiler-explorer/gcc-trunk//lib:/opt/compiler-explorer/gcc-trunk/lib64:${LD_LIBRARY_PATH}"

V=${BASEVERSION}
for i in 1 2 3; do
    F=0
    for candidate in $(find  /opt/compiler-explorer/ -maxdepth 1 -name "gcc-${V}*" -type d); do
        echo "Using ${candidate} as the host base compiler"
        export PATH="${candidate}/bin:${PATH}"
        export LD_LIBRARY_PATH="${candidate}/lib:${candidate}/lib64:${LD_LIBRARY_PATH}"
        F=1
    done
    if [[ "$F" == 1 ]]; then
       break
    fi

    V=${V%.*}
done

cp "${CONFIG_FILE}" .config
${CT} olddefconfig
# oldconfig will restore mirror urls, so as a workaround until
# https://github.com/crosstool-ng/crosstool-ng/issues/1609 gets
# fixed we have to update the mirror url after calling oldconfig
sed -i -r 's|CT_ISL_MIRRORS=".*"|CT_ISL_MIRRORS="https://libisl.sourceforge.io/"|g' .config
if ! ${CT} "build.$(nproc)"; then
    cat build.log
    exit 1
fi

export XZ_DEFAULTS="-T 0"
tar Jcf "${OUTPUT}" -C "${STAGING_DIR}"/.. "gcc-${VERSION}"

if [[ -n "${S3OUTPUT}" ]]; then
    aws s3 cp --storage-class REDUCED_REDUNDANCY "${OUTPUT}" "${S3OUTPUT}"
fi

echo "ce-build-status:OK"
