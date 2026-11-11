#!/usr/bin/env bash
# ==============================================================================
# Script Name: run-resilience-drills.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Reproducible Mayastor storage resilience and recovery drill runner.
# Scenarios:
#   - io-engine-restart:      Restart 1 io-engine pod to observe partial rebuild (<10m)
#   - worker-cordon-drain:    Cordon/uncordon worker + verify 3-node anti-affinity state
#   - pool-degradation-check: Inspect DiskPool states, capacity alerts, rebuild window
#   - nfs-gateway-restart:    Restart NFS RWX gateway over Mayastor RWO & verify recovery
#
# Governance & Safety Guardrails:
#   - Default `--mode dry-run` (and `--mode simulate`): ZERO cluster mutations.
#   - `--mode execute` UNCONDITIONALLY REFUSES execution on WSL2 hosts.
#   - Never deletes PVCs, PVs, or DiskPools.
#   - Requires explicit `--confirm-drill YES-EXECUTE-RESILIENCE-DRILL` in execute mode.
#   - Registers EXIT trap to automatically uncordon any node cordoned during a drill.
# ==============================================================================

set -euo pipefail

log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

SCENARIO="io-engine-restart"
MODE="dry-run" # dry-run | simulate | execute
TARGET_NODE=""
CONFIRM_DRILL=""
OBSERVE_SEC=20
REPORT_DIR="${REPO_ROOT}/reports/storage"
SCENARIO_SPEC="${REPO_ROOT}/tests/storage/resilience-scenarios.yaml"
OBSERVER="${SCRIPT_DIR}/observe-rebuild-events.sh"
CHECKSUM_VERIFIER="${SCRIPT_DIR}/verify-volume-checksum.sh"

IS_WSL2=false
if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    IS_WSL2=true
fi

CORDONED_NODE=""
# shellcheck disable=SC2317
cleanup() {
    if [[ -n "${CORDONED_NODE}" ]] && command -v kubectl >/dev/null 2>&1; then
        log_warn "Cleanup trap: uncordoning node ${CORDONED_NODE}..."
        kubectl uncordon "${CORDONED_NODE}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Plans or executes controlled Mayastor storage failure-recovery drills.

Options:
      --scenario NAME        io-engine-restart (default) | worker-cordon-drain |
                             pool-degradation-check | nfs-gateway-restart
      --mode MODE            dry-run (default) | simulate | execute
      --target-node NODE     Explicit worker node for worker-cordon-drain / io-engine drill
      --observe-sec SEC      Post-fault observation window in execute mode (default: 20)
      --confirm-drill ACK    Required for execute: YES-EXECUTE-RESILIENCE-DRILL
  -o, --output-dir DIR       Output directory for drill reports (default: reports/storage)
  -h, --help                 Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --scenario)
        SCENARIO="${2:-}"
        shift 2
        ;;
    --mode)
        MODE="${2:-}"
        shift 2
        ;;
    --target-node)
        TARGET_NODE="${2:-}"
        shift 2
        ;;
    --observe-sec)
        OBSERVE_SEC="${2:-20}"
        shift 2
        ;;
    --confirm-drill)
        CONFIRM_DRILL="${2:-}"
        shift 2
        ;;
    -o | --output-dir)
        REPORT_DIR="${2:-}"
        shift 2
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

case "${SCENARIO}" in
io-engine-restart | worker-cordon-drain | pool-degradation-check | nfs-gateway-restart) ;;
*)
    log_error "Invalid --scenario '${SCENARIO}'."
    exit 2
    ;;
esac

case "${MODE}" in
dry-run | simulate | execute) ;;
*)
    log_error "Invalid --mode '${MODE}'. Must be dry-run, simulate, or execute."
    exit 2
    ;;
esac

if [[ ! -f "${SCENARIO_SPEC}" ]]; then
    log_error "Scenario matrix missing: ${SCENARIO_SPEC}"
    exit 1
fi

run_plan_or_simulate() {
    local ts out_txt
    ts="$(date '+%Y-%m-%d_%H-%M-%S')"
    mkdir -p "${REPORT_DIR}"
    out_txt="${REPORT_DIR}/drill-${SCENARIO}-${MODE}-${ts}.txt"

    yq ".scenarios[] | select(.id == \"${SCENARIO}\")" "${SCENARIO_SPEC}" >"${out_txt}"
    log_info "[${MODE^^}] Scenario '${SCENARIO}' validated cleanly from ${SCENARIO_SPEC}."
    log_info "[${MODE^^}] Zero cluster resources modified. Archived walkthrough to ${out_txt}"
    cat "${out_txt}"
}

