#!/bin/bash
# compile musl static apps

#set -x
. ./build.conf
if [ "$BUILD_TARBALL" ] ; then
	. ./${BUILD_TARBALL}
fi
export MKFLG
export MWD=`pwd`
export TARGET_TRIPLET=

ARCH_LIST="i686 x86_64 arm aarch64"

SITE=https://musl.cc

X86_CC=i686-linux-musl-cross.tgz
X86_64_CC=x86_64-linux-musl-cross.tgz
ARM_CC=armv6-linux-musleabihf-cross.tgz #armv6
ARM64_CC=aarch64-linux-musl-cross.tgz

INITRD_STATIC='initrd_progs-20191121-static.tar.xz'
PREBUILT_BINARIES="no prebuilt binaries"
#aarch64_PREBUILT_BINARIES=
#arm_PREBUILT_BINARIES=
#i686_PREBUILT_BINARIES=
#x86_64_PREBUILT_BINARIES=

TARGET_TRIPLET_x86="i686-linux-musl"
TARGET_TRIPLET_x86_64="x86_64-linux-musl"
TARGET_TRIPLET_arm="armv6-linux-musleabihf"
TARGET_TRIPLET_arm64="aarch64-linux-musl"

ARCH=`uname -m`
OS_ARCH=$ARCH

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function get_initrd_progs() {
	local var=INITRD_PROGS
	[ "$1" = "-pkg" ] && { var=PACKAGES ; shift ; }
	local arch=$1
	[ "$arch" = "" ] && arch=`uname -m`
	case "$arch" in i?86) arch="x86" ;; esac
	case "$arch" in arm*) arch='arm' ;; esac
	eval echo \$$var \$${var}_${arch} #ex: $PACKAGES $PACKAGES_x86, $INITRD_PROGS $INITRD_PROGS_x86
}

# build.sh tarball [build.conf] [arch]
case "$1" in release|tarball) #this contains the $PREBUILT_BINARIES
	echo "If you made changes then don't forget to remove all 00_* directories first"
	shift
	if [ -f "$1" ] ; then
		export BUILD_TARBALL=$1
		shift
	fi
	sleep 4
	if [ -n "$1" ]; then
		$0 -nord -auto -arch $2
		pkgx=initrd_progs-${2}-$(date "+%Y%m%d")-static.tar.xz
	else
		for a in ${ARCH_LIST} ; do $0 -nord -auto -arch $a || exit 1 ; done
		pkgx=initrd_progs-$(date "+%Y%m%d")-static.tar.xz
	fi
	echo -e "\n\n\n*** Creating $pkgx"
	while read ARCH ; do
		for PROG in $(get_initrd_progs ${ARCH#00_}) ; do
			case $PROG in ""|'#'*) continue ;; esac
			progs2tar+=" ${ARCH}/bin/${PROG}"
		done
	done <<< "$(ls -d 00_*)"
	tar -Jcf $pkgx ${progs2tar}
	echo "Done."
	exit
esac

case "$1" in w|w_apps|c)
	for a in ${ARCH_LIST} ; do $0 -nord -auto -arch $a -pkg w_apps ; done
	exit
esac

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function fatal_error() { echo -e "$@" ; exit 1 ; }
function exit_error() { echo -e "$@" ; exit 1 ; }

help_msg() {
	echo "Build static apps in the queue defined in build.conf

Usage:
  $0 [-arch target] [options]

[-arch target] is only required if cross-compiling [default for x86]

Options:
  -pkg pkg    : compile specific pkg only
  -all        : force building all *_static pkgs
  -arch target: compile for target arch
  -sysgcc     : use system gcc
  -download   : download pkgs only, this overrides other options
  -specs file : DISTRO_SPECS file to use
  -prebuilt   : use prebuilt binaries
  -auto       : don't prompt for input
  -help       : show help and exit

  Valid <targets> for -arch:
      ${ARCH_LIST} default
"
}

## defaults (other defaults are in build.conf) ##
USE_SYS_GCC=no
CROSS_COMPILE=no
FORCE_BUILD_ALL=no
export DLD_ONLY=no
INITRD_CREATE=yes
INITRD_COMP=gz

