#!/bin/bash

set -eu

ARCH="$1"
VERSION="$2"

OUTDIR=output
RET=0

mkdir -p $OUTDIR

DOCKER=docker
if ! type -P ${DOCKER} 2>/dev/null ; then
	DOCKER=podman
fi

if [ "$VERSION" = "trunk" ]; then
    OUTPUT_VERSION_FILE="${VERSION}-$(date +%Y%m%d)"
else
    OUTPUT_VERSION_FILE="${VERSION}"
fi

CID=$(${DOCKER} create -ti --name dummy gcc-cross ./build.sh "$ARCH" "$VERSION" /opt/ nope)

if ${DOCKER} start -a "$CID";
then
   ${DOCKER} cp "dummy:/opt/$ARCH-gcc-${OUTPUT_VERSION_FILE}.tar.xz" "$OUTDIR"/
   echo "$ARCH SUCCESS"
else
    echo "$ARCH FAILED"
    RET=1
fi
${DOCKER} rm -f dummy
exit "$RET"
