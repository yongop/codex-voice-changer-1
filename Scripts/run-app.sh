#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${PROJECT_DIR}/dist/Codex Voice Changer 1.app"

if [[ ! -d "${APP_DIR}" ]]; then
    "${SCRIPT_DIR}/build-app.sh"
fi

open "${APP_DIR}"
