#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-mayastor-deployment.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates a deployed OpenEBS Mayastor stack across Helm release status,
#          control-plane Deployments, io-engine DaemonSet, CSI Node DaemonSet,
#          DiskPools, StorageClasses, NVMe-oF TCP connectivity, and optional
#          active PVC/Pod SHA-256 data-integrity verification.
#
# Governance:
#   - Distinguishes PASS, FAIL, WARNING, and NOT_TESTABLE honestly.
#   - Never fakes passing results when Mayastor is absent (such as WSL2 dev nodes).
#   - Supports read-only `--report-only` inspection mode.
#   - Archives human-readable (.txt) and JSON (.json) audit reports to reports/storage/.
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

NAMESPACE="openebs"
RELEASE_NAME="openebs"
REPORT_DIR="${REPO_ROOT}/reports/storage"
REPORT_ONLY=false
REQUIRE_DEPLOYED=false
QUIET_MODE=false
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

Validates OpenEBS Mayastor v2.12.2 deployment health and storage provisioning.

Options:
  --report-only         Run strictly read-only inspection checks (skips PVC/Pod probe)
  --require-deployed    Return exit code 1 (FAIL) if Mayastor is not deployed even on WSL2
  -n, --namespace NS    Mayastor namespace (default: ${NAMESPACE})
  -o, --output-dir DIR  Output directory for reports (default: reports/storage)
  -q, --quiet           Suppress console check rows (still generates reports)
  -h, --help            Display this help message

Exit Codes:
  0 - Validation completed with zero FAILs (NOT_TESTABLE / WSL2 absent-warning permitted)
  1 - One or more FAIL conditions detected (broken Mayastor pods/pools or --require-deployed unmet)
  2 - Invalid arguments
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

