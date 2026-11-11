#!/usr/bin/env bash
# ==============================================================================
# Script Name: 06-deploy-kubevirt.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Preflights CPU virtualization, /dev/kvm, virtctl, and cluster readiness,
#          validates KubeVirt v1.9.1 and CDI v1.66.1 configurations (plus optional
#          csi-driver-nfs v4.9.0 RWX gateway), and deploys them safely onto target
#          multi-node Kubernetes clusters.
#
# Governance & Safety Guardrails:
#   - Unconditionally REFUSES live deployment inside WSL2 (3.5 GiB dev host).
#   - Supports non-mutating `--dry-run` validation (safe on WSL2 & CI).
#   - Supports `--operator-dir PATH` for offline cached operator manifests.
#   - Requires explicit interactive confirmation (`DEPLOY-KUBEVIRT`) before apply.
# ==============================================================================

set -euo pipefail

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

KV_INSTALL_DIR="${REPO_ROOT}/kubevirt/installation"
NFS_DIR="${REPO_ROOT}/storage/nfs"
REPORT_DIR="${REPO_ROOT}/reports/kubevirt"

KUBEVIRT_VERSION="v1.9.1"
CDI_VERSION="v1.66.1"
NFS_CHART_VERSION="v4.9.0"

KUBEVIRT_OPERATOR_URL="https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
CDI_OPERATOR_URL="https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml"

DRY_RUN=false
INSTALL_NFS_FALLBACK=false
OPERATOR_DIR=""

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Validates virtualization prerequisites and deploys KubeVirt ${KUBEVIRT_VERSION} & CDI ${CDI_VERSION}.

Options:
      --dry-run               Validate manifests, schemas, KVM/CPU preflight, and cluster API
                              without installing KubeVirt, CDI, or modifying host/cluster
      --install-nfs-fallback  Also deploy csi-driver-nfs ${NFS_CHART_VERSION} + Mayastor-backed RWX
                              NFS server & nfs-mayastor-rwx StorageClass (target cluster only)
      --operator-dir PATH     Directory containing pre-downloaded kubevirt-operator.yaml and
                              cdi-operator.yaml (for air-gapped or proxy-restricted labs)
  -h, --help                  Display this help message

Safety Guardrails:
  - Refuses live execution inside WSL2 hosts (single-node 3.5 GiB dev environment).
  - Never executes without explicit DEPLOY-KUBEVIRT typed confirmation.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    --install-nfs-fallback)
        INSTALL_NFS_FALLBACK=true
        shift
        ;;
    --operator-dir)
        OPERATOR_DIR="${2:-}"
        shift 2
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

