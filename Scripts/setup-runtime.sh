#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CACHE_DIR="${PROJECT_DIR}/.training_cache/tsukuyomi_rvc"
RVC_DIR="${CACHE_DIR}/RVC"
MODEL_DIR="${CACHE_DIR}/models"
VENV_DIR="${PROJECT_DIR}/.rvc_env"

RVC_REPOSITORY="https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI.git"
RVC_COMMIT="4338f12c3c28c80b3ac015e2d0df66c41592746d"
OFFICIAL_MODEL_URL="https://tyc.rei-yumesaki.net/files/voice/tyc-rvc.zip"
OFFICIAL_MODEL_PAGE="https://tyc.rei-yumesaki.net/work/software/rvc/"
OFFICIAL_TERMS_URL="https://tyc.rei-yumesaki.net/work/software/rvc/terms/"

ARCHIVE_SHA256="1207590e7bac95bbbdeeced54714933390d73f0f7795a8f97fa1be60e542f201"
MODEL_SHA256="cd4996435d0e9c9f93858a13d9ddf5442a011388478daab1f732e0ac2b2c4020"
HUBERT_CONFIG_SHA256="0346950779dfb7f9316fa74ed846e2b8a22a08eedfdc5387b73f327cb1a4a7cf"
HUBERT_PREPROCESSOR_SHA256="7c1976a680fb7acc757cd36fb08eef878fa36c70b4c9d2d595df9c608bbbbf0e"
HUBERT_MODEL_SHA256="cc8c20f4b90a520757260197a3ff2505705a7adbd20ad9eeaa4e1a9b38442ef5"
RMVPE_SHA256="6d62215f4306e3ca278246188607209f09af3dc77ed4232efdd069798c4ec193"

if [[ "${1:-}" != "--accept-tsukuyomi-terms" || "$#" -ne 1 ]]; then
    print -u2 "This setup downloads the official つくよみちゃん RVC model."
    print -u2 "Read the model page and current terms before continuing:"
    print -u2 "  ${OFFICIAL_MODEL_PAGE}"
    print -u2 "  ${OFFICIAL_TERMS_URL}"
    print -u2
    print -u2 "If you accept them, run:"
    print -u2 "  ./Scripts/setup-runtime.sh --accept-tsukuyomi-terms"
    exit 64
fi

for command_name in curl git shasum ditto uv; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        print -u2 "Missing required command: ${command_name}"
        exit 69
    fi
done

verify_sha256() {
    local artifact_path="$1"
    local expected="$2"
    local actual
    actual="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
        print -u2 "SHA-256 mismatch: ${artifact_path}"
        print -u2 "expected ${expected}"
        print -u2 "actual   ${actual}"
        return 1
    fi
}

download_checked() {
    local source_url="$1"
    local destination="$2"
    local expected="$3"

    if [[ -f "${destination}" ]]; then
        if verify_sha256 "${destination}" "${expected}"; then
            print "Using verified ${destination}"
            return
        fi
        print -u2 "Remove the mismatched cache file and run setup again."
        exit 65
    fi

    mkdir -p "${destination:h}"
    local temporary_file="${destination}.download"
    curl --fail --location --retry 3 --output "${temporary_file}" "${source_url}"
    verify_sha256 "${temporary_file}" "${expected}"
    mv "${temporary_file}" "${destination}"
}

mkdir -p "${CACHE_DIR}" "${MODEL_DIR}"

if [[ ! -d "${RVC_DIR}/.git" ]]; then
    if [[ -e "${RVC_DIR}" ]]; then
        print -u2 "${RVC_DIR} exists but is not a Git checkout."
        exit 73
    fi
    mkdir -p "${RVC_DIR}"
    git -C "${RVC_DIR}" init
    git -C "${RVC_DIR}" remote add origin "${RVC_REPOSITORY}"
    git -C "${RVC_DIR}" fetch --depth 1 origin "${RVC_COMMIT}"
    git -C "${RVC_DIR}" checkout --detach FETCH_HEAD
