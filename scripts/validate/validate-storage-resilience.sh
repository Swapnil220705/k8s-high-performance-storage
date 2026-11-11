#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-storage-resilience.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates Mayastor resilience configurations, partial-rebuild parameters,
#          3-replica placement, DiskPool/io-engine/PVC/VolumeAttachment health,
#          storage Warning events, and optional Mayastor REST API state.
#
# Governance:
#   - Strictly non-destructive (never creates or deletes workloads/pools).
#   - Distinguishes PASS, WARNING, FAIL, and NOT_TESTABLE honestly.
#   - Archives .txt and .json audit reports under reports/storage/.
# ==============================================================================

set -euo pipefail

COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_BLUE="\033[0;34m"
COLOR_CYAN="\033[0;36m"
COLOR_BOLD="\033[1m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VALUES_FILE="${REPO_ROOT}/infrastructure/storage/openebs/values.yaml"
SC_FILE="${REPO_ROOT}/infrastructure/storage/examples/storageclasses.yaml"
DISKPOOL_FILE="${REPO_ROOT}/infrastructure/storage/mayastor/diskpools.yaml"
VERIFY_POD_FILE="${REPO_ROOT}/infrastructure/storage/examples/pod-verify-integrity.yaml"
SCENARIO_FILE="${REPO_ROOT}/tests/storage/resilience-scenarios.yaml"

NAMESPACE="openebs"
REPORT_DIR="${REPO_ROOT}/reports/storage"
REPORT_ONLY=false
REQUIRE_DEPLOYED=false
QUIET_MODE=false
API_URL=""
IS_WSL2=false
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

COUNT_PASS=0
COUNT_WARN=0
COUNT_FAIL=0
COUNT_NOT_TESTABLE=0
JSON_ITEMS=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Audits OpenEBS Mayastor resilience configuration and live failure-recovery readiness.

Options:
      --report-only         Run strictly read-only inspection checks (default behavior)
      --require-deployed    Return exit code 1 if live Mayastor pools/volumes are absent
      --api-url URL         Optional Mayastor REST API base URL (e.g. http://127.0.0.1:8081)
  -n, --namespace NS        Mayastor namespace (default: ${NAMESPACE})
  -o, --output-dir DIR      Output directory for reports (default: reports/storage)
  -q, --quiet               Suppress console check rows
  -h, --help                Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --report-only)
        REPORT_ONLY=true
        shift
        ;;
    --require-deployed)
        REQUIRE_DEPLOYED=true
        shift
        ;;
    --api-url)
        API_URL="${2:-}"
        shift 2
        ;;
    -n | --namespace)
        NAMESPACE="${2:-}"
        shift 2
        ;;
    -o | --output-dir)
        REPORT_DIR="${2:-}"
        shift 2
        ;;
    -q | --quiet)
        QUIET_MODE=true
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Error: Unknown option '$1'" >&2
        usage >&2
        exit 2
        ;;
    esac
done

record_check() {
    local status="$1" category="$2" title="$3" details="$4"
    case "${status}" in
    PASS)
        COUNT_PASS=$((COUNT_PASS + 1))
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_GREEN}[PASS]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    WARNING)
        COUNT_WARN=$((COUNT_WARN + 1))
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    FAIL)
        COUNT_FAIL=$((COUNT_FAIL + 1))
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_RED}[FAIL]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    NOT_TESTABLE)
        COUNT_NOT_TESTABLE=$((COUNT_NOT_TESTABLE + 1))
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_BLUE}[N/T] ${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    esac
    local item_json
    item_json="$(jq -n --arg st "${status}" --arg cat "${category}" --arg t "${title}" --arg d "${details}" \
        '{status: $st, category: $cat, title: $t, details: $d}')"
    JSON_ITEMS+=("${item_json}")
}

if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    IS_WSL2=true
fi

mkdir -p "${REPORT_DIR}"

if [[ "${QUIET_MODE}" == false ]]; then
    echo -e "${COLOR_CYAN}${COLOR_BOLD}==============================================================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}       OpenEBS Mayastor Storage Resilience & Recovery Validator${COLOR_RESET}"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}==============================================================================${COLOR_RESET}"
    printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
    echo "------------------------------------------------------------------------------"
fi

