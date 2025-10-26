FROM ubuntu:22.04
MAINTAINER Matt Godbolt <matt@godbolt.org>

ARG DEBIAN_FRONTEND=noninteractive

# Annoyingly crosstool whinges if it's run as root.
RUN mkdir -p /opt && mkdir -p /home/gcc-user && useradd gcc-user && chown gcc-user /opt /home/gcc-user

RUN apt-get clean -y && apt-get check -y

## for nightly build of cross compiler with GNAT (Ada), we need "a matching"
## compiler. So using gcc-13 for master is not working. So we have a *hardcoded*
## snapshot below that should be "good enough". When there's a failure caused by
## GNAT, it's probably time to bump the snapshot.

RUN apt-get update -y -q && apt-get upgrade -y -q && apt-get upgrade -y -q && \
    apt-get install -y -q \
    autoconf \
    automake \
    libtool \
    bison \
    bzip2 \
    curl \
    file \
    flex \
    git \
    gawk \
    binutils-multiarch \
    gperf \
    help2man \
    libc6-dev-i386 \
    libncurses5-dev \
    libtool-bin \
    linux-libc-dev \
    make \
    ninja-build \
    device-tree-compiler \
    patch \
    rsync \
    s3cmd \
    sed \
    subversion \
    texinfo \
    wget \
    unzip \
    autopoint \
    gettext \
    vim \
    zlib1g-dev \
    software-properties-common \
    xz-utils && \
    cd /tmp && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip -q awscliv2.zip && \
    ./aws/install && \
    rm -rf aws* && \
    mkdir -p /opt/compiler-explorer/ && \
    cd /opt/compiler-explorer && \
    curl "https://s3.amazonaws.com/compiler-explorer/opt/gcc-11.4.0.tar.xz" -o gcc11.tar.xz && \
    curl "https://s3.amazonaws.com/compiler-explorer/opt/gcc-12.3.0.tar.xz" -o gcc12.tar.xz && \
    curl "https://s3.amazonaws.com/compiler-explorer/opt/gcc-13.2.0.tar.xz" -o gcc13.tar.xz && \
    curl "https://s3.amazonaws.com/compiler-explorer/opt/gcc-14.2.0.tar.xz" -o gcc14.tar.xz && \
    curl "https://s3.amazonaws.com/compiler-explorer/opt/gcc-trunk-20251023.tar.xz" -o gcc-trunk.tar.xz && \
    tar Jxf gcc11.tar.xz && \
    tar Jxf gcc12.tar.xz && \
    tar Jxf gcc13.tar.xz && \
    tar Jxf gcc14.tar.xz && \
    tar Jxf gcc-trunk.tar.xz && \
    mv gcc-trunk-20251023 gcc-trunk && \
    rm gcc*.tar.xz

## Beware of the "trunk" download. It is useful when a cross compiler really
## needs a very recent base compiler (e.g. GNAT). The hardcoded filename for
## trunk will only work for some time as we are expiring them after a few days.

## Need for host GCC version to be ~= latest cross GCC being built.
## This is at least needed for building cross-GNAT (Ada) as the GNAT runtime has no
## requirement on a minimal supported version (e.g. need GCC 12 to build any GNAT runtime).
## This is only true for cross compiler. Native compiler can use host's runtime
## and bootstrap everything.
ENV PATH="/opt/compiler-explorer/gcc-14.2.0/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/compiler-explorer/gcc-14.2.0/lib64:${PATH}"
# This is needed because cross-tools needs to look within this location for a libatomic from
# the host toolchain.  But cross-tools overrides the sysroot, and so problems occur during
# building because GCC now links -latomic by default.
ENV LDFLAGS="-L/opt/compiler-explorer/gcc-14.2.0/lib64"

WORKDIR /opt

## This patch is needed to force ct-ng to not error out because we are setting
## LD_LIBRARY_PATH. There's no easy way to have ct-ng use a particular compiler
## (...). If we have strange behavior, maybe we'll have to look at this.
## Couldn't see anything suspicious (yet).
COPY build/patches/crosstool-ng/ld_library_path.patch ./

## TAG is pointing to a specific ct-ng revision (usually the current dev one
## when updating this script or ct-ng)
RUN TAG=b0a9dd7365050bbb79e7b2697cd62336e799058f && \
    curl -sL https://github.com/dkm/crosstool-ng/archive/${TAG}.zip --output crosstool-ng-master.zip  && \
    unzip crosstool-ng-master.zip && \
    cd crosstool-ng-${TAG} && \
    patch -p1 < ../ld_library_path.patch && \
    ./bootstrap && \
    ./configure --prefix=/opt/crosstool-ng-latest && \
    make -j$(nproc) && \
    make install

RUN mkdir -p /opt/.build/tarballs /build
COPY build /opt/
RUN chown -R gcc-user /opt /build
USER gcc-user