if [[ "${MODE}" == "dry-run" ]] || [[ "${MODE}" == "simulate" ]]; then
    "${OBSERVER}" --dry-run
    "${CHECKSUM_VERIFIER}" --mode k8s-pod --dry-run
    if [[ "${MODE}" == "simulate" ]]; then
        run_plan_or_simulate
    else
        yq eval ".scenarios[] | select(.id == \"${SCENARIO}\") | .id" "${SCENARIO_SPEC}" >/dev/null
        log_info "[DRY-RUN] Resilience drill '${SCENARIO}' and dependencies passed static validation."
    fi
    exit 0
fi

# ------------------------------------------------------------------------------
# Execute Mode Guards (Never allowed on WSL2 or unconfirmed targets)
# ------------------------------------------------------------------------------
if [[ "${IS_WSL2}" == true ]]; then
    log_error "WSL2 environment detected. Destructive or multi-node fault drills are REFUSED on WSL2 dev host."
    exit 1
fi

if [[ "${CONFIRM_DRILL}" != "YES-EXECUTE-RESILIENCE-DRILL" ]]; then
    log_error "Refusing execute mode without '--confirm-drill YES-EXECUTE-RESILIENCE-DRILL'."
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "No active target Kubernetes cluster reachable."
    exit 1
fi

ready_workers="$(kubectl get nodes -l openebs.io/engine=mayastor --no-headers 2>/dev/null | grep -c ' Ready ' || true)"
if [[ "${ready_workers}" -lt 3 ]]; then
    log_error "Live resilience drills require >= 3 Ready Mayastor storage workers (found ${ready_workers})."
    exit 1
fi

log_info "Capturing pre-drill resilience snapshot..."
"${OBSERVER}" -o "${REPORT_DIR}"

case "${SCENARIO}" in
pool-degradation-check)
    log_info "Executing read-only DiskPool & volume health inspection..."
    "${OBSERVER}" -o "${REPORT_DIR}" --duration "${OBSERVE_SEC}"
    ;;
io-engine-restart)
    local_node="${TARGET_NODE:-$(kubectl get nodes -l openebs.io/engine=mayastor -o jsonpath='{.items[0].metadata.name}')}"
    target_pod="$(kubectl get pods -n openebs -l app=io-engine --field-selector "spec.nodeName=${local_node}" -o jsonpath='{.items[0].metadata.name}')"
    if [[ -z "${target_pod}" ]]; then
        log_error "No openebs-io-engine pod found on node ${local_node}."
        exit 1
    fi
    log_info "Running pre-fault PVC SHA-256 verification..."
    "${CHECKSUM_VERIFIER}" --mode k8s-pod
    log_warn "Restarting io-engine pod openebs/${target_pod} on ${local_node} to observe write-log rebuild..."
    kubectl delete pod "${target_pod}" -n openebs --wait=false
    "${OBSERVER}" -o "${REPORT_DIR}" --duration "${OBSERVE_SEC}" --interval 5
    kubectl rollout status ds/openebs-io-engine -n openebs --timeout=300s
    log_info "Running post-recovery PVC SHA-256 verification..."
    "${CHECKSUM_VERIFIER}" --mode k8s-pod
    ;;
worker-cordon-drain)
    if [[ -z "${TARGET_NODE}" ]]; then
        log_error "--target-node NODE is required for worker-cordon-drain scenario."
        exit 2
    fi
    CORDONED_NODE="${TARGET_NODE}"
    log_warn "Cordoning storage worker ${TARGET_NODE} (non-destructive scheduling isolation drill)..."
    kubectl cordon "${TARGET_NODE}"
    "${OBSERVER}" -o "${REPORT_DIR}" --duration "${OBSERVE_SEC}" --interval 5
    kubectl uncordon "${TARGET_NODE}"
    CORDONED_NODE=""
    log_info "Uncordoned ${TARGET_NODE} cleanly."
    ;;
nfs-gateway-restart)
    log_info "Restarting storage-nfs/mayastor-nfs-server gateway pod to verify RWO re-attach..."
    kubectl delete pod -n storage-nfs -l app.kubernetes.io/name=mayastor-nfs-server --wait=false
    "${OBSERVER}" -o "${REPORT_DIR}" --duration "${OBSERVE_SEC}" --interval 5
    kubectl rollout status deployment/mayastor-nfs-server -n storage-nfs --timeout=180s
    ;;
esac

log_info "Resilience scenario '${SCENARIO}' completed cleanly. Review artifacts under ${REPORT_DIR}."
exit 0
