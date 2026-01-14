#!/bin/bash
#
# Build build-machine (macOS) tools needed during cross builds, without
# disturbing the existing iOS (device) build artifacts.
#
# Today we mainly need:
#   - libgnu.a (host / macOS) to link host tools
#   - make-docfile (host / macOS) to generate globals.h (and etc/DOC)
#
# Why: target (iOS) binaries like make-docfile cannot be executed on macOS,
# so we must build a host copy and run it on the build machine.
#
# Usage:
#   ./iPad/build-host-tools.sh            # build host make-docfile
#   ./iPad/build-host-tools.sh --globals  # also generate GnuEmacs/src/globals.h
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GNUEMACS_DIR="${ROOT_DIR}/GnuEmacs"
HOST_BUILD_DIR="${GNUEMACS_DIR}/build-host"

DO_GLOBALS=0
if [[ "${1-}" == "--globals" ]]; then
  DO_GLOBALS=1
elif [[ -n "${1-}" ]]; then
  echo "Usage: $0 [--globals]" >&2
  exit 2
fi

if [[ ! -d "${GNUEMACS_DIR}" ]]; then
  echo "Error: GnuEmacs directory not found: ${GNUEMACS_DIR}" >&2
  exit 1
fi

mkdir -p "${HOST_BUILD_DIR}"

echo "==> Host build dir: ${HOST_BUILD_DIR}"

if [[ ! -f "${HOST_BUILD_DIR}/config.status" ]]; then
  echo "==> Configuring host build (macOS) ..."
  cd "${HOST_BUILD_DIR}"

  # Minimal-ish configuration for host tools.
  # (We are not building Emacs.app here; only libgnu + make-docfile.)
  "${GNUEMACS_DIR}/configure" \
    --without-ns \
    --with-x=no \
    --with-pgtk=no \
    --with-x-toolkit=no \
    CC=clang
else
  echo "==> Host build already configured."
fi

echo "==> Building host libgnu.a ..."
make -C "${HOST_BUILD_DIR}/lib" libgnu.a

echo "==> Building host make-docfile ..."
make -C "${HOST_BUILD_DIR}/lib-src" make-docfile

if [[ "${DO_GLOBALS}" -ne 1 ]]; then
  echo "==> Done."
  exit 0
fi

echo "==> Generating globals.h using host make-docfile ..."

# We reuse the exact object list that the (target/iOS) src/Makefile would pass
# to make-docfile, but we run the HOST make-docfile binary.
#
# This avoids guessing the platform-conditional object list.
MAKE_DRYRUN_LINE="$(
  cd "${GNUEMACS_DIR}/src" && \
  make -n globals.h 2>/dev/null | grep -E '/make-docfile .* -g ' | head -1 || true
)"

if [[ -z "${MAKE_DRYRUN_LINE}" ]]; then
  echo "Error: could not extract make-docfile invocation from ${GNUEMACS_DIR}/src/Makefile" >&2
  echo "Hint: ensure target configure has produced GnuEmacs/src/Makefile" >&2
  exit 1
fi

# Extract the arguments after "-g" and before redirection (">").
OBJ_LIST="$(
  python3 - <<'PY' "${MAKE_DRYRUN_LINE}"
import re, sys
line = sys.argv[1]
# Strip redirection.
line = line.split('>')[0].strip()
m = re.search(r'\s-g\s+(.*)$', line)
if not m:
  sys.exit(1)
args = m.group(1).strip().split()
print("\n".join(args))
PY
)"

HOST_MAKE_DOCFILE="${HOST_BUILD_DIR}/lib-src/make-docfile"
MOVE_IF_CHANGE="${GNUEMACS_DIR}/build-aux/move-if-change"
OUT_DIR="${GNUEMACS_DIR}/src"

if [[ ! -x "${HOST_MAKE_DOCFILE}" ]]; then
  echo "Error: host make-docfile not found/executable: ${HOST_MAKE_DOCFILE}" >&2
  exit 1
fi
if [[ ! -x "${MOVE_IF_CHANGE}" ]]; then
  echo "Error: move-if-change not found/executable: ${MOVE_IF_CHANGE}" >&2
  exit 1
fi

TMP="${OUT_DIR}/globals.tmp"
OUT="${OUT_DIR}/globals.h"

cd "${OUT_DIR}"
${HOST_MAKE_DOCFILE} -d "${OUT_DIR}" -g ${OBJ_LIST} > "${TMP}"
${MOVE_IF_CHANGE} "${TMP}" "${OUT}"

echo "==> Generated: ${OUT}"

