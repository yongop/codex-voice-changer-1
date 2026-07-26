#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${1:-release}"
APP_NAME="Codex Voice Changer 1"
APP_DIR="${PROJECT_DIR}/dist/${APP_NAME}.app"
EXECUTABLE="${PROJECT_DIR}/.build/${CONFIGURATION}/CodexVoiceChanger1"

cd "${PROJECT_DIR}"
swift build -c "${CONFIGURATION}" --product CodexVoiceChanger1

if [[ -d "${APP_DIR}" ]]; then
    rm -rf "${APP_DIR}"
fi
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
mkdir -p "${APP_DIR}/Contents/Resources/Models"

install -m 755 "${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/CodexVoiceChanger1"
install -m 644 "${PROJECT_DIR}/Config/Info.plist" "${APP_DIR}/Contents/Info.plist"
ditto \
    "${PROJECT_DIR}/ThirdPartyLicenses" \
    "${APP_DIR}/Contents/Resources/ThirdPartyLicenses"
install -m 644 \
    "${PROJECT_DIR}/Resources/Models/TSUKUYOMI_RVC_MODEL_CARD.md" \
    "${APP_DIR}/Contents/Resources/Models/TSUKUYOMI_RVC_MODEL_CARD.md"
install -m 644 \
    "${PROJECT_DIR}/Resources/Models/TSUKUYOMI_RVC_MANIFEST.json" \
    "${APP_DIR}/Contents/Resources/Models/TSUKUYOMI_RVC_MANIFEST.json"
"${PROJECT_DIR}/Scripts/package-rvc-runtime.sh" \
    "${APP_DIR}/Contents/Resources/RVC"

plutil -lint "${APP_DIR}/Contents/Info.plist"
codesign --force --sign - --timestamp=none "${APP_DIR}"
codesign --verify --strict --verbose=2 "${APP_DIR}"

echo "${APP_DIR}"
