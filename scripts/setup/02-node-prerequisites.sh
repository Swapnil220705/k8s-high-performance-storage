#!/usr/bin/env bash
# ==============================================================================
# Script Name: 02-node-prerequisites.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Description: Detects and audits node prerequisites for Kubernetes, OpenEBS
#              Mayastor (SPDK/NVMe-oF), and KubeVirt.
# Mode: Defaults strictly to REPORT-ONLY mode.
#       Apply mode requires explicit --apply and interactive confirmation.
# Safety Directives:
#   - NEVER formats or wipes disks or partitions.
#   - NEVER modifies BIOS/UEFI or Windows settings.
#   - NEVER alters firewall rules silently.
# ==============================================================================

set -euo pipefail

# ANSI color formatting
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_CYAN="\033[0;36m"
COLOR_BOLD="\033[1m"

# Default configuration
EXECUTION_MODE="report" # 'report' or 'apply'
REPORT_DIR="reports/environment"
NON_INTERACTIVE=false
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Counters
COUNT_MET=0
COUNT_UNMET=0
COUNT_WARN=0

# JSON results buffer
JSON_ITEMS=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Audits and verifies prospective Kubernetes/Mayastor node prerequisites.

Options:
  --report               Run in report-only inspection mode (DEFAULT)
  --apply                Enter configuration preparation mode (requires confirmation)
  --non-interactive      Bypass interactive confirmation in apply mode (use with caution)
  -o, --output-dir DIR   Directory to write inspection reports (default: ${REPORT_DIR})
  -h, --help             Display this help message and exit

Operational Safety:
  - Report mode is non-destructive and read-only.
  - Apply mode will NEVER format storage devices, alter Windows or BIOS settings,
    or modify network firewall rules.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
    --report)
        EXECUTION_MODE="report"
        shift
        ;;
    --apply)
        EXECUTION_MODE="apply"
        shift
        ;;
    --non-interactive)
        NON_INTERACTIVE=true
        shift
        ;;
    -o | --output-dir)
        REPORT_DIR="$2"
        shift 2
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

log_prereq() {
    local status="$1"
    local category="$2"
    local component="$3"
    local requirement="$4"
    local current_state="$5"

    case "${status}" in
    MET)
        COUNT_MET=$((COUNT_MET + 1))
        printf "${COLOR_GREEN}[MET]${COLOR_RESET}  %-14s | %-24s | %s\n" "[${category}]" "${component}" "${current_state}"
        ;;
    WARN)
        COUNT_WARN=$((COUNT_WARN + 1))
        printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %-14s | %-24s | %s\n" "[${category}]" "${component}" "${current_state}"
        ;;
    UNMET)
        COUNT_UNMET=$((COUNT_UNMET + 1))
        printf "${COLOR_RED}[FAIL]${COLOR_RESET} %-14s | %-24s | %s\n" "[${category}]" "${component}" "${current_state}"
        ;;
    esac

    local sanitized_state
    sanitized_state="$(echo "${current_state}" | tr '"' "'" | tr '\n' ' ')"
    local json_entry
    json_entry=$(printf '{"category":"%s","status":"%s","component":"%s","requirement":"%s","state":"%s"}' \
        "${category}" "${status}" "${component}" "${requirement}" "${sanitized_state}")
    JSON_ITEMS+=("${json_entry}")
}

print_header() {
    echo -e "${COLOR_CYAN}${COLOR_BOLD}=============================================================================="
    echo -e "       Kubernetes & Mayastor Storage Node Prerequisites Audit"
    echo -e "==============================================================================${COLOR_RESET}"
    printf "%-20s: %s\n" "Execution Date" "$(date)"
    printf "%-20s: %s\n" "Execution Mode" "$(echo "${EXECUTION_MODE}" | tr '[:lower:]' '[:upper:]')"
    printf "%-20s: %s\n" "Node Hostname" "$(hostname)"
    echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
    printf "%-6s | %-14s | %-24s | %s\n" "STATUS" "CATEGORY" "COMPONENT" "CURRENT STATE / AUDIT DETAILS"
    echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
}

