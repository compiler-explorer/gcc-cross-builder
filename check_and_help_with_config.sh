#!/bin/bash

set -eu

ARCH="$1"
VERSION="$2"

CONFIG_DIR="$3"

## C is always enabled
LANGS=( "ADA" "D" "FORTRAN" "CXX" )

function versionId {
    echo "$1" | tr -d '\.'
}

function archId {
    A="$(toLower "$1")"
    case "$A" in
        powerpc*)
            echo "${A/powerpc/ppc}"
            ;;
        riscv*)
            echo "${A/riscv/rv}"
            ;;
        *)
            echo "$A"
            ;;
        esac
}

function toLower {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

function compilerName {
    base=""
    prefix=""
    arch=$(archId "$1")
    version=$(versionId "$2")

    case "$3" in
        D)
            prefix="gdc"
            ;;
        ADA)
            prefix="gnat"
            base=""
            ;;
        C)
            prefix="c"
            base="g"
            ;;
        CXX)
            base="g"
            ;;
        FORTRAN)
            prefix="f"
            base="g"
            ;;
        *)
            echo "Woops, unknown lang $1"
            exit 1
            ;;
    esac

    echo "${prefix}${arch}${base}${version}"
}

function findObjdump {
    E=$(find "/opt/compiler-explorer/${1}/gcc-${2}" -type f -executable -name "*-objdump" -print)
    echo "$E"
}

function findConfig {
    base="$(toLower "$2")"

    case "$2" in
        CXX)
            base="c++"
            ;;
        *)
            ;;
    esac
    E=$(find "${1}" -type f  -name "${base}.amazon.properties" -print)
    echo "$E"
}

function findCompiler {
    endsWith=""
    case "$3" in
        D)
            endsWith="-gdc"
            ;;
        C)
            endsWith="-gcc"
            ;;
        CXX)
            endsWith="-g++"
            ;;
        ADA)
            endsWith="-gnatmake"
            ;;
        FORTRAN)
            endsWith="-gfortran"
            ;;
        *)
            echo "Woops, unknown lang $1"
            exit 1
            ;;
    esac
    E=$(find "/opt/compiler-explorer/${1}/gcc-${2}" -type f -executable -name "*${endsWith}" -print)
    echo "$E"
}

function checkCompilerInConfig {
    if grep -q "$1" "$2";
    then
        echo "[OK]"
    else
        echo "[MISSING]"
    fi
}

function check {
    arch="$1"
    version="$2"
    lang="$3"

    conf=$(findConfig "${CONFIG_DIR}" "$lang")
    cid=$(compilerName "$ARCH" "$VERSION" "$lang")
    cexe=$(findCompiler "$ARCH" "$VERSION" "$lang")
    od=$(findObjdump "$arch" "$version")

    config_ok=$(checkCompilerInConfig "$cid" "$conf")
    echo "For ${conf} ${config_ok}"
    echo
    echo "compiler.${cid}.exe=${cexe}"
    echo "compiler.${cid}.semver=${version}"
    echo "compiler.${cid}.objdumper=${od}"
    echo
}

check "$ARCH" "$VERSION" "C"

for l in "${LANGS[@]}"
do
    if grep -q "CT_CC_LANG_${l}=y" "build/latest/${ARCH}-${VERSION}.config"; then
        check "$ARCH" "$VERSION" "$l"
    fi
done
