#!/bin/bash

# Emacs builder

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
    rm -rf ${srcdir}
    rm -rf ${pkgdir}        
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
    declare -r filesum=`shasum -a 256 ${pkgname}-${pkgver}.tar.xz`
    if test ${filesum} != ${sha256sum}; then
        echo "Unmatch sha256sum"
        exit -1
    fi
    
    tar Jxfv ${pkgname}-${pkgver}.tar.xz
    cd ${pkgname}-${pkgver}
    patch -p1 -i ../../01-remove-blessmail.patch
    patch -p1 -i ../../02-provisional-emacs26.3-unexmacosx.c.patch

    ./autogen.sh
    ./configure CC=clang\
                --with-ns\
                --with-modules\
                --without-x\
                --without-selinux\
                --without-makeinfo\
                --without-mail-unlink\
                --without-mailhost\
                --without-pop\
                --without-mailutils

    make bootstrap
    make install

    cd ../../
    mkdir -p ${pkgdir}
    mv ${srcdir}/${pkgname}-${pkgver}/nextstep/Emacs.app ./${pkgdir}
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
    "emacs26")
        build_emacs26
        exit 0
        ;;
    *)
        echo "Unknown command '${COMMAND}'\n"
        help
        exit 1
        ;;
esac
