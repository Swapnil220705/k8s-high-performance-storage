#!/usr/bin/env bash
# ==============================================================================
# Script Name: dev-cluster-local.sh
# Project: Deploy High-Performance Storage for Kubernetes (SWFW_5S_08)
# Purpose: Installs, manages, and validates a lightweight, resource-bounded
#          single-node K3s (v1.36.6+k3s1) local development cluster inside WSL2.
#
# Architectural Role & Safeguards:
#   - Uses isolated embedded containerd v2.3.7 LTS (/run/k3s/containerd/containerd.sock)
#     so pre-installed host Docker (29.1.3) and containerd (2.2.1) remain untouched.
#   - Disables traefik & servicelb to minimize RAM and disk footprint.
#   - Enforces pre-install RAM (>= 1500 MiB avail) and disk (>= 2 GiB free) guards.
#   - Local dev ONLY: Must NOT be represented as a 4-node production cluster.
#   - Does NOT install Mayastor or KubeVirt and does NOT reserve HugePages.
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

# Pinned Release Specification (Candidate B alignment: Kubernetes v1.36.6 + containerd v2.3.7)
K3S_VERSION="v1.36.6+k3s1"
K3S_URL_TAG="v1.36.6%2Bk3s1"
K3S_SHA256="66ceb8e67edfa547195135d74783bfadc2ecc04a91059e90ae5f70a3dbc98c15"
K3S_BIN="/usr/local/bin/k3s"
K3S_SERVICE="/etc/systemd/system/k3s.service"
K3S_DATA_DIR="/var/lib/rancher/k3s"
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

# Conservative Resource Safeguards
MIN_AVAIL_RAM_MB=1500
MIN_AVAIL_DISK_GB=2

usage() {
    cat <<EOF
Usage: $0 <COMMAND>

Manages the lightweight single-node K3s (${K3S_VERSION}) local development cluster.

Commands:
  install     Verify resource headroom, download verified K3s binary, and start cluster
  start       Start the local K3s systemd service and refresh kubeconfig
  stop        Stop the local K3s systemd service (frees RAM, preserves cluster state)
  restart     Restart the local K3s systemd service cleanly
  status      Show service status, resource usage, nodes, and system pods
  kubeconfig  Copy cluster kubeconfig cleanly to ~/.kube/config (mode 0600)
  uninstall   Stop K3s and remove its binaries/state (leaves Docker untouched)
EOF
}

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This action requires root privileges. Run with sudo: sudo $0 <COMMAND>"
        exit 1
    fi
}

check_resource_headroom() {
    local mem_avail_kb mem_avail_mb disk_avail_kb disk_avail_gb
    mem_avail_kb="$(grep -i '^MemAvailable:' /proc/meminfo | awk '{print $2}')"
    mem_avail_mb=$((mem_avail_kb / 1024))

    disk_avail_kb="$(df -k / | awk 'NR==2 {print $4}')"
    disk_avail_gb=$((disk_avail_kb / 1024 / 1024))

    log_info "Pre-flight resource check: MemAvailable=${mem_avail_mb} MiB, RootFree=${disk_avail_gb} GiB"

    if [[ "${mem_avail_mb}" -lt "${MIN_AVAIL_RAM_MB}" ]]; then
        log_error "Insufficient available RAM (${mem_avail_mb} MiB < ${MIN_AVAIL_RAM_MB} MiB required)."
        log_error "Refusing local cluster startup to prevent host instability."
        exit 1
    fi

    if [[ "${disk_avail_gb}" -lt "${MIN_AVAIL_DISK_GB}" ]]; then
        log_error "Insufficient free disk space (${disk_avail_gb} GiB < ${MIN_AVAIL_DISK_GB} GiB required)."
        exit 1
    fi
}

setup_kubeconfig() {
    if [[ ! -f "${K3S_KUBECONFIG}" ]]; then
        log_error "K3s kubeconfig not found at ${K3S_KUBECONFIG}."
        return 1
    fi

    local target_user="${SUDO_USER:-$(id -un)}"
    local target_home
    target_home="$(getent passwd "${target_user}" | cut -d: -f6)"
    [[ -z "${target_home}" ]] && target_home="${HOME}"

    local kube_dir="${target_home}/.kube"
    mkdir -p "${kube_dir}"
    cp -f "${K3S_KUBECONFIG}" "${kube_dir}/config"
    chmod 0600 "${kube_dir}/config"
    if [[ "${target_user}" != "root" ]]; then
        chown -R "${target_user}:${target_user}" "${kube_dir}"
    fi
    log_info "Updated kubeconfig at ${kube_dir}/config (mode 0600, context 'default')."
}

wait_for_cluster_ready() {
    log_info "Waiting for K3s API server and single-node Ready state..."
    local retries=45
    local ready=false
    for _ in $(seq 1 "${retries}"); do
        if KUBECONFIG="${K3S_KUBECONFIG}" kubectl get nodes --no-headers 2>/dev/null | grep -q -w "Ready"; then
            ready=true
            break
        fi
        sleep 2
    done

    if [[ "${ready}" != true ]]; then
        log_error "Timed out waiting for local node to become Ready. Inspect 'journalctl -u k3s'."
        exit 1
    fi

    log_info "Waiting for CoreDNS and metrics-server deployments..."
    for _ in $(seq 1 "${retries}"); do
        if KUBECONFIG="${K3S_KUBECONFIG}" kubectl -n kube-system get deployment coredns >/dev/null 2>&1 &&
            KUBECONFIG="${K3S_KUBECONFIG}" kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
    KUBECONFIG="${K3S_KUBECONFIG}" kubectl -n kube-system rollout status deployment/coredns --timeout=120s
    KUBECONFIG="${K3S_KUBECONFIG}" kubectl -n kube-system rollout status deployment/local-path-provisioner --timeout=120s || true
    KUBECONFIG="${K3S_KUBECONFIG}" kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s
    log_info "Local K3s single-node development cluster is UP and Ready."
}

