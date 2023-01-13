#!/bin/bash

set -eu

ARCH="$1"
VERSION="$2"

OUTDIR=output
RET=0

mkdir -p $OUTDIR

if [ "$VERSION" = "trunk" ]; then
    OUTPUT_VERSION_FILE="${VERSION}-$(date +%Y%m%d)"
else
    OUTPUT_VERSION_FILE="${VERSION}"
fi

CID=$(docker create -ti --name dummy gcc-cross ./build.sh "$ARCH" "$VERSION" /opt/ nope)

if docker start -a "$CID";
then
   docker cp "dummy:/opt/$ARCH-gcc-${OUTPUT_VERSION_FILE}.tar.xz" "$OUTDIR"/
   echo "$ARCH successful"
else
    echo "$ARCH not successful"
    RET=1
fi
docker rm -f dummy
exit "$RET"
