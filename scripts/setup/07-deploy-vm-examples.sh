#!/usr/bin/env bash
# ==============================================================================
# Script Name: 07-deploy-vm-examples.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates prerequisites and deploys KubeVirt VM workload tiers
#          (RWO filesystem, RWO raw block, default NFS RWX live-migratable,
#          hotplug-ready, and opt-in experimental RWX block).
#
# Governance & Safety Guardrails:
#   - Strictly refuses live deployment on WSL2 (prevents OOM/disk pressure).
#   - Never uses experimental Mayastor RWX block unless explicitly requested.
#   - Never deploys VM cloud-init secrets with unreplaced `<OPERATOR_SSH_PUBLIC_KEY>`.
#   - Supports non-mutating `--dry-run` validation.
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

VM_DIR="${REPO_ROOT}/kubevirt/virtualmachines"
MIG_DIR="${REPO_ROOT}/kubevirt/migration"
HP_DIR="${REPO_ROOT}/kubevirt/hotplug"
SCHEMA_DIR="${REPO_ROOT}/kubevirt/installation/schemas"

TIER="standard" # standard, rwo-fs, rwo-block, nfs-rwx, hotplug, cirros, all-safe
INCLUDE_EXPERIMENTAL_RWX=false
SSH_PUBKEY_FILE=""
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploys KubeVirt VirtualMachine workload tiers onto an already-validated KubeVirt/Mayastor cluster.

Options:
      --tier TIER                 Workload tier to deploy/validate:
                                    standard  (rwo-fs + nfs-rwx migration + policy) [DEFAULT]
                                    rwo-fs    (vm-ubuntu-rwo-fs + mayastor-nvme-r3-ext4)
                                    rwo-block (vm-ubuntu-rwo-block + mayastor-nvme-r3-block)
                                    nfs-rwx   (vm-ubuntu-migration-nfs + MigrationPolicy)
                                    hotplug   (vm-ubuntu-hotplug + staged hotplug PVCs/DVs)
                                    cirros    (vm-cirros-dev-minimal constrained test)
                                    all-safe  (all non-experimental VMs + migration policy)
      --include-experimental-rwx  Also deploy EXPERIMENTAL vm-ubuntu-rwx-block-exp
      --ssh-key-file PATH         Substitute <OPERATOR_SSH_PUBLIC_KEY> in temporary Secret render
      --dry-run                   Validate schemas, dependencies, and rendered cloud-init safely
  -h, --help                      Display this help message

Safety Guardrails:
  - Prohibits live execution inside WSL2 dev environments.
  - Refuses applying cloud-init Secret if SSH key placeholder was not supplied/replaced.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --tier)
        TIER="${2:-}"
        if [[ ! "${TIER}" =~ ^(standard|rwo-fs|rwo-block|nfs-rwx|hotplug|cirros|all-safe)$ ]]; then
            log_error "Invalid --tier '${TIER}'."
            usage >&2
            exit 2
        fi
        shift 2
        ;;
    --include-experimental-rwx)
        INCLUDE_EXPERIMENTAL_RWX=true
        shift
        ;;
    --ssh-key-file)
        SSH_PUBKEY_FILE="${2:-}"
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

MANIFEST_LIST=()