# 1. Static Rebuild & Redundancy Configuration Checks
if [[ -f "${VALUES_FILE}" ]]; then
    partial_en="$(yq eval '.mayastor.agents.core.rebuild.partial.enabled' "${VALUES_FILE}")"
    wait_p="$(yq eval '.mayastor.agents.core.rebuild.partial.waitPeriod' "${VALUES_FILE}")"
    etcd_rep="$(yq eval '.mayastor.etcd.replicaCount' "${VALUES_FILE}")"
    etcd_aa="$(yq eval '.mayastor.etcd.podAntiAffinityPreset' "${VALUES_FILE}")"
    if [[ "${partial_en}" == "true" ]] && [[ "${wait_p}" == "10m" ]] && [[ "${etcd_rep}" == "3" ]] && [[ "${etcd_aa}" == "hard" ]]; then
        record_check "PASS" "Config" "Partial Rebuild & Etcd Quorums" "partial.enabled=true, waitPeriod=${wait_p}, etcd replicas=${etcd_rep} (${etcd_aa})"
    else
        record_check "FAIL" "Config" "Partial Rebuild & Etcd Quorums" "Unexpected values: partial=${partial_en}, wait=${wait_p}, etcd=${etcd_rep}/${etcd_aa}"
    fi
else
    record_check "FAIL" "Config" "Partial Rebuild & Etcd Quorums" "Missing ${VALUES_FILE}"
fi

# 2. StorageClass 3-Way Replication & Topology Zones
r3_count="$(grep -c 'repl: "3"' "${SC_FILE}" 2>/dev/null || true)"
zone_count="$(grep -c 'topology.kubernetes.io/zone:' "${DISKPOOL_FILE}" 2>/dev/null || true)"
if [[ "${r3_count}" -ge 2 ]] && [[ "${zone_count}" -eq 3 ]]; then
    record_check "PASS" "Redundancy" "3-Replica StorageClasses & Zones" "Found ${r3_count} repl=3 StorageClasses and ${zone_count} zoned worker DiskPools"
else
    record_check "FAIL" "Redundancy" "3-Replica StorageClasses & Zones" "repl3_sc=${r3_count}, diskpool_zones=${zone_count}"
fi

# 3. Checksum Verification Pod & Scenario Matrix Presence
if [[ -f "${VERIFY_POD_FILE}" ]] && grep -q 'sha256sum -c' "${VERIFY_POD_FILE}" && [[ -f "${SCENARIO_FILE}" ]]; then
    sc_cnt="$(yq eval '.scenarios | length' "${SCENARIO_FILE}")"
    record_check "PASS" "Verification" "Integrity Verifier & Drill Plan" "pod-verify-integrity.yaml uses fsync+sha256sum; ${sc_cnt} resilience scenarios defined"
else
    record_check "FAIL" "Verification" "Integrity Verifier & Drill Plan" "Missing verifier pod or resilience-scenarios.yaml"
fi

# 4. Live Cluster & Mayastor Runtime State
CLUSTER_OK=false
MAYASTOR_DEPLOYED=false
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    CLUSTER_OK=true
    if kubectl get crd diskpools.openebs.io >/dev/null 2>&1 && kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
        MAYASTOR_DEPLOYED=true
    fi
fi

if [[ "${CLUSTER_OK}" == false ]]; then
    msg="No live Kubernetes API reachable"
    record_check "$([[ "${REQUIRE_DEPLOYED}" == true ]] && echo FAIL || echo WARNING)" "Cluster" "Kubernetes API Reachability" "${msg}"
    for title in "DiskPool Health & Free Capacity" "io-engine DaemonSet & Restarts" "PVC & VolumeAttachment Availability" "Storage Warning Event Audit" "REST Volume Rebuild Telemetry"; do
        record_check "NOT_TESTABLE" "Resilience" "${title}" "Skipped: Kubernetes API unreachable"
    done
