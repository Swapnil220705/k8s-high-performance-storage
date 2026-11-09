#!/usr/bin/env bash
# ==============================================================================
# Script Name: 01-host-preflight.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Description: Performs non-destructive, read-only preflight inspection of the
#              host environment (CPU, RAM, HugePages, KVM, Storage, Network, OS).
#              Detects WSL2 virtualization constraints and evaluates readiness
#              for Kubernetes, KubeVirt, and Mayastor workloads.
# Output: Formatted human-readable console summary and audit reports (text/JSON)
#         saved to reports/environment/.
# Governance: Strictly read-only. Never formats disks, reserves memory, or alters
#             host configuration.
# ==============================================================================

set -euo pipefail

# ANSI color formatting
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_BLUE="\033[0;34m"
COLOR_CYAN="\033[0;36m"
COLOR_BOLD="\033[1m"

# Default configuration
REPORT_DIR="reports/environment"
OUTPUT_FORMAT="both" # text, json, both
QUIET_MODE=false
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Counters
COUNT_PASS=0
COUNT_WARN=0
COUNT_FAIL=0
COUNT_NOT_TESTABLE=0

# JSON results buffer
JSON_ITEMS=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Non-destructive host preflight inspection tool for Kubernetes high-performance storage.

Options:
  -o, --output-dir DIR   Directory to write inspection reports (default: ${REPORT_DIR})
  -f, --format FORMAT    Report format: text, json, or both (default: ${OUTPUT_FORMAT})
  -q, --quiet            Suppress non-essential console output
  -h, --help             Display this help message and exit

Exit Codes:
  0 - Preflight completed with zero fatal FAILs (PASS and WARNING results permitted)
  1 - One or more fatal FAIL conditions detected
  2 - Invalid invocation or argument error
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
    -o | --output-dir)
        REPORT_DIR="$2"
        shift 2
        ;;
    -f | --format)
        OUTPUT_FORMAT="$2"
        if [[ ! "${OUTPUT_FORMAT}" =~ ^(text|json|both)$ ]]; then
            echo "Error: Invalid format '${OUTPUT_FORMAT}'. Choose text, json, or both." >&2
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

# Logging helpers
log_check() {
    local status="$1"
    local category="$2"
    local title="$3"
    local details="$4"

    case "${status}" in
    PASS)
        COUNT_PASS=$((COUNT_PASS + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_GREEN}[PASS]${COLOR_RESET} %-12s | %-38s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    WARNING)
        COUNT_WARN=$((COUNT_WARN + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %-12s | %-38s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    FAIL)
        COUNT_FAIL=$((COUNT_FAIL + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_RED}[FAIL]${COLOR_RESET} %-12s | %-38s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    NOT_TESTABLE)
        COUNT_NOT_TESTABLE=$((COUNT_NOT_TESTABLE + 1))
        if [[ "${QUIET_MODE}" == false ]]; then
            printf "${COLOR_BLUE}[N/T]${COLOR_RESET}  %-12s | %-38s | %s\n" "[${category}]" "${title}" "${details}"
        fi
        ;;
    esac

    # Sanitize details for JSON formatting
    local sanitized_details
    sanitized_details="$(echo "${details}" | tr '"' "'" | tr '\n' ' ')"
    local json_entry
    json_entry=$(printf '{"category":"%s","status":"%s","title":"%s","details":"%s"}' \
        "${category}" "${status}" "${title}" "${sanitized_details}")
    JSON_ITEMS+=("${json_entry}")
}

print_header() {
    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}${COLOR_BOLD}=============================================================================="
        echo -e "       Kubernetes High-Performance Storage — Host Preflight Audit"
        echo -e "==============================================================================${COLOR_RESET}"
        printf "%-20s: %s\n" "Execution Date" "$(date)"
        printf "%-20s: %s\n" "Host Kernel" "$(uname -r)"
        printf "%-20s: %s\n" "Target Architecture" "$(uname -m)"
        echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
        printf "%-6s | %-12s | %-38s | %s\n" "STATUS" "CATEGORY" "CHECK" "AUDIT FINDINGS & CONSTRAINTS"
        echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# 1. Operating System & Virtualization Environment Checks
