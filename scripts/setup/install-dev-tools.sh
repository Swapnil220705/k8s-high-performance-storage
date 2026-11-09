#!/usr/bin/env bash
# ==============================================================================
# Script Name: install-dev-tools.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Description: Installs and verifies the required client-side development, linting,
#              and validation toolchain inside WSL2 Ubuntu 24.04.
# Tools Installed:
#   - apt: shellcheck, yamllint, shfmt, jq, fio
#   - binary (verified SHA-256): kubectl, helm, kubeconform, yq, virtctl
# Safety:
#   - Uses official release sources and cryptographic SHA-256 validation.
#   - Idempotent: Skips or updates safely without polluting system paths.
#   - Does NOT install or modify container runtimes or Kubernetes clusters.
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

# Require root permissions for package and /usr/local/bin installation
if [[ "$(id -u)" -ne 0 ]]; then
    log_error "This script requires root privileges. Please run with sudo or as root: sudo $0"
    exit 1
fi

INSTALL_BIN_DIR="/usr/local/bin"
mkdir -p "${INSTALL_BIN_DIR}"

# Pinned versions & SHA-256 checksums (linux-amd64)
KUBECTL_VERSION="v1.36.0"
KUBECTL_SHA256="123d8c8844f46b1244c547fffb3c17180c0c26dac9890589fe7e67763298748e"

HELM_VERSION="v3.17.1"
HELM_SHA256="3b66f3cd28409f29832b1b35b43d9922959a32d795003149707fea84cbcd4469"

KUBECONFORM_VERSION="v0.8.0"
KUBECONFORM_SHA256="9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883"

YQ_VERSION="v4.54.3"
YQ_SHA256="129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973"

VIRTCTL_VERSION="v1.9.0"
VIRTCTL_SHA256="40ede2ee37c98a1aeed71c9c219616a05247ce2be109e1edddf0477572e8b978"

# 1. Update APT and install Linux repository tools
log_info "Verifying and installing standard APT packages (shellcheck, yamllint, shfmt, jq, fio, curl, git)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    shellcheck \
    yamllint \
    shfmt \
    jq \
    fio

# Temporary directory for binary downloads
TMP_DIR="$(mktemp -d /tmp/k8s-dev-tools-XXXXXX)"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

# Helper for SHA-256 verification
verify_sha256() {
    local file_path="$1"
    local expected_hash="$2"
    local computed_hash
    computed_hash="$(sha256sum "${file_path}" | awk '{print $1}')"

    if [[ "${computed_hash}" != "${expected_hash}" ]]; then
        log_error "SHA-256 verification failed for ${file_path}!"
        log_error "Expected: ${expected_hash}"
        log_error "Got:      ${computed_hash}"
        return 1
    fi
    log_info "SHA-256 verified successfully for $(basename "${file_path}")."
}

# 2. Install kubectl
log_info "Checking kubectl (${KUBECTL_VERSION})..."
if ! command -v kubectl >/dev/null 2>&1 || [[ "$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | awk '{print $2}')" != "${KUBECTL_VERSION}" ]]; then
    log_info "Downloading kubectl ${KUBECTL_VERSION}..."
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o "${TMP_DIR}/kubectl"
    verify_sha256 "${TMP_DIR}/kubectl" "${KUBECTL_SHA256}"
    install -m 0755 "${TMP_DIR}/kubectl" "${INSTALL_BIN_DIR}/kubectl"
else
    log_info "kubectl ${KUBECTL_VERSION} already installed."
fi

# 3. Install Helm
log_info "Checking Helm (${HELM_VERSION})..."
if ! command -v helm >/dev/null 2>&1 || [[ "$(helm version --short 2>/dev/null | cut -d+ -f1)" != "${HELM_VERSION}" ]]; then
    log_info "Downloading Helm ${HELM_VERSION}..."
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o "${TMP_DIR}/helm.tar.gz"
    verify_sha256 "${TMP_DIR}/helm.tar.gz" "${HELM_SHA256}"
    tar -xzf "${TMP_DIR}/helm.tar.gz" -C "${TMP_DIR}" linux-amd64/helm
    install -m 0755 "${TMP_DIR}/linux-amd64/helm" "${INSTALL_BIN_DIR}/helm"