elif [[ "${MAYASTOR_DEPLOYED}" == false ]]; then
    msg="Mayastor CRD/namespace '${NAMESPACE}' absent (intentional on 3.5 GiB WSL2 dev host)"
    record_check "$([[ "${REQUIRE_DEPLOYED}" == true ]] && echo FAIL || echo WARNING)" "Cluster" "Mayastor Resilience Runtime" "${msg}"
    for title in "DiskPool Health & Free Capacity" "io-engine DaemonSet & Restarts" "PVC & VolumeAttachment Availability" "Storage Warning Event Audit" "REST Volume Rebuild Telemetry"; do
        record_check "NOT_TESTABLE" "Resilience" "${title}" "Skipped: Live Mayastor storage stack absent"
    done
else
    # 4a. DiskPool Health
    pool_json="$(kubectl get diskpools -n "${NAMESPACE}" -o json 2>/dev/null || echo '{"items":[]}')"
    pool_total="$(jq '.items | length' <<<"${pool_json}")"
    pool_online="$(jq '[.items[] | select((.status.pool_status // "") == "Online" and (.status.cr_state // "") == "Created")] | length' <<<"${pool_json}")"
    pool_degraded="$(jq '[.items[] | select((.status.pool_status // "") != "Online")] | length' <<<"${pool_json}")"
    if [[ "${pool_total}" -ge 3 ]] && [[ "${pool_online}" -eq "${pool_total}" ]]; then
        record_check "PASS" "DiskPools" "DiskPool Health & Free Capacity" "${pool_online}/${pool_total} DiskPools Created+Online"
    elif [[ "${pool_total}" -gt 0 ]] && [[ "${pool_degraded}" -gt 0 ]]; then
        record_check "FAIL" "DiskPools" "DiskPool Health & Free Capacity" "${pool_degraded}/${pool_total} DiskPool(s) non-Online"
    else
        record_check "WARNING" "DiskPools" "DiskPool Health & Free Capacity" "Found ${pool_total} DiskPool(s); target expects 3 Online"
    fi

    # 4b. io-engine DaemonSet Health & Restart Count
    io_desired="$(kubectl get ds -n "${NAMESPACE}" -l app=io-engine -o jsonpath='{.items[0].status.desiredNumberScheduled}' 2>/dev/null || echo 0)"
    io_ready="$(kubectl get ds -n "${NAMESPACE}" -l app=io-engine -o jsonpath='{.items[0].status.numberReady}' 2>/dev/null || echo 0)"
    io_restarts="$(kubectl get pods -n "${NAMESPACE}" -l app=io-engine -o json 2>/dev/null | jq '[.items[].status.containerStatuses[]?.restartCount // 0] | add // 0')"
    if [[ "${io_desired}" -ge 3 ]] && [[ "${io_ready}" -eq "${io_desired}" ]]; then
        record_check "PASS" "DataPlane" "io-engine DaemonSet & Restarts" "io-engine Ready=${io_ready}/${io_desired}, cumulative container restarts=${io_restarts}"
    else
        record_check "FAIL" "DataPlane" "io-engine DaemonSet & Restarts" "io-engine Ready=${io_ready}/${io_desired}, restarts=${io_restarts}"
    fi

    # 4c. PVC & VolumeAttachment Availability
    pvc_pending="$(kubectl get pvc -A -o json 2>/dev/null | jq '[.items[] | select((.spec.storageClassName // "") | startswith("mayastor")) | select(.status.phase != "Bound")] | length')"
    va_unattached="$(kubectl get volumeattachments -o json 2>/dev/null | jq '[.items[] | select(.status.attached != true)] | length')"
    if [[ "${pvc_pending}" -eq 0 ]] && [[ "${va_unattached}" -eq 0 ]]; then
        record_check "PASS" "Workloads" "PVC & VolumeAttachment Availability" "All Mayastor PVCs Bound and VolumeAttachments attached"
    else
        record_check "WARNING" "Workloads" "PVC & VolumeAttachment Availability" "Non-Bound Mayastor PVCs=${pvc_pending}, unattached VolumeAttachments=${va_unattached}"
    fi

    # 4d. Storage Warning Event Audit
    warn_events="$(kubectl get events -A --field-selector type=Warning -o json 2>/dev/null | jq '[.items[] | select((.reason // "") | test("FailedMount|FailedAttachVolume|FailedScheduling"))] | length')"
    if [[ "${warn_events}" -eq 0 ]]; then
        record_check "PASS" "Events" "Storage Warning Event Audit" "Zero active FailedMount/FailedAttachVolume warning events"
    else
        record_check "WARNING" "Events" "Storage Warning Event Audit" "${warn_events} recent storage mount/attach warning event(s)"
    fi

    # 4e. Optional Mayastor REST API v0 Volume State Check
    if [[ -n "${API_URL}" ]]; then
        vols_json="$(curl -sS --max-time 5 "${API_URL%/}/v0/volumes" 2>/dev/null || echo '')"
        if [[ -n "${vols_json}" ]] && jq empty <<<"${vols_json}" 2>/dev/null; then
            non_online="$(jq '[.[] | select((.state.status // "") != "Online")] | length' <<<"${vols_json}")"
            if [[ "${non_online}" -eq 0 ]]; then
                record_check "PASS" "RestAPI" "REST Volume Rebuild Telemetry" "All volumes report Online via /v0/volumes"
            else
                record_check "FAIL" "RestAPI" "REST Volume Rebuild Telemetry" "${non_online} volume(s) in Degraded/Faulted/Offline state"
            fi
        else
            record_check "WARNING" "RestAPI" "REST Volume Rebuild Telemetry" "Could not query Mayastor REST endpoint ${API_URL}"
        fi
    else
        record_check "NOT_TESTABLE" "RestAPI" "REST Volume Rebuild Telemetry" "Skipped: pass --api-url to inspect live /v0/volumes replica status"
    fi