cmd_install() {
    require_root
    check_resource_headroom

    if ! systemctl status systemd-journald >/dev/null 2>&1; then
        log_error "systemd is not running as PID 1 in this environment. K3s service setup requires systemd."
        exit 1
    fi

    if [[ -x "${K3S_BIN}" ]] && "${K3S_BIN}" --version 2>/dev/null | grep -q "${K3S_VERSION}"; then
        log_info "Pinned ${K3S_BIN} (${K3S_VERSION}) already installed."
    else
        local tmp_dir
        tmp_dir="$(mktemp -d /tmp/k3s-install-XXXXXX)"
        trap 'rm -rf "${tmp_dir}"' RETURN

        log_info "Downloading official K3s ${K3S_VERSION} binary (~75 MB)..."
        curl -fSL --http1.1 --retry 5 --retry-all-errors --retry-delay 2 -C - \
            "https://github.com/k3s-io/k3s/releases/download/${K3S_URL_TAG}/k3s" \
            -o "${tmp_dir}/k3s"

        log_info "Verifying cryptographic SHA-256 checksum..."
        local computed_sha
        computed_sha="$(sha256sum "${tmp_dir}/k3s" | awk '{print $1}')"
        if [[ "${computed_sha}" != "${K3S_SHA256}" ]]; then
            log_error "SHA-256 checksum mismatch for K3s binary!"
            log_error "Expected: ${K3S_SHA256}"
            log_error "Actual:   ${computed_sha}"
            exit 1
        fi
        install -m 0755 "${tmp_dir}/k3s" "${K3S_BIN}"
        log_info "Verified and installed ${K3S_BIN}."
    fi

    log_info "Writing systemd unit ${K3S_SERVICE} with conservative dev flags (PodCIDR=10.244.0.0/16, ServiceCIDR=10.96.0.0/12)..."
    cat <<EOF >"${K3S_SERVICE}"
[Unit]
Description=Lightweight Kubernetes (K3s) Local Development Cluster (${K3S_VERSION})
Documentation=https://k3s.io
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=-/etc/systemd/system/k3s.service.env
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=${K3S_BIN} server \\
    --disable=traefik,servicelb \\
    --cluster-cidr=10.244.0.0/16 \\
    --service-cidr=10.96.0.0/12 \\
    --node-name=wsl2-dev-node \\
    --kubelet-arg=fail-swap-on=false \\
    --write-kubeconfig-mode=0640

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable k3s.service
    systemctl start k3s.service

    wait_for_cluster_ready
    setup_kubeconfig
}

cmd_start() {
    require_root
    check_resource_headroom
    systemctl start k3s.service
    wait_for_cluster_ready
    setup_kubeconfig
}

cmd_stop() {
    require_root
    log_info "Stopping k3s.service cleanly (cluster state in ${K3S_DATA_DIR} is preserved)..."
    systemctl stop k3s.service || true
    log_info "k3s.service stopped."
}

cmd_restart() {
    require_root
    check_resource_headroom
    log_info "Restarting k3s.service..."
    systemctl restart k3s.service
    wait_for_cluster_ready
    setup_kubeconfig
}

cmd_status() {
    echo "=== Systemd Service State ==="
    systemctl status k3s.service --no-pager -l 2>&1 || true
    echo ""
    echo "=== WSL2 Memory Snapshot ==="
    free -m
    echo ""
    if [[ -r "${K3S_KUBECONFIG}" ]] || [[ -r "${HOME}/.kube/config" ]]; then
        echo "=== Cluster Nodes & System Pods ==="
        kubectl get nodes -o wide 2>&1 || true
        kubectl get pods -A -o wide 2>&1 || true
    fi
}

cmd_uninstall() {
    require_root
    log_warn "This will stop and remove the local K3s binary, systemd unit, and ${K3S_DATA_DIR}."
    log_warn "Pre-installed host Docker and host containerd (/var/lib/docker) will NOT be touched."
    read -r -p "Type 'UNINSTALL-K3S' to confirm removal: " confirm
    if [[ "${confirm}" != "UNINSTALL-K3S" ]]; then
        log_info "Uninstall cancelled."
        exit 0
    fi

    systemctl stop k3s.service 2>/dev/null || true
    systemctl disable k3s.service 2>/dev/null || true
    rm -f "${K3S_SERVICE}"
    systemctl daemon-reload
    rm -f "${K3S_BIN}"
    rm -rf "${K3S_DATA_DIR}" /etc/rancher/k3s
    log_info "Local K3s development cluster removed cleanly."
}

main() {
    local action="${1:-}"
    case "${action}" in
    install)
        cmd_install
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    status)
        cmd_status
        ;;
    kubeconfig)
        require_root
        setup_kubeconfig
        ;;
    uninstall)
        cmd_uninstall
        ;;
    -h | --help | "")
        usage
        [[ -z "${action}" ]] && exit 2 || exit 0
        ;;
    *)
        log_error "Unknown command: ${action}"
        usage >&2
        exit 2
        ;;
    esac
}

main "$@"