select_manifests() {
    case "${TIER}" in
    standard)
        MANIFEST_LIST=(
            "${VM_DIR}/vm-ubuntu-rwo-filesystem.yaml"
            "${VM_DIR}/vm-ubuntu-rwx-nfs-migration.yaml"
            "${MIG_DIR}/migration-policy.yaml"
        )
        ;;
    rwo-fs)
        MANIFEST_LIST=("${VM_DIR}/vm-ubuntu-rwo-filesystem.yaml")
        ;;
    rwo-block)
        MANIFEST_LIST=("${VM_DIR}/vm-ubuntu-mayastor-rwo-block.yaml")
        ;;
    nfs-rwx)
        MANIFEST_LIST=(
            "${VM_DIR}/vm-ubuntu-rwx-nfs-migration.yaml"
            "${MIG_DIR}/migration-policy.yaml"
        )
        ;;
    hotplug)
        MANIFEST_LIST=(
            "${HP_DIR}/vm-ubuntu-hotplug-ready.yaml"
            "${HP_DIR}/hotplug-data-volume.yaml"
        )
        ;;
    cirros)
        MANIFEST_LIST=("${VM_DIR}/vm-cirros-dev-minimal.yaml")
        ;;
    all-safe)
        MANIFEST_LIST=(
            "${VM_DIR}/vm-ubuntu-rwo-filesystem.yaml"
            "${VM_DIR}/vm-ubuntu-mayastor-rwo-block.yaml"
            "${VM_DIR}/vm-ubuntu-rwx-nfs-migration.yaml"
            "${MIG_DIR}/migration-policy.yaml"
            "${HP_DIR}/vm-ubuntu-hotplug-ready.yaml"
            "${HP_DIR}/hotplug-data-volume.yaml"
            "${VM_DIR}/vm-cirros-dev-minimal.yaml"
        )
        ;;
    esac

    if [[ "${INCLUDE_EXPERIMENTAL_RWX}" == true ]]; then
        log_warn "Experimental native Mayastor RWX block VM included explicitly; NOT default migration tier."
        MANIFEST_LIST+=("${VM_DIR}/vm-ubuntu-rwx-block-experimental.yaml")
    fi
}

validate_manifests_and_cloudinit() {
    for bin in kubectl kubeconform yq jq; do
        if ! command -v "${bin}" >/dev/null 2>&1; then
            log_error "Required binary missing: ${bin}"
            exit 1
        fi
    done

    local schema_tmpl="${SCHEMA_DIR}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    local core_schema_tmpl="${REPO_ROOT}/infrastructure/k8s/schemas/v1.36.6-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json"
    local kc_cache="${HOME:-/tmp}/.cache/kubeconform"
    mkdir -p "${kc_cache}"
    log_info "Validating cloud-init Secret and ${#MANIFEST_LIST[@]} tier manifest(s) with kubeconform -strict..."
    kubeconform -strict -summary \
        -cache "${kc_cache}" \
        -schema-location "${schema_tmpl}" \
        -schema-location "${core_schema_tmpl}" \
        -schema-location default \
        "${VM_DIR}/cloud-init-secret.yaml" \
        "${MANIFEST_LIST[@]}"

    if command -v yamllint >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/.yamllint.yaml" ]]; then
        yamllint -c "${REPO_ROOT}/.yamllint.yaml" "${VM_DIR}/cloud-init-secret.yaml" "${MANIFEST_LIST[@]}"
    fi
}