## command line ##
while [ "$1" ] ; do
	case $1 in
		-sysgcc)   USE_SYS_GCC=yes     ; USE_PREBUILT=no; shift ;;
		-all)      FORCE_BUILD_ALL=yes ; shift ;;
		-download) DLD_ONLY=yes        ; shift ;;
		-prebuilt) USE_PREBUILT=yes    ; shift ;;
		-nord)     INITRD_CREATE=no    ; shift ;;
		-auto)     PROMPT=no           ; shift ;;
		-v)        V=-v                ; shift ;;
		-pkg)      BUILD_PKG="$2"      ; shift 2
			       [ "$BUILD_PKG" = "" ] && fatal_error "$0 -pkg: Specify a pkg to compile" ;;
		-pet)      export CREATE_PET=1
			       shift
			       [ "$1" ] && [[ $1 != -* ]] && BUILD_PKG="$1" && shift ;;
		-a|-arch)  TARGET_ARCH="$2"    ; shift 2
			       [ "$TARGET_ARCH" = "" ] && fatal_error "$0 -arch: Specify a target arch" ;;
		-specs)    DISTRO_SPECS="$2"   ; shift 2
			       [ ! -f "$DISTRO_SPECS" ] && fatal_error "$0 -specs: '${DISTRO_SPECS}' is not a regular file" ;;
	-h|-help|--help) help_msg ; exit ;;
		-clean)
			echo -e "Press P and hit enter to proceed, any other combination to cancel.." ; read zz
			case $zz in p|P) echo rm -rf initrd.[gx]z initrd_progs-*.tar.* ZZ_initrd-expanded 00_* 0sources *-linux-musl* cross-compiler* ;; esac
			exit
			;;
		*)
			echo "Unrecognized option: $1"
			shift
			;;
	esac
done

if ! [ -d pkg ] ; then
	USE_PREBUILT=yes
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function use_prebuilt_binaries()
{
	[ ! "$PREBUILT_BINARIES" ] && exit_error "No prebuilt binaries"
	case "$TARGET_ARCH" in
		i686)    [ -n "$i686_PREBUILT_BINARIES" ]    && PREBUILT_BINARIES=${i686_PREBUILT_BINARIES} ;;
		x86_64)  [ -n "$x86_64_PREBUILT_BINARIES" ]  && PREBUILT_BINARIES=${x86_64_PREBUILT_BINARIES} ;;
		arm)     [ -n "$arm_PREBUILT_BINARIES" ]     && PREBUILT_BINARIES=${arm_PREBUILT_BINARIES} ;;
		aarch64) [ -n "$aarch64_PREBUILT_BINARIES" ] && PREBUILT_BINARIES=${aarch64_PREBUILT_BINARIES} ;;
	esac
	zfile=0sources/${PREBUILT_BINARIES##*/}
	if [ -f "$zfile" ] ; then
		#verify file integrity
		tar -tf "$zfile" &>/dev/null || rm -f "$zfile"
	fi
	if [ ! -f "$zfile" ] ; then
		mkdir -p 0sources
		wget -P 0sources --no-check-certificate "$PREBUILT_BINARIES"
		if [ $? -ne 0 ] ; then
			rm -f "$zfile"
			exit_error "ERROR downloading $zfile"
		fi
	fi
	echo "* Extracting ${zfile##*/}..."
	tar -xf "$zfile" || {
		rm -f "$zfile"
		exit_error "ERROR extracting $zfile"
	}
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function select_target_arch()
{
	[ "$CROSS_COMPILE" = "no" -a "$USE_PREBUILT" = "no" ] && return
	[ "$USE_SYS_GCC" = "yes" ] && return
	if ! [ "$TARGET_ARCH" ] ; then
		echo -e "\nMust specify target arch: -a <arch>"
		echo "  <arch> can be one of these: $ARCH_LIST default"
		echo -e "\nSee also: $0 --help"
		exit 1
	fi
	#-- defaults
	case $TARGET_ARCH in
		default) TARGET_ARCH=${ARCH} ;;
		x86|i?86)TARGET_ARCH=i686    ;;
		arm64)   TARGET_ARCH=aarch64 ;;
		arm*)    TARGET_ARCH=arm     ;;
	esac
	VALID_TARGET_ARCH=no
	for a in $ARCH_LIST ; do
		if [ "$TARGET_ARCH" = "$a" ] ; then
			VALID_TARGET_ARCH=yes
			ARCH=$a
			break
		fi
	done
	if [ "$VALID_TARGET_ARCH" = "no" ] ; then
		exit_error "Invalid target arch: $TARGET_ARCH"
	fi
	# using prebuilt binaries: echo $ARCH and return
	[ "$USE_PREBUILT" = "yes" ] && echo "Arch: $ARCH" && return
	#--
	case $ARCH in
		i*86)    CC_TARBALL=$X86_CC    ; TARGET_TRIPLET=${TARGET_TRIPLET_x86} ;;
		x86_64)  CC_TARBALL=$X86_64_CC ; TARGET_TRIPLET=${TARGET_TRIPLET_x86_64} ;;
		arm*)    CC_TARBALL=$ARM_CC    ; TARGET_TRIPLET=${TARGET_TRIPLET_arm} ;;
		aarch64) CC_TARBALL=$ARM64_CC  ; TARGET_TRIPLET=${TARGET_TRIPLET_arm64} ;;
	esac
	if [ -z "$CC_TARBALL" ] ; then
		exit_error "Cross compiler for $TARGET_ARCH is not available at the moment..."
	fi
	#--
	echo "Arch: $ARCH"
	sleep 1.5
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function set_gcc()
{
	if ! which make &>/dev/null ; then
		fatal_error echo "It looks like development tools are not installed.. stopping"
	fi
	if [ "$USE_SYS_GCC" = "no" ] ; then
		case $ARCH in
			i?86|x86_64) CROSS_COMPILE=yes ;;
			*) USE_SYS_GCC=yes ;; # use system gcc in a non-x86 system
		esac
	fi
	if [ "$USE_SYS_GCC" = "yes" ] ; then
		which gcc &>/dev/null || fatal_error "No gcc, aborting..."
		echo -e "\nBuilding in: $ARCH"
		echo -e "\n* Using system gcc\n"
		sleep 1.5
	fi
}