log_check() {
    local status="$1"
    local category="$2"
    local title="$3"
    local details="$4"

    case "${status}" in
    PASS)
        COUNT_PASS=$((COUNT_PASS + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_GREEN}[PASS]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    WARNING)
        COUNT_WARN=$((COUNT_WARN + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    FAIL)
        COUNT_FAIL=$((COUNT_FAIL + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_RED}[FAIL]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    NOT_TESTABLE)
        COUNT_NOT_TESTABLE=$((COUNT_NOT_TESTABLE + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_BLUE}[N/T]${COLOR_RESET}  %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    esac

    local json_entry
    json_entry="$(jq -nc \
        --arg cat "${category}" \
        --arg st "${status}" \
        --arg ttl "${title}" \
        --arg det "${details}" \
        '{category: $cat, status: $st, title: $ttl, details: $det}')"
    JSON_ITEMS+=("${json_entry}")
}

record_not_deployed_suite() {
    local reason="$1"
    if [[ "${IS_WSL2}" == true ]] && [[ "${REQUIRE_DEPLOYED}" == false ]]; then
        log_check "WARNING" "Deployment" "Mayastor Helm Release Status" "${reason}"
    else
        log_check "FAIL" "Deployment" "Mayastor Helm Release Status" "${reason}"
    fi
    log_check "NOT_TESTABLE" "CRDs" "Mayastor DiskPool CRD (v1beta3)" "Skipped: Mayastor not deployed on active cluster"
    log_check "NOT_TESTABLE" "ControlPlane" "Mayastor Core / CSI Pods" "Skipped: Mayastor not deployed on active cluster"
    log_check "NOT_TESTABLE" "DataPlane" "Mayastor io-engine DaemonSet" "Skipped: Mayastor not deployed on active cluster"
    log_check "NOT_TESTABLE" "CSINode" "Mayastor csi-node DaemonSet" "Skipped: Mayastor not deployed on active cluster"
    log_check "NOT_TESTABLE" "DiskPools" "DiskPool Online & Capacity Audit" "Skipped: Mayastor not deployed on active cluster"
    log_check "NOT_TESTABLE" "StorageClass" "Mayastor StorageClasses" "Skipped: Mayastor not deployed on active cluster"
    log_check "NOT_TESTABLE" "NVMe-oF" "NVMe-oF TCP Target & Replicas" "Skipped: Mayastor not deployed on active cluster"
    log_check "NOT_TESTABLE" "Integrity" "PVC Provision & Write/Read Probe" "Skipped: Mayastor not deployed on active cluster"
}

check_deployed_stack() {
    # 1. CRDs
    if kubectl get crd diskpools.openebs.io >/dev/null 2>&1; then
        log_check "PASS" "CRDs" "Mayastor DiskPool CRD" "diskpools.openebs.io CRD installed in cluster"
    else
        log_check "FAIL" "CRDs" "Mayastor DiskPool CRD" "diskpools.openebs.io CRD missing despite active namespace"
    fi

    # 2. Control Plane pods (Deployments & StatefulSets in openebs namespace)
    local pods_json total_pods non_ready
    pods_json="$(kubectl get pods -n "${NAMESPACE}" -o json)"
    total_pods="$(echo "${pods_json}" | jq '.items | length')"
    non_ready="$(echo "${pods_json}" | jq -r '[.items[] | select(.status.phase != "Succeeded" and ([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length) == 0) | "\(.metadata.name)(\(.status.phase))"] | join(",")')"

    if [[ "${total_pods}" -gt 0 ]] && [[ -z "${non_ready}" ]]; then
        log_check "PASS" "ControlPlane" "All OpenEBS/Mayastor Pods" "All ${total_pods} pod(s) in '${NAMESPACE}' report Ready=True"
    else
        log_check "FAIL" "ControlPlane" "All OpenEBS/Mayastor Pods" "Unready/missing pods in '${NAMESPACE}': ${non_ready:-zero pods running}"
    fi

    # 3. io-engine DaemonSet & CSI node DaemonSet
    local io_desired io_ready csi_desired csi_ready
    io_desired="$(kubectl get ds -n "${NAMESPACE}" openebs-io-engine -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"
    io_ready="$(kubectl get ds -n "${NAMESPACE}" openebs-io-engine -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"
    if [[ "${io_desired}" -ge 3 ]] && [[ "${io_ready}" -eq "${io_desired}" ]]; then
        log_check "PASS" "DataPlane" "Mayastor io-engine DaemonSet" "${io_ready}/${io_desired} io-engine pods Ready"
    elif [[ "${io_desired}" -ge 1 ]]; then
        log_check "FAIL" "DataPlane" "Mayastor io-engine DaemonSet" "Insufficient/unready io-engine pods: ${io_ready}/${io_desired} Ready (target >=3)"
    else
        log_check "FAIL" "DataPlane" "Mayastor io-engine DaemonSet" "DaemonSet openebs-io-engine scheduled 0 pods (check openebs.io/engine=mayastor labels and hugepages-2Mi)"
    fi

    csi_desired="$(kubectl get ds -n "${NAMESPACE}" openebs-csi-node -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"
    csi_ready="$(kubectl get ds -n "${NAMESPACE}" openebs-csi-node -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"
    if [[ "${csi_desired}" -ge 1 ]] && [[ "${csi_ready}" -eq "${csi_desired}" ]]; then
        log_check "PASS" "CSINode" "Mayastor csi-node DaemonSet" "${csi_ready}/${csi_desired} csi-node pods Ready"
    else
        log_check "FAIL" "CSINode" "Mayastor csi-node DaemonSet" "csi-node DaemonSet unhealthy: ${csi_ready}/${csi_desired} Ready"
    fi

    # 4. DiskPools
    local dsp_json dsp_count dsp_online
    if dsp_json="$(kubectl get diskpools.openebs.io -n "${NAMESPACE}" -o json 2>/dev/null)"; then
        dsp_count="$(echo "${dsp_json}" | jq '.items | length')"
        dsp_online="$(echo "${dsp_json}" | jq '[.items[] | select((.status.status // .status.pool_status) == "Online")] | length')"
        if [[ "${dsp_count}" -ge 3 ]] && [[ "${dsp_online}" -eq "${dsp_count}" ]]; then
            log_check "PASS" "DiskPools" "DiskPool Online & Health" "${dsp_online}/${dsp_count} DiskPools Online (supports repl=3)"
        elif [[ "${dsp_count}" -eq 0 ]]; then
            log_check "WARNING" "DiskPools" "DiskPool Online & Health" "Zero DiskPools created yet (apply verified diskpools.yaml)"
        else
            log_check "FAIL" "DiskPools" "DiskPool Online & Health" "Only ${dsp_online}/${dsp_count} DiskPools reporting Online"
        fi
    else
        log_check "FAIL" "DiskPools" "DiskPool Online & Health" "Failed querying diskpools.openebs.io CRs"
    fi

    # 5. StorageClasses
    local sc_count
    sc_count="$(kubectl get sc -o json 2>/dev/null | jq '[.items[] | select(.provisioner == "io.openebs.csi-mayastor")] | length' || echo 0)"
    if [[ "${sc_count}" -ge 1 ]]; then
        log_check "PASS" "StorageClass" "Mayastor StorageClasses" "${sc_count} StorageClass(es) registered for provisioner io.openebs.csi-mayastor"
    else
        log_check "WARNING" "StorageClass" "Mayastor StorageClasses" "Zero StorageClasses found for io.openebs.csi-mayastor"
    fi

    # 6. Active write/read verification probe
    if [[ "${REPORT_ONLY}" == true ]]; then
        log_check "NOT_TESTABLE" "NVMe-oF" "NVMe-oF TCP Target & Replicas" "Skipped active volume attachment inspection (--report-only mode)"
        log_check "NOT_TESTABLE" "Integrity" "PVC Provision & Write/Read Probe" "Skipped live PVC/Pod integrity probe (--report-only mode)"
        return 0
    fi

    if [[ "${dsp_online:-0}" -lt 3 ]] || ! kubectl get sc mayastor-nvme-r3-ext4 >/dev/null 2>&1; then
        log_check "NOT_TESTABLE" "NVMe-oF" "NVMe-oF TCP Target & Replicas" "Requires >=3 Online DiskPools and mayastor-nvme-r3-ext4 StorageClass"
        log_check "NOT_TESTABLE" "Integrity" "PVC Provision & Write/Read Probe" "Skipped: >=3 Online DiskPools + StorageClass not yet present"
        return 0
    fi

    # Deploy non-destructive example PVC & integrity verifier Pod in mayastor-verification namespace
    if kubectl apply -f "${REPO_ROOT}/infrastructure/storage/examples/pvc-replicated-r3.yaml" >/dev/null &&
        kubectl apply -f "${REPO_ROOT}/infrastructure/storage/examples/pod-verify-integrity.yaml" >/dev/null; then
        local ok=false
        for _ in $(seq 1 45); do
            local phase
            phase="$(kubectl -n mayastor-verification get pod mayastor-integrity-verifier -o jsonpath='{.status.phase}' 2>/dev/null || echo '')"
            if [[ "${phase}" == "Succeeded" ]]; then
                ok=true
                break
            elif [[ "${phase}" == "Failed" ]]; then
                break
            fi
            sleep 2
        done

        if [[ "${ok}" == true ]]; then
            local pod_logs
            pod_logs="$(kubectl -n mayastor-verification logs mayastor-integrity-verifier 2>/dev/null || true)"
            if echo "${pod_logs}" | grep -q "\[PASS\]"; then
                log_check "PASS" "NVMe-oF" "NVMe-oF TCP Target & Replicas" "CSI controller/node provisioned and attached 3-replica NVMe-oF volume"
                log_check "PASS" "Integrity" "PVC Provision & Write/Read Probe" "mayastor-integrity-verifier wrote and verified 16MiB SHA-256 checksum on PVC"
            else
                log_check "FAIL" "Integrity" "PVC Provision & Write/Read Probe" "Verification Pod succeeded without expected [PASS] signature"
            fi
        else
            log_check "FAIL" "NVMe-oF" "NVMe-oF TCP Target & Replicas" "Verification Pod failed to bind/mount replicated Mayastor PVC within 90s"
            log_check "FAIL" "Integrity" "PVC Provision & Write/Read Probe" "mayastor-integrity-verifier did not complete successfully"
        fi
        kubectl -n mayastor-verification delete pod mayastor-integrity-verifier --ignore-not-found=true >/dev/null 2>&1 || true
        kubectl -n mayastor-verification delete pvc mayastor-r3-fs-verify mayastor-r3-block-verify --ignore-not-found=true >/dev/null 2>&1 || true
    else
        log_check "FAIL" "Integrity" "PVC Provision & Write/Read Probe" "Failed applying example PVC/Pod manifests"
    fi
}

generate_reports() {
    mkdir -p "${REPORT_DIR}"
    local text_file="${REPORT_DIR}/mayastor-deployment-validation-${TIMESTAMP}.txt"
    local json_file="${REPORT_DIR}/mayastor-deployment-validation-${TIMESTAMP}.json"

    {
        echo "=============================================================================="
        echo "      OpenEBS Mayastor (v2.12.2 / Chart 4.6.2) Deployment Validation"
        echo "=============================================================================="
        echo "Report Date:    ${REPORT_DATE}"
        echo "Namespace:      ${NAMESPACE}"
        echo "Report Mode:    $([[ "${REPORT_ONLY}" == true ]] && echo "REPORT-ONLY" || echo "ACTIVE-PROBE")"
        echo "WSL2 Detected:  ${IS_WSL2}"
        echo "Summary:        PASS: ${COUNT_PASS} | WARN: ${COUNT_WARN} | FAIL: ${COUNT_FAIL} | N/T: ${COUNT_NOT_TESTABLE}"
        echo "------------------------------------------------------------------------------"
        printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo "------------------------------------------------------------------------------"
        for item in "${JSON_ITEMS[@]}"; do
            local st cat ttl det
            st="$(echo "${item}" | jq -r '.status')"
            cat="$(echo "${item}" | jq -r '.category')"
            ttl="$(echo "${item}" | jq -r '.title')"
            det="$(echo "${item}" | jq -r '.details')"
            printf "%-6s | %-14s | %-34s | %s\n" "[${st:0:4}]" "[${cat}]" "${ttl}" "${det}"
        done
        echo "=============================================================================="
    } >"${text_file}"

    local checks_json="[]"
    if [[ "${#JSON_ITEMS[@]}" -gt 0 ]]; then
        checks_json="$(printf '%s\n' "${JSON_ITEMS[@]}" | jq -s '.')"
    fi
    jq -n \
        --arg reportDate "${REPORT_DATE}" \
        --arg ns "${NAMESPACE}" \
        --argjson reportOnly "${REPORT_ONLY}" \
        --argjson wsl2 "${IS_WSL2}" \
        --argjson pass "${COUNT_PASS}" \
        --argjson warn "${COUNT_WARN}" \
        --argjson fail "${COUNT_FAIL}" \
        --argjson nt "${COUNT_NOT_TESTABLE}" \
        --argjson checks "${checks_json}" \
        '{
          metadata: {
            reportDate: $reportDate,
            namespace: $ns,
            reportOnly: $reportOnly,
            wsl2Detected: $wsl2,
            summary: {
              pass: $pass,
              warning: $warn,
              fail: $fail,
              notTestable: $nt
            }
          },
          checks: $checks
        }' >"${json_file}"

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "\n${COLOR_GREEN}[INFO]${COLOR_RESET} Validation reports written to:"
        echo "  - ${text_file}"
        echo "  - ${json_file}"
    fi
}

