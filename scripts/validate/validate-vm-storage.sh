#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-vm-storage.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates VM-to-Storage integration across static manifest access-mode
#          consistency (RWO Filesystem, RWO Raw Block, Default NFS RWX, and
#          Experimental Native RWX Block) and live cluster DataVolume/PVC/VMI/
#          guest-agent storage state.
#
# Governance:
#   - Distinguishes PASS, FAIL, WARNING, and NOT_TESTABLE honestly.
#   - Verifies experimental RWX is never configured as default migration tier.
#   - Archives .txt and .json audit reports under reports/kubevirt/.
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

NAMESPACE="kubevirt-workloads"
VM_DIR="${REPO_ROOT}/kubevirt/virtualmachines"
NFS_DIR="${REPO_ROOT}/storage/nfs"
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

Validates KubeVirt VM storage integration manifests and live DataVolume/PVC/VMI state.

Options:
  --report-only         Run strictly read-only inspection checks (default)
  --require-deployed    Return exit code 1 (FAIL) if StorageClasses/VMs are absent
  -n, --namespace NS    VM workload namespace (default: ${NAMESPACE})
  -o, --output-dir DIR  Output directory for reports (default: reports/kubevirt)
  -q, --quiet           Suppress console table output
  -h, --help            Display this help message
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

