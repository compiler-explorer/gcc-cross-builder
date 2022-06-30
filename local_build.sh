#!/bin/bash

set -eu

ARCH="$1"
VERSION="$2"

OUTDIR=output
RET=0

mkdir -p $OUTDIR

CID=$(docker create -ti --name dummy gcc-cross ./build.sh "$ARCH" "$VERSION" /opt/ nope)


if docker start -a "$CID";
then
   docker cp "dummy:/opt/$ARCH-gcc-$VERSION.tar.xz" "$OUTDIR"/
   echo "$ARCH successful"
else
    echo "$ARCH not successful"
    RET=1
fi
docker rm -f dummy
exit "$RET"