function setup_cross_compiler()
{
	[ "$CROSS_COMPILE" = "no" ] && return
	CC_DIR=$(echo ${CC_TARBALL} | cut -f 1 -d '.')
	echo
	## download
	if [ ! -f "0sources/${CC_TARBALL}" ];then
		echo "Download cross compiler"
		[ "$PROMPT" = "yes" ] && echo -n "Press enter to continue, CTRL-C to cancel..." && read zzz
		wget -c -P 0sources ${SITE}/${CC_TARBALL}
		if [ $? -ne 0 ] ; then
			rm -rf ${CC_DIR}
			exit_error "failed to download ${CC_TARBALL}"
		fi
	else
		if [ "$DLD_ONLY" = "yes" ] ; then
			echo "Already downloaded ${CC_TARBALL}"
		fi
	fi
	[ "$DLD_ONLY" = "yes" ] && return
	## extract
	if [ ! -d "$CC_DIR" ] ; then
		tar --directory=$PWD -xaf 0sources/${CC_TARBALL}
		if [ $? -ne 0 ] ; then
			rm -rf ${CC_DIR}
			rm -fv 0sources/${CC_TARBALL}
			exit_error "failed to extract ${CC_TARBALL}"
		fi
	fi
	#--
	if [ ! -d "$CC_DIR" ] ; then
		exit_error "$CC_DIR not found"
	fi
	case $OS_ARCH in i*86)
		_gcc=$(find $CC_DIR/bin -name '*gcc' | head -1)
		if [ ! -z $_gcc ] && file $_gcc | grep '64-bit' ; then
			exit_error "\nERROR: trying to use a 64-bit (static) cross compiler in a 32-bit system"
		fi
	esac
	echo -e "\nUsing cross compiler\n"
	export OVERRIDE_ARCH=${ARCH}  # = cross compiling # see ./func
	export XPATH=${PWD}/${CC_DIR} # = cross compiling # see ./func
	CC_INSTALL_DIR=$(echo ${XPATH}/*linux-musl*)
	if ! [ -d "$CC_INSTALL_DIR" ] ; then
		CC_INSTALL_DIR=${XPATH}
	fi
	export CC_INSTALL_DIR
}

#--------------

function check_bin()
{
	case $init_pkg in
		""|'#'*) continue ;;
		coreutils_static) static_bins='cp' ;;
		dosfstools_static) static_bins='fsck.fat' ;;
		e2fsprogs_static) static_bins='e2fsck resize2fs' ;;
		exfat-utils_static) static_bins='exfatfsck' ;;
		f2fs-tools_static) static_bins='fsck.f2fs'  ;;
		fuse-exfat_static) static_bins='mount.exfat-fuse' ;;
		findutils_static) static_bins='find' ;;
		util-linux_static) static_bins='losetup' ;;
		*) static_bins=${init_pkg%_*} ;;
	esac
	for sbin in ${static_bins} ; do
		if ! [ -f ./00_${ARCH}/bin/${sbin} ] ; then
			return 1
		fi
	done
}


function build_pkgs()
{
	rm -f .fatal
	mkdir -p 00_${ARCH}/bin 00_${ARCH}/log 0sources
	if [ "$DLD_ONLY" = "no" ] ; then
		echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
		echo -e "\nbuilding packages for the initial ram disk\n"
		sleep 1
	fi
	#--
	if [ "$FORCE_BUILD_ALL" = "yes" ] ; then
		PACKAGES=$(find pkg -maxdepth 1 -type d -name '*_static' | sed 's|.*/||' | sort)
	elif [ "$BUILD_PKG" != "" ] ; then
		PACKAGES="$BUILD_PKG"
	else
		PACKAGES=$(get_initrd_progs -pkg $ARCH)
	fi
	#--
	for init_pkg in ${PACKAGES}
	do
		case $init_pkg in ""|'#'*) continue ;; esac
		if [ -f .fatal ] ; then
			rm -f .fatal_error
			exit_error "Exiting.."
		fi
		if [ -d pkg/"${init_pkg}_static" ] ; then
			init_pkg=${init_pkg}_static
		fi
		if [ "$DLD_ONLY" = "no" -a ! "$CREATE_PET" ] ; then
			check_bin $init_pkg
			[ $? -eq 0 ] && { echo "$init_pkg exists ... skipping" ; continue ; }
			echo -e "\n+=============================================================================+"
			echo -e "\nbuilding $init_pkg"
			sleep 1
		fi
		#--
		cd pkg/${init_pkg}
		mkdir -p ${MWD}/00_${ARCH}/log
		sh ${init_pkg}.petbuild 2>&1 | tee ${MWD}/00_${ARCH}/log/${init_pkg}build.log
		cd ${MWD}
		[ "$DLD_ONLY" = "yes" ] && continue
		if [ ! "$CREATE_PET" ] ; then
			check_bin $init_pkg || exit_error "target binary does not exist..."
		fi
	done
	rm -f .fatal
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