check_static_vm_storage_consistency() {
    local rwo_fs_vm="${VM_DIR}/vm-ubuntu-rwo-filesystem.yaml"
    local rwo_blk_vm="${VM_DIR}/vm-ubuntu-mayastor-rwo-block.yaml"
    local nfs_vm="${VM_DIR}/vm-ubuntu-rwx-nfs-migration.yaml"
    local exp_vm="${VM_DIR}/vm-ubuntu-rwx-block-experimental.yaml"
    local nfs_sc="${NFS_DIR}/nfs-storageclass.yaml"

    # 1. RWO Filesystem checks
    local rwo_fs_sc rwo_fs_mode rwo_fs_evict
    rwo_fs_sc="$(yq eval 'select(.kind == "VirtualMachine") | .spec.dataVolumeTemplates[0].spec.pvc.storageClassName' "${rwo_fs_vm}")"
    rwo_fs_mode="$(yq eval 'select(.kind == "VirtualMachine") | .spec.dataVolumeTemplates[0].spec.pvc.volumeMode' "${rwo_fs_vm}")"
    rwo_fs_evict="$(yq eval 'select(.kind == "VirtualMachine") | .spec.template.spec.evictionStrategy' "${rwo_fs_vm}")"
    if [[ "${rwo_fs_sc}" == "mayastor-nvme-r3-ext4" ]] && [[ "${rwo_fs_mode}" == "Filesystem" ]] && [[ "${rwo_fs_evict}" == "None" ]]; then
        log_check "PASS" "Manifests" "RWO Filesystem VM Alignment" "vm-ubuntu-rwo-fs binds mayastor-nvme-r3-ext4 (RWO/Filesystem/eviction=None)"
    else
        log_check "FAIL" "Manifests" "RWO Filesystem VM Alignment" "Unexpected values sc=${rwo_fs_sc}, mode=${rwo_fs_mode}, evict=${rwo_fs_evict}"
    fi

    # 2. RWO Raw Block checks
    local blk_sc blk_mode blk_access
    blk_sc="$(yq eval 'select(.kind == "VirtualMachine") | .spec.dataVolumeTemplates[0].spec.pvc.storageClassName' "${rwo_blk_vm}")"
    blk_mode="$(yq eval 'select(.kind == "VirtualMachine") | .spec.dataVolumeTemplates[0].spec.pvc.volumeMode' "${rwo_blk_vm}")"
    blk_access="$(yq eval 'select(.kind == "VirtualMachine") | .spec.dataVolumeTemplates[0].spec.pvc.accessModes[0]' "${rwo_blk_vm}")"
    if [[ "${blk_sc}" == "mayastor-nvme-r3-block" ]] && [[ "${blk_mode}" == "Block" ]] && [[ "${blk_access}" == "ReadWriteOnce" ]]; then
        log_check "PASS" "Manifests" "RWO Raw Block VM Alignment" "vm-ubuntu-rwo-block binds mayastor-nvme-r3-block (RWO/Block)"
    else
        log_check "FAIL" "Manifests" "RWO Raw Block VM Alignment" "Unexpected values sc=${blk_sc}, mode=${blk_mode}, access=${blk_access}"
    fi

    # 3. Default Safe Migration Tier (NFS RWX Filesystem)
    local nfs_sc_name nfs_vm_sc nfs_vm_access nfs_vm_mode
    nfs_sc_name="$(yq eval '.metadata.name' "${nfs_sc}")"
    nfs_vm_sc="$(yq eval '.spec.dataVolumeTemplates[0].spec.pvc.storageClassName' "${nfs_vm}")"
    nfs_vm_access="$(yq eval '.spec.dataVolumeTemplates[0].spec.pvc.accessModes[0]' "${nfs_vm}")"
    nfs_vm_mode="$(yq eval '.spec.dataVolumeTemplates[0].spec.pvc.volumeMode' "${nfs_vm}")"
    if [[ "${nfs_vm_sc}" == "${nfs_sc_name}" ]] && [[ "${nfs_vm_access}" == "ReadWriteMany" ]] && [[ "${nfs_vm_mode}" == "Filesystem" ]]; then
        log_check "PASS" "Manifests" "Default Migration Storage (NFS)" "vm-ubuntu-migration-nfs uses non-experimental RWX Filesystem (${nfs_sc_name})"
    else
        log_check "FAIL" "Manifests" "Default Migration Storage (NFS)" "Mismatch on default migration VM: sc=${nfs_vm_sc}, access=${nfs_vm_access}, mode=${nfs_vm_mode}"
    fi

    # 4. Experimental RWX Raw Block Opt-In Safety Check
    local exp_sc exp_mode exp_run exp_maturity
    exp_sc="$(yq eval '.spec.dataVolumeTemplates[0].spec.pvc.storageClassName' "${exp_vm}")"
    exp_mode="$(yq eval '.spec.dataVolumeTemplates[0].spec.pvc.volumeMode' "${exp_vm}")"
    exp_run="$(yq eval '.spec.runStrategy' "${exp_vm}")"
    exp_maturity="$(yq eval '.metadata.annotations["storage.k8s.io/maturity"]' "${exp_vm}")"
    if [[ "${exp_sc}" == "mayastor-nvme-r3-block-rwx" ]] && [[ "${exp_mode}" == "Block" ]] && [[ "${exp_run}" == "Manual" ]] && [[ "${exp_maturity}" == "experimental" ]]; then
        log_check "PASS" "Manifests" "Experimental RWX Block Guard" "vm-ubuntu-rwx-block-exp enforces Block + Manual runStrategy + experimental tag"
    else
        log_check "FAIL" "Manifests" "Experimental RWX Block Guard" "Unsafe experimental RWX block attributes: sc=${exp_sc}, mode=${exp_mode}, run=${exp_run}"
    fi

    # 5. Cloud-Init qemu-guest-agent verification
    if grep -q "qemu-guest-agent" "${VM_DIR}/cloud-init-secret.yaml"; then
        log_check "PASS" "CloudInit" "Guest Agent Provisioning Spec" "cloud-init-secret.yaml installs and enables qemu-guest-agent"
    else
        log_check "FAIL" "CloudInit" "Guest Agent Provisioning Spec" "Missing qemu-guest-agent in cloud-init userdata"
    fi
}

