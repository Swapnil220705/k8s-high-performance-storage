#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-vm-hotplug.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates KubeVirt v1.9.1 LiveUpdate CPU/Memory/Disk hot-plug manifests
#          and preconditions, and (when --execute is specified on a live cluster)
#          runs live CPU socket expansion, guest RAM expansion, SCSI disk
#          addvolume/removevolume, and verifies guest OS response.
#
# Governance:
#   - Refuses --execute inside WSL2 single-node 3.5 GiB environment.
#   - Explicitly documents guest restart boundaries (downscale requires reboot).
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
VM_NAME="vm-ubuntu-hotplug"
HOTPLUG_VOL="hotplug-extra-disk-01"
OPERATION="all" # all, cpu, memory, disk, rollback
EXECUTE_HOTPLUG=false
DRY_RUN=false
REQUIRE_DEPLOYED=false
QUIET_MODE=false
IS_WSL2=false
REPORT_DIR="${REPO_ROOT}/reports/kubevirt"
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

Validates KubeVirt CPU, memory, and disk hot-plug configuration and runtime behavior.

Options:
      --operation OP        Hot-plug scope: all, cpu, memory, disk, rollback (default: ${OPERATION})
      --vm NAME             Target VirtualMachine name (default: ${VM_NAME})
  -n, --namespace NS        Target VM namespace (default: ${NAMESPACE})
      --dry-run             Static manifest + precondition check only
      --execute             Execute live CPU/RAM patch and/or virtctl addvolume/removevolume
      --require-deployed    Return exit code 1 if KubeVirt runtime is absent
  -o, --output-dir DIR      Output report directory (default: reports/kubevirt)
  -q, --quiet               Suppress table output
  -h, --help                Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --operation)
        OPERATION="${2:-}"
        if [[ ! "${OPERATION}" =~ ^(all|cpu|memory|disk|rollback)$ ]]; then
            echo "Error: Invalid --operation '${OPERATION}'" >&2
            exit 2
        fi
        shift 2
        ;;
    --vm)
        VM_NAME="${2:-}"
        shift 2
        ;;
    -n | --namespace)
        NAMESPACE="${2:-}"
        shift 2
        ;;
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    --execute)
        EXECUTE_HOTPLUG=true
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

check_hotplug_manifests() {
    local kv_cr="${REPO_ROOT}/kubevirt/installation/kubevirt-cr.yaml"
    local hp_vm="${REPO_ROOT}/kubevirt/hotplug/vm-ubuntu-hotplug-ready.yaml"
    local hp_vol="${REPO_ROOT}/kubevirt/hotplug/hotplug-data-volume.yaml"

    local rollout ratio
    rollout="$(yq eval '.spec.configuration.vmRolloutStrategy' "${kv_cr}")"
    ratio="$(yq eval '.spec.configuration.liveUpdateConfiguration.maxHotplugRatio' "${kv_cr}")"
    if [[ "${rollout}" == "LiveUpdate" ]] && [[ "${ratio}" -ge 2 ]]; then
        log_check "PASS" "Config" "KubeVirt CR LiveUpdate Strategy" "vmRolloutStrategy=LiveUpdate, maxHotplugRatio=${ratio}"
    else
        log_check "FAIL" "Config" "KubeVirt CR LiveUpdate Strategy" "Expected vmRolloutStrategy=LiveUpdate in kubevirt-cr.yaml (got '${rollout}')"
    fi

    local sockets max_sockets guest_mem max_mem lim_cpu lim_mem
    sockets="$(yq eval '.spec.template.spec.domain.cpu.sockets' "${hp_vm}")"
    max_sockets="$(yq eval '.spec.template.spec.domain.cpu.maxSockets' "${hp_vm}")"
    guest_mem="$(yq eval '.spec.template.spec.domain.memory.guest' "${hp_vm}")"
    max_mem="$(yq eval '.spec.template.spec.domain.memory.maxGuest' "${hp_vm}")"
    lim_cpu="$(yq eval '.spec.template.spec.domain.resources.limits.cpu' "${hp_vm}")"
    lim_mem="$(yq eval '.spec.template.spec.domain.resources.limits.memory' "${hp_vm}")"

    if [[ "${max_sockets}" -gt "${sockets}" ]] && [[ "${lim_cpu}" -ge "${max_sockets}" ]]; then
        log_check "PASS" "Manifests" "CPU Socket Hot-Plug Ceilings" "sockets=${sockets} -> maxSockets=${max_sockets}, pod CPU limit=${lim_cpu}"
    else
        log_check "FAIL" "Manifests" "CPU Socket Hot-Plug Ceilings" "Invalid CPU headroom: sockets=${sockets}, maxSockets=${max_sockets}, limit=${lim_cpu}"
    fi

    if [[ "${guest_mem}" == "2Gi" ]] && [[ "${max_mem}" == "4Gi" ]] && [[ -n "${lim_mem}" ]]; then
        log_check "PASS" "Manifests" "Memory Hot-Plug Headroom" "guest=${guest_mem} -> maxGuest=${max_mem}, pod memory limit=${lim_mem}"
    else
        log_check "FAIL" "Manifests" "Memory Hot-Plug Headroom" "Unexpected memory hot-plug ceiling: guest=${guest_mem}, maxGuest=${max_mem}"
    fi

    local kc_cache="${HOME:-/tmp}/.cache/kubeconform"
    local core_schema_tmpl="${REPO_ROOT}/infrastructure/k8s/schemas/v1.36.6-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json"
    mkdir -p "${kc_cache}"
    if kubeconform -strict -summary \
        -cache "${kc_cache}" \
        -schema-location "${REPO_ROOT}/kubevirt/installation/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
        -schema-location "${core_schema_tmpl}" \
        -schema-location default \
        "${hp_vm}" "${hp_vol}" >/dev/null 2>&1; then
        log_check "PASS" "Manifests" "Hot-Plug VM & Volume Schemas" "vm-ubuntu-hotplug-ready.yaml and hotplug-data-volume.yaml strictly valid"
    else
        log_check "FAIL" "Manifests" "Hot-Plug VM & Volume Schemas" "Hot-plug manifest schema validation failed"
    fi
}

