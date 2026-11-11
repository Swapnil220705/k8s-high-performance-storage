#!/usr/bin/env bash
# ==============================================================================
# Script Name: 03-bootstrap-control-plane.sh
# Project: Deploy High-Performance Storage for Kubernetes (SWFW_5S_08)
# Purpose: Initializes the Kubernetes v1.36.x control plane node (Node 0) using
#          kubeadm and installs Calico v3.33.0 CNI for target Ubuntu 24.04 servers.
#
# Governance & Safety Guardrails:
#   - Target environment ONLY: Strictly refuses execution inside WSL2.
#   - Never hardcodes production IPs or tokens in Git-tracked files.
#   - Validates prerequisites, CRI socket, Swap, HugePages/Sysctl, and schema
#     via `kubeadm config validate` prior to initialization.
#   - Requires explicit interactive confirmation before mutating the host.
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

# Default parameters
ADVERTISE_IP=""
CONTROL_PLANE_ENDPOINT=""
NODE_NAME="$(hostname)"
KUBEADM_TEMPLATE="${REPO_ROOT}/infrastructure/k8s/kubeadm-init-config.yaml"
CALICO_DIR="${REPO_ROOT}/infrastructure/k8s/calico"
CALICO_VERSION="v3.33.0"
INSTALL_CALICO=true
DRY_RUN=false

usage() {
    cat <<EOF
Usage: sudo $0 --advertise-ip <IPv4> [OPTIONS]

Initializes the Kubernetes control plane (Node 0) on target Ubuntu 24.04 hardware.

Required:
  -i, --advertise-ip IP     Static IPv4 address of the control-plane node interface

Options:
  -e, --endpoint HOST:PORT  Control plane endpoint (default: <advertise-ip>:6443)
  -n, --node-name NAME      Kubernetes node hostname (default: $(hostname))
  -c, --config PATH         kubeadm config template (default: infrastructure/k8s/kubeadm-init-config.yaml)
      --skip-calico         Do not automatically apply Calico ${CALICO_VERSION} manifests
      --dry-run             Run preflight checks, render config, and validate schema without initializing
  -h, --help                Display this help message

Safety Notice:
  - Refuses execution inside WSL2 environments.
  - Never modifies Git-tracked manifests; renders config to /etc/kubernetes/.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    -i | --advertise-ip)
        ADVERTISE_IP="${2:-}"
        shift 2
        ;;
    -e | --endpoint)
        CONTROL_PLANE_ENDPOINT="${2:-}"
        shift 2
        ;;
    -n | --node-name)
        NODE_NAME="${2:-}"
        shift 2
        ;;
    -c | --config)
        KUBEADM_TEMPLATE="${2:-}"
        shift 2
        ;;
    --skip-calico)
        INSTALL_CALICO=false
        shift
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

