#!/usr/bin/env bash
# ==============================================================================
# Script Name: 04-join-worker-node.sh
# Project: Deploy High-Performance Storage for Kubernetes (SWFW_5S_08)
# Purpose: Joins a worker/storage node (Nodes 1-3) to the Kubernetes cluster
#          using kubeadm JoinConfiguration on target Ubuntu 24.04 servers.
#
# Governance & Security Guardrails:
#   - Target environment ONLY: Strictly refuses execution inside WSL2.
#   - NEVER hardcodes tokens or CA hashes.
#   - NEVER passes secrets in command-line arguments visible to `ps` or writes
#     credentials into Git-tracked files.
#   - Accepts bootstrap tokens exclusively via 0600-protected `--token-file`
#     outside the repository or interactive hidden input (`read -rs`).
#   - Requires explicit interactive confirmation prior to `kubeadm join`.
# ==============================================================================

set -euo pipefail

# Standardized logging
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
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ENDPOINT=""
NODE_IP=""
NODE_NAME="$(hostname)"
CA_CERT_HASH=""
TOKEN_FILE=""
DRY_RUN=false

usage() {
    cat <<EOF
Usage: sudo $0 --endpoint <HOST:PORT> --node-ip <IPv4> --ca-cert-hash <sha256:HEX> [OPTIONS]

Joins a prepared Ubuntu 24.04 node into the target Kubernetes cluster.

Required:
  -e, --endpoint HOST:PORT     Control plane API endpoint (e.g. control-plane-ip:6443)
  -i, --node-ip IP             Static IPv4 address of this worker node (for Calico NodeInternalIP)
  -H, --ca-cert-hash HASH      Discovery CA certificate hash (format: sha256:<64-hex-chars>)

Options:
  -n, --node-name NAME         Kubernetes node hostname (default: $(hostname))
  -t, --token-file PATH        Path to root/user-only (0600/0400) file containing kubeadm token
                               (must be outside Git repo; prompts securely if omitted)
      --dry-run                Validate prerequisites and join schema without modifying host
  -h, --help                   Display this help message

Security Policy:
  - Never pass raw bootstrap tokens via CLI flags.
  - Never store tokens or kubeconfigs inside ${REPO_ROOT}.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    -e | --endpoint)
        ENDPOINT="${2:-}"
        shift 2
        ;;
    -i | --node-ip)
        NODE_IP="${2:-}"
        shift 2
        ;;
    -n | --node-name)
        NODE_NAME="${2:-}"
        shift 2
        ;;
    -H | --ca-cert-hash)
        CA_CERT_HASH="${2:-}"
        shift 2
        ;;
    -t | --token-file)
        TOKEN_FILE="${2:-}"
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

