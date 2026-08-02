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
  emacs30: Build Emacs v30 (v30.2)
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

# Build Emacs 30 (v30.2)
build_emacs30() {
    echo "Run ${FUNCNAME[0]}"

    declare -r pkgname="emacs"
    declare pkgver="30.2"
    declare -i pkgrel=1
    declare -r sha256sum="b3f36f18a6dd2715713370166257de2fae01f9d38cfe878ced9b1e6ded5befd9"

    mkdir -p ${srcdir}
    cd ${srcdir}

    # Use the official tarball, not the emacs-mirror git tree: git checkouts
    # lack a generated `configure` and require autogen.sh, which hurts
    # reproducibility. See docs/roadmap.md Phase 0.
    curl -LO https://ftp.gnu.org/gnu/emacs/${pkgname}-${pkgver}.tar.xz
    if test -e ns-inline-patch; then
        rm -rf ns-inline-patch
    fi
    git clone --depth 1 https://github.com/takaxp/ns-inline-patch.git

    checksum ${pkgname}-${pkgver}.tar.xz\
             "${sha256sum}"
    if test $? -ne 0; then
        echo "Unmatch sha256sum"
        exit -1
    fi

    # emacs-29.1-inline.patch is the version the upstream README lists as
    # applicable to Emacs 30.x. It creates src/macim.[hm] on its own, so
    # unlike the old 26.3 setup it does not need 04-macos-big-sur.patch
    # as a prerequisite. Confirmed on real hardware (M-x mac-ime-toggle
    # works) before this was wired in. See docs/roadmap.md Phase 0 (0-A).
    checksum ns-inline-patch/emacs-29.1-inline.patch\
             "57dfd88aecf8366b561421db5b7828c9475b9cfb61743883a6296223cff82e2a"
    if test $? -ne 0; then
        echo "Unmatch sha256sum"
        exit -1
    fi

    tar Jxfv ${pkgname}-${pkgver}.tar.xz
    cd ${pkgname}-${pkgver}
    patch -p1 -i ../../00-bump-copyright-year.patch
    patch -p1 -i ../../01-remove-blessmail.patch
    patch -p1 -i ../../03-bump-emacs-version.patch
    patch -p1 -i ../ns-inline-patch/emacs-29.1-inline.patch

    ./autogen.sh

    # Why use without-jpeg, without-lcms2 and without-gnutls?
    # Reason: https://github.com/hiroakit/emacs-on-apple/issues/2
    # Carried over unverified for v30.2; re-check on real hardware before
    # dropping. See docs/roadmap.md Phase 0 (0-C).
    ./configure CC=clang\
                --with-ns\
                --with-modules\
                --without-x\
                --without-selinux\
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
    "emacs30")
        clean && build_emacs30
        exit 0
        ;;
    *)
        echo "Unknown command '${COMMAND}'\n"
        help
        exit 1
        ;;
esac