verify_dependencies_and_manifests() {
    local required_bins=("kubectl" "virtctl" "jq" "yq" "curl")
    for bin in "${required_bins[@]}"; do
        if ! command -v "${bin}" >/dev/null 2>&1; then
            log_error "Required binary missing from PATH: ${bin}"
            exit 1
        fi
    done

    local virtctl_ver
    virtctl_ver="$(virtctl version --client 2>/dev/null | grep -oE 'GitVersion:"[^"]+"' | cut -d'"' -f2 || echo 'unknown')"
    log_info "Detected virtctl client version: ${virtctl_ver} (target KubeVirt ${KUBEVIRT_VERSION})"

    local required_files=(
        "${KV_INSTALL_DIR}/release-metadata.yaml"
        "${KV_INSTALL_DIR}/namespaces.yaml"
        "${KV_INSTALL_DIR}/kubevirt-cr.yaml"
        "${KV_INSTALL_DIR}/cdi-cr.yaml"
        "${NFS_DIR}/nfs-server-mayastor.yaml"
        "${NFS_DIR}/nfs-storageclass.yaml"
    )
    for f in "${required_files[@]}"; do
        if [[ ! -f "${f}" ]]; then
            log_error "Required manifest file missing: ${f}"
            exit 1
        fi
    done

    local pinned_kv pinned_cdi
    pinned_kv="$(yq eval '.metadata.kubevirt.version' "${KV_INSTALL_DIR}/release-metadata.yaml")"
    pinned_cdi="$(yq eval '.metadata.cdi.version' "${KV_INSTALL_DIR}/release-metadata.yaml")"
    if [[ "${pinned_kv}" != "${KUBEVIRT_VERSION}" ]] || [[ "${pinned_cdi}" != "${CDI_VERSION}" ]]; then
        log_error "release-metadata.yaml mismatch: got KubeVirt=${pinned_kv}, CDI=${pinned_cdi}"
        exit 1
    fi

    if command -v yamllint >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/.yamllint.yaml" ]]; then
        log_info "Linting KubeVirt & NFS YAML manifests with yamllint..."
        yamllint -c "${REPO_ROOT}/.yamllint.yaml" "${KV_INSTALL_DIR}" "${NFS_DIR}"
    fi

    if command -v kubeconform >/dev/null 2>&1; then
        log_info "Validating KubeVirt, CDI, and NFS manifests against strict schemas..."
        local kv_schema_tmpl="${KV_INSTALL_DIR}/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
        local core_schema_tmpl="${REPO_ROOT}/infrastructure/k8s/schemas/v1.36.6-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json"
        local kc_cache="${HOME:-/tmp}/.cache/kubeconform"
        mkdir -p "${kc_cache}"
        kubeconform -strict -summary \
            -cache "${kc_cache}" \
            -schema-location "${kv_schema_tmpl}" \
            -schema-location "${core_schema_tmpl}" \
            -schema-location default \
            "${KV_INSTALL_DIR}/namespaces.yaml" \
            "${KV_INSTALL_DIR}/kubevirt-cr.yaml" \
            "${KV_INSTALL_DIR}/cdi-cr.yaml" \
            "${NFS_DIR}/nfs-server-mayastor.yaml" \
            "${NFS_DIR}/nfs-storageclass.yaml"
    fi
}

check_host_and_cluster_preflight() {
    # Hardware virtualization flags (Intel vmx / AMD svm)
    if grep -qE '\b(vmx|svm)\b' /proc/cpuinfo 2>/dev/null; then
        log_info "CPU hardware virtualization extensions (vmx/svm) detected."
    else
        log_error "CPU lacks vmx/svm hardware virtualization extensions; KubeVirt requires hardware KVM."
        return 1
    fi

    # /dev/kvm device inspection
    if [[ -c /dev/kvm ]]; then
        local kvm_stat
        kvm_stat="$(stat -c '%A %U:%G' /dev/kvm 2>/dev/null || echo 'unknown')"
        log_info "/dev/kvm character device present (${kvm_stat})."
    else
        log_error "/dev/kvm character device missing on host; hardware acceleration unavailable."
        return 1
    fi

    # Kubernetes API & version window verification (>=1.35 <1.37 for KubeVirt 1.9.x)
    local ver_json k8s_ver ready_nodes node_count
    if ! ver_json="$(kubectl version -o json 2>/dev/null)"; then
        log_error "Unable to reach active Kubernetes API server via kubectl."
        return 1
    fi
    k8s_ver="$(echo "${ver_json}" | jq -r '.serverVersion.gitVersion // "unknown"')"
    log_info "Connected Kubernetes server version: ${k8s_ver}"
    if [[ "${k8s_ver}" =~ ^v1\.(35|36)\. ]]; then
        log_info "Kubernetes ${k8s_ver} falls within KubeVirt ${KUBEVIRT_VERSION} support window (>=1.35 <1.37)."
    else
        log_warn "Kubernetes ${k8s_ver} is outside KubeVirt ${KUBEVIRT_VERSION} qualified window (>=1.35 <1.37)."
    fi

    node_count="$(kubectl get nodes -o json | jq '.items | length')"
    ready_nodes="$(kubectl get nodes -o json | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')"
    log_info "Cluster nodes Ready: ${ready_nodes}/${node_count}."

    if [[ "${DRY_RUN}" == true ]]; then
        if [[ "${ready_nodes}" -lt 2 ]]; then
            log_warn "[DRY-RUN] Cluster has ${ready_nodes} node(s); live multi-node VM scheduling & migration require >=2 Ready workers."
        fi
        return 0
    fi

    if [[ "${ready_nodes}" -lt 3 ]]; then
        log_error "Target deployment requires >=3 Ready nodes (found ${ready_nodes})."
        return 1
    fi
}

stage_operator_manifests() {
    local stage_dir="$1"
    if [[ -n "${OPERATOR_DIR}" ]]; then
        if [[ ! -f "${OPERATOR_DIR}/kubevirt-operator.yaml" ]] || [[ ! -f "${OPERATOR_DIR}/cdi-operator.yaml" ]]; then
            log_error "Offline --operator-dir missing kubevirt-operator.yaml or cdi-operator.yaml"
            exit 1
        fi
        cp "${OPERATOR_DIR}/kubevirt-operator.yaml" "${stage_dir}/kubevirt-operator.yaml"
        cp "${OPERATOR_DIR}/cdi-operator.yaml" "${stage_dir}/cdi-operator.yaml"
        return 0
    fi

    log_info "Downloading KubeVirt ${KUBEVIRT_VERSION} operator manifest..."
    curl -4 -fsSL --max-time 120 "${KUBEVIRT_OPERATOR_URL}" -o "${stage_dir}/kubevirt-operator.yaml"
    log_info "Downloading CDI ${CDI_VERSION} operator manifest..."
    curl -4 -fsSL --max-time 120 "${CDI_OPERATOR_URL}" -o "${stage_dir}/cdi-operator.yaml"
}

deploy_live() {
    local stage_dir="$1"
    stage_operator_manifests "${stage_dir}"

    echo ""
    echo "=============================================================================="
    echo " KubeVirt & CDI Live Cluster Deployment Plan"
    echo "=============================================================================="
    echo "  KubeVirt:      ${KUBEVIRT_VERSION} -> namespace kubevirt"
    echo "  CDI:           ${CDI_VERSION} -> namespace cdi"
    echo "  Workloads NS:  kubevirt-workloads (PSA baseline / NonRoot)"
    if [[ "${INSTALL_NFS_FALLBACK}" == true ]]; then
        echo "  NFS Gateway:   csi-driver-nfs ${NFS_CHART_VERSION} + storage/nfs/ -> storage-nfs"
    else
        echo "  NFS Gateway:   Skipped (--install-nfs-fallback not specified)"
    fi
    echo "=============================================================================="

    local confirm=""
    read -r -p "Type DEPLOY-KUBEVIRT to execute cluster installation: " confirm || true
    if [[ "${confirm}" != "DEPLOY-KUBEVIRT" ]]; then
        log_warn "Confirmation mismatch; cancelled without modifying cluster."
        exit 1
    fi

    log_info "Applying KubeVirt, CDI, and workload namespaces..."
    kubectl apply -f "${KV_INSTALL_DIR}/namespaces.yaml"

    log_info "Deploying KubeVirt operator ${KUBEVIRT_VERSION}..."
    kubectl apply -f "${stage_dir}/kubevirt-operator.yaml"
    kubectl -n kubevirt wait --for=condition=Available deployment/virt-operator --timeout=300s

    log_info "Applying KubeVirt CR (${KV_INSTALL_DIR}/kubevirt-cr.yaml)..."
    kubectl apply -f "${KV_INSTALL_DIR}/kubevirt-cr.yaml"
    kubectl -n kubevirt wait kv/kubevirt --for=condition=Available --timeout=600s

    log_info "Deploying CDI operator ${CDI_VERSION}..."
    kubectl apply -f "${stage_dir}/cdi-operator.yaml"
    kubectl -n cdi wait --for=condition=Available deployment/cdi-operator --timeout=300s

    log_info "Applying CDI CR (${KV_INSTALL_DIR}/cdi-cr.yaml)..."
    kubectl apply -f "${KV_INSTALL_DIR}/cdi-cr.yaml"
    kubectl wait cdi/cdi --for=condition=Available --timeout=600s

    if [[ "${INSTALL_NFS_FALLBACK}" == true ]]; then
        if ! command -v helm >/dev/null 2>&1; then
            log_error "helm binary required for --install-nfs-fallback"
            exit 1
        fi
        log_info "Deploying csi-driver-nfs ${NFS_CHART_VERSION} and Mayastor-backed NFS gateway..."
        if ! helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "csi-driver-nfs"; then
            helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts >/dev/null
        fi
        helm repo update csi-driver-nfs >/dev/null
        helm upgrade --install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
            --version "${NFS_CHART_VERSION}" \
            --namespace kube-system \
            --wait --timeout 5m
        kubectl apply -f "${NFS_DIR}/nfs-server-mayastor.yaml"
        kubectl -n storage-nfs wait --for=condition=Available deployment/mayastor-nfs-server --timeout=300s
        kubectl apply -f "${NFS_DIR}/nfs-storageclass.yaml"
    fi

    mkdir -p "${REPORT_DIR}"
    local ts report_file
    ts="$(date '+%Y-%m-%d_%H-%M-%S')"
    report_file="${REPORT_DIR}/kubevirt-deployment-${ts}.txt"
    {
        echo "KubeVirt & CDI Deployment Summary"
        echo "Date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "KubeVirt:   ${KUBEVIRT_VERSION}"
        echo "CDI:        ${CDI_VERSION}"
        kubectl get kubevirt kubevirt -n kubevirt
        kubectl get cdi cdi
        kubectl get pods -n kubevirt -o wide
        kubectl get pods -n cdi -o wide
    } >"${report_file}"
    log_info "KubeVirt deployment complete. Summary written to ${report_file}"
}

main() {
    verify_dependencies_and_manifests
    check_host_and_cluster_preflight

    local stage_dir
    stage_dir="$(mktemp -d /tmp/kubevirt-deploy-XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '${stage_dir}'" EXIT

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Verifying server/client schema dry-run feasibility for namespaces..."
        kubectl apply --dry-run=client -f "${KV_INSTALL_DIR}/namespaces.yaml" >/dev/null
        log_info "[DRY-RUN] Preflight and strict manifest checks passed with zero mutations."
        exit 0
    fi

    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        log_error "WSL2 environment detected. Live KubeVirt + CDI + VM stack deployment is prohibited on WSL2 (3.5 GiB total RAM, single-node K3s)."
        log_error "Reason: Prevents destabilizing the local dev host and fake validation against Mayastor-less single-node K3s."
        log_error "Safe alternative: Run '$0 --dry-run' on WSL2 or run live on the 4-node Ubuntu cluster."
        exit 1
    fi

    deploy_live "${stage_dir}"
}

main "$@"