validate_prerequisites() {
    # 1. WSL2 guard
    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        log_error "WSL2 environment detected. Target worker join script is prohibited on WSL2."
        exit 1
    fi

    # 2. Root privileges
    if [[ "${DRY_RUN}" == false ]] && [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script requires root privileges (sudo)."
        exit 1
    fi

    # 3. Parameter checks
    if [[ -z "${ENDPOINT}" || -z "${NODE_IP}" || -z "${CA_CERT_HASH}" ]]; then
        log_error "Missing required options (--endpoint, --node-ip, and --ca-cert-hash are mandatory)."
        usage >&2
        exit 2
    fi

    if ! [[ "${NODE_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        log_error "Invalid IPv4 format for --node-ip: ${NODE_IP}"
        exit 2
    fi

    if ! [[ "${CA_CERT_HASH}" =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
        log_error "Invalid CA cert hash format (expected sha256:<64 hex characters>)."
        exit 2
    fi

    # 4. Validate token file security if provided
    if [[ -n "${TOKEN_FILE}" ]]; then
        if [[ ! -f "${TOKEN_FILE}" ]]; then
            log_error "Token file not found: ${TOKEN_FILE}"
            exit 1
        fi
        local abs_token_path
        abs_token_path="$(readlink -f "${TOKEN_FILE}")"
        if [[ "${abs_token_path}" == "${REPO_ROOT}"* ]]; then
            log_error "Security violation: Token file must NEVER reside inside the Git repository (${REPO_ROOT})."
            exit 1
        fi
        local perms
        perms="$(stat -c '%a' "${TOKEN_FILE}")"
        if [[ "${perms}" != "600" && "${perms}" != "400" ]]; then
            log_error "Token file permissions too permissive (${perms}). Require 0600 or 0400."
            exit 1
        fi
    fi

    # 5. Required binaries
    for bin in kubeadm kubelet containerd; do
        if ! command -v "${bin}" >/dev/null 2>&1; then
            log_error "Required binary missing from PATH: ${bin}"
            exit 1
        fi
    done

    # 6. Check swap & kernel modules
    if [[ -n "$(swapon --show 2>/dev/null || true)" ]]; then
        log_error "Swap is enabled. Kubernetes worker nodes require swap disabled (sudo swapoff -a)."
        exit 1
    fi

    for mod in overlay br_netfilter; do
        if ! lsmod 2>/dev/null | grep -q -E "^${mod}\b"; then
            log_error "Required kernel module '${mod}' is not loaded."
            exit 1
        fi
    done

    if ! lsmod 2>/dev/null | grep -q -E "^nvme_tcp\b"; then
        log_warn "Kernel module nvme_tcp is not currently loaded (required later in M3 for Mayastor data plane)."
    fi

    if [[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)" != "1" ]]; then
        log_error "net.ipv4.ip_forward must equal 1."
        exit 1
    fi

    # 7. Check containerd CRI & cgroups
    if [[ ! -S /run/containerd/containerd.sock ]]; then
        log_error "containerd CRI socket missing at /run/containerd/containerd.sock."
        exit 1
    fi
    if ! containerd config dump 2>/dev/null | grep -q "SystemdCgroup = true"; then
        log_error "containerd must be configured with SystemdCgroup = true."
        exit 1
    fi

    # 8. Check CPU / RAM / KVM warnings for future Mayastor/KubeVirt workloads
    local cpu_cores mem_kb mem_mb
    cpu_cores="$(nproc)"
    mem_kb="$(grep -i '^MemTotal:' /proc/meminfo | awk '{print $2}')"
    mem_mb=$((mem_kb / 1024))
    if [[ "${cpu_cores}" -lt 6 ]]; then
        log_warn "Node has ${cpu_cores} CPU cores (< 6 cores recommended for Mayastor SPDK + KubeVirt workers)."
    fi
    if [[ "${mem_mb}" -lt 14000 ]]; then
        log_warn "Node has ${mem_mb} MiB RAM (< 16 GB minimum / 32 GB recommended for multi-VM live migration)."
    fi
    if [[ ! -c /dev/kvm ]]; then
        log_warn "/dev/kvm not found; KubeVirt hardware acceleration will be unavailable on this node."
    fi

    # 9. Guard against re-joining an already configured node
    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
        log_error "/etc/kubernetes/kubelet.conf already exists. Refusing to overwrite existing node state."
        exit 1
    fi
}

read_token_securely() {
    local token_val=""
    if [[ -n "${TOKEN_FILE}" ]]; then
        token_val="$(tr -d ' \t\r\n' <"${TOKEN_FILE}")"
    else
        echo -n "Enter kubeadm bootstrap token (hidden input, format [a-z0-9]{6}.[a-z0-9]{16}): " >&2
        read -rs token_val
        echo "" >&2
    fi

    if ! [[ "${token_val}" =~ ^[a-z0-9]{6}\.[a-z0-9]{16}$ ]]; then
        log_error "Invalid bootstrap token format."
        exit 1
    fi
    printf "%s" "${token_val}"
}

main() {
    validate_prerequisites

    local join_token=""
    if [[ "${DRY_RUN}" == true ]] && [[ -z "${TOKEN_FILE}" ]]; then
        # Use placeholder dummy format ONLY in offline dry-run schema validation
        join_token="000000.0000000000000000"
        log_info "Dry-run mode without --token-file: using ephemeral syntax placeholder for schema validation only."
    else
        join_token="$(read_token_securely)"
    fi

    local tmp_join_cfg
    tmp_join_cfg="$(mktemp /tmp/kubeadm-join-XXXXXX.yaml)"
    chmod 0600 "${tmp_join_cfg}"
    cleanup() {
        rm -f "${tmp_join_cfg}"
    }
    trap cleanup EXIT

    cat <<EOF >"${tmp_join_cfg}"
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "${ENDPOINT}"
    token: "${join_token}"
    caCertHashes:
      - "${CA_CERT_HASH}"
nodeRegistration:
  name: "${NODE_NAME}"
  criSocket: unix:///run/containerd/containerd.sock
EOF
    unset join_token

    log_info "Validating JoinConfiguration against kubeadm schema..."
    if ! kubeadm config validate --config "${tmp_join_cfg}"; then
        log_error "kubeadm config validate failed on JoinConfiguration."
        exit 1
    fi

    echo ""
    echo "=============================================================================="
    echo "          Worker Node Join Execution Plan (Target Worker)"
    echo "=============================================================================="
    echo "  Target Cluster API:      ${ENDPOINT}"
    echo "  Worker Node Hostname:    ${NODE_NAME}"
    echo "  Worker Node IP:          ${NODE_IP}"
    echo "  CRI Socket:              unix:///run/containerd/containerd.sock"
    echo "  Bootstrap Token:         [REDACTED]"
    echo "  CA Cert Hash:            ${CA_CERT_HASH:0:22}..."
    echo "=============================================================================="
    echo ""

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "Dry-run mode active: skipping kubeadm join and host modifications."
        exit 0
    fi

    read -r -p "Type 'JOIN' to join this worker node to ${ENDPOINT}: " confirm
    if [[ "${confirm}" != "JOIN" ]]; then
        log_warn "Worker join aborted by user confirmation prompt."
        exit 0
    fi

    log_info "Setting kubelet --node-ip=${NODE_IP} in /etc/default/kubelet..."
    cat <<EOF >/etc/default/kubelet
KUBELET_EXTRA_ARGS="--node-ip=${NODE_IP}"
EOF
    systemctl daemon-reload

    log_info "Executing kubeadm join..."
    kubeadm join --config "${tmp_join_cfg}"

    log_info "Worker node '${NODE_NAME}' successfully joined ${ENDPOINT}."
    log_info "Remember to inspect 'kubectl get nodes -o wide' from Node 0."
}

main "$@"
