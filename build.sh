#!/bin/bash

# A build script to make GNU Emacs on macOS.
# Copyright (C) 2020 Hiroaki ENDOH
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -o pipefail
set -e

declare -r pkgdir="pkg"
declare -r srcdir="src"

# Show usage.
help() {
cat <<EOF
Help: sh $0 command
command:
  emacs26: Build Emacs v26
  clean:   Remove pkgdir, srcdir
EOF
}

# Validate input arguments.
# $# return total count of arguments.
if [ "$#" -eq 0 -o "$#" -gt 2 ]; then
    help
    exit 1
fi

clean() {
    echo "Run ${FUNCNAME[0]}"

    rm -rf ${srcdir}
    rm -rf ${pkgdir}
}

checksum() {
    declare -r filesum=`shasum -a 256 ${1} | awk '{print $1}'`
    declare -r sha256sum=${2}
    if test ${filesum} != ${sha256sum}; then
        echo "Unmatch sha256sum"
        exit -1
    fi
}

codesign() {
    echo "Run ${FUNCNAME[0]}"

    if [ "$#" -eq 0 -o "$#" -gt 1 ]; then
        echo "Require Developer ID. Check Keychain.app on your Mac."
        exit 1
    fi

    declare DEVELOPER_ID="$1"

    xcrun codesign --verify \
                   --sign "Developer ID Application: ${DEVELOPER_ID}" \
                   --force \
                   --verbose \
                   --deep \
                   --options runtime \
                   --entitlements entitlements.plist \
                   --timestamp \
                   ./pkg/Applications/Emacs/Emacs.app
}

# Build Emacs 26
build_emacs26() {
    echo "Run ${FUNCNAME[0]}"

    declare -r pkgname="emacs"
    declare pkgver="26.3"
    declare -i pkgrel=1
    declare -r sha256sum="4d90e6751ad8967822c6e092db07466b9d383ef1653feb2f95c93e7de66d3485"

    mkdir -p ${srcdir}
    cd ${srcdir}

    curl -LO https://ftp.gnu.org/gnu/emacs/${pkgname}-${pkgver}.tar.xz
    if test -e ns-inline-patch; then
        rm -rf ns-inline-patch
    fi
    git clone --depth 1 https://github.com/takaxp/ns-inline-patch.git

    checksum ${pkgname}-${pkgver}.tar.xz\
             "4d90e6751ad8967822c6e092db07466b9d383ef1653feb2f95c93e7de66d3485"
    if test $? -ne 0; then
        echo "Unmatch sha256sum"
        exit -1
    fi

    checksum ns-inline-patch/emacs-25.2-inline.patch\
             "36cc154a9bad2f8a1927bc87b4c89183fb25f2e3bbe04d73690bf947f59639d8"
    if test $? -ne 0; then
        echo "Unmatch sha256sum"
        exit -1
    fi

    tar Jxfv ${pkgname}-${pkgver}.tar.xz
    cd ${pkgname}-${pkgver}
    patch -p1 -i ../../00-bump-copyright-year.patch
    patch -p1 -i ../../01-remove-blessmail.patch
    patch -p1 -i ../../02-provisional-emacs26.3-unexmacosx.c.patch
    patch -p1 -i ../../03-bump-emacs-version.patch
    patch -p1 -i ../../04-macos-big-sur.patch
    patch -p1 -i ../ns-inline-patch/emacs-25.2-inline.patch

    ./autogen.sh

    # Why use without-jpeg, without-lcms2 and without-gnutls?
    # Reason: https://github.com/hiroakit/emacs-on-apple/issues/2
    ./configure CC=clang\
                --with-ns\
                --with-modules\
                --without-x\
                --without-selinux\
                --without-makeinfo\
                --without-mail-unlink\
                --without-mailhost\
                --without-pop\
                --without-mailutils\
                --without-jpeg\
                --without-lcms2\
                --without-gnutls

    make bootstrap
    make install

    cd ../../
    mkdir -p ./${pkgdir}/Applications/Emacs
    cp -r ${srcdir}/${pkgname}-${pkgver}/nextstep/Emacs.app ./${pkgdir}/Applications/Emacs
}