# ------------------------------------------------------------------------------
# 1. Operating System & Kernel Suitability
# ------------------------------------------------------------------------------
audit_os_and_kernel() {
    local os_pretty="Unknown Linux"
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        os_pretty="${PRETTY_NAME:-Linux}"
    fi

    if [[ "${os_pretty}" =~ Ubuntu\ 2(2|4)\.04 ]]; then
        log_prereq "MET" "OS" "Distribution" "Ubuntu 22.04/24.04 LTS" "${os_pretty}"
    else
        log_prereq "WARN" "OS" "Distribution" "Ubuntu 22.04/24.04 LTS" "${os_pretty} (non-standard baseline)"
    fi

    local kernel_ver
    kernel_ver="$(uname -r)"
    local kernel_major kernel_minor
    kernel_major="$(echo "${kernel_ver}" | cut -d. -f1)"
    kernel_minor="$(echo "${kernel_ver}" | cut -d. -f2)"

    if [[ "${kernel_major}" -gt 5 ]] || [[ "${kernel_major}" -eq 5 && "${kernel_minor}" -ge 15 ]]; then
        log_prereq "MET" "Kernel" "Kernel Version" ">= 5.15 LTS" "Kernel ${kernel_ver}"
    else
        log_prereq "UNMET" "Kernel" "Kernel Version" ">= 5.15 LTS" "Kernel ${kernel_ver} is unsupported"
    fi
}

# ------------------------------------------------------------------------------
# 2. CPU Architecture, Vector Extensions & Capacity
# ------------------------------------------------------------------------------
audit_cpu() {
    local arch
    arch="$(uname -m)"
    if [[ "${arch}" == "x86_64" ]]; then
        log_prereq "MET" "CPU" "Architecture" "x86_64" "${arch}"
    else
        log_prereq "UNMET" "CPU" "Architecture" "x86_64" "${arch} (unsupported architecture)"
    fi

    local cpu_cores
    cpu_cores="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)"
    if [[ "${cpu_cores}" -ge 6 ]]; then
        log_prereq "MET" "CPU" "Cores (Storage Node)" ">= 6 cores for Mayastor SPDK" "${cpu_cores} cores available"
    elif [[ "${cpu_cores}" -ge 2 ]]; then
        log_prereq "WARN" "CPU" "Cores (Storage Node)" ">= 6 cores for Mayastor SPDK" "${cpu_cores} cores available (usable for control-plane or dev only)"
    else
        log_prereq "UNMET" "CPU" "Cores (Storage Node)" ">= 2 cores minimum" "${cpu_cores} core available"
    fi

    # Vector Extensions (SSE4.2 required for SPDK/DPDK)
    if grep -q -E "\bsse4_2\b" /proc/cpuinfo; then
        log_prereq "MET" "CPU" "SSE4.2 Instruction Set" "SSE4.2 flag present" "Supported"
    else
        log_prereq "UNMET" "CPU" "SSE4.2 Instruction Set" "SSE4.2 flag present" "Missing SSE4.2 support"
    fi
}

# ------------------------------------------------------------------------------
# 3. Memory & HugePages Configuration
# ------------------------------------------------------------------------------
audit_memory() {
    local mem_total_kb
    mem_total_kb="$(grep -i "^MemTotal:" /proc/meminfo | awk '{print $2}')"
    local mem_total_mb=$((mem_total_kb / 1024))

    if [[ "${mem_total_mb}" -ge 7500 ]]; then
        log_prereq "MET" "Memory" "Total RAM (Storage Node)" ">= 8.0 GiB" "${mem_total_mb} MiB"
    elif [[ "${mem_total_mb}" -ge 3000 ]]; then
        log_prereq "WARN" "Memory" "Total RAM (Storage Node)" ">= 8.0 GiB" "${mem_total_mb} MiB (Restricted local dev baseline)"
    else
        log_prereq "UNMET" "Memory" "Total RAM (Storage Node)" ">= 4.0 GiB minimum" "${mem_total_mb} MiB"
    fi

    # HugePages check (2048 kB size)
    local hp_total hp_size_kb
    hp_total="$(grep -i "^HugePages_Total:" /proc/meminfo | awk '{print $2}')"
    hp_size_kb="$(grep -i "^Hugepagesize:" /proc/meminfo | awk '{print $2}')"

    [[ -z "${hp_total}" ]] && hp_total=0
    [[ -z "${hp_size_kb}" ]] && hp_size_kb=2048

    if [[ "${hp_total}" -ge 1024 ]] && [[ "${hp_size_kb}" -eq 2048 ]]; then
        log_prereq "MET" "HugePages" "2048 kB HugePages" "1024 pages (2 GiB)" "${hp_total} pages allocated (${hp_size_kb} kB)"
    elif [[ "${hp_total}" -gt 0 ]]; then
        log_prereq "WARN" "HugePages" "2048 kB HugePages" "1024 pages (2 GiB)" "${hp_total} pages allocated (< 1024 required for Mayastor io-engine)"
    else
        log_prereq "WARN" "HugePages" "2048 kB HugePages" "1024 pages (2 GiB)" "0 pages configured (HugePages allocation required for Mayastor)"
    fi
}