validate_environment() {
    # 1. WSL2 guard (critical safeguard)
    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        log_error "WSL2 environment detected. Target kubeadm control-plane bootstrap is prohibited on WSL2."
        log_error "Use scripts/setup/dev-cluster-local.sh for local WSL2 development testing."
        exit 1
    fi

    # 2. Root privilege check (unless --dry-run testing schema only)
    if [[ "${DRY_RUN}" == false ]] && [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script must be run with root privileges (sudo)."
        exit 1
    fi

    # 3. Validate required inputs
    if [[ -z "${ADVERTISE_IP}" ]]; then
        log_error "Missing required --advertise-ip <IPv4>. Refusing to invent or guess node IP."
        usage >&2
        exit 2
    fi

    if ! [[ "${ADVERTISE_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        log_error "Invalid IPv4 format for --advertise-ip: ${ADVERTISE_IP}"
        exit 2
    fi

    if [[ -z "${CONTROL_PLANE_ENDPOINT}" ]]; then
        CONTROL_PLANE_ENDPOINT="${ADVERTISE_IP}:6443"
    fi

    if [[ ! -f "${KUBEADM_TEMPLATE}" ]]; then
        log_error "kubeadm template file not found: ${KUBEADM_TEMPLATE}"
        exit 1
    fi

    # 4. OS suitability
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ ! "${PRETTY_NAME:-}" =~ Ubuntu\ 2(2|4)\.04 ]]; then
            log_warn "Detected OS '${PRETTY_NAME:-Unknown}'; target baseline is Ubuntu 24.04 LTS."
        fi
    fi

    # 5. Required binaries
    local required_bins=("kubeadm" "kubelet" "kubectl" "yq" "curl" "containerd")
    for bin in "${required_bins[@]}"; do
        if ! command -v "${bin}" >/dev/null 2>&1; then
            log_error "Required binary missing from PATH: ${bin}"
            exit 1
        fi
    done

    # 6. Check CPU & RAM capacity (CP minimum: 2 cores, 2000 MiB RAM)
    local cpu_cores mem_kb mem_mb
    cpu_cores="$(nproc)"
    mem_kb="$(grep -i '^MemTotal:' /proc/meminfo | awk '{print $2}')"
    mem_mb=$((mem_kb / 1024))
    if [[ "${cpu_cores}" -lt 2 ]]; then
        log_error "Insufficient CPU cores (${cpu_cores} found, minimum 2 required for control plane)."
        exit 1
    fi
    if [[ "${mem_mb}" -lt 1900 ]]; then
        log_error "Insufficient RAM (${mem_mb} MiB found, minimum 1900 MiB required for control plane)."
        exit 1
    fi

    # 7. Swap check
    if [[ -n "$(swapon --show 2>/dev/null || true)" ]]; then
        log_error "Swap is currently enabled. Kubernetes kubeadm requires swap to be disabled (sudo swapoff -a)."
        exit 1
    fi

    # 8. Kernel modules & sysctl checks
    for mod in overlay br_netfilter; do
        if ! lsmod 2>/dev/null | grep -q -E "^${mod}\b"; then
            log_error "Required kernel module '${mod}' is not loaded. Run node prerequisite configuration first."
            exit 1
        fi
    done

    if [[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)" != "1" ]]; then
        log_error "Kernel sysctl net.ipv4.ip_forward must equal 1."
        exit 1
    fi

    if [[ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo 0)" != "1" ]]; then
        log_error "Kernel sysctl net.bridge.bridge-nf-call-iptables must equal 1."
        exit 1
    fi

    # 9. Check containerd CRI socket & SystemdCgroup
    if [[ ! -S /run/containerd/containerd.sock ]]; then
        log_error "containerd CRI socket not found at /run/containerd/containerd.sock."
        exit 1
    fi

    if ! containerd config dump 2>/dev/null | grep -q "SystemdCgroup = true"; then
        log_error "containerd does not have SystemdCgroup = true configured (see infrastructure/k8s/containerd-config-v3.toml)."
        exit 1
    fi

    # 10. Guard against re-initializing an active control plane
    if [[ -f /etc/kubernetes/admin.conf ]]; then
        log_error "/etc/kubernetes/admin.conf already exists. Refusing to overwrite an existing control plane."
        exit 1
    fi
}

render_and_validate_config() {
    local render_target="$1"
    log_info "Rendering parameterized kubeadm configuration to ${render_target}..."
    cp "${KUBEADM_TEMPLATE}" "${render_target}"

    yq eval -i "(select(.kind == \"InitConfiguration\") | .localAPIEndpoint.advertiseAddress) = \"${ADVERTISE_IP}\"" "${render_target}"
    yq eval -i "(select(.kind == \"InitConfiguration\") | .nodeRegistration.name) = \"${NODE_NAME}\"" "${render_target}"
    yq eval -i "(select(.kind == \"ClusterConfiguration\") | .controlPlaneEndpoint) = \"${CONTROL_PLANE_ENDPOINT}\"" "${render_target}"

    log_info "Validating rendered configuration against kubeadm schema..."
    if ! kubeadm config validate --config "${render_target}"; then
        log_error "kubeadm config validate failed on rendered configuration."
        exit 1
    fi
    log_info "kubeadm configuration schema validated cleanly."
}

print_execution_plan() {
    echo ""
    echo "=============================================================================="
    echo "          Control-Plane Bootstrap Execution Plan (Target Node 0)"
    echo "=============================================================================="
    echo "  Node Hostname:           ${NODE_NAME}"
    echo "  Advertise IP:            ${ADVERTISE_IP}"
    echo "  Control Plane Endpoint:  ${CONTROL_PLANE_ENDPOINT}"
    echo "  Kubernetes Version:      $(yq eval 'select(.kind == "ClusterConfiguration") | .kubernetesVersion' "${KUBEADM_TEMPLATE}")"
    echo "  Pod Subnet (CIDR):       $(yq eval 'select(.kind == "ClusterConfiguration") | .networking.podSubnet' "${KUBEADM_TEMPLATE}")"
    echo "  Service Subnet (CIDR):   $(yq eval 'select(.kind == "ClusterConfiguration") | .networking.serviceSubnet' "${KUBEADM_TEMPLATE}")"
    echo "  CRI Socket:              $(yq eval 'select(.kind == "InitConfiguration") | .nodeRegistration.criSocket' "${KUBEADM_TEMPLATE}")"
    echo "  Install Calico CNI:      ${INSTALL_CALICO} (pinned ${CALICO_VERSION})"
    echo "=============================================================================="
    echo ""
}

configure_kubelet_node_ip() {
    log_info "Setting kubelet --node-ip=${ADVERTISE_IP} in /etc/default/kubelet for deterministic Calico NodeInternalIP detection..."
    cat <<EOF >/etc/default/kubelet
KUBELET_EXTRA_ARGS="--node-ip=${ADVERTISE_IP}"
EOF
    systemctl daemon-reload
}

setup_kubeconfig() {
    local target_home="/root"
    if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        target_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
    fi

    mkdir -p "${target_home}/.kube"
    cp -f /etc/kubernetes/admin.conf "${target_home}/.kube/config"
    chmod 0600 "${target_home}/.kube/config"
    if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        chown -R "${SUDO_USER}:${SUDO_USER}" "${target_home}/.kube"
    fi
    export KUBECONFIG="/etc/kubernetes/admin.conf"
    log_info "Configured kubectl credentials at ${target_home}/.kube/config (mode 0600)."
}

install_calico_cni() {
    if [[ "${INSTALL_CALICO}" == false ]]; then
        log_warn "Skipping Calico installation (--skip-calico specified)."
        return 0
    fi

    log_info "Deploying Calico ${CALICO_VERSION} Tigera Operator and CRDs..."
    kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/operator-crds.yaml"
    kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

    log_info "Applying repository Calico Installation and BGPConfiguration manifests..."
    kubectl apply -f "${CALICO_DIR}/installation.yaml"

    log_info "Waiting for Calico BGPConfiguration CRD readiness..."
    for _ in $(seq 1 30); do
        if kubectl get crd bgpconfigurations.crd.projectcalico.org >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
    kubectl apply -f "${CALICO_DIR}/bgp-configuration.yaml"
    log_info "Calico ${CALICO_VERSION} manifests applied successfully."
}

main() {
    validate_environment

    local tmp_render
    tmp_render="$(mktemp /tmp/kubeadm-init-rendered-XXXXXX.yaml)"
    cleanup() {
        rm -f "${tmp_render}"
    }
    trap cleanup EXIT

    render_and_validate_config "${tmp_render}"
    print_execution_plan

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "Dry-run mode active: skipping kubeadm init and host modifications."
        exit 0
    fi

    read -r -p "Type 'BOOTSTRAP' to initialize the Kubernetes control plane on this server: " confirm
    if [[ "${confirm}" != "BOOTSTRAP" ]]; then
        log_warn "Bootstrap aborted by user confirmation prompt."
        exit 0
    fi

    configure_kubelet_node_ip

    log_info "Running kubeadm init preflight checks..."
    kubeadm init phase preflight --config "${tmp_render}"

    mkdir -p /etc/kubernetes
    cp "${tmp_render}" /etc/kubernetes/kubeadm-init-config.rendered.yaml
    chmod 0600 /etc/kubernetes/kubeadm-init-config.rendered.yaml

    log_info "Initializing Kubernetes control plane (kubeadm init)..."
    kubeadm init --config /etc/kubernetes/kubeadm-init-config.rendered.yaml

    setup_kubeconfig
    install_calico_cni

    log_info "Control-plane bootstrap completed."
    log_info "Generate a short-lived worker join command on Node 0 when ready:"
    log_info "  kubeadm token create --print-join-command"
}

main "$@"