build_emacs28() {
    echo "Run ${FUNCNAME[0]}"

    declare -r emacs_pkgname="emacs"
    declare emacs_pkgver="28.0.90"
    declare -r emacs_sha256sum="6f10c72f9358fe1e39c761faf84bc1e5d81fb848f282c95bec34a9a77bc16288"

    mkdir -p ${srcdir}
    cd ${srcdir}

    curl -LO https://alpha.gnu.org/gnu/emacs/pretest/${emacs_pkgname}-${emacs_pkgver}.tar.xz
#    if test -e ns-inline-patch; then
#        rm -rf ns-inline-patch
#    fi
    checksum ${emacs_pkgname}-${emacs_pkgver}.tar.xz ${emacs_sha256sum}
    if test $? -ne 0; then
        echo "Unmatch sha256sum"
        exit -1
    fi

    tar Jxfv ${emacs_pkgname}-${emacs_pkgver}.tar.xz
    cd ${emacs_pkgname}-${emacs_pkgver}
#    patch -p1 -i ../../patches/emacs28/00-bump-copyright-year.patch
    patch -p1 -i ../../patches/emacs28/01_remove-blessmail.patch
    patch -p1 -i ../../patches/emacs28/02-bump-emacs-version.patch
    patch -p1 -i ../../patches/emacs28/10_window-autosave.patch

    ./autogen.sh

    # Why use without-jpeg, without-lcms2 and without-gnutls?
    # Reason: https://github.com/hiroakit/emacs-on-apple/issues/2
    ./configure CC=clang\
                --with-ns\
                --with-modules\
                --without-x\
                --without-selinux\
                --without-makeinfo\
                --without-mail-unlink\
                --without-mailhost\
                --without-pop\
                --without-mailutils\
                --without-jpeg\
                --without-lcms2\
                --without-gnutls

    make bootstrap
    make install

    cd ../../
    mkdir -p ./${pkgdir}/Applications/Emacs
    cp -r ${srcdir}/${emacs_pkgname}-${emacs_pkgver}/nextstep/Emacs.app ./${pkgdir}/Applications/Emacs
}

build_gmp() {
    declare -r pkgname="gmp"
    declare -r pkgver="6.2.1"
    declare -r pkgfile=${pkgname}-${pkgver}.tar.xz
    declare -r WORK_DIR=$HOME/build

    mkdir -p $WORK_DIR/src
    pushd $WORK_DIR/src

    # Get files if needed
    if [ ! -d ${pkgname}-${pkgver} ]; then
        # Download
        if [ ! -e ${pkgfile} ]; then
            curl -LO https://ftp.jaist.ac.jp/pub/GNU/${pkgname}/${pkgfile}
        fi
        if [ ! -e ${pkgfile}.sig ]; then
            curl -LO https://ftp.jaist.ac.jp/pub/GNU/${pkgname}/${pkgfile}.sig
        fi

        # Verify
        # /usr/local/MacGPG2/bin/gpg --verify ${pkgfile}.sig
        # if [ $? -ne 0 ]; then
        #     exit -1
        # fi

        # Unarchive
        tar xzf ${pkgname}-${pkgver}.tar.xz
    fi
    pushd ${pkgname}-${pkgver}

    # Build
    ./configure --prefix=$WORK_DIR\
                --enable-shared\
                --disable-cxx\
                --disable-static\
                --build=`uname -m`-apple-darwin`uname -r`
    make
    make install
    popd
}

build_nettle() {
    declare -r pkgname="nettle"
    declare -r pkgver="3.7.3"
    declare -r pkgfile=${pkgname}-${pkgver}.tar.gz
    declare -r WORK_DIR=$HOME/build

    curl -LO https://ftp.jaist.ac.jp/pub/GNU/nettle/${pkgfile}
    curl -LO https://ftp.jaist.ac.jp/pub/GNU/nettle/${pkgfile}.sig
    
#    /usr/local/MacGPG2/bin/gpg --verify ${pkgname}-${pkgver}.tar.gz.sig
#    if [ $? -ne 0 ]; then
#       exit -1
#    fi
    tar xzf ${pkgfile}
    pushd ${pkgname}-${pkgver}

    PKG_CONFIG_PATH=${WORK_DIR}/lib/pkgconfig    
    ./configure --prefix=$WORK_DIR\
                --disable-cxx\
                --disable-openssl\
                --disable-static\
                --enable-mini-gmp\
                --build=`uname -m`-apple-darwin`uname -r`
    make
    make install
    make check
    popd
}