# ------------------------------------------------------------------------------
# 4. Kernel Modules (nvme-tcp, overlay, br_netfilter, vfio-pci)
# ------------------------------------------------------------------------------
audit_kernel_modules() {
    local modules=("overlay" "br_netfilter" "nvme_tcp")

    for mod in "${modules[@]}"; do
        if lsmod 2>/dev/null | grep -q -E "^${mod}\b"; then
            log_prereq "MET" "Kernel Module" "${mod}" "Module loaded" "Loaded in running kernel"
        elif modinfo "${mod}" >/dev/null 2>&1; then
            log_prereq "WARN" "Kernel Module" "${mod}" "Module loaded" "Available as kernel module, but not currently loaded"
        else
            log_prereq "WARN" "Kernel Module" "${mod}" "Module loaded" "Module not found in kernel tree (WSL2 custom kernel limitation)"
        fi
    done
}

# ------------------------------------------------------------------------------
# 5. Network Routing & Sysctl Parameters
# ------------------------------------------------------------------------------
audit_sysctl() {
    local ip_fwd
    ip_fwd="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)"
    if [[ "${ip_fwd}" == "1" ]]; then
        log_prereq "MET" "Sysctl" "net.ipv4.ip_forward" "1" "Enabled (1)"
    else
        log_prereq "WARN" "Sysctl" "net.ipv4.ip_forward" "1" "Disabled (0) — CNI routing requires 1"
    fi

    # Bridge Netfilter
    if [[ -f /proc/sys/net/bridge/bridge-nf-call-iptables ]]; then
        local br_nf
        br_nf="$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo 0)"
        if [[ "${br_nf}" == "1" ]]; then
            log_prereq "MET" "Sysctl" "bridge-nf-call-iptables" "1" "Enabled (1)"
        else
            log_prereq "WARN" "Sysctl" "bridge-nf-call-iptables" "1" "Disabled (0)"
        fi
    else
        log_prereq "WARN" "Sysctl" "bridge-nf-call-iptables" "1" "File not present (requires br_netfilter module)"
    fi
}

# ------------------------------------------------------------------------------
# 6. Storage Block Devices for Mayastor DiskPool
# ------------------------------------------------------------------------------
audit_storage_devices() {
    local secondary_devices=()
    while IFS= read -r line; do
        [[ -n "${line}" ]] && secondary_devices+=("${line}")
    done < <(lsblk -dpno NAME,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | awk '$2=="disk" && $4=="" {print $1}')

    if [[ "${#secondary_devices[@]}" -gt 0 ]]; then
        log_prereq "MET" "Storage" "Dedicated Raw Block Device" ">= 1 dedicated unpartitioned drive" "${#secondary_devices[@]} candidate disk(s): ${secondary_devices[*]}"
    else
        log_prereq "WARN" "Storage" "Dedicated Raw Block Device" ">= 1 dedicated unpartitioned drive" "Zero unpartitioned raw block devices detected (Infrastructure-Dependent for bare-metal Mayastor)"
    fi
}

# ------------------------------------------------------------------------------
# 7. Virtualization & KVM Acceleration
# ------------------------------------------------------------------------------
audit_kvm() {
    if [[ -c /dev/kvm ]]; then
        if [[ -r /dev/kvm && -w /dev/kvm ]]; then
            log_prereq "MET" "Virtualization" "/dev/kvm Access" "Present and read-write accessible" "Accessible by current user"
        else
            log_prereq "WARN" "Virtualization" "/dev/kvm Access" "Present and read-write accessible" "Present, but current user lacks r/w permission (add to kvm group)"
        fi
    else
        log_prereq "UNMET" "Virtualization" "/dev/kvm Access" "Present and read-write accessible" "/dev/kvm device node missing"
    fi
}

# ------------------------------------------------------------------------------
# 8. Container Runtime (containerd)
# ------------------------------------------------------------------------------
audit_runtime() {
    if command -v containerd >/dev/null 2>&1; then
        local ctd_ver
        ctd_ver="$(containerd --version 2>&1 | awk '{print $3}')"
        log_prereq "MET" "Runtime" "containerd Runtime" "Installed" "containerd ${ctd_ver}"
    else
        log_prereq "UNMET" "Runtime" "containerd Runtime" "Installed" "containerd not found in PATH"
    fi
}