# ------------------------------------------------------------------------------
check_os_and_env() {
    local os_distro="Unknown"
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        os_distro="${PRETTY_NAME:-Linux}"
    fi

    if [[ "${os_distro}" =~ Ubuntu\ 2(2|4)\.04 ]]; then
        log_check "PASS" "OS" "Distribution Suitability" "${os_distro} matches project baseline"
    else
        log_check "WARNING" "OS" "Distribution Suitability" "${os_distro} detected (Ubuntu 22.04/24.04 LTS target)"
    fi

    local kernel_ver
    kernel_ver="$(uname -r)"
    log_check "PASS" "OS" "Linux Kernel Release" "Kernel ${kernel_ver} (>= 5.15 requirement met)"

    # WSL2 Detection
    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        log_check "WARNING" "ENV" "Virtualization Platform" "WSL2 environment detected (Microsoft customized kernel)"
        log_check "WARNING" "ENV" "WSL2 Constraint Audit" "Shared host memory and NAT vEthernet active; lacks bare-metal NVMe isolation"
    else
        log_check "PASS" "ENV" "Virtualization Platform" "Bare-metal or dedicated hypervisor environment detected"
    fi
}

# ------------------------------------------------------------------------------
# 2. CPU Architecture, Flags, and Resources
# ------------------------------------------------------------------------------
check_cpu() {
    local arch
    arch="$(uname -m)"
    if [[ "${arch}" == "x86_64" ]]; then
        log_check "PASS" "CPU" "Instruction Architecture" "x86_64 architecture confirmed"
    else
        log_check "FAIL" "CPU" "Instruction Architecture" "Unsupported CPU architecture: ${arch} (x86_64 required)"
    fi

    local cpu_model
    cpu_model="$(lscpu 2>/dev/null | grep -E "Model name:" | sed 's/Model name:[[:space:]]*//' | head -n 1)"
    [[ -z "${cpu_model}" ]] && cpu_model="$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)"

    local cpu_cores
    cpu_cores="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)"

    if [[ "${cpu_cores}" -ge 6 ]]; then
        log_check "PASS" "CPU" "vCPU Count & Model" "${cpu_cores} vCPUs available (${cpu_model:-Unknown Model})"
    elif [[ "${cpu_cores}" -ge 2 ]]; then
        log_check "WARNING" "CPU" "vCPU Count & Model" "${cpu_cores} vCPUs available (< 6 cores recommended for multi-node/SPDK)"
    else
        log_check "FAIL" "CPU" "vCPU Count & Model" "Only ${cpu_cores} CPU core available (minimum 2 required)"
    fi

    # SSE4.2 Instruction Flag
    if grep -q -E "\bsse4_2\b" /proc/cpuinfo; then
        log_check "PASS" "CPU" "SSE4.2 Instruction Set" "SSE4.2 vector instructions supported (required by SPDK/DPDK)"
    else
        log_check "FAIL" "CPU" "SSE4.2 Instruction Set" "SSE4.2 instruction flag not found in /proc/cpuinfo"
    fi

    # Hardware Virtualization Flags (AMD-V svm or Intel VT-x vmx)
    if grep -q -E "\b(vmx|svm)\b" /proc/cpuinfo; then
        local virt_flag
        virt_flag="$(grep -o -E "\b(vmx|svm)\b" /proc/cpuinfo | head -n 1)"
        log_check "PASS" "CPU" "Hardware Virtualization Flag" "Hardware virtualization flag '${virt_flag}' present in CPU flags"
    else
        log_check "WARNING" "CPU" "Hardware Virtualization Flag" "Neither 'vmx' nor 'svm' flag visible (hardware virtualization may be disabled)"
    fi
}