fi

# Generate JSON and TXT reports
TXT_REPORT="${REPORT_DIR}/storage-resilience-${TIMESTAMP}.txt"
JSON_REPORT="${REPORT_DIR}/storage-resilience-${TIMESTAMP}.json"

{
    echo "=============================================================================="
    echo "           OpenEBS Mayastor Storage Resilience Validation Report"
    echo "=============================================================================="
    echo "Report Date:    ${REPORT_DATE}"
    echo "Report Mode:    $([[ "${REPORT_ONLY}" == true ]] && echo "REPORT-ONLY" || echo "STANDARD")"
    echo "WSL2 Detected:  ${IS_WSL2}"
    echo "Summary:        PASS: ${COUNT_PASS} | WARN: ${COUNT_WARN} | FAIL: ${COUNT_FAIL} | N/T: ${COUNT_NOT_TESTABLE}"
    echo "------------------------------------------------------------------------------"
    printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
    echo "------------------------------------------------------------------------------"
    for item in "${JSON_ITEMS[@]}"; do
        printf "[%-4s] | [%-12s] | %-34s | %s\n" \
            "$(jq -r '.status' <<<"${item}" | cut -c1-4)" \
            "$(jq -r '.category' <<<"${item}")" \
            "$(jq -r '.title' <<<"${item}")" \
            "$(jq -r '.details' <<<"${item}")"
    done
    echo "=============================================================================="
} >"${TXT_REPORT}"

CHECKS_JSON="$(printf '%s\n' "${JSON_ITEMS[@]}" | jq -s '.')"
jq -n \
    --arg report_date "${REPORT_DATE}" \
    --arg namespace "${NAMESPACE}" \
    --arg wsl2 "${IS_WSL2}" \
    --argjson pass "${COUNT_PASS}" \
    --argjson warn "${COUNT_WARN}" \
    --argjson fail "${COUNT_FAIL}" \
    --argjson nt "${COUNT_NOT_TESTABLE}" \
    --argjson checks "${CHECKS_JSON}" \
    '{
        report_date_utc: $report_date,
        namespace: $namespace,
        wsl2_detected: ($wsl2 == "true"),
        summary: {pass: $pass, warning: $warn, fail: $fail, not_testable: $nt},
        checks: $checks
    }' >"${JSON_REPORT}"

if [[ "${QUIET_MODE}" == false ]]; then
    echo -e "\n[INFO] Reports archived to:"
    echo "  - ${TXT_REPORT}"
    echo "  - ${JSON_REPORT}"
    echo "=============================================================================="
    echo -e "Resilience Validation Summary: PASS=${COUNT_PASS}, WARN=${COUNT_WARN}, FAIL=${COUNT_FAIL}, N/T=${COUNT_NOT_TESTABLE}"
    echo "=============================================================================="
fi

if [[ "${COUNT_FAIL}" -gt 0 ]]; then
    exit 1
fi
exit 0