fi

CURRENT_RVC_COMMIT="$(git -C "${RVC_DIR}" rev-parse HEAD)"
if [[ "${CURRENT_RVC_COMMIT}" != "${RVC_COMMIT}" ]]; then
    print -u2 "Unexpected RVC commit in ${RVC_DIR}."
    print -u2 "expected ${RVC_COMMIT}"
    print -u2 "actual   ${CURRENT_RVC_COMMIT}"
    exit 65
fi

ARCHIVE_PATH="${CACHE_DIR}/tyc-rvc.zip"
MODEL_PATH="${MODEL_DIR}/tsukuyomi_01.pth"
download_checked "${OFFICIAL_MODEL_URL}" "${ARCHIVE_PATH}" "${ARCHIVE_SHA256}"

if [[ -f "${MODEL_PATH}" ]]; then
    verify_sha256 "${MODEL_PATH}" "${MODEL_SHA256}"
else
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-voice-changer-1.XXXXXX")"
    trap 'rm -rf "${TEMP_DIR}"' EXIT
    ditto -x -k "${ARCHIVE_PATH}" "${TEMP_DIR}"
    EXTRACTED_MODEL="$(
        find "${TEMP_DIR}" -type f -name '*.pth' -print \
          | LC_ALL=C sort \
          | sed -n '1p'
    )"
    if [[ -z "${EXTRACTED_MODEL}" ]]; then
        print -u2 "Could not locate the 通常1 checkpoint in the official archive."
        exit 66
    fi
    verify_sha256 "${EXTRACTED_MODEL}" "${MODEL_SHA256}"
    install -m 644 "${EXTRACTED_MODEL}" "${MODEL_PATH}"
fi

HF_ROOT="https://huggingface.co/lj1995/VoiceConversionWebUI/resolve/main"
download_checked \
    "${HF_ROOT}/hubert_base/config.json" \
    "${RVC_DIR}/assets/hubert_base/config.json" \
    "${HUBERT_CONFIG_SHA256}"
download_checked \
    "${HF_ROOT}/hubert_base/preprocessor_config.json" \
    "${RVC_DIR}/assets/hubert_base/preprocessor_config.json" \
    "${HUBERT_PREPROCESSOR_SHA256}"
download_checked \
    "${HF_ROOT}/hubert_base/pytorch_model.bin" \
    "${RVC_DIR}/assets/hubert_base/pytorch_model.bin" \
    "${HUBERT_MODEL_SHA256}"
download_checked \
    "${HF_ROOT}/rmvpe.pt" \
    "${RVC_DIR}/assets/rmvpe/rmvpe.pt" \
    "${RMVPE_SHA256}"

if [[ -x "${VENV_DIR}/bin/python" ]]; then
    VENV_PYTHON_VERSION="$(
        "${VENV_DIR}/bin/python" -c \
          'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'
    )"
    if [[ "${VENV_PYTHON_VERSION}" != "3.11" ]]; then
        print -u2 "${VENV_DIR} uses Python ${VENV_PYTHON_VERSION}; Python 3.11 is required."
        print -u2 "Move that local environment aside and run setup again."
        exit 65
    fi
    print "Using existing Python ${VENV_PYTHON_VERSION} environment at ${VENV_DIR}"
else
    uv venv --python 3.11 "${VENV_DIR}"
fi
uv pip install \
    --python "${VENV_DIR}/bin/python" \
    --requirement "${PROJECT_DIR}/Runtime/requirements.txt"

(
    cd "${RVC_DIR}"
    "${VENV_DIR}/bin/python" -B -c "from infer.rtrvc import RVC"
)

print
print "RVC runtime is ready."
print "Build and run with:"
print "  ./Scripts/build-app.sh"
print "  ./Scripts/run-app.sh"