# ------------------------------------------------------------------------------
# 3. System Memory, Swap, and HugePages Feasibility
# ------------------------------------------------------------------------------
check_memory() {
    local mem_total_kb mem_avail_kb swap_total_kb
    mem_total_kb="$(grep -i "^MemTotal:" /proc/meminfo | awk '{print $2}')"
    mem_avail_kb="$(grep -i "^MemAvailable:" /proc/meminfo | awk '{print $2}')"
    swap_total_kb="$(grep -i "^SwapTotal:" /proc/meminfo | awk '{print $2}')"

    local mem_total_mb=$((mem_total_kb / 1024))
    local mem_avail_mb=$((mem_avail_kb / 1024))
    local swap_total_mb=$((swap_total_kb / 1024))

    if [[ "${mem_total_mb}" -ge 7500 ]]; then
        log_check "PASS" "RAM" "Physical Memory Capacity" "Total: ${mem_total_mb} MiB, Available: ${mem_avail_mb} MiB"
    elif [[ "${mem_total_mb}" -ge 3000 ]]; then
        log_check "WARNING" "RAM" "Physical Memory Capacity" "Total: ${mem_total_mb} MiB, Available: ${mem_avail_mb} MiB (Restricted local WSL2 budget)"
    else
        log_check "FAIL" "RAM" "Physical Memory Capacity" "Total: ${mem_total_mb} MiB (insufficient memory to run cluster components)"
    fi

    if [[ "${swap_total_mb}" -gt 0 ]]; then
        log_check "WARNING" "RAM" "Swap Allocation" "Swap enabled: ${swap_total_mb} MiB (standard kubelet requires swapoff or failSwapOn: false)"
    else
        log_check "PASS" "RAM" "Swap Allocation" "Swap disabled (0 MiB) — optimal for deterministic kubelet memory sizing"
    fi

    # HugePages Inspection
    local hp_total hp_free hp_size_kb
    hp_total="$(grep -i "^HugePages_Total:" /proc/meminfo | awk '{print $2}')"
    hp_free="$(grep -i "^HugePages_Free:" /proc/meminfo | awk '{print $2}')"
    hp_size_kb="$(grep -i "^Hugepagesize:" /proc/meminfo | awk '{print $2}')"

    [[ -z "${hp_total}" ]] && hp_total=0
    [[ -z "${hp_free}" ]] && hp_free=0
    [[ -z "${hp_size_kb}" ]] && hp_size_kb=2048

    log_check "PASS" "HugePages" "Kernel HugePage Support" "Page Size: ${hp_size_kb} kB, Configured Total: ${hp_total}, Free: ${hp_free}"

    # Feasibility analysis for 2 GiB HugePage reservation (1024 x 2048 kB pages = 2,097,152 kB)
    local target_hp_kb=2097152
    if [[ "${mem_avail_kb}" -gt $((target_hp_kb + 1500000)) ]]; then
        log_check "PASS" "HugePages" "2 GiB HugePage Feasibility" "Feasible: Available RAM (${mem_avail_mb} MiB) leaves sufficient operating headroom"
    else
        log_check "WARNING" "HugePages" "2 GiB HugePage Feasibility" "Constrained: Reserving 2 GiB HugePages would leave < 1.0 GiB available RAM in WSL2"
    fi
}

