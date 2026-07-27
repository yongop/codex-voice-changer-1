#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${1:-release}"
APP_NAME="Codex Voice Changer 1"
DIST_DIR="${PROJECT_DIR}/dist"
ARCHIVE_PATH="${DIST_DIR}/${APP_NAME}.app.zip"
EXECUTABLE="${PROJECT_DIR}/.build/${CONFIGURATION}/CodexVoiceChanger1"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-voice-changer-build.XXXXXX")"
APP_DIR="${STAGING_DIR}/${APP_NAME}.app"
STAGED_ARCHIVE="${STAGING_DIR}/${APP_NAME}.app.zip"

cleanup() {
    rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

cd "${PROJECT_DIR}"
swift build -c "${CONFIGURATION}" --product CodexVoiceChanger1

mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
mkdir -p "${APP_DIR}/Contents/Resources/Models"

install -m 755 "${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/CodexVoiceChanger1"
install -m 644 "${PROJECT_DIR}/Config/Info.plist" "${APP_DIR}/Contents/Info.plist"
install -m 644 \
    "${PROJECT_DIR}/Resources/Assets/CodexVoiceChanger.icns" \
    "${APP_DIR}/Contents/Resources/CodexVoiceChanger.icns"
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
xattr -cr "${APP_DIR}"
codesign --force --sign - --timestamp=none "${APP_DIR}"
codesign --verify --strict --verbose=2 "${APP_DIR}"

mkdir -p "${DIST_DIR}"
ditto -c -k --keepParent --norsrc --noextattr \
    "${APP_DIR}" \
    "${STAGED_ARCHIVE}"
install -m 644 "${STAGED_ARCHIVE}" "${ARCHIVE_PATH}"

echo "${ARCHIVE_PATH}"
