FROM ubuntu:22.04
LABEL maintainer="Matt Godbolt <matt@godbolt.org>"

ARG DEBIAN_FRONTEND=noninteractive

# Annoyingly crosstool whinges if it's run as root.
RUN mkdir -p /opt && mkdir -p /home/gcc-user && useradd gcc-user && chown gcc-user /opt /home/gcc-user

RUN apt-get clean -y && apt-get check -y

## For nightly build of cross compiler with GNAT (Ada), we need "a matching"
## compiler. The nightly gcc trunk is installed via ce_install which handles
## the symlink automatically.

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
    xz-utils \
    openssh-client \
    python3 \
    python3-venv && \
    cd /tmp && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip -q awscliv2.zip && \
    ./aws/install && \
    rm -rf aws*

# Add github public key to known_hosts for interaction-less clone
RUN mkdir -p /root/.ssh && \
    touch /root/.ssh/known_hosts && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

# Clone infra and set up ce_install
RUN mkdir -p /opt/compiler-explorer && \
    git clone https://github.com/compiler-explorer/infra /opt/compiler-explorer/infra && \
    cd /opt/compiler-explorer/infra && make ce

# Install host GCC compilers via ce_install
RUN /opt/compiler-explorer/infra/bin/ce_install install 'compilers/c++/x86/gcc 11.4.0' && \
    /opt/compiler-explorer/infra/bin/ce_install install 'compilers/c++/x86/gcc 12.3.0' && \
    /opt/compiler-explorer/infra/bin/ce_install install 'compilers/c++/x86/gcc 13.2.0' && \
    /opt/compiler-explorer/infra/bin/ce_install install 'compilers/c++/x86/gcc 14.2.0' && \
    /opt/compiler-explorer/infra/bin/ce_install --enable nightly install 'compilers/c++/nightly/gcc trunk' && \
    ln -sf $(readlink /opt/compiler-explorer/gcc-snapshot) /opt/compiler-explorer/gcc-trunk

## The trunk download is useful when a cross compiler really needs a very recent
## base compiler (e.g. GNAT). ce_install handles the trunk symlink automatically.

## Need for host GCC version to be ~= latest cross GCC being built.
## This is at least needed for building cross-GNAT (Ada) as the GNAT runtime has no
## requirement on a minimal supported version (e.g. need GCC 12 to build any GNAT runtime).
## This is only true for cross compiler. Native compiler can use host's runtime
## and bootstrap everything.
ENV PATH="/opt/compiler-explorer/gcc-14.2.0/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/compiler-explorer/gcc-14.2.0/lib64"

WORKDIR /opt

## This patch is needed to force ct-ng to not error out because we are setting
## LD_LIBRARY_PATH. There's no easy way to have ct-ng use a particular compiler
## (...). If we have strange behavior, maybe we'll have to look at this.
## Couldn't see anything suspicious (yet).
COPY build/patches/crosstool-ng/ld_library_path.patch ./

## TAG is pointing to a specific ct-ng revision (usually the current dev one
## when updating this script or ct-ng)
RUN TAG=d04b73234f716e0d473aa059cf4c812d18703ac6 && \
    curl -sL https://github.com/crosstool-ng/crosstool-ng/archive/${TAG}.zip --output crosstool-ng-master.zip  && \
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