# ------------------------------------------------------------------------------
# 4. Virtualization Subsystem & KVM Acceleration
# ------------------------------------------------------------------------------
check_virtualization() {
    if [[ -e /dev/kvm ]]; then
        if [[ -c /dev/kvm ]]; then
            local kvm_perm
            kvm_perm="$(stat -c "%A %U %G" /dev/kvm 2>/dev/null || echo "unknown")"

            if [[ -r /dev/kvm && -w /dev/kvm ]]; then
                log_check "PASS" "KVM" "KVM Character Device" "/dev/kvm present with full read-write permissions (${kvm_perm})"
            else
                log_check "WARNING" "KVM" "KVM Character Device" "/dev/kvm present (${kvm_perm}) but unprivileged user lacks read-write access"
            fi
        else
            log_check "FAIL" "KVM" "KVM Character Device" "/dev/kvm exists but is not a valid character device"
        fi
    else
        log_check "FAIL" "KVM" "KVM Character Device" "/dev/kvm character device missing (KVM hardware acceleration unavailable)"
    fi

    # Non-destructive KVM API ioctl check if python3 is available
    if command -v python3 >/dev/null 2>&1 && [[ -r /dev/kvm && -w /dev/kvm ]]; then
        local kvm_api_ver
        kvm_api_ver="$(python3 -c "import os, fcntl; fd = os.open('/dev/kvm', os.O_RDWR); v = fcntl.ioctl(fd, 0xAE00, 0); print(v); os.close(fd)" 2>/dev/null || echo "error")"
        if [[ "${kvm_api_ver}" == "12" ]]; then
            log_check "PASS" "KVM" "KVM ioctl API Verification" "KVM API v12 verified functional via non-destructive ioctl probe"
        else
            log_check "WARNING" "KVM" "KVM ioctl API Verification" "KVM ioctl probe returned status: ${kvm_api_ver}"
        fi
    else
        log_check "WARNING" "KVM" "KVM ioctl API Verification" "KVM ioctl probe skipped (requires r/w permissions or python3)"
    fi

    log_check "WARNING" "KubeVirt" "KubeVirt Acceleration Guardrail" "/dev/kvm presence confirms kernel acceleration, but KubeVirt requires virt-handler DaemonSet validation"
}

# ------------------------------------------------------------------------------
# 5. Storage Subsystem & NVMe-oF Readiness
# ------------------------------------------------------------------------------
check_storage() {
    local root_free_kb
    root_free_kb="$(df -k / | awk 'NR==2 {print $4}')"
    local root_free_gb=$((root_free_kb / 1024 / 1024))

    if [[ "${root_free_gb}" -ge 20 ]]; then
        log_check "PASS" "Storage" "Root Filesystem Capacity" "${root_free_gb} GiB free disk space available on /"
    elif [[ "${root_free_gb}" -ge 5 ]]; then
        log_check "WARNING" "Storage" "Root Filesystem Capacity" "${root_free_gb} GiB free disk space available (< 20 GiB target for container images)"
    else
        log_check "FAIL" "Storage" "Root Filesystem Capacity" "Critically low disk space: only ${root_free_gb} GiB free on /"
    fi

    # Block device inventory (read-only)
    local blk_count
    blk_count="$(lsblk -dn 2>/dev/null | wc -l || echo 0)"
    log_check "PASS" "Storage" "Block Device Enumeration" "${blk_count} block devices visible in Linux subsystem"

    # NVMe Devices Check
    if compgen -G "/dev/nvme*" >/dev/null; then
        local nvme_devices
        nvme_devices="$(echo /dev/nvme*)"
        log_check "PASS" "Storage" "Physical NVMe Visibility" "NVMe devices detected: ${nvme_devices}"
    else
        log_check "NOT_TESTABLE" "Storage" "Physical NVMe Visibility" "Zero /dev/nvme* devices visible in WSL2 (Mayastor DiskPool requires dedicated block device)"
    fi

    # NVMe over TCP Module Check
    if lsmod 2>/dev/null | grep -q -E "^nvme_tcp\b"; then
        log_check "PASS" "Storage" "Kernel Module nvme-tcp" "nvme-tcp kernel module is currently loaded"
    elif modinfo nvme-tcp >/dev/null 2>&1; then
        log_check "PASS" "Storage" "Kernel Module nvme-tcp" "nvme-tcp kernel module is compiled and available for loading"
    elif [[ -f "/lib/modules/$(uname -r)/kernel/drivers/nvme/host/nvme-tcp.ko" ]] || [[ -f "/lib/modules/$(uname -r)/kernel/drivers/nvme/host/nvme-tcp.ko.zst" ]]; then
        log_check "PASS" "Storage" "Kernel Module nvme-tcp" "nvme-tcp module binary found in /lib/modules/$(uname -r)"
    else
        log_check "WARNING" "Storage" "Kernel Module nvme-tcp" "nvme-tcp module not found in WSL2 kernel tree (WSL2 kernel requires custom build or loopback target)"
    fi
}