else
    log_info "Helm ${HELM_VERSION} already installed."
fi

# 4. Install kubeconform
log_info "Checking kubeconform (${KUBECONFORM_VERSION})..."
if ! command -v kubeconform >/dev/null 2>&1 || ! kubeconform -v 2>&1 | grep -q "${KUBECONFORM_VERSION#v}"; then
    log_info "Downloading kubeconform ${KUBECONFORM_VERSION}..."
    curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" -o "${TMP_DIR}/kubeconform.tar.gz"
    verify_sha256 "${TMP_DIR}/kubeconform.tar.gz" "${KUBECONFORM_SHA256}"
    tar -xzf "${TMP_DIR}/kubeconform.tar.gz" -C "${TMP_DIR}" kubeconform
    install -m 0755 "${TMP_DIR}/kubeconform" "${INSTALL_BIN_DIR}/kubeconform"
else
    log_info "kubeconform ${KUBECONFORM_VERSION} already installed."
fi

# 5. Install yq
log_info "Checking yq (${YQ_VERSION})..."
if ! command -v yq >/dev/null 2>&1 || ! yq --version 2>&1 | grep -q "${YQ_VERSION#v}"; then
    log_info "Downloading yq ${YQ_VERSION}..."
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o "${TMP_DIR}/yq"
    verify_sha256 "${TMP_DIR}/yq" "${YQ_SHA256}"
    install -m 0755 "${TMP_DIR}/yq" "${INSTALL_BIN_DIR}/yq"
else
    log_info "yq ${YQ_VERSION} already installed."
fi

# 6. Install virtctl
log_info "Checking virtctl (${VIRTCTL_VERSION})..."
if ! command -v virtctl >/dev/null 2>&1 || ! virtctl version --client 2>&1 | grep -q "${VIRTCTL_VERSION}"; then
    log_info "Downloading virtctl ${VIRTCTL_VERSION}..."
    curl -fsSL "https://github.com/kubevirt/kubevirt/releases/download/${VIRTCTL_VERSION}/virtctl-${VIRTCTL_VERSION}-linux-amd64" -o "${TMP_DIR}/virtctl"
    verify_sha256 "${TMP_DIR}/virtctl" "${VIRTCTL_SHA256}"
    install -m 0755 "${TMP_DIR}/virtctl" "${INSTALL_BIN_DIR}/virtctl"
else
    log_info "virtctl ${VIRTCTL_VERSION} already installed."
fi

# 7. Verification Summary Table
echo ""
echo "=============================================================================="
echo "          Development Toolchain Verification Summary"
echo "=============================================================================="
printf "%-15s | %-30s | %-15s\n" "Tool" "Installed Version" "Status"
echo "----------------+--------------------------------+----------------------------"

check_tool() {
    local name="$1"
    local cmd="$2"
    if command -v "${name}" >/dev/null 2>&1; then
        local ver
        ver="$(${cmd} 2>&1 | head -n 1 | tr -d '\r')"
        printf "%-15s | %-30s | \033[0;32mINSTALLED\033[0m\n" "${name}" "${ver:0:30}"
    else
        printf "%-15s | %-30s | \033[0;31mMISSING\033[0m\n" "${name}" "N/A"
    fi
}

check_tool "kubectl" "kubectl version --client -o yaml"
check_tool "helm" "helm version --short"
check_tool "kubeconform" "kubeconform -v"
check_tool "yamllint" "yamllint --version"
check_tool "shellcheck" "shellcheck --version"
check_tool "shfmt" "shfmt --version"
check_tool "jq" "jq --version"
check_tool "yq" "yq --version"
check_tool "git" "git --version"
check_tool "curl" "curl --version"
check_tool "fio" "fio --version"
check_tool "virtctl" "virtctl version --client"
check_tool "containerd" "containerd --version"
check_tool "docker" "docker --version"

echo "=============================================================================="
log_info "Development toolchain installation and verification completed successfully."
