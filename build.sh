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
declare -r BASE_PATH="$(cd "$(dirname "$0")" && pwd)"

# Keep the source version and checksum in one file. Bitrise also hashes this
# file for its download-cache key, so changing either value invalidates the
# cached archive automatically.
source "${BASE_PATH}/emacs-source.lock"
readonly EMACS_VERSION EMACS_SHA256

# Show usage.
help() {
cat <<EOF
Help: sh $0 command
command:
  emacs:   Build GNU Emacs ${EMACS_VERSION}
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
        return 1
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

# Build the pinned GNU Emacs release
build_emacs() {
    echo "Run ${FUNCNAME[0]}"

    declare -r pkgname="emacs"
    declare -r pkgver="${EMACS_VERSION}"
    declare -i pkgrel=1
    declare -r sha256sum="${EMACS_SHA256}"
    declare -r archive="${pkgname}-${pkgver}.tar.xz"
    declare -r cachedir="../.cache/downloads"
    declare -r cached_archive="${cachedir}/${archive}"

    mkdir -p ${srcdir}
    cd ${srcdir}

    # Use the official tarball, not the emacs-mirror git tree: git checkouts
    # lack a generated `configure` and require autogen.sh, which hurts
    # reproducibility. See docs/roadmap.md Phase 0.
    mkdir -p "${cachedir}"
    if test -f "${cached_archive}" && \
       ! checksum "${cached_archive}" "${sha256sum}"; then
        echo "Discard cached archive with unexpected sha256sum"
        rm -f "${cached_archive}"
    fi
    if ! test -f "${cached_archive}"; then
        curl --fail --location \
             --output "${cached_archive}.tmp" \
             "https://ftp.gnu.org/gnu/emacs/${archive}"
        checksum "${cached_archive}.tmp" "${sha256sum}"
        mv "${cached_archive}.tmp" "${cached_archive}"
    fi
    checksum "${cached_archive}" "${sha256sum}"

    # Pin the upstream inline IME patch whose NS event table matches Emacs 31.
    declare -r inline_revision="c858a26201f57b98da5bb0b21d0ff42e5ef27a67"
    curl --fail --location --output ns-inline.patch \
         "https://raw.githubusercontent.com/takaxp/ns-inline-patch/${inline_revision}/emacs-head-inline.patch"
    checksum ns-inline.patch \
             "1c77650e1eb5f661efc3fab02a9c8491915e5e65a40caf1503aff0e222c1a613"

    tar Jxfv "${cached_archive}"
    cd ${pkgname}-${pkgver}
    patch -t -F 0 -p1 -i ../../01-remove-blessmail.patch
    patch -t -F 0 -p1 -i ../../03-bump-emacs-version.patch
    patch -t -F 0 -p1 -i ../../05-info-plist-lifecycle.patch
    patch -t -p1 -i ../ns-inline.patch
    patch -t -F 0 -p1 -i ../../06-macos-workspace-notifications.patch

    ./autogen.sh

    # Why use without-jpeg, without-lcms2 and without-gnutls?
    # Reason: https://github.com/hiroakit/emacs-on-apple/issues/2
    # Carried over unverified for v30.2; re-check on real hardware before
    # dropping. See docs/roadmap.md Phase 0 (0-C).
    ./configure CC="${CC:-clang}"\
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
    "emacs"|"emacs30")
        clean && build_emacs
        exit 0
        ;;
    *)
        echo "Unknown command '${COMMAND}'\n"
        help
        exit 1
        ;;
esac