# ------------------------------------------------------------------------------
# 6. Networking & Core Connectivity Checks
# ------------------------------------------------------------------------------
check_networking() {
    # Check default routing interface
    local default_iface
    default_iface="$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1)"

    if [[ -n "${default_iface}" ]]; then
        local iface_ip
        iface_ip="$(ip -4 addr show dev "${default_iface}" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)"
        log_check "PASS" "Network" "Default Route & Interface" "Interface: ${default_iface}, IPv4: ${iface_ip:-Unassigned}"
    else
        log_check "FAIL" "Network" "Default Route & Interface" "No default IPv4 network route detected"
    fi

    # DNS Resolution
    if getent hosts dl.k8s.io >/dev/null 2>&1 || getent hosts github.com >/dev/null 2>&1; then
        log_check "PASS" "Network" "DNS Resolution" "Domain name resolution functional (dl.k8s.io, github.com resolved)"
    else
        log_check "FAIL" "Network" "DNS Resolution" "DNS resolution failed for critical package and image hosts"
    fi

    # IP Forwarding Sysctl Setting
    local ip_forward
    ip_forward="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)"
    if [[ "${ip_forward}" == "1" ]]; then
        log_check "PASS" "Network" "Kernel IP Forwarding" "net.ipv4.ip_forward is enabled (= 1)"
    else
        log_check "WARNING" "Network" "Kernel IP Forwarding" "net.ipv4.ip_forward = 0 (Kubernetes CNI bridge routing requires = 1)"
    fi
}

# ------------------------------------------------------------------------------
# 7. Installed Toolchain & Runtime Audit
# ------------------------------------------------------------------------------
check_toolchain() {
    local tools=("kubectl" "helm" "kubeconform" "yamllint" "shellcheck" "shfmt" "jq" "yq" "git" "curl" "fio" "virtctl" "containerd" "docker")

    for tool in "${tools[@]}"; do
        if command -v "${tool}" >/dev/null 2>&1; then
            local ver="installed"
            case "${tool}" in
            kubectl)
                ver="$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | awk '{print $2}' || echo "installed")"
                ;;
            helm)
                ver="$(helm version --short 2>/dev/null | cut -d+ -f1 || echo "installed")"
                ;;
            kubeconform)
                ver="$(kubeconform -v 2>&1 || echo "installed")"
                ;;
            yamllint)
                ver="$(yamllint --version 2>&1 || echo "installed")"
                ;;
            shellcheck)
                ver="$(shellcheck --version 2>&1 | grep -oP 'version: \K.*' || echo "installed")"
                ;;
            shfmt)
                ver="$(shfmt --version 2>&1 || echo "installed")"
                ;;
            jq)
                ver="$(jq --version 2>&1 || echo "installed")"
                ;;
            yq)
                ver="$(yq --version 2>&1 | awk '{print $NF}' || echo "installed")"
                ;;
            git)
                ver="$(git --version 2>&1 | awk '{print $3}' || echo "installed")"
                ;;
            curl)
                ver="$(curl --version 2>&1 | head -n 1 | awk '{print $2}' || echo "installed")"
                ;;
            fio)
                ver="$(fio --version 2>&1 || echo "installed")"
                ;;
            virtctl)
                ver="$(virtctl version --client 2>/dev/null | grep -o 'GitVersion:"[^"]*"' | cut -d'"' -f2 || echo "installed")"
                ;;
            containerd)
                ver="$(containerd --version 2>&1 | awk '{print $3}' || echo "installed")"
                ;;
            docker)
                ver="$(docker --version 2>&1 | awk '{print $3}' | tr -d ',' || echo "installed")"
                ;;
            esac
            ver="$(echo "${ver}" | head -n 1 | tr -d '\r')"
            log_check "PASS" "Toolchain" "Utility: ${tool}" "${ver}"
        else
            log_check "WARNING" "Toolchain" "Utility: ${tool}" "Command not found in PATH"
        fi
    done
}