build_gnutls() {
    declare -r pkgname="gnutls"
    declare -r pkgver="3.7.3"
    declare -r pkgfile=${pkgname}-${pkgver}.tar.xz
    declare -r WORK_DIR=$HOME/build

    mkdir -p $WORK_DIR/src
    pushd $WORK_DIR/src

    # Get files if needed    
    if [ ! -d ${pkgname}-${pkgver} ]; then
        # Download
        if [ ! -e ${pkgfile} ]; then
            curl -LO https://www.gnupg.org/ftp/gcrypt/gnutls/v3.7/${pkgfile}
        fi
        if [ ! -e ${pkgfile}.sig ]; then
            curl -LO https://www.gnupg.org/ftp/gcrypt/gnutls/v3.7/${pkgfile}.sig
        fi

        # Verify
        /usr/local/MacGPG2/bin/gpg --verify ${pkgfile}.sig
        if [ $? -ne 0 ]; then
            exit -1
        fi

        # Unarchive
        tar xzf ${pkgname}-${pkgver}.tar.xz
    fi
    pushd ${pkgname}-${pkgver}

    # Cleanup files if needed
    # if [ -e config.status ]; then
#       make distclean
#       exit 0
#    fi

    # Build
    PKG_CONFIG_PATH=${WORK_DIR}/lib/pkgconfig
    ./configure --prefix=$WORK_DIR\
                --disable-cxx\
                --disable-guile\
                --without-p11-kit\
                --with-included-libtasn1\
                --with-included-unistring\
                --build=`uname -m`-apple-darwin`uname -r`
    make
    make install
    popd
}

build_texinfo() {
    declare -r pkgname="texinfo"
    declare -r pkgver="6.8"
    declare -r pkgfile=${pkgname}-${pkgver}.tar.xz
    declare -r WORK_DIR=$HOME/build

    mkdir -p $WORK_DIR/src
    pushd $WORK_DIR/src

    # Get files if needed    
    if [ ! -d ${pkgname}-${pkgver} ]; then
        # Download
        if [ ! -e ${pkgfile} ]; then
            curl -LO https://ftp.jaist.ac.jp/pub/GNU/texinfo/${pkgfile}
        fi
        if [ ! -e ${pkgfile}.sig ]; then
            curl -LO https://ftp.jaist.ac.jp/pub/GNU/texinfo/${pkgfile}.sig
        fi

        # Verify
        # /usr/local/MacGPG2/bin/gpg --verify ${pkgfile}.sig
        # if [ $? -ne 0 ]; then
        #     exit -1
        # fi

        # Unarchive
        tar xzf ${pkgname}-${pkgver}.tar.xz
    fi
    pushd ${pkgname}-${pkgver}

    ./configure --prefix=$WORK_DIR\
                --build=`uname -m`-apple-darwin`uname -r`
    make
    make install
    popd
}

COMMAND="$1"                 # Using 1st argument as command
BASE_PATH="$(dirname "$0")"  # Calling script location

case "$COMMAND" in
    "help")
        help
        exit 0
        ;;
    "clean")
        clean
        exit 0
        ;;
    "codesign")
        # Require Developer ID at 2nd argument.
        codesign "$2"
        exit 0
        ;;
    "emacs26")
        clean && build_emacs26
        exit 0
        ;;
    "emacs28")
        clean && build_emacs28
        exit 0
        ;;
    "gnutls")
        clean
        rm -rf ~/build
        build_texinfo
        build_gmp
        build_nettle
        build_gnutls
        exit 0
        ;;
    *)
        echo "Unknown command '${COMMAND}'\n"
        help
        exit 1
        ;;
esac
