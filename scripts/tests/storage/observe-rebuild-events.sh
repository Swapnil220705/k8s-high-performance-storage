#!/usr/bin/env bash
# ==============================================================================
# Script Name: observe-rebuild-events.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Non-destructive observer capturing Mayastor DiskPool states, PVC &
#          VolumeAttachment states, io-engine / agent-core logs, Kubernetes storage
#          Warning events, and optional Mayastor REST API /v0/volumes state.
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

NAMESPACE="openebs"
WORKLOAD_NS="mayastor-verification"
REPORT_DIR="${REPO_ROOT}/reports/storage"
DURATION_SEC=0
INTERVAL_SEC=5
API_URL=""
DRY_RUN=false
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Captures storage health, replica rebuild states, events, and Mayastor logs read-only.

Options:
  -n, --namespace NS     Mayastor namespace (default: ${NAMESPACE})
      --workload-ns NS   Workload PVC namespace (default: ${WORKLOAD_NS})
      --duration SEC     Poll duration in seconds (default: 0 = single snapshot)
      --interval SEC     Poll interval in seconds (default: 5)
      --api-url URL      Optional Mayastor REST base URL (e.g. http://127.0.0.1:8081)
  -o, --output-dir DIR   Output directory for logs & JSON summary (default: reports/storage)
      --dry-run          Verify environment and log collection commands without polling
  -h, --help             Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    -n | --namespace)
        NAMESPACE="${2:-}"
        shift 2
        ;;
    --workload-ns)
        WORKLOAD_NS="${2:-}"
        shift 2
        ;;
    --duration)
        DURATION_SEC="${2:-0}"
        shift 2
        ;;
    --interval)
        INTERVAL_SEC="${2:-5}"
        shift 2
        ;;
    --api-url)
        API_URL="${2:-}"
        shift 2
        ;;
    -o | --output-dir)
        REPORT_DIR="${2:-}"
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

mkdir -p "${REPORT_DIR}"
LOG_OUT="${REPORT_DIR}/rebuild-observation-${TIMESTAMP}.log"
JSON_OUT="${REPORT_DIR}/rebuild-observation-${TIMESTAMP}.json"

if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Observer configured for ns=${NAMESPACE}, workload-ns=${WORKLOAD_NS}, duration=${DURATION_SEC}s."
    exit 0
fi

if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
    log_warn "No active Kubernetes API reachable; archiving unavailable-cluster status."
    jq -n \
        --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg status "UNAVAILABLE" \
        '{timestamp_utc: $ts, cluster_reachable: false, status: $status}' >"${JSON_OUT}"
    exit 0
fi

collect_snapshot() {
    local iter="$1"
    {
        echo "==================== SNAPSHOT #${iter} ($(date -u '+%Y-%m-%dT%H:%M:%SZ')) ===================="
        echo "--- DiskPools (${NAMESPACE}) ---"
        kubectl get diskpools -n "${NAMESPACE}" -o wide 2>&1 || echo "DiskPool CRD unavailable"
        echo "--- Mayastor Pods (${NAMESPACE}) ---"
        kubectl get pods -n "${NAMESPACE}" -o wide 2>&1 || true
        echo "--- VolumeAttachments ---"
        kubectl get volumeattachments -o wide 2>&1 || true
        echo "--- PVCs (${WORKLOAD_NS}, kubevirt-workloads, storage-nfs) ---"
        for wns in "${WORKLOAD_NS}" "kubevirt-workloads" "storage-nfs"; do
            if kubectl get ns "${wns}" >/dev/null 2>&1; then
                echo "[ns=${wns}]"
                kubectl get pvc -n "${wns}" -o wide 2>&1 || true
            fi
        done
        echo "--- Recent Storage Warning Events ---"
        kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | grep -iE 'volume|diskpool|mayastor|nvme|nfs|pvc|mount|attach' | tail -n 20 || echo "None"
    } >>"${LOG_OUT}"
}

collect_mayastor_logs() {
    {
        echo "--- Mayastor io-engine & agent-core Log Tail ---"
        for comp in io-engine agent-core agent-ha-node; do
            local pods
            pods="$(kubectl get pods -n "${NAMESPACE}" -l "app=${comp}" -o name 2>/dev/null || true)"
            for p in ${pods}; do
                echo "[logs ${p}]"
                kubectl logs -n "${NAMESPACE}" "${p}" --tail=30 2>&1 | grep -iE 'fault|degrad|rebuild|online|nexus|pool|err' || true
            done
        done
    } >>"${LOG_OUT}"
}

query_rest_api() {
    if [[ -n "${API_URL}" ]] && command -v curl >/dev/null 2>&1; then
        {
            echo "--- Mayastor REST API /v0/volumes & /v0/pools ---"
            curl -sS --max-time 5 "${API_URL%/}/v0/pools" 2>&1 || true
            curl -sS --max-time 5 "${API_URL%/}/v0/volumes" 2>&1 || true
        } >>"${LOG_OUT}"
    fi
}

: >"${LOG_OUT}"
iter=1
collect_snapshot "${iter}"
collect_mayastor_logs
query_rest_api

if [[ "${DURATION_SEC}" -gt 0 ]]; then
    end_ts=$((SECONDS + DURATION_SEC))
    while [[ "${SECONDS}" -lt "${end_ts}" ]]; do
        sleep "${INTERVAL_SEC}"
        iter=$((iter + 1))
        collect_snapshot "${iter}"
    done
    collect_mayastor_logs
    query_rest_api
fi

ns_exists=false
if kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
    ns_exists=true
fi

jq -n \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg ns "${NAMESPACE}" \
    --arg log_file "${LOG_OUT}" \
    --argjson ns_exists "${ns_exists}" \
    --argjson snapshots "${iter}" \
    '{
        timestamp_utc: $ts,
        namespace: $ns,
        mayastor_namespace_present: $ns_exists,
        snapshots_collected: $snapshots,
        log_file: $log_file
    }' >"${JSON_OUT}"

log_info "Saved resilience observation logs to ${LOG_OUT} and ${JSON_OUT}"
exit 0