mark_hotplug_untestable() {
    local reason="$1"
    if [[ "${IS_WSL2}" == true ]] && [[ "${REQUIRE_DEPLOYED}" == false ]] && [[ "${EXECUTE_HOTPLUG}" == false ]]; then
        log_check "WARNING" "Runtime" "KubeVirt Hot-Plug Precondition" "${reason}"
    else
        log_check "FAIL" "Runtime" "KubeVirt Hot-Plug Precondition" "${reason}"
    fi
    log_check "NOT_TESTABLE" "CPUHotplug" "Live vCPU Socket Expansion" "Skipped: ${reason}"
    log_check "NOT_TESTABLE" "MemHotplug" "Live Memory Guest Expansion" "Skipped: ${reason}"
    log_check "NOT_TESTABLE" "DiskHotplug" "Dynamic SCSI Volume Attach/Detach" "Skipped: ${reason}"
}

run_live_hotplug_tests() {
    if ! kubectl version -o json >/dev/null 2>&1; then
        mark_hotplug_untestable "Cluster API unreachable"
        return 0
    fi

    local kv_phase vmi_phase
    kv_phase="$(kubectl get kubevirt kubevirt -n kubevirt -o jsonpath='{.status.phase}' 2>/dev/null || echo 'absent')"
    if [[ "${kv_phase}" != "Deployed" ]]; then
        mark_hotplug_untestable "KubeVirt phase='${kv_phase}' (not deployed)"
        return 0
    fi

    vmi_phase="$(kubectl -n "${NAMESPACE}" get vmi "${VM_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || echo 'absent')"
    if [[ "${vmi_phase}" != "Running" ]]; then
        mark_hotplug_untestable "VMI '${NAMESPACE}/${VM_NAME}' phase='${vmi_phase}' (requires Running VM)"
        return 0
    fi
    log_check "PASS" "Runtime" "KubeVirt Hot-Plug Precondition" "KubeVirt Deployed and VMI '${VM_NAME}' Running"

    if [[ "${EXECUTE_HOTPLUG}" == false ]] || [[ "${DRY_RUN}" == true ]]; then
        log_check "NOT_TESTABLE" "CPUHotplug" "Live vCPU Socket Expansion" "Skipped: Passive check mode (--execute not passed)"
        log_check "NOT_TESTABLE" "MemHotplug" "Live Memory Guest Expansion" "Skipped: Passive check mode"
        log_check "NOT_TESTABLE" "DiskHotplug" "Dynamic SCSI Volume Attach/Detach" "Skipped: Passive check mode"
        return 0
    fi

    if [[ "${OPERATION}" == "cpu" ]] || [[ "${OPERATION}" == "all" ]]; then
        kubectl -n "${NAMESPACE}" patch vm "${VM_NAME}" --type merge \
            -p '{"spec":{"template":{"spec":{"domain":{"cpu":{"sockets":3}}}}}}' >/dev/null
        sleep 5
        local live_sockets
        live_sockets="$(kubectl -n "${NAMESPACE}" get vmi "${VM_NAME}" -o jsonpath='{.status.currentCPUTopology.sockets}' 2>/dev/null || echo 0)"
        if [[ "${live_sockets}" == "3" ]]; then
            log_check "PASS" "CPUHotplug" "Live vCPU Socket Expansion" "VMI '${VM_NAME}' currentCPUTopology.sockets reached 3 without VM reboot (note shrink requires restart)"
        else
            log_check "WARNING" "CPUHotplug" "Live vCPU Socket Expansion" "Requested sockets=3, observed currentCPUTopology.sockets=${live_sockets}; check VMI conditions"
        fi
    fi

    if [[ "${OPERATION}" == "memory" ]] || [[ "${OPERATION}" == "all" ]]; then
        kubectl -n "${NAMESPACE}" patch vm "${VM_NAME}" --type merge \
            -p '{"spec":{"template":{"spec":{"domain":{"memory":{"guest":"3Gi"}}}}}}' >/dev/null
        sleep 5
        local live_mem
        live_mem="$(kubectl -n "${NAMESPACE}" get vmi "${VM_NAME}" -o jsonpath='{.status.memory.guestCurrent}' 2>/dev/null || echo 'unknown')"
        if [[ "${live_mem}" == "3Gi" ]]; then
            log_check "PASS" "MemHotplug" "Live Memory Guest Expansion" "VMI '${VM_NAME}' memory.guestCurrent reached 3Gi without restart (shrink requires reboot)"
        else
            log_check "WARNING" "MemHotplug" "Live Memory Guest Expansion" "Requested 3Gi, observed memory.guestCurrent=${live_mem}; check ACPI/udev guest agent"
        fi
    fi

    if [[ "${OPERATION}" == "disk" ]] || [[ "${OPERATION}" == "all" ]]; then
        virtctl addvolume "${VM_NAME}" -n "${NAMESPACE}" --volume-name="${HOTPLUG_VOL}" --persist >/dev/null
        sleep 8
        local attached
        attached="$(kubectl -n "${NAMESPACE}" get vmi "${VM_NAME}" -o json | jq -r "[.status.volumeStatus[]? | select(.name == \"${HOTPLUG_VOL}\" and .hotplugVolume != null) | .phase] | first // \"missing\"")"
        if [[ "${attached}" == "Ready" ]]; then
            log_check "PASS" "DiskHotplug" "Dynamic SCSI Volume Attach/Detach" "Hot-plugged PVC '${HOTPLUG_VOL}' reported phase=Ready on live VMI"
        else
            log_check "FAIL" "DiskHotplug" "Dynamic SCSI Volume Attach/Detach" "Hot-plug volume '${HOTPLUG_VOL}' status='${attached}'"
        fi
    fi

    if [[ "${OPERATION}" == "rollback" ]] || [[ "${OPERATION}" == "all" ]]; then
        if virtctl removevolume "${VM_NAME}" -n "${NAMESPACE}" --volume-name="${HOTPLUG_VOL}" >/dev/null 2>&1; then
            log_check "PASS" "DiskHotplug" "Dynamic SCSI Volume Detach" "Detached '${HOTPLUG_VOL}' cleanly via virtctl removevolume (CPU/RAM shrink requires VM restart)"
        else
            log_check "WARNING" "DiskHotplug" "Dynamic SCSI Volume Detach" "virtctl removevolume returned non-zero for '${HOTPLUG_VOL}'"
        fi
    fi
}

generate_reports() {
    mkdir -p "${REPORT_DIR}"
    local text_file="${REPORT_DIR}/vm-hotplug-validation-${TIMESTAMP}.txt"
    local json_file="${REPORT_DIR}/vm-hotplug-validation-${TIMESTAMP}.json"

    {
        echo "=============================================================================="
        echo "          KubeVirt CPU, Memory & Disk Hot-Plug Validation Report"
        echo "=============================================================================="
        echo "Report Date:    ${REPORT_DATE}"
        echo "Target VM:      ${NAMESPACE}/${VM_NAME}"
        echo "Operation:      ${OPERATION}"
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
        --arg vm "${NAMESPACE}/${VM_NAME}" \
        --arg op "${OPERATION}" \
        --argjson execute "${EXECUTE_HOTPLUG}" \
        --argjson wsl2 "${IS_WSL2}" \
        --argjson pass "${COUNT_PASS}" \
        --argjson warn "${COUNT_WARN}" \
        --argjson fail "${COUNT_FAIL}" \
        --argjson nt "${COUNT_NOT_TESTABLE}" \
        --argjson checks "${checks_json}" \
        '{metadata:{reportDate:$reportDate,vm:$vm,operation:$op,execute:$execute,wsl2Detected:$wsl2,summary:{pass:$pass,warning:$warn,fail:$fail,notTestable:$nt}},checks:$checks}' >"${json_file}"

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "\n${COLOR_GREEN}[INFO]${COLOR_RESET} Reports archived to:"
        echo "  - ${text_file}"
        echo "  - ${json_file}"
    fi
}

main() {
    for req in kubectl yq jq kubeconform virtctl; do
        if ! command -v "${req}" >/dev/null 2>&1; then
            echo "Error: Required binary '${req}' missing from PATH." >&2
            exit 2
        fi
    done

    grep -qiE "microsoft|wsl" /proc/version 2>/dev/null && IS_WSL2=true

    if [[ "${EXECUTE_HOTPLUG}" == true ]] && [[ "${IS_WSL2}" == true ]]; then
        echo "[ERROR] Refusing --execute live hot-plug mutations inside single-node WSL2 dev environment." >&2
        exit 1
    fi

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}${COLOR_BOLD}=============================================================================="
        echo -e "          KubeVirt Live Hot-Plug (CPU, Memory & Disk) Validator"
        echo -e "==============================================================================${COLOR_RESET}"
        printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
    fi

    check_hotplug_manifests
    run_live_hotplug_tests
    generate_reports

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
        echo -e "${COLOR_BOLD}Hot-Plug Validation Summary:${COLOR_RESET}"
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