function generate_initrd()
{
	[ "$CREATE_PET" ] && return
	[ "$DLD_ONLY" = "yes" ] && return
	[ "$INITRD_CREATE" = "no" ] && return
	INITRD_FILE="initrd.gz"

	if [ "$USE_PREBUILT" = "no" ] ; then
		[ "$PROMPT" = "yes" ] && echo -en "\nPress enter to create ${INITRD_FILE}, CTRL-C to end here.." && read zzz
		echo -e "\n============================================"
		echo "Now creating the initial ramdisk (${INITRD_FILE})"
		echo -e "=============================================\n"
	fi

	rm -rf ZZ_initrd-expanded
	mkdir -p ZZ_initrd-expanded
	cp -rf 0initrd/* ZZ_initrd-expanded
	cd ZZ_initrd-expanded

	for PROG in $(get_initrd_progs ${ARCH}) ; do
		case $PROG in ""|'#'*) continue ;; esac
		if [ -f ../00_${ARCH}/bin/${PROG} ] ; then
			file ../00_${ARCH}/bin/${PROG} | grep -E 'dynamically|shared' && exit 1
			cp -a ${V} --remove-destination ../00_${ARCH}/bin/${PROG} bin
		else
			exit_error "00_${ARCH}/bin/${PROG} not found"
		fi
	done

	echo
	if [ ! -f "$DISTRO_SPECS" -a -f ../DISTRO_SPECS ] ; then
		DISTRO_SPECS='../DISTRO_SPECS'
	fi
	if [ ! -f "$DISTRO_SPECS" -a ! -f ../0initrd/DISTRO_SPECS ] ; then
		[ -f /etc/DISTRO_SPECS ] && DISTRO_SPECS='/etc/DISTRO_SPECS'
		[ -f /initrd/DISTRO_SPECS ] && DISTRO_SPECS='/initrd/DISTRO_SPECS'
		. /etc/rc.d/PUPSTATE #PUPMODE
	fi
	[ -f "$DISTRO_SPECS" ] && cp -f ${V} "${DISTRO_SPECS}" .
	[ -x ../init ] && cp -f ${V} ../init .

	. ./DISTRO_SPECS

	find . | cpio -o -H newc > ../initrd 2>/dev/null
	cd ..
	gzip -f initrd
	[ $? -eq 0 ] || exit_error "ERROR"

	echo -e "\n***        INITRD: ${INITRD_FILE} [${ARCH}]"
	echo -e "*** /DISTRO_SPECS: ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_TARGETARCH}"

	[ "$USE_PREBUILT" = "yes" ] && return
	echo -e "\n@@ -- You can inspect ZZ_initrd-expanded to see the final results -- @@"
	echo -e "Finished.\n"
}

###############################################
#                 MAIN
###############################################

if [ "$USE_PREBUILT" = "yes" ] ; then
	select_target_arch
	use_prebuilt_binaries
else
	V="-v"
	set_gcc
	select_target_arch
	setup_cross_compiler
	build_pkgs
	cd ${MWD}
fi

generate_initrd

### END ###