render_cloudinit_secret() {
    local out_file="$1"
    if [[ -n "${SSH_PUBKEY_FILE}" ]]; then
        if [[ ! -f "${SSH_PUBKEY_FILE}" ]]; then
            log_error "Specified --ssh-key-file not found: ${SSH_PUBKEY_FILE}"
            exit 1
        fi
        local pubkey
        pubkey="$(head -n 1 "${SSH_PUBKEY_FILE}" | tr -d '\r\n')"
        if [[ ! "${pubkey}" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
            log_error "Invalid SSH public key format in ${SSH_PUBKEY_FILE}"
            exit 1
        fi
        sed "s|<OPERATOR_SSH_PUBLIC_KEY>|${pubkey}|g" "${VM_DIR}/cloud-init-secret.yaml" >"${out_file}"
        return 0
    fi

    if grep -q "<OPERATOR_SSH_PUBLIC_KEY>" "${VM_DIR}/cloud-init-secret.yaml"; then
        if [[ "${DRY_RUN}" == true ]]; then
            log_warn "[DRY-RUN] cloud-init-secret.yaml retains placeholder <OPERATOR_SSH_PUBLIC_KEY>; pass --ssh-key-file PATH for live apply."
            cp "${VM_DIR}/cloud-init-secret.yaml" "${out_file}"
            return 0
        fi
        log_error "Refusing live apply: <OPERATOR_SSH_PUBLIC_KEY> placeholder unreplaced. Pass --ssh-key-file PATH."
        exit 1
    fi
    cp "${VM_DIR}/cloud-init-secret.yaml" "${out_file}"
}

verify_cluster_prereqs() {
    local kv_phase cdi_phase
    kv_phase="$(kubectl get kubevirt kubevirt -n kubevirt -o jsonpath='{.status.phase}' 2>/dev/null || echo 'absent')"
    cdi_phase="$(kubectl get cdi cdi -o jsonpath='{.status.phase}' 2>/dev/null || echo 'absent')"

    if [[ "${kv_phase}" != "Deployed" ]] || [[ "${cdi_phase}" != "Deployed" ]]; then
        log_error "Cluster prerequisites unmet: KubeVirt phase='${kv_phase}', CDI phase='${cdi_phase}' (both must be Deployed)."
        return 1
    fi

    for sc in mayastor-nvme-r3-ext4 mayastor-nvme-r3-block; do
        if ! kubectl get sc "${sc}" >/dev/null 2>&1; then
            log_error "Required StorageClass '${sc}' not found on cluster."
            return 1
        fi
    done

    if [[ "${TIER}" == "standard" ]] || [[ "${TIER}" == "nfs-rwx" ]] || [[ "${TIER}" == "all-safe" ]]; then
        if ! kubectl get sc nfs-mayastor-rwx >/dev/null 2>&1; then
            log_error "Required StorageClass 'nfs-mayastor-rwx' not found (deploy 06-deploy-kubevirt.sh --install-nfs-fallback first)."
            return 1
        fi
    fi

    if [[ "${INCLUDE_EXPERIMENTAL_RWX}" == true ]]; then
        if ! kubectl get sc mayastor-nvme-r3-block-rwx >/dev/null 2>&1; then
            log_error "Experimental StorageClass 'mayastor-nvme-r3-block-rwx' not found."
            return 1
        fi
    fi
}

main() {
    select_manifests
    validate_manifests_and_cloudinit

    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/vm-examples-XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp_dir}'" EXIT

    local rendered_secret="${tmp_dir}/cloud-init-secret.yaml"
    render_cloudinit_secret "${rendered_secret}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Selected tier '${TIER}' (${#MANIFEST_LIST[@]} manifest file(s)) validated with zero cluster changes."
        for m in "${MANIFEST_LIST[@]}"; do
            log_info "[DRY-RUN] Verified manifest: ${m#"${REPO_ROOT}/"}"
        done
        exit 0
    fi

    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        log_error "WSL2 environment detected. Refusing live multi-GiB VM deployment on 3.5 GiB WSL2 dev host."
        log_error "Safe alternative: Run '$0 --tier ${TIER} --dry-run' for static/schema validation."
        exit 1
    fi

    verify_cluster_prereqs

    local confirm=""
    read -r -p "Type DEPLOY-VMS to apply '${TIER}' manifests into kubevirt-workloads: " confirm || true
    if [[ "${confirm}" != "DEPLOY-VMS" ]]; then
        log_warn "Confirmation mismatch; cancelled without modifying cluster."
        exit 1
    fi

    kubectl apply -f "${REPO_ROOT}/kubevirt/installation/namespaces.yaml"
    kubectl apply -f "${rendered_secret}"
    for m in "${MANIFEST_LIST[@]}"; do
        log_info "Applying ${m#"${REPO_ROOT}/"}..."
        kubectl apply -f "${m}"
    done
    log_info "VM manifests applied cleanly. Run validate-vm-storage.sh to track DataVolume import and VMI readiness."
}

main "$@"
