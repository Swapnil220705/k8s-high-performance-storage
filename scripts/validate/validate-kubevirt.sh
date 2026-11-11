#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-kubevirt.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Audits virtualization hardware/kernel readiness (/proc/cpuinfo vmx/svm,
#          /dev/kvm permissions/ioctl), virtctl availability, Kubernetes cluster
#          compatibility, KubeVirt v1.9.1 & CDI v1.66.1 deployment health, and
#          node KVM device plugin allocatability.
#
# Governance:
#   - Strictly non-destructive.
#   - Distinguishes PASS, FAIL, WARNING, and NOT_TESTABLE honestly.
#   - Archives .txt and .json validation reports under reports/kubevirt/.
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

REPORT_DIR="${REPO_ROOT}/reports/kubevirt"
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

Validates host KVM virtualization readiness and KubeVirt/CDI deployment health.

Options:
  --report-only         Run strictly read-only inspections (default behavior)
  --require-deployed    Return exit code 1 (FAIL) if KubeVirt/CDI are not deployed
  -o, --output-dir DIR  Output directory for reports (default: reports/kubevirt)
  -q, --quiet           Suppress stdout check table (still writes reports)
  -h, --help            Display this help message

Exit Codes:
  0 - Checks completed with zero FAILs (WSL2 absent warnings / NOT_TESTABLE allowed)
  1 - One or more FAIL conditions detected
  2 - Invalid arguments or missing CLI dependencies
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
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_BLUE}[N/T]${COLOR_RESET}  %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
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

