#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
INSTALL_DIR="${CVS_APP_INSTALL_DIR:-/Applications}"
APP_DIR="${INSTALL_DIR}/Codex Voice Changer 1.app"

if [[ ! -d "${APP_DIR}" ]]; then
    "${SCRIPT_DIR}/install-app.sh"
fi

open "${APP_DIR}"
