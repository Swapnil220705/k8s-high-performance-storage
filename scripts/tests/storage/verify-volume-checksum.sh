#!/usr/bin/env bash
# ==============================================================================
# Script Name: verify-volume-checksum.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Reproducible SHA-256 data-integrity verifier supporting:
#            1. Local directory sanity verification (--mode cycle|write|verify)
#            2. Live Kubernetes PVC verification reusing pod-verify-integrity.yaml
#            3. Safe non-mutating `--dry-run` validation
# ==============================================================================

set -euo pipefail

log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# shellcheck disable=SC2317
log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

MODE="verify" # write | verify | cycle | k8s-pod
TARGET_DIR=""
SIZE_MB=8
NAMESPACE="mayastor-verification"
POD_NAME="mayastor-integrity-verifier"
DRY_RUN=false
MANIFEST_POD="${REPO_ROOT}/infrastructure/storage/examples/pod-verify-integrity.yaml"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Verifies deterministic storage payload integrity via fsync + SHA-256 readback.

Options:
      --mode MODE        write | verify | cycle | k8s-pod (default: verify)
      --target-dir DIR   Target directory for local/mounted volume write/verify
      --size-mb N        Payload size in MiB for local modes (default: 8, max 64)
  -n, --namespace NS     Kubernetes namespace for k8s-pod mode (default: ${NAMESPACE})
      --pod NAME         Pod name for k8s-pod mode (default: ${POD_NAME})
      --dry-run          Validate inputs and print planned verification without writing
  -h, --help             Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --mode)
        MODE="${2:-}"
        shift 2
        ;;
    --target-dir)
        TARGET_DIR="${2:-}"
        shift 2
        ;;
    --size-mb)
        SIZE_MB="${2:-8}"
        shift 2
        ;;
    -n | --namespace)
        NAMESPACE="${2:-}"
        shift 2
        ;;
    --pod)
        POD_NAME="${2:-}"
        shift 2
        ;;
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        log_error "Unknown option: $1"
        usage >&2
        exit 2
        ;;
    esac
done

case "${MODE}" in
write | verify | cycle | k8s-pod) ;;
*)
    log_error "Invalid --mode '${MODE}'."
    exit 2
    ;;
esac

if [[ "${MODE}" == "k8s-pod" ]]; then
    if [[ ! -f "${MANIFEST_POD}" ]]; then
        log_error "Pod verifier manifest missing: ${MANIFEST_POD}"
        exit 1
    fi
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Verified k8s integrity manifest: ${MANIFEST_POD} (namespace=${NAMESPACE}, pod=${POD_NAME})"
        exit 0
    fi
    if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Active Kubernetes cluster required for --mode k8s-pod."
        exit 1
    fi
    if ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
        log_error "Namespace '${NAMESPACE}' not found (provisioned on target Mayastor cluster)."
        exit 1
    fi
    log_info "Executing Kubernetes PVC checksum verifier pod ${NAMESPACE}/${POD_NAME}..."
    kubectl delete pod "${POD_NAME}" -n "${NAMESPACE}" --ignore-not-found=true >/dev/null
    kubectl apply -f "${MANIFEST_POD}"
    kubectl wait -n "${NAMESPACE}" --for=jsonpath='{.status.phase}'=Succeeded "pod/${POD_NAME}" --timeout=180s
    kubectl logs -n "${NAMESPACE}" "pod/${POD_NAME}"
    exit 0
fi

if [[ -z "${TARGET_DIR}" ]]; then
    log_error "--target-dir is required for --mode ${MODE}."
    exit 2
fi

case "${TARGET_DIR}" in
/ | /boot* | /etc* | /usr* | /var | /proc* | /sys* | /dev*)
    log_error "Refusing unsafe target directory: ${TARGET_DIR}"
    exit 1
    ;;
esac

if [[ "${SIZE_MB}" -le 0 ]] || [[ "${SIZE_MB}" -gt 64 ]]; then
    log_error "--size-mb must be between 1 and 64 (got '${SIZE_MB}')."
    exit 2
fi

DATA_FILE="${TARGET_DIR}/swfw-integrity-payload.bin"
SUM_FILE="${TARGET_DIR}/swfw-integrity-payload.sha256"

if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run '${MODE}' SHA-256 verification (${SIZE_MB} MiB) against ${DATA_FILE}."
    exit 0
fi

mkdir -p "${TARGET_DIR}"

write_payload() {
    log_info "Writing deterministic ${SIZE_MB} MiB test pattern with sync to ${DATA_FILE}..."
    dd if=/dev/zero bs=1048576 count="${SIZE_MB}" 2>/dev/null | tr '\000' 'K' >"${DATA_FILE}"
    sync
    (cd "${TARGET_DIR}" && sha256sum "$(basename "${DATA_FILE}")" >"$(basename "${SUM_FILE}")")
    sync
    log_info "Recorded SHA-256 baseline: $(cat "${SUM_FILE}")"
}

verify_payload() {
    if [[ ! -f "${DATA_FILE}" ]] || [[ ! -f "${SUM_FILE}" ]]; then
        log_error "Checksum baseline files missing in ${TARGET_DIR} (${DATA_FILE} / ${SUM_FILE})."
        exit 1
    fi
    log_info "Verifying SHA-256 integrity of ${DATA_FILE}..."
    (cd "${TARGET_DIR}" && sha256sum -c "$(basename "${SUM_FILE}")")
    log_info "[PASS] SHA-256 data-integrity verification passed."
}

case "${MODE}" in
write)
    write_payload
    ;;
verify)
    verify_payload
    ;;
cycle)
    write_payload
    verify_payload
    ;;
esac

exit 0
