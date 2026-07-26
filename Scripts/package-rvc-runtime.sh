#!/bin/zsh
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "usage: package-rvc-runtime.sh <app-resource-rvc-directory>" >&2
    exit 64
fi

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DESTINATION="$1"
RVC_SOURCE="${PROJECT_DIR}/.training_cache/tsukuyomi_rvc/RVC"
MODEL_SOURCE="${PROJECT_DIR}/.training_cache/tsukuyomi_rvc/models/tsukuyomi_01.pth"
WORKER_SOURCE="${PROJECT_DIR}/Runtime/rvc_stream_worker.py"

verify_sha256() {
    local artifact_path="$1"
    local expected="$2"
    if [[ ! -f "${artifact_path}" ]]; then
        echo "missing RVC artifact: ${artifact_path}" >&2
        exit 66
    fi
    local actual
    actual="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "RVC artifact SHA-256 mismatch: ${artifact_path}" >&2
        echo "expected ${expected}" >&2
        echo "actual   ${actual}" >&2
        exit 65
    fi
}

verify_sha256 \
    "${MODEL_SOURCE}" \
    "cd4996435d0e9c9f93858a13d9ddf5442a011388478daab1f732e0ac2b2c4020"
verify_sha256 \
    "${RVC_SOURCE}/assets/hubert_base/pytorch_model.bin" \
    "cc8c20f4b90a520757260197a3ff2505705a7adbd20ad9eeaa4e1a9b38442ef5"
verify_sha256 \
    "${RVC_SOURCE}/assets/rmvpe/rmvpe.pt" \
    "6d62215f4306e3ca278246188607209f09af3dc77ed4232efdd069798c4ec193"

mkdir -p "${DESTINATION}/runtime/assets"
ditto "${RVC_SOURCE}/infer" "${DESTINATION}/runtime/infer"
mkdir -p "${DESTINATION}/runtime/tools"
install -m 644 \
    "${RVC_SOURCE}/tools/cuda_graph.py" \
    "${DESTINATION}/runtime/tools/cuda_graph.py"
install -m 644 \
    "${RVC_SOURCE}/tools/file_io.py" \
    "${DESTINATION}/runtime/tools/file_io.py"
ditto "${RVC_SOURCE}/i18n" "${DESTINATION}/runtime/i18n"
ditto \
    "${RVC_SOURCE}/assets/hubert_base" \
    "${DESTINATION}/runtime/assets/hubert_base"
ditto \
    "${RVC_SOURCE}/assets/rmvpe" \
    "${DESTINATION}/runtime/assets/rmvpe"
install -m 644 "${MODEL_SOURCE}" "${DESTINATION}/tsukuyomi_01.pth"
install -m 755 "${WORKER_SOURCE}" "${DESTINATION}/rvc_stream_worker.py"
install -m 644 \
    "${PROJECT_DIR}/Resources/Models/TSUKUYOMI_RVC_MANIFEST.json" \
    "${DESTINATION}/manifest.json"

find "${DESTINATION}" -type d -name __pycache__ -prune -exec rm -rf {} +
find "${DESTINATION}" -type f -name '*.pyc' -delete
find "${DESTINATION}" -type f -name '.DS_Store' -delete

(
    cd "${DESTINATION}/runtime"
    "${PROJECT_DIR}/.rvc_env/bin/python" -B -c \
        "from infer.rtrvc import RVC"
)

echo "${DESTINATION}"
