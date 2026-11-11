#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-mayastor-prerequisites.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Non-destructive pre-deployment prerequisite validator for OpenEBS
#          Mayastor (chart v4.6.2 / engine v2.12.2) across CPU, memory/HugePages,
#          kernel modules, read-only block device suitability, networking ports,
#          and Kubernetes cluster readiness.
#
# Governance & Safety Guardrails:
#   - STRICTLY READ-ONLY: Never wipes, formats, partitions, or mounts disks.
#   - Never modifies HugePages sysctls, kernel modules, or firewall rules.
#   - Distinguishes PASS, FAIL, WARNING, and NOT_TESTABLE accurately.
#   - Explicitly highlights single-node WSL2 limitations without overclaiming.
# ==============================================================================

set -euo pipefail

# ANSI colors
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_BLUE="\033[0;34m"
COLOR_CYAN="\033[0;36m"
COLOR_BOLD="\033[1m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REPORT_DIR="${REPO_ROOT}/reports/storage"
OUTPUT_FORMAT="both" # text, json, both
QUIET_MODE=false
MIN_DISK_GIB=10
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
IS_WSL2=false

COUNT_PASS=0
COUNT_WARN=0
COUNT_FAIL=0
COUNT_NOT_TESTABLE=0
JSON_ITEMS=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Non-destructive prerequisite validator for OpenEBS Mayastor v2.12.2 deployment.

Options:
  -o, --output-dir DIR    Directory for reports (default: reports/storage)
  -f, --format FORMAT     Report format: text, json, or both (default: both)
      --min-disk-gib N    Minimum size in GiB for candidate pool devices (default: ${MIN_DISK_GIB})
  -q, --quiet             Suppress stdout check lines (reports are still generated)
  -h, --help              Display this help message