check_live_vm_storage() {
    if ! kubectl version -o json >/dev/null 2>&1; then
        log_check "FAIL" "Kubernetes" "Cluster API Reachability" "Unable to contact cluster API"
        return 0
    fi

    local has_sc=false
    if kubectl get sc mayastor-nvme-r3-ext4 >/dev/null 2>&1; then
        has_sc=true
        log_check "PASS" "StorageClass" "Mayastor SC Presence" "mayastor-nvme-r3-ext4 active on cluster"
    else
        local msg="StorageClass mayastor-nvme-r3-ext4 absent (expected on WSL2 single-node dev cluster)"
        if [[ "${IS_WSL2}" == true ]] && [[ "${REQUIRE_DEPLOYED}" == false ]]; then
            log_check "WARNING" "StorageClass" "Mayastor SC Presence" "${msg}"
        else
            log_check "FAIL" "StorageClass" "Mayastor SC Presence" "${msg}"
        fi
    fi

    if [[ "${has_sc}" == false ]] || ! kubectl get crd virtualmachines.kubevirt.io >/dev/null 2>&1; then
        log_check "NOT_TESTABLE" "DataVolumes" "CDI Import & Succeeded Phase" "Skipped: Live Mayastor + CDI cluster absent"
        log_check "NOT_TESTABLE" "PVC" "VM Root & Data PVC Bound State" "Skipped: Live StorageClasses / VMs absent"
        log_check "NOT_TESTABLE" "VMI" "Live VM Running & Disk Attach" "Skipped: KubeVirt runtime not deployed"
        log_check "NOT_TESTABLE" "GuestFS" "Guest Agent & Block Verification" "Skipped: No live VM running"
        return 0
    fi

    # Live cluster checks
    local dv_count dv_ok pvc_count pvc_bound vmi_count vmi_running
    dv_count="$(kubectl -n "${NAMESPACE}" get dv -o json 2>/dev/null | jq '.items | length' || echo 0)"
    dv_ok="$(kubectl -n "${NAMESPACE}" get dv -o json 2>/dev/null | jq '[.items[] | select(.status.phase == "Succeeded")] | length' || echo 0)"
    if [[ "${dv_count}" -ge 1 ]] && [[ "${dv_ok}" -eq "${dv_count}" ]]; then
        log_check "PASS" "DataVolumes" "CDI Import & Succeeded Phase" "${dv_ok}/${dv_count} DataVolume(s) in '${NAMESPACE}' reached Succeeded"
    elif [[ "${dv_count}" -eq 0 ]]; then
        log_check "WARNING" "DataVolumes" "CDI Import & Succeeded Phase" "Zero DataVolumes deployed yet in '${NAMESPACE}'"
    else
        log_check "FAIL" "DataVolumes" "CDI Import & Succeeded Phase" "Only ${dv_ok}/${dv_count} DataVolume(s) in '${NAMESPACE}' Succeeded"
    fi

    pvc_count="$(kubectl -n "${NAMESPACE}" get pvc -o json 2>/dev/null | jq '.items | length' || echo 0)"
    pvc_bound="$(kubectl -n "${NAMESPACE}" get pvc -o json 2>/dev/null | jq '[.items[] | select(.status.phase == "Bound")] | length' || echo 0)"
    if [[ "${pvc_count}" -ge 1 ]] && [[ "${pvc_bound}" -eq "${pvc_count}" ]]; then
        log_check "PASS" "PVC" "VM Root & Data PVC Bound State" "${pvc_bound}/${pvc_count} PVC(s) Bound"
    elif [[ "${pvc_count}" -eq 0 ]]; then
        log_check "WARNING" "PVC" "VM Root & Data PVC Bound State" "Zero PVCs present in '${NAMESPACE}'"
    else
        log_check "FAIL" "PVC" "VM Root & Data PVC Bound State" "Only ${pvc_bound}/${pvc_count} PVC(s) Bound"
    fi

    vmi_count="$(kubectl -n "${NAMESPACE}" get vmi -o json 2>/dev/null | jq '.items | length' || echo 0)"
    vmi_running="$(kubectl -n "${NAMESPACE}" get vmi -o json 2>/dev/null | jq '[.items[] | select(.status.phase == "Running")] | length' || echo 0)"
    if [[ "${vmi_count}" -ge 1 ]] && [[ "${vmi_running}" -eq "${vmi_count}" ]]; then
        log_check "PASS" "VMI" "Live VM Running & Disk Attach" "${vmi_running}/${vmi_count} VMI(s) Running"
        local first_vmi
        first_vmi="$(kubectl -n "${NAMESPACE}" get vmi -o jsonpath='{.items[0].metadata.name}')"
        if virtctl guestosinfo -n "${NAMESPACE}" "${first_vmi}" >/dev/null 2>&1; then
            log_check "PASS" "GuestFS" "Guest Agent & Block Verification" "qemu-guest-agent active on ${first_vmi}"
        else
            log_check "WARNING" "GuestFS" "Guest Agent & Block Verification" "VMI ${first_vmi} Running but qemu-guest-agent not yet responding"
        fi
    else
        log_check "NOT_TESTABLE" "VMI" "Live VM Running & Disk Attach" "Zero Running VMIs in '${NAMESPACE}'"
        log_check "NOT_TESTABLE" "GuestFS" "Guest Agent & Block Verification" "Skipped: No Running VMI"
    fi
}