main() {
    for req in kubectl helm jq; do
        if ! command -v "${req}" >/dev/null 2>&1; then
            echo "Error: Mandatory command '${req}' missing from PATH." >&2
            exit 2
        fi
    done

    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        IS_WSL2=true
    fi

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}${COLOR_BOLD}=============================================================================="
        echo -e "     OpenEBS Mayastor v2.12.2 — Deployment & Storage Integrity Validator"
        echo -e "==============================================================================${COLOR_RESET}"
        printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
    fi

    if ! kubectl version -o json >/dev/null 2>&1; then
        log_check "FAIL" "API" "Kubernetes API Connectivity" "Unable to communicate with Kubernetes cluster"
    elif ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || ! helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        if [[ "${IS_WSL2}" == true ]]; then
            record_not_deployed_suite "Mayastor Helm release '${RELEASE_NAME}' not present in '${NAMESPACE}' on WSL2 dev node (INFRASTRUCTURE-DEPENDENT on 4-node NVMe cluster)"
        else
            record_not_deployed_suite "Mayastor Helm release '${RELEASE_NAME}' not found in namespace '${NAMESPACE}'"
        fi
    else
        log_check "PASS" "Deployment" "Mayastor Helm Release Status" "Release '${RELEASE_NAME}' active in namespace '${NAMESPACE}'"
        check_deployed_stack
    fi

    generate_reports

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
        echo -e "${COLOR_BOLD}Deployment Validation Summary:${COLOR_RESET}"
        echo -e "  ${COLOR_GREEN}PASS:${COLOR_RESET}         ${COUNT_PASS}"
        echo -e "  ${COLOR_YELLOW}WARNING:${COLOR_RESET}      ${COUNT_WARN}"
        echo -e "  ${COLOR_RED}FAIL:${COLOR_RESET}         ${COUNT_FAIL}"
        echo -e "  ${COLOR_BLUE}NOT TESTABLE:${COLOR_RESET} ${COUNT_NOT_TESTABLE}"
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    fi

    if [[ "${COUNT_FAIL}" -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