Exit Codes:
  0 - All mandatory Mayastor deployment prerequisites passed (FAIL == 0)
  1 - One or more mandatory Mayastor prerequisites failed (expected on WSL2)
  2 - Invalid arguments or missing host inspection commands
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    -o | --output-dir)
        REPORT_DIR="${2:-}"
        shift 2
        ;;
    -f | --format)
        OUTPUT_FORMAT="${2:-}"
        if [[ ! "${OUTPUT_FORMAT}" =~ ^(text|json|both)$ ]]; then
            echo "Error: Invalid format '${OUTPUT_FORMAT}'. Use text, json, or both." >&2
            exit 2
        fi
        shift 2
        ;;
    --min-disk-gib)
        MIN_DISK_GIB="${2:-}"
        if ! [[ "${MIN_DISK_GIB}" =~ ^[0-9]+$ ]] || [[ "${MIN_DISK_GIB}" -lt 1 ]]; then
            echo "Error: --min-disk-gib must be a positive integer." >&2
            exit 2
        fi
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
            printf "${COLOR_GREEN}[PASS]${COLOR_RESET} %-12s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    WARNING)
        COUNT_WARN=$((COUNT_WARN + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %-12s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    FAIL)
        COUNT_FAIL=$((COUNT_FAIL + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_RED}[FAIL]${COLOR_RESET} %-12s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    NOT_TESTABLE)
        COUNT_NOT_TESTABLE=$((COUNT_NOT_TESTABLE + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_BLUE}[N/T]${COLOR_RESET}  %-12s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
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

detect_environment() {
    local kernel_ver
    kernel_ver="$(uname -r 2>/dev/null || echo 'unknown')"
    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        IS_WSL2=true
        log_check "WARNING" "Environment" "WSL2 Hypervisor Detection" "Running on WSL2 (${kernel_ver}); hardware NVMe, dedicated SPDK HugePages, and multi-node fabric are unavailable locally"
    else
        log_check "PASS" "Environment" "Host Kernel Environment" "Standard Linux kernel (${kernel_ver}); non-WSL2 host"
    fi
}

check_cpu() {
    local arch cores sse42
    arch="$(uname -m 2>/dev/null || echo 'unknown')"
    cores="$(nproc 2>/dev/null || echo 0)"
    sse42="$(grep -m1 -o 'sse4_2' /proc/cpuinfo 2>/dev/null || true)"

    if [[ "${arch}" == "x86_64" ]]; then
        log_check "PASS" "CPU" "x86_64 Architecture" "Architecture verified: ${arch}"
    else
        log_check "FAIL" "CPU" "x86_64 Architecture" "Architecture '${arch}' does not match x86_64 target profile"
    fi

    if [[ "${sse42}" == "sse4_2" ]]; then
        log_check "PASS" "CPU" "SPDK SSE4.2 Instruction Set" "CPU flags expose required sse4_2 instruction set"
    else
        log_check "FAIL" "CPU" "SPDK SSE4.2 Instruction Set" "Required sse4_2 CPU flag not found in /proc/cpuinfo"
    fi

    if [[ "${cores}" -ge 4 ]]; then
        log_check "PASS" "CPU" "Core Headroom for SPDK + OS" "${cores} CPU cores available (>=2 SPDK polling cores + OS/kubelet headroom)"
    elif [[ "${cores}" -ge 2 ]]; then
        log_check "WARNING" "CPU" "Core Headroom for SPDK + OS" "Only ${cores} CPU cores present; SPDK busy-polling requires 2 cores leaving minimal OS/workload capacity"
    else
        log_check "FAIL" "CPU" "Core Headroom for SPDK + OS" "Only ${cores} CPU core(s) found; minimum 2 cores strictly required by Mayastor io-engine"
    fi
}

check_memory_and_hugepages() {
    local mem_total_kb mem_avail_kb mem_total_mib mem_avail_mib
    local hp_size_kb hp_total hp_free hp_2m_mib
    mem_total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    mem_avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    mem_total_mib=$((mem_total_kb / 1024))
    mem_avail_mib=$((mem_avail_kb / 1024))

    hp_size_kb="$(awk '/^Hugepagesize:/ {print $2}' /proc/meminfo 2>/dev/null || echo 2048)"
    hp_total=0
    hp_free=0
    if [[ -r /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages ]]; then
        hp_total="$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo 0)"
        hp_free="$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages 2>/dev/null || echo 0)"
    else
        hp_total="$(awk '/^HugePages_Total:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
        hp_free="$(awk '/^HugePages_Free:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    fi
    hp_2m_mib=$((hp_total * 2))

    # Production worker node target: >=16384 MiB (constrained baseline) / >=32768 MiB (preferred)
    if [[ "${mem_total_mib}" -ge 15000 ]]; then
        log_check "PASS" "Memory" "Total Host RAM Capacity" "${mem_total_mib} MiB total RAM (${mem_avail_mib} MiB available); satisfies worker RAM floor"
    elif [[ "${mem_total_mib}" -ge 4096 ]]; then
        log_check "WARNING" "Memory" "Total Host RAM Capacity" "${mem_total_mib} MiB total RAM (${mem_avail_mib} MiB available); tight for concurrent SPDK (2Gi HP + 1Gi RAM) + OS + workloads"
    else
        log_check "FAIL" "Memory" "Total Host RAM Capacity" "${mem_total_mib} MiB total RAM (${mem_avail_mib} MiB available); insufficient for Mayastor io-engine (2GiB HugePages + 1GiB pod + OS)"
    fi

    if [[ "${hp_size_kb}" -eq 2048 ]] && [[ "${hp_total}" -ge 1024 ]]; then
        log_check "PASS" "HugePages" "2MiB HugePages Reservation" "${hp_total} x 2MiB pages reserved (${hp_2m_mib} MiB total, ${hp_free} free; requires >=1024 pages)"
    else
        log_check "FAIL" "HugePages" "2MiB HugePages Reservation" "${hp_total} x 2MiB pages configured (${hp_2m_mib} MiB, page size ${hp_size_kb} kB); Mayastor requires >=1024 x 2MiB pages (2048 MiB)"
    fi
}

check_kernel_support() {
    local kver loaded_mods mod_available nvme_detail
    kver="$(uname -r 2>/dev/null || echo 'unknown')"
    loaded_mods="$(lsmod 2>/dev/null || true)"

    # nvme-tcp check (built-in in /lib/modules/*/modules.builtin, loaded in lsmod, or loadable via modinfo)
    mod_available=false
    nvme_detail=""
    if echo "${loaded_mods}" | grep -q -E '^(nvme_tcp|nvme-tcp)\b'; then
        mod_available=true
        nvme_detail="Module nvme_tcp is currently loaded in kernel ${kver}"
        log_check "PASS" "Kernel" "nvme_tcp Initiator Support" "${nvme_detail}"
    else
        if [[ -r "/lib/modules/${kver}/modules.builtin" ]] && grep -qE 'nvme[-_]tcp' "/lib/modules/${kver}/modules.builtin" 2>/dev/null; then
            mod_available=true
            log_check "PASS" "Kernel" "nvme_tcp Initiator Support" "nvme-tcp compiled built-in in kernel ${kver}"
        elif modinfo nvme_tcp >/dev/null 2>&1 || grep -qE 'nvme[-_]tcp' "/lib/modules/${kver}/modules.dep" 2>/dev/null; then
            mod_available=true
            log_check "WARNING" "Kernel" "nvme_tcp Initiator Support" "Module nvme_tcp exists for kernel ${kver} but is not currently loaded (run 'sudo modprobe nvme_tcp' on target host)"
        fi
        if [[ "${mod_available}" == false ]]; then
            log_check "FAIL" "Kernel" "nvme_tcp Initiator Support" "Kernel support for nvme_tcp missing in ${kver}"
        fi
    fi

    # Filesystem checks (ext4 mandatory, xfs optional)
    if grep -qw 'ext4' /proc/filesystems 2>/dev/null || modinfo ext4 >/dev/null 2>&1; then
        log_check "PASS" "Kernel" "ext4 Filesystem Support" "ext4 filesystem driver available in kernel/modules"
    else
        log_check "FAIL" "Kernel" "ext4 Filesystem Support" "Required ext4 filesystem driver not found"
    fi

    if grep -qw 'xfs' /proc/filesystems 2>/dev/null || modinfo xfs >/dev/null 2>&1; then
        log_check "PASS" "Kernel" "xfs Filesystem Support" "Optional xfs filesystem driver available in kernel/modules"
    else
        log_check "WARNING" "Kernel" "xfs Filesystem Support" "Optional xfs filesystem driver not currently loaded/available; use ext4 StorageClass"
    fi
}

check_storage_devices_readonly() {
    if ! command -v lsblk >/dev/null 2>&1; then
        log_check "FAIL" "Storage" "Block Device Inventory (lsblk)" "lsblk binary unavailable; cannot perform read-only disk inspection"
        return 0
    fi

    local lsblk_json disks_json dev_count candidate_count=0 inspected_summary=""
    if ! lsblk_json="$(lsblk -J -b -o NAME,KNAME,TYPE,SIZE,ROTA,TRAN,MOUNTPOINT,FSTYPE,PTTYPE,PKNAME 2>/dev/null)"; then
        log_check "FAIL" "Storage" "Block Device Inventory (lsblk)" "Failed reading block devices via read-only lsblk"
        return 0
    fi

    disks_json="$(echo "${lsblk_json}" | jq '[.blockdevices[]? | select(.type == "disk")]')"
    dev_count="$(echo "${disks_json}" | jq 'length')"
    if [[ "${dev_count}" -eq 0 ]]; then
        log_check "FAIL" "Storage" "Block Device Inventory" "No whole-disk block devices detected"
        return 0
    fi

    local min_bytes=$((MIN_DISK_GIB * 1024 * 1024 * 1024))
    local idx=0
    while [[ "${idx}" -lt "${dev_count}" ]]; do
        local dname size_bytes size_gib size_mib size_label tran fstype pttype mountpoint child_count reasons=""
        dname="$(echo "${disks_json}" | jq -r ".[${idx}].name")"
        size_bytes="$(echo "${disks_json}" | jq -r ".[${idx}].size // 0")"
        size_mib=$((size_bytes / 1024 / 1024))
        size_gib=$((size_mib / 1024))
        if [[ "${size_gib}" -ge 1 ]]; then
            size_label="${size_gib}GiB"
        else
            size_label="${size_mib}MiB"
        fi
        tran="$(echo "${disks_json}" | jq -r ".[${idx}].tran // \"none\"")"
        fstype="$(echo "${disks_json}" | jq -r ".[${idx}].fstype // \"none\"")"
        pttype="$(echo "${disks_json}" | jq -r ".[${idx}].pttype // \"none\"")"
        mountpoint="$(echo "${disks_json}" | jq -r ".[${idx}].mountpoint // \"none\"")"
        child_count="$(echo "${disks_json}" | jq ".[${idx}].children // [] | length")"

        if [[ "${mountpoint}" != "none" ]]; then
            reasons+="mounted(${mountpoint}),"
        fi
        if [[ "${fstype}" != "none" ]]; then
            reasons+="fstype(${fstype}),"
        fi
        if [[ "${pttype}" != "none" ]]; then
            reasons+="pttype(${pttype}),"
        fi
        if [[ "${child_count}" -gt 0 ]]; then
            reasons+="has_partitions(${child_count}),"
        fi
        if [[ "${size_bytes}" -lt "${min_bytes}" ]]; then
            reasons+="too_small(${size_label}<${MIN_DISK_GIB}GiB),"
        fi
        if [[ "${IS_WSL2}" == true ]] && [[ "${tran}" != "nvme" ]]; then
            reasons+="wsl2_virtual_disk(${tran}),"
        fi

        if [[ -z "${reasons}" ]]; then
            candidate_count=$((candidate_count + 1))
            inspected_summary+="/dev/${dname}[${size_label},${tran}:SUITABLE] "
        else
            inspected_summary+="/dev/${dname}[${size_label},${tran}:${reasons%,}] "
        fi

        idx=$((idx + 1))
    done

    log_check "PASS" "Storage" "Read-Only Block Inventory" "Observed ${dev_count} disk(s) without modifying any device: ${inspected_summary% }"

    if [[ "${candidate_count}" -ge 1 ]]; then
        log_check "PASS" "Storage" "Dedicated Raw Pool Disk Suitability" "${candidate_count} unmounted/unformatted candidate block device(s) >=${MIN_DISK_GIB}GiB detected; manual institutional wipe confirmation still required before DiskPool creation"
    else
        log_check "FAIL" "Storage" "Dedicated Raw Pool Disk Suitability" "Zero clean, unformatted, unmounted block devices >=${MIN_DISK_GIB}GiB available (all detected disks contain filesystems, swaps, mountpoints, or WSL2 virtual disks)"
    fi
}

check_network_ports() {
    local required_ports=("10124:Mayastor_io_engine_gRPC" "8420:NVMe_oF_TCP_IO_Target" "4421:NVMe_oF_TCP_Controller")
    local listening_ports=""
    if command -v ss >/dev/null 2>&1; then
        listening_ports="$(ss -tlnH 2>/dev/null | awk '{print $4}' || true)"
    fi

    for entry in "${required_ports[@]}"; do
        local port="${entry%%:*}"
        local label="${entry#*:}"
        if [[ -z "${listening_ports}" ]]; then
            log_check "WARNING" "Network" "Port ${port} Availability (${label})" "Unable to query listening TCP sockets via ss"
        elif echo "${listening_ports}" | grep -qE ":${port}$"; then
            log_check "WARNING" "Network" "Port ${port} Availability (${label})" "TCP port ${port} already bound locally; verify whether existing Mayastor io-engine or conflicting service owns it"
        else
            log_check "PASS" "Network" "Port ${port} Availability (${label})" "TCP port ${port} is free and unallocated on host"
        fi
    done

    local iface_summary
    iface_summary="$(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | tr '\n' ',' | sed 's/,$//' || echo 'unknown')"
    log_check "PASS" "Network" "Active Host Interfaces" "Detected UP interfaces: ${iface_summary}"

    log_check "NOT_TESTABLE" "Network" "Multi-Node NVMe-oF TCP Reachability" "Cross-node NVMe-oF TCP transport (ports 8420/4421/10124) and MTU verification require active multi-node cluster connectivity"
}

check_kubernetes_readiness() {
    if ! command -v kubectl >/dev/null 2>&1; then
        log_check "FAIL" "Kubernetes" "kubectl Availability" "kubectl CLI missing from PATH"
        return 0
    fi
    if ! command -v helm >/dev/null 2>&1; then
        log_check "FAIL" "Kubernetes" "Helm v3 Availability" "helm CLI missing from PATH"
    else
        local helm_ver
        helm_ver="$(helm version --short 2>/dev/null || echo 'unknown')"
        log_check "PASS" "Kubernetes" "Helm v3 Availability" "Helm binary available (${helm_ver})"
    fi

    local ver_json server_ver nodes_json node_count ready_count engine_labeled_count hp_capable_nodes
    if ! ver_json="$(kubectl version -o json 2>/dev/null)"; then
        log_check "FAIL" "Kubernetes" "Cluster API Reachability" "Unable to contact active Kubernetes API server via current kubeconfig"
        return 0
    fi
    server_ver="$(echo "${ver_json}" | jq -r '.serverVersion.gitVersion // "unknown"')"

    if [[ "${server_ver}" =~ ^v1\.36\. ]]; then
        log_check "WARNING" "Kubernetes" "Cluster Version Compatibility" "Server ${server_ver} matches Candidate B (1.36.x); note upstream Mayastor v2.12.2 CI qualification covers up to v1.35.6 (K8s 1.36 requires explicit cluster validation)"
    elif [[ "${server_ver}" =~ ^v1\.35\. ]]; then
        log_check "PASS" "Kubernetes" "Cluster Version Compatibility" "Server ${server_ver} aligns with Mayastor v2.12.2 upstream qualified version"
    else
        log_check "WARNING" "Kubernetes" "Cluster Version Compatibility" "Server ${server_ver} diverges from planned Kubernetes 1.35/1.36 compatibility window"
    fi

    nodes_json="$(kubectl get nodes -o json 2>/dev/null)"
    node_count="$(echo "${nodes_json}" | jq '.items | length')"
    ready_count="$(echo "${nodes_json}" | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')"
    engine_labeled_count="$(echo "${nodes_json}" | jq '[.items[] | select(.metadata.labels["openebs.io/engine"] == "mayastor")] | length')"
    hp_capable_nodes="$(echo "${nodes_json}" | jq '[.items[] | select((.status.allocatable["hugepages-2Mi"] // "0") != "0")] | length')"

    if [[ "${ready_count}" -ge 3 ]] && [[ "${node_count}" -ge 3 ]]; then
        log_check "PASS" "Kubernetes" "3-Worker Replica Topology" "${ready_count}/${node_count} Ready nodes support 3-replica Mayastor distribution"
    else
        log_check "FAIL" "Kubernetes" "3-Worker Replica Topology" "Only ${ready_count}/${node_count} Ready node(s); 3-replica Mayastor target design requires >=3 dedicated storage worker nodes"
    fi

    if [[ "${engine_labeled_count}" -ge 3 ]]; then
        log_check "PASS" "Kubernetes" "Mayastor Engine Node Labels" "${engine_labeled_count} nodes carry label openebs.io/engine=mayastor"
    elif [[ "${engine_labeled_count}" -ge 1 ]]; then
        log_check "WARNING" "Kubernetes" "Mayastor Engine Node Labels" "Only ${engine_labeled_count} node(s) labeled openebs.io/engine=mayastor; 3 required for repl=3"
    else
        log_check "FAIL" "Kubernetes" "Mayastor Engine Node Labels" "Zero nodes carry openebs.io/engine=mayastor scheduling label"
    fi

    if [[ "${hp_capable_nodes}" -ge 3 ]]; then
        log_check "PASS" "Kubernetes" "Node Allocatable hugepages-2Mi" "${hp_capable_nodes} nodes advertise allocatable hugepages-2Mi resources"
    else
        log_check "FAIL" "Kubernetes" "Node Allocatable hugepages-2Mi" "Only ${hp_capable_nodes} node(s) advertise hugepages-2Mi allocatable capacity; io-engine DaemonSet will remain Pending"
    fi

    if kubectl get crd diskpools.openebs.io >/dev/null 2>&1; then
        log_check "PASS" "Kubernetes" "Mayastor DiskPool CRD Presence" "CRD diskpools.openebs.io already registered on cluster"
    else
        log_check "WARNING" "Kubernetes" "Mayastor DiskPool CRD Presence" "CRD diskpools.openebs.io not yet installed (expected prior to Helm deployment)"
    fi
}

generate_reports() {
    mkdir -p "${REPORT_DIR}"
    local text_file="${REPORT_DIR}/mayastor-prerequisites-${TIMESTAMP}.txt"
    local json_file="${REPORT_DIR}/mayastor-prerequisites-${TIMESTAMP}.json"

    if [[ "${OUTPUT_FORMAT}" == "text" ]] || [[ "${OUTPUT_FORMAT}" == "both" ]]; then
        {
            echo "=============================================================================="
            echo "       OpenEBS Mayastor (v2.12.2 / Chart 4.6.2) Prerequisite Audit"
            echo "=============================================================================="
            echo "Report Date:    ${REPORT_DATE}"
            echo "Host / Kernel:  $(hostname) / $(uname -r)"
            echo "WSL2 Detected:  ${IS_WSL2}"
            echo "Summary:        PASS: ${COUNT_PASS} | WARN: ${COUNT_WARN} | FAIL: ${COUNT_FAIL} | N/T: ${COUNT_NOT_TESTABLE}"
            echo "------------------------------------------------------------------------------"
            printf "%-6s | %-12s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
            echo "------------------------------------------------------------------------------"
            for item in "${JSON_ITEMS[@]}"; do
                local st cat ttl det
                st="$(echo "${item}" | jq -r '.status')"
                cat="$(echo "${item}" | jq -r '.category')"
                ttl="$(echo "${item}" | jq -r '.title')"
                det="$(echo "${item}" | jq -r '.details')"
                printf "%-6s | %-12s | %-34s | %s\n" "[${st:0:4}]" "[${cat}]" "${ttl}" "${det}"
            done
            echo "=============================================================================="
        } >"${text_file}"
    fi

    if [[ "${OUTPUT_FORMAT}" == "json" ]] || [[ "${OUTPUT_FORMAT}" == "both" ]]; then
        local checks_json="[]"
        if [[ "${#JSON_ITEMS[@]}" -gt 0 ]]; then
            checks_json="$(printf '%s\n' "${JSON_ITEMS[@]}" | jq -s '.')"
        fi
        jq -n \
            --arg reportDate "${REPORT_DATE}" \
            --arg host "$(hostname)" \
            --arg kernel "$(uname -r)" \
            --argjson isWsl2 "${IS_WSL2}" \
            --argjson pass "${COUNT_PASS}" \
            --argjson warn "${COUNT_WARN}" \
            --argjson fail "${COUNT_FAIL}" \
            --argjson nt "${COUNT_NOT_TESTABLE}" \
            --argjson checks "${checks_json}" \
            '{
              metadata: {
                reportDate: $reportDate,
                hostname: $host,
                kernel: $kernel,
                wsl2Detected: $isWsl2,
                chartTarget: "openebs/openebs:4.6.2",
                mayastorTarget: "2.12.2",
                summary: {
                  pass: $pass,
                  warning: $warn,
                  fail: $fail,
                  notTestable: $nt
                }
              },
              checks: $checks
            }' >"${json_file}"
    fi

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "\n${COLOR_GREEN}[INFO]${COLOR_RESET} Reports archived to:"
        [[ "${OUTPUT_FORMAT}" != "json" ]] && echo "  - ${text_file}"
        [[ "${OUTPUT_FORMAT}" != "text" ]] && echo "  - ${json_file}"
    fi
}

main() {
    for req in awk grep jq uname lsmod; do
        if ! command -v "${req}" >/dev/null 2>&1; then
            echo "Error: Mandatory host inspection command '${req}' missing from PATH." >&2
            exit 2
        fi
    done

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}${COLOR_BOLD}=============================================================================="
        echo -e "     OpenEBS Mayastor v2.12.2 — Non-Destructive Prerequisite Validator"
        echo -e "==============================================================================${COLOR_RESET}"
        printf "%-6s | %-12s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
    fi

    detect_environment
    check_cpu
    check_memory_and_hugepages
    check_kernel_support
    check_storage_devices_readonly
    check_network_ports
    check_kubernetes_readiness

    generate_reports

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
        echo -e "${COLOR_BOLD}Prerequisite Validation Summary:${COLOR_RESET}"
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