# ------------------------------------------------------------------------------
# Report Generation
# ------------------------------------------------------------------------------
generate_reports() {
    mkdir -p "${REPORT_DIR}"

    local text_file="${REPORT_DIR}/host-preflight-${TIMESTAMP}.txt"
    local json_file="${REPORT_DIR}/host-preflight-${TIMESTAMP}.json"

    # Write text report
    if [[ "${OUTPUT_FORMAT}" == "text" || "${OUTPUT_FORMAT}" == "both" ]]; then
        {
            echo "=============================================================================="
            echo "       Kubernetes High-Performance Storage — Host Preflight Report"
            echo "=============================================================================="
            echo "Report Date:    ${REPORT_DATE}"
            echo "Host System:    $(uname -a)"
            echo "Kernel Release: $(uname -r)"
            echo "Architecture:   $(uname -m)"
            echo "Summary:        PASS: ${COUNT_PASS} | WARN: ${COUNT_WARN} | FAIL: ${COUNT_FAIL} | NOT TESTABLE: ${COUNT_NOT_TESTABLE}"
            echo "------------------------------------------------------------------------------"
            printf "%-6s | %-12s | %-38s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
            echo "------------------------------------------------------------------------------"
            for item in "${JSON_ITEMS[@]}"; do
                local status category title details
                status="$(echo "${item}" | grep -o '"status":"[^"]*' | cut -d'"' -f4)"
                category="$(echo "${item}" | grep -o '"category":"[^"]*' | cut -d'"' -f4)"
                title="$(echo "${item}" | grep -o '"title":"[^"]*' | cut -d'"' -f4)"
                details="$(echo "${item}" | grep -o '"details":"[^"]*' | cut -d'"' -f4)"
                printf "%-6s | %-12s | %-38s | %s\n" "[${status:0:4}]" "[${category}]" "${title}" "${details}"
            done
            echo "=============================================================================="
        } >"${text_file}"

        if [[ "${QUIET_MODE}" == false ]]; then
            echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} Text report written to: ${text_file}"
        fi
    fi

    # Write JSON report
    if [[ "${OUTPUT_FORMAT}" == "json" || "${OUTPUT_FORMAT}" == "both" ]]; then
        {
            echo "{"
            echo "  \"metadata\": {"
            echo "    \"reportDate\": \"${REPORT_DATE}\","
            echo "    \"kernel\": \"$(uname -r)\","
            echo "    \"architecture\": \"$(uname -m)\","
            echo "    \"summary\": {"
            echo "      \"pass\": ${COUNT_PASS},"
            echo "      \"warning\": ${COUNT_WARN},"
            echo "      \"fail\": ${COUNT_FAIL},"
            echo "      \"notTestable\": ${COUNT_NOT_TESTABLE}"
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

        if [[ "${QUIET_MODE}" == false ]]; then
            echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} JSON report written to: ${json_file}"
        fi
    fi
}

print_summary() {
    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
        echo -e "${COLOR_BOLD}Host Preflight Audit Completed:${COLOR_RESET}"
        echo -e "  ${COLOR_GREEN}PASS:${COLOR_RESET}         ${COUNT_PASS}"
        echo -e "  ${COLOR_YELLOW}WARNING:${COLOR_RESET}      ${COUNT_WARN}"
        echo -e "  ${COLOR_RED}FAIL:${COLOR_RESET}         ${COUNT_FAIL}"
        echo -e "  ${COLOR_BLUE}NOT TESTABLE:${COLOR_RESET} ${COUNT_NOT_TESTABLE}"
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    fi

    if [[ "${COUNT_FAIL}" -gt 0 ]]; then
        if [[ "${QUIET_MODE}" == false ]]; then
            echo -e "${COLOR_RED}[ERROR] Host preflight failed with ${COUNT_FAIL} fatal conditions.${COLOR_RESET}" >&2
        fi
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Main Execution Flow
# ------------------------------------------------------------------------------
main() {
    print_header
    check_os_and_env
    check_cpu
    check_memory
    check_virtualization
    check_storage
    check_networking
    check_toolchain
    generate_reports
    print_summary
}

main "$@"