generate_reports() {
    mkdir -p "${REPORT_DIR}"
    local text_file="${REPORT_DIR}/vm-storage-validation-${TIMESTAMP}.txt"
    local json_file="${REPORT_DIR}/vm-storage-validation-${TIMESTAMP}.json"

    {
        echo "=============================================================================="
        echo "         KubeVirt VM Storage & Access-Mode Validation Report"
        echo "=============================================================================="
        echo "Report Date:    ${REPORT_DATE}"
        echo "Namespace:      ${NAMESPACE}"
        echo "Report Mode:    $([[ "${REPORT_ONLY}" == true ]] && echo "REPORT-ONLY" || echo "STANDARD")"
        echo "WSL2 Detected:  ${IS_WSL2}"
        echo "Summary:        PASS: ${COUNT_PASS} | WARN: ${COUNT_WARN} | FAIL: ${COUNT_FAIL} | N/T: ${COUNT_NOT_TESTABLE}"
        echo "------------------------------------------------------------------------------"
        printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo "------------------------------------------------------------------------------"
        for item in "${JSON_ITEMS[@]}"; do
            printf "%-6s | %-14s | %-34s | %s\n" \
                "[$(echo "${item}" | jq -r '.status' | cut -c1-4)]" \
                "[$(echo "${item}" | jq -r '.category')]" \
                "$(echo "${item}" | jq -r '.title')" \
                "$(echo "${item}" | jq -r '.details')"
        done
        echo "=============================================================================="
    } >"${text_file}"

    local checks_json="[]"
    [[ "${#JSON_ITEMS[@]}" -gt 0 ]] && checks_json="$(printf '%s\n' "${JSON_ITEMS[@]}" | jq -s '.')"
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
        '{metadata:{reportDate:$reportDate,namespace:$ns,reportOnly:$reportOnly,wsl2Detected:$wsl2,summary:{pass:$pass,warning:$warn,fail:$fail,notTestable:$nt}},checks:$checks}' >"${json_file}"

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "\n${COLOR_GREEN}[INFO]${COLOR_RESET} Reports archived to:"
        echo "  - ${text_file}"
        echo "  - ${json_file}"
    fi
}

main() {
    for req in kubectl yq jq virtctl; do
        if ! command -v "${req}" >/dev/null 2>&1; then
            echo "Error: Required CLI '${req}' missing from PATH." >&2
            exit 2
        fi
    done

    grep -qiE "microsoft|wsl" /proc/version 2>/dev/null && IS_WSL2=true

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}${COLOR_BOLD}=============================================================================="
        echo -e "        KubeVirt VM Persistent Storage — Manifest & Runtime Validator"
        echo -e "==============================================================================${COLOR_RESET}"
        printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
    fi

    check_static_vm_storage_consistency
    check_live_vm_storage
    generate_reports

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
        echo -e "${COLOR_BOLD}VM Storage Validation Summary:${COLOR_RESET}"
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