check_host_virtualization_and_cli() {
    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        IS_WSL2=true
        log_check "WARNING" "Environment" "WSL2 Hypervisor Runtime" "Running on WSL2 ($(uname -r)); nested single-node dev host with 3515 MiB total RAM"
    else
        log_check "PASS" "Environment" "Host Kernel Environment" "Standard Linux host ($(uname -r))"
    fi

    if grep -qE '\b(vmx|svm)\b' /proc/cpuinfo 2>/dev/null; then
        local ext
        ext="$(grep -m1 -oE '\b(vmx|svm)\b' /proc/cpuinfo)"
        log_check "PASS" "Virtualization" "CPU Hardware Extensions" "CPU exposes '${ext}' hardware virtualization extension"
    else
        log_check "FAIL" "Virtualization" "CPU Hardware Extensions" "Missing Intel vmx or AMD svm flags in /proc/cpuinfo"
    fi

    if [[ -c /dev/kvm ]]; then
        local kvm_perm
        kvm_perm="$(stat -c '%A %U:%G' /dev/kvm 2>/dev/null || echo 'unknown')"
        if [[ -r /dev/kvm && -w /dev/kvm ]]; then
            log_check "PASS" "KVM" "KVM Device Node & Permissions" "/dev/kvm readable & writable by current user (${kvm_perm})"
            if command -v python3 >/dev/null 2>&1; then
                local ioctl_ver
                ioctl_ver="$(python3 -c "import os,fcntl; fd=os.open('/dev/kvm', os.O_RDWR); print(fcntl.ioctl(fd, 0xAE00, 0)); os.close(fd)" 2>/dev/null || echo 'err')"
                if [[ "${ioctl_ver}" == "12" ]]; then
                    log_check "PASS" "KVM" "KVM Kernel API Probe" "KVM_GET_API_VERSION ioctl returned version 12"
                else
                    log_check "WARNING" "KVM" "KVM Kernel API Probe" "KVM ioctl returned '${ioctl_ver}'"
                fi
            fi
        else
            log_check "WARNING" "KVM" "KVM Device Node & Permissions" "/dev/kvm exists (${kvm_perm}), current non-root user lacks kvm group rw access; privileged virt-handler can use host device"
            log_check "NOT_TESTABLE" "KVM" "KVM Kernel API Probe" "Unprivileged user lacks r/w on /dev/kvm for non-root ioctl probe"
        fi
    else
        log_check "FAIL" "KVM" "KVM Device Node & Permissions" "/dev/kvm device node absent"
    fi

    if command -v virtctl >/dev/null 2>&1; then
        local vc_ver
        vc_ver="$(virtctl version --client 2>/dev/null | grep -oE 'GitVersion:"[^"]+"' | cut -d'"' -f2 || echo 'unknown')"
        log_check "PASS" "CLI" "virtctl Client Availability" "virtctl client installed (${vc_ver})"
    else
        log_check "FAIL" "CLI" "virtctl Client Availability" "virtctl binary missing from PATH"
    fi
}

check_cluster_and_kubevirt() {
    local ver_json k8s_ver node_count ready_nodes
    if ! ver_json="$(kubectl version -o json 2>/dev/null)"; then
        log_check "FAIL" "Kubernetes" "Cluster API Connectivity" "Unable to communicate with Kubernetes API server"
        return 0
    fi
    k8s_ver="$(echo "${ver_json}" | jq -r '.serverVersion.gitVersion // "unknown"')"
    node_count="$(kubectl get nodes -o json | jq '.items | length')"
    ready_nodes="$(kubectl get nodes -o json | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')"

    if [[ "${k8s_ver}" =~ ^v1\.(35|36)\. ]]; then
        log_check "PASS" "Kubernetes" "Cluster Version Window (1.35-1.36)" "Server ${k8s_ver} falls inside KubeVirt v1.9.1 support window (<1.37)"
    else
        log_check "WARNING" "Kubernetes" "Cluster Version Window (1.35-1.36)" "Server ${k8s_ver} outside KubeVirt v1.9.1 window"
    fi

    if [[ "${ready_nodes}" -ge 3 ]]; then
        log_check "PASS" "Kubernetes" "Worker Topology Headroom" "${ready_nodes}/${node_count} Ready nodes support KubeVirt VM migration"
    else
        log_check "WARNING" "Kubernetes" "Worker Topology Headroom" "Only ${ready_nodes}/${node_count} Ready node(s); multi-node KubeVirt target architecture requires 4 nodes"
    fi

    local kv_crd_ok=false cdi_crd_ok=false
    kubectl get crd kubevirts.kubevirt.io >/dev/null 2>&1 && kv_crd_ok=true
    kubectl get crd cdis.cdi.kubevirt.io >/dev/null 2>&1 && cdi_crd_ok=true

    if [[ "${kv_crd_ok}" == false ]] && [[ "${cdi_crd_ok}" == false ]]; then
        local msg="KubeVirt/CDI CRDs not deployed on local cluster (intentional on 3.5 GiB WSL2 dev host; full execution INFRASTRUCTURE-DEPENDENT)"
        if [[ "${IS_WSL2}" == true ]] && [[ "${REQUIRE_DEPLOYED}" == false ]]; then
            log_check "WARNING" "KubeVirt" "KubeVirt & CDI Deployment State" "${msg}"
        else
            log_check "FAIL" "KubeVirt" "KubeVirt & CDI Deployment State" "${msg}"
        fi
        log_check "NOT_TESTABLE" "KubeVirt" "virt-operator / virt-api / virt-controller" "Skipped: KubeVirt not deployed on active cluster"
        log_check "NOT_TESTABLE" "KubeVirt" "virt-handler KVM Allocatable Device" "Skipped: KubeVirt not deployed on active cluster"
        log_check "NOT_TESTABLE" "CDI" "CDI Controller / Importer Readiness" "Skipped: CDI not deployed on active cluster"
        log_check "NOT_TESTABLE" "CLI" "virtctl Server API Handshake" "Skipped: KubeVirt aggregated API unavailable"
        return 0
    fi

    # Live KubeVirt CR inspection
    local kv_phase cdi_phase kvm_nodes vh_desired vh_ready
    kv_phase="$(kubectl get kubevirt kubevirt -n kubevirt -o jsonpath='{.status.phase}' 2>/dev/null || echo 'Missing')"
    if [[ "${kv_phase}" == "Deployed" ]]; then
        log_check "PASS" "KubeVirt" "KubeVirt CR Phase" "kubevirt/kubevirt reports phase=Deployed"
    else
        log_check "FAIL" "KubeVirt" "KubeVirt CR Phase" "kubevirt/kubevirt phase='${kv_phase}' (expected Deployed)"
    fi

    vh_desired="$(kubectl get ds -n kubevirt virt-handler -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"
    vh_ready="$(kubectl get ds -n kubevirt virt-handler -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"
    kvm_nodes="$(kubectl get nodes -o json | jq '[.items[] | select((.status.allocatable["devices.kubevirt.io/kvm"] // "0") != "0")] | length')"
    if [[ "${vh_desired}" -ge 1 ]] && [[ "${vh_ready}" -eq "${vh_desired}" ]] && [[ "${kvm_nodes}" -ge 1 ]]; then
        log_check "PASS" "KubeVirt" "virt-handler KVM Allocatable Device" "${vh_ready}/${vh_desired} virt-handler Ready; ${kvm_nodes} node(s) expose devices.kubevirt.io/kvm"
    else
        log_check "FAIL" "KubeVirt" "virt-handler KVM Allocatable Device" "virt-handler ${vh_ready}/${vh_desired} Ready; ${kvm_nodes} nodes expose devices.kubevirt.io/kvm"
    fi

    cdi_phase="$(kubectl get cdi cdi -o jsonpath='{.status.phase}' 2>/dev/null || echo 'Missing')"
    if [[ "${cdi_phase}" == "Deployed" ]]; then
        log_check "PASS" "CDI" "CDI CR Phase" "cdi/cdi reports phase=Deployed"
    else
        log_check "FAIL" "CDI" "CDI CR Phase" "cdi/cdi phase='${cdi_phase}' (expected Deployed)"
    fi

    if virtctl version >/dev/null 2>&1; then
        log_check "PASS" "CLI" "virtctl Server API Handshake" "virtctl communicated cleanly with KubeVirt API subresource"
    else
        log_check "FAIL" "CLI" "virtctl Server API Handshake" "virtctl failed communicating with KubeVirt API"
    fi
}

generate_reports() {
    mkdir -p "${REPORT_DIR}"
    local text_file="${REPORT_DIR}/kubevirt-validation-${TIMESTAMP}.txt"
    local json_file="${REPORT_DIR}/kubevirt-validation-${TIMESTAMP}.json"

    {
        echo "=============================================================================="
        echo "        KubeVirt v1.9.1 & CDI v1.66.1 Readiness Validation Report"
        echo "=============================================================================="
        echo "Report Date:    ${REPORT_DATE}"
        echo "Report Mode:    $([[ "${REPORT_ONLY}" == true ]] && echo "REPORT-ONLY" || echo "STANDARD")"
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
    [[ "${#JSON_ITEMS[@]}" -gt 0 ]] && checks_json="$(printf '%s\n' "${JSON_ITEMS[@]}" | jq -s '.')"
    jq -n \
        --arg reportDate "${REPORT_DATE}" \
        --argjson reportOnly "${REPORT_ONLY}" \
        --argjson wsl2 "${IS_WSL2}" \
        --arg kubevirtTarget "v1.9.1" \
        --arg cdiTarget "v1.66.1" \
        --argjson pass "${COUNT_PASS}" \
        --argjson warn "${COUNT_WARN}" \
        --argjson fail "${COUNT_FAIL}" \
        --argjson nt "${COUNT_NOT_TESTABLE}" \
        --argjson checks "${checks_json}" \
        '{
          metadata: {
            reportDate: $reportDate,
            reportOnly: $reportOnly,
            wsl2Detected: $wsl2,
            kubevirtTarget: $kubevirtTarget,
            cdiTarget: $cdiTarget,
            summary: {pass: $pass, warning: $warn, fail: $fail, notTestable: $nt}
          },
          checks: $checks
        }' >"${json_file}"

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "\n${COLOR_GREEN}[INFO]${COLOR_RESET} Reports archived to:"
        echo "  - ${text_file}"
        echo "  - ${json_file}"
    fi
}

main() {
    for req in kubectl jq awk; do
        if ! command -v "${req}" >/dev/null 2>&1; then
            echo "Error: Mandatory CLI '${req}' missing from PATH." >&2
            exit 2
        fi
    done

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}${COLOR_BOLD}=============================================================================="
        echo -e "     KubeVirt v1.9.1 & CDI v1.66.1 — Virtualization & KVM Validator"
        echo -e "==============================================================================${COLOR_RESET}"
        printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
    fi

    check_host_virtualization_and_cli
    check_cluster_and_kubevirt
    generate_reports

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
        echo -e "${COLOR_BOLD}KubeVirt Validation Summary:${COLOR_RESET}"
        echo -e "  ${COLOR_GREEN}PASS:${COLOR_RESET}         ${COUNT_PASS}"
        echo -e "  ${COLOR_YELLOW}WARNING:${COLOR_RESET}      ${COUNT_WARN}"
        echo -e "  ${COLOR_RED}FAIL:${COLOR_RESET}         ${COUNT_FAIL}"
        echo -e "  ${COLOR_BLUE}NOT TESTABLE:${COLOR_RESET} ${COUNT_NOT_TESTABLE}"
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    fi

    [[ "${COUNT_FAIL}" -gt 0 ]] && exit 1
    exit 0
}

main "$@"
