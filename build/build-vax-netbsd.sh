#!/usr/bin/env bash

set -e

#
# Global variables.
#
s3=
nb_requested_timestamp=$(date '+%s')
nb_arch=vax
nb_mach=vax
nb_git="https://github.com/NetBSD/src.git"
gcc_target=vax--netbsdelf
gcc_dir=gcc.old
declare -a build_vars
workdir=/opt/build-netbsd.$$
src_checkout_dir="${workdir}/src"
reldir="${workdir}/rel"
destdir="${workdir}/dest"
tooldir="${workdir}/tools"

#
# Parse `--new`, `--old`, `--s3`, `--timestamp` and `--force-output`.
#
# new/old: Refers to "new" GCC and "old" GCC in the context of NetBSD.
# Currently "old": 10.x (default)
#           "new": 12.x
#

if ! parsed_opts=$(getopt -o ons:t:f:h --long old,new,s3:,timestamp:,force-output:,help -n "${0}" -- "$@"); then
	echo "Error parsing options." >&2
	exit 1
fi

eval set -- "${parsed_opts}"
while :; do
	case "${1}" in
		-o | --old)
			gcc_dir=gcc.old
			build_vars=( "-V" "HAVE_GCC=10" )
			shift
			;;

		-n | --new)
			gcc_dir=gcc
			build_vars=()
			shift
			;;

		-s | --s3)
			s3="${2}"
			shift 2
			;;

		-t | --timestamp)
			nb_requested_timestamp="${2}"
			shift 2
			;;

		-f | --force-output)
			forced_output_filename="${2}"
			shift 2
			;;

		--)
			shift
			break
			;;

		-h | --help | *)
			echo "${0} <--old | --new> <--s3 s3://...> <--timestamp 1699485114> <--force-output /path/to/gcc-out.tar.xz>" >&2
			echo "Defaults are: --old, current timestamp, no s3 upload, output tarball in workdir" >&2
			echo >&2
			echo "Option --old               will build the current NetBSD compiler" >&2
			echo "Option --new               will set HAVE_GCC=12 (which is correct while the 10.x -> 12.x transition is on the way) to build the experimental compiler" >&2
			echo "Option --timestamp <epoch> will checkout the most recent commit older or equal than the supplied timestamp" >&2
			echo "Option --force-output <f>  will create the compiler tarball (.xz) with the supplied filename" >&2
			exit 1
			;;
	esac
done

#
# Now build the compiler and create a tarball.
#

# Prepare a clean workdir, fetch sources, get GCC version number and build it.
rm -rf "${workdir}"
mkdir -p "${workdir}"
git clone -q "${nb_git}" "${src_checkout_dir}"
pushd "${src_checkout_dir}"
	# Do checkout based on supplied/current timestamp, notice actual commit timestamp.
	git_rev="$(git rev-list -n 1 --before="@${nb_requested_timestamp}" trunk)"
	git checkout "${git_rev}"
	nb_actual_timestamp="$(git log -1 --format="%as")"

	# Get GCC version number.
	gcc_version="$(cat "external/gpl3/${gcc_dir}/dist/gcc/BASE-VER")"

	# Build all the Compiler / Libs stuff.
	./build.sh -P -U "${build_vars[@]}" -m "${nb_mach}" -a "${nb_arch}" -E -D "${destdir}" -R "${reldir}" -T "${tooldir}" tools libs
popd

# Package newly built compiler.
gcc_name="gcc-${gcc_target}-${gcc_version}-${nb_actual_timestamp}"
gcc_tarball="${workdir}/${gcc_name}.tar.xz"

if [ -z "${forced_output_filename}" ]; then
	gcc_tarball="${gcc_name}.tar.xz"
elif [ -d "${forced_output_filename}" ]; then
	gcc_tarball="${forced_output_filename}/${gcc_name}.tar.xz"
else
	gcc_tarball="${forced_output_filename}"
fi

gcc_destdir="${workdir}/${gcc_name}"
gcc_destdir_sysroot="${gcc_destdir}/${gcc_target}-sysroot"
mkdir -p "${gcc_destdir}"
mkdir -p "${gcc_destdir_sysroot}"
(cd "${tooldir}" && tar cf - .) | (cd "${gcc_destdir}" && tar xf -)
(cd "${destdir}" && tar cf - .) | (cd "${gcc_destdir_sysroot}" && tar xf -)

# Try to use this new compiler.
printf 'int main(int argc, char *argv[]) {return argc*4+3;}\n' > t.c
"${gcc_destdir}/bin/${gcc_target}-gcc" --sysroot="${gcc_destdir_sysroot}" -o t t.c
"${gcc_destdir}/bin/${gcc_target}-objdump" -Sw t

# Create tarball.
export XZ_DEFAULTS="-T 0"
tar Jcf "${gcc_tarball}" -C "${workdir}" "${gcc_name}"

# Maybe copy to S3 storage.
if [ -n "${s3}" ]; then
	aws s3 cp --storage-class REDUCED_REDUNDANCY "${gcc_tarball}" "${s3}"
fi

# State outcome.
echo "ce-build-output:${gcc_tarball}"
echo "ce-build-status:OK"