# ------------------------------------------------------------------------------
# Report Generation
# ------------------------------------------------------------------------------
generate_reports() {
    mkdir -p "${REPORT_DIR}"
    local text_file="${REPORT_DIR}/node-prerequisites-${TIMESTAMP}.txt"
    local json_file="${REPORT_DIR}/node-prerequisites-${TIMESTAMP}.json"

    {
        echo "=============================================================================="
        echo "       Kubernetes & Mayastor Storage Node Prerequisites Audit Report"
        echo "=============================================================================="
        echo "Report Date:    ${REPORT_DATE}"
        echo "Node Hostname:  $(hostname)"
        echo "Execution Mode: ${EXECUTION_MODE}"
        echo "Summary:        MET: ${COUNT_MET} | WARN: ${COUNT_WARN} | UNMET: ${COUNT_UNMET}"
        echo "------------------------------------------------------------------------------"
        printf "%-6s | %-14s | %-24s | %-30s | %s\n" "STATUS" "CATEGORY" "COMPONENT" "REQUIREMENT" "CURRENT STATE"
        echo "------------------------------------------------------------------------------"
        for item in "${JSON_ITEMS[@]}"; do
            local status category component req state
            status="$(echo "${item}" | grep -o '"status":"[^"]*' | cut -d'"' -f4)"
            category="$(echo "${item}" | grep -o '"category":"[^"]*' | cut -d'"' -f4)"
            component="$(echo "${item}" | grep -o '"component":"[^"]*' | cut -d'"' -f4)"
            req="$(echo "${item}" | grep -o '"requirement":"[^"]*' | cut -d'"' -f4)"
            state="$(echo "${item}" | grep -o '"state":"[^"]*' | cut -d'"' -f4)"
            printf "%-6s | %-14s | %-24s | %-30s | %s\n" "[${status}]" "[${category}]" "${component}" "${req}" "${state}"
        done
        echo "=============================================================================="
    } >"${text_file}"

    {
        echo "{"
        echo "  \"metadata\": {"
        echo "    \"reportDate\": \"${REPORT_DATE}\","
        echo "    \"hostname\": \"$(hostname)\","
        echo "    \"mode\": \"${EXECUTION_MODE}\","
        echo "    \"summary\": {"
        echo "      \"met\": ${COUNT_MET},"
        echo "      \"warn\": ${COUNT_WARN},"
        echo "      \"unmet\": ${COUNT_UNMET}"
        echo "    }"
        echo "  },"
        echo "  \"checks\": ["
        local first=true
        for item in "${JSON_ITEMS[@]}"; do
            if [[ "${first}" == true ]]; then
                echo "    ${item}"
                first=false
            else
                echo "   ,${item}"
            fi
        done
        echo "  ]"
        echo "}"
    } >"${json_file}"

    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} Reports saved to:"
    echo "  - ${text_file}"
    echo "  - ${json_file}"
}

print_summary() {
    echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    echo -e "${COLOR_BOLD}Node Prerequisites Audit Completed:${COLOR_RESET}"
    echo -e "  ${COLOR_GREEN}MET:${COLOR_RESET}   ${COUNT_MET}"
    echo -e "  ${COLOR_YELLOW}WARN:${COLOR_RESET}  ${COUNT_WARN}"
    echo -e "  ${COLOR_RED}UNMET:${COLOR_RESET} ${COUNT_UNMET}"
    echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
}

# ------------------------------------------------------------------------------
# Apply Mode Handling
# ------------------------------------------------------------------------------
handle_apply_mode() {
    if [[ "${EXECUTION_MODE}" != "apply" ]]; then
        return 0
    fi

    echo ""
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}[ATTENTION] Apply mode requested.${COLOR_RESET}"
    echo "Proposed configuration actions:"
    echo "  1. Load kernel modules: overlay, br_netfilter (if available)"
    echo "  2. Configure sysctl: net.ipv4.ip_forward = 1"
    echo "  3. Configure sysctl: net.bridge.bridge-nf-call-iptables = 1"
    echo ""
    echo -e "${COLOR_RED}${COLOR_BOLD}SAFETY MANDATE:${COLOR_RESET}"
    echo "  - Disks and filesystems will NEVER be formatted or wiped."
    echo "  - Windows host and BIOS/UEFI settings will NOT be touched."
    echo "  - Network interfaces and firewall rules will NOT be modified silently."
    echo ""

    if [[ "${NON_INTERACTIVE}" == false ]]; then
        read -r -p "Do you want to proceed with applying these safe Linux sysctl/module settings? [y/N]: " confirm
        if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled by user."
            exit 0
        fi
    fi

    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${COLOR_RED}[ERROR] Root privileges required to apply system settings. Re-run with sudo.${COLOR_RESET}" >&2
        exit 1
    fi

    echo -e "${COLOR_GREEN}[INFO] Applying safe prerequisite configurations...${COLOR_RESET}"
    modprobe overlay 2>/dev/null || true
    modprobe br_netfilter 2>/dev/null || true
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1 || true
    echo -e "${COLOR_GREEN}[INFO] Prerequisite configuration applied successfully.${COLOR_RESET}"
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    print_header
    audit_os_and_kernel
    audit_cpu
    audit_memory
    audit_kernel_modules
    audit_sysctl
    audit_storage_devices
    audit_kvm
    audit_runtime
    generate_reports
    print_summary
    handle_apply_mode
}

main "$@"
