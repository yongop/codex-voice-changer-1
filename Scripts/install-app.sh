#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${1:-release}"
APP_NAME="Codex Voice Changer 1"
ARCHIVE_PATH="${PROJECT_DIR}/dist/${APP_NAME}.app.zip"
INSTALL_DIR="${CVS_APP_INSTALL_DIR:-/Applications}"
FINAL_APP_DIR="${INSTALL_DIR}/${APP_NAME}.app"
INCOMING_APP_DIR="${INSTALL_DIR}/.${APP_NAME}.incoming.$$.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-voice-changer-install.XXXXXX")"
STAGED_APP_DIR="${STAGING_DIR}/${APP_NAME}.app"

cleanup() {
    rm -rf "${STAGING_DIR}"
    rm -rf "${INCOMING_APP_DIR}"
}
trap cleanup EXIT

mkdir -p "${INSTALL_DIR}"
if [[ ! -w "${INSTALL_DIR}" ]]; then
    print -u2 "Install directory is not writable: ${INSTALL_DIR}"
    print -u2 "Set CVS_APP_INSTALL_DIR to a writable Applications directory."
    exit 73
fi

"${SCRIPT_DIR}/build-app.sh" "${CONFIGURATION}"

ditto -x -k "${ARCHIVE_PATH}" "${STAGING_DIR}"
xattr -cr "${STAGED_APP_DIR}"
codesign --verify --strict --verbose=2 "${STAGED_APP_DIR}"

ditto --norsrc --noextattr "${STAGED_APP_DIR}" "${INCOMING_APP_DIR}"
xattr -cr "${INCOMING_APP_DIR}"
codesign --verify --strict --verbose=2 "${INCOMING_APP_DIR}"

if [[ -e "${FINAL_APP_DIR}" || -L "${FINAL_APP_DIR}" ]]; then
    rm -rf "${FINAL_APP_DIR}"
fi
mv "${INCOMING_APP_DIR}" "${FINAL_APP_DIR}"
xattr -cr "${FINAL_APP_DIR}"
codesign --verify --strict --verbose=2 "${FINAL_APP_DIR}"

echo "${FINAL_APP_DIR}"
