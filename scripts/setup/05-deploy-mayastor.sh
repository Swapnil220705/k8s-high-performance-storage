#!/usr/bin/env bash
# ==============================================================================
# Script Name: 05-deploy-mayastor.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates prerequisites, renders and lints pinned OpenEBS 4.6.2
#          (Mayastor v2.12.2) Helm configuration, safely blocks unsupported hosts
#          (including WSL2), and deploys Mayastor control/data plane + StorageClasses
#          onto verified multi-node target Kubernetes clusters.
#
# Governance & Safety Guardrails:
#   - Strictly REFUSES live deployment inside WSL2 or when prerequisites fail.
#   - Supports non-mutating `--dry-run` validation (safe on WSL2 & CI).
#   - Requires explicit interactive confirmation (`DEPLOY-MAYASTOR`) before apply.
#   - Never automatically creates DiskPools or wipes block devices; operator must
#     verify NVMe paths & institutional permission before applying diskpools.yaml.
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

OPENEBS_DIR="${REPO_ROOT}/infrastructure/storage/openebs"
EXAMPLES_DIR="${REPO_ROOT}/infrastructure/storage/examples"
PREREQ_SCRIPT="${REPO_ROOT}/scripts/validate/validate-mayastor-prerequisites.sh"
REPORT_DIR="${REPO_ROOT}/reports/storage"

CHART_REPO_NAME="openebs"
CHART_REPO_URL="https://openebs.github.io/openebs"
CHART_NAME="openebs/openebs"
CHART_VERSION="4.6.2"
EXPECTED_APP_VERSION="2.12.2"
RELEASE_NAME="openebs"
NAMESPACE="openebs"

DRY_RUN=false
SKIP_STORAGECLASSES=false
CHART_DIR=""

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploys OpenEBS Helm chart v${CHART_VERSION} (Mayastor v${EXPECTED_APP_VERSION}) to a verified
multi-node Kubernetes cluster after passing strict safety and prerequisite gates.

Options:
      --dry-run              Perform non-mutating chart lint, template render, image tag
                             audit, and prerequisite report check without modifying cluster
      --chart-dir PATH       Use an already-pulled local OpenEBS v${CHART_VERSION} chart directory
      --skip-storageclasses  Do not apply infrastructure/storage/examples/storageclasses.yaml
  -h, --help                 Display this help message

Safety Guardrails:
  - Live deployment is unconditionally prohibited on WSL2 hosts.
  - Requires >=3 Ready worker nodes labeled openebs.io/engine=mayastor with hugepages-2Mi.
  - DiskPools (infrastructure/storage/mayastor/diskpools.yaml) are NEVER auto-applied.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    --chart-dir)
        CHART_DIR="${2:-}"
        shift 2
        ;;
    --skip-storageclasses)
        SKIP_STORAGECLASSES=true
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

verify_local_artifacts() {
    local required_bins=("kubectl" "helm" "jq" "yq")
    for bin in "${required_bins[@]}"; do
        if ! command -v "${bin}" >/dev/null 2>&1; then
            log_error "Required binary missing from PATH: ${bin}"
            exit 1
        fi
    done

    local required_files=(
        "${OPENEBS_DIR}/chart-metadata.yaml"
        "${OPENEBS_DIR}/namespace.yaml"
        "${OPENEBS_DIR}/values.yaml"
        "${EXAMPLES_DIR}/storageclasses.yaml"
        "${PREREQ_SCRIPT}"
    )
    for f in "${required_files[@]}"; do
        if [[ ! -f "${f}" ]]; then
            log_error "Required project artifact missing: ${f}"
            exit 1
        fi
    done

    local meta_chart_ver meta_engine_ver
    meta_chart_ver="$(yq eval '.metadata.umbrellaChart.version' "${OPENEBS_DIR}/chart-metadata.yaml")"
    meta_engine_ver="$(yq eval '.metadata.replicatedStorageSubchart.version' "${OPENEBS_DIR}/chart-metadata.yaml")"
    if [[ "${meta_chart_ver}" != "${CHART_VERSION}" ]] || [[ "${meta_engine_ver}" != "${EXPECTED_APP_VERSION}" ]]; then
        log_error "chart-metadata.yaml mismatch: expected chart=${CHART_VERSION}/mayastor=${EXPECTED_APP_VERSION}, found chart=${meta_chart_ver}/mayastor=${meta_engine_ver}"
        exit 1
    fi

    if command -v yamllint >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/.yamllint.yaml" ]]; then
        log_info "Linting OpenEBS & example YAML configurations with yamllint..."
        yamllint -c "${REPO_ROOT}/.yamllint.yaml" "${OPENEBS_DIR}" "${EXAMPLES_DIR}"
    fi
}

UNPACKED_CHART_PATH=""

prepare_chart_source() {
    local work_dir="$1"
    if [[ -n "${CHART_DIR}" ]]; then
        if [[ ! -f "${CHART_DIR}/Chart.yaml" ]]; then
            log_error "Specified --chart-dir '${CHART_DIR}' does not contain Chart.yaml"
            exit 1
        fi
        local local_ver
        local_ver="$(yq eval '.version' "${CHART_DIR}/Chart.yaml")"
        if [[ "${local_ver}" != "${CHART_VERSION}" ]]; then
            log_error "Local chart version '${local_ver}' != expected '${CHART_VERSION}'"
            exit 1
        fi
        UNPACKED_CHART_PATH="${CHART_DIR}"
        return 0
    fi

    log_info "Ensuring Helm repo '${CHART_REPO_NAME}' (${CHART_REPO_URL}) is registered..."
    if ! helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "${CHART_REPO_NAME}"; then
        helm repo add "${CHART_REPO_NAME}" "${CHART_REPO_URL}" >/dev/null
    fi
    helm repo update "${CHART_REPO_NAME}" >/dev/null

    log_info "Pulling pinned chart ${CHART_NAME} v${CHART_VERSION} into temporary staging directory..."
    helm pull "${CHART_NAME}" --version "${CHART_VERSION}" --untar --untardir "${work_dir}" >/dev/null
    UNPACKED_CHART_PATH="${work_dir}/openebs"
}

validate_rendered_chart() {
    local unpacked_chart="$1"
    local rendered_yaml="$2"

    log_info "Running helm lint against ${unpacked_chart} with infrastructure/storage/openebs/values.yaml..."
    helm lint "${unpacked_chart}" --namespace "${NAMESPACE}" -f "${OPENEBS_DIR}/values.yaml"

    log_info "Rendering Helm manifests via helm template for static verification..."
    helm template "${RELEASE_NAME}" "${unpacked_chart}" --namespace "${NAMESPACE}" -f "${OPENEBS_DIR}/values.yaml" >"${rendered_yaml}"

    if grep -qE '^\s+image:.*:latest\b' "${rendered_yaml}"; then
        log_error "Rendered Helm manifests contain forbidden ':latest' container image tags."
        exit 1
    fi

    if ! grep -q "mayastor-io-engine:v${EXPECTED_APP_VERSION}" "${rendered_yaml}"; then
        log_error "Rendered Helm manifests do not contain expected mayastor-io-engine:v${EXPECTED_APP_VERSION} image."
        exit 1
    fi

    if grep -qE 'kind: DaemonSet' "${rendered_yaml}" && grep -qE 'openebs-(lvm|zfs|rawfile)-localpv' "${rendered_yaml}"; then
        log_error "Unused localpv engine detected in rendered manifests despite being disabled in values.yaml."
        exit 1
    fi

    log_info "Static Helm lint, pinned image audit (v${EXPECTED_APP_VERSION}), and excluded-engine verification PASSED."
}

enforce_live_safety_gates() {
    # 1. Unconditional WSL2 refusal in live mode
    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        log_error "WSL2 environment detected. Live Mayastor deployment is strictly prohibited on WSL2 dev hosts."
        log_error "Reason: WSL2 lacks dedicated raw NVMe disks, 2GiB HugePages headroom, and multi-node K8s workers."
        log_error "Safe alternative: Run '$0 --dry-run' for offline chart/manifest rendering verification."
        exit 1
    fi

    # 2. Run prerequisite validator strictly before proceeding
    local tmp_prereq_dir
    tmp_prereq_dir="$(mktemp -d /tmp/mayastor-prereq-gate-XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp_prereq_dir}'" RETURN

    log_info "Executing non-destructive prerequisite gate via validate-mayastor-prerequisites.sh..."
    if ! "${PREREQ_SCRIPT}" -o "${tmp_prereq_dir}"; then
        log_error "Mayastor prerequisites check reported mandatory FAIL condition(s). Deployment aborted."
        exit 1
    fi

    # 3. Verify 3 Ready worker nodes carry openebs.io/engine=mayastor and advertise hugepages-2Mi
    local nodes_json ready_engine_nodes hp_nodes
    nodes_json="$(kubectl get nodes -o json)"
    ready_engine_nodes="$(echo "${nodes_json}" | jq '[.items[] | select((.metadata.labels["openebs.io/engine"] == "mayastor") and ([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length) > 0)] | length')"
    hp_nodes="$(echo "${nodes_json}" | jq '[.items[] | select((.metadata.labels["openebs.io/engine"] == "mayastor") and ((.status.allocatable["hugepages-2Mi"] // "0") != "0"))] | length')"

    if [[ "${ready_engine_nodes}" -lt 3 ]]; then
        log_error "Found ${ready_engine_nodes} Ready node(s) labeled openebs.io/engine=mayastor; minimum 3 required."
        exit 1
    fi
    if [[ "${hp_nodes}" -lt 3 ]]; then
        log_error "Only ${hp_nodes} labeled worker(s) expose hugepages-2Mi allocatable resources; minimum 3 required."
        exit 1
    fi

    log_info "Verified ${ready_engine_nodes} Ready labeled Mayastor worker nodes with hugepages-2Mi active."
}

deploy_live() {
    local unpacked_chart="$1"

    echo ""
    echo "=============================================================================="
    echo " OpenEBS / Mayastor Live Cluster Deployment Execution Plan"
    echo "=============================================================================="
    echo "  Chart:          ${CHART_NAME} v${CHART_VERSION} (Mayastor v${EXPECTED_APP_VERSION})"
    echo "  Release Name:   ${RELEASE_NAME}"
    echo "  Namespace:      ${NAMESPACE}"
    echo "  Values File:    ${OPENEBS_DIR}/values.yaml"
    echo "  Step 1:         kubectl apply -f ${OPENEBS_DIR}/namespace.yaml"
    echo "  Step 2:         helm upgrade --install ${RELEASE_NAME} ${unpacked_chart} --namespace ${NAMESPACE} -f ${OPENEBS_DIR}/values.yaml --wait --timeout 15m"
    if [[ "${SKIP_STORAGECLASSES}" == false ]]; then
        echo "  Step 3:         kubectl apply -f ${EXAMPLES_DIR}/storageclasses.yaml"
    else
        echo "  Step 3:         SKIPPED (--skip-storageclasses specified)"
    fi
    echo "  Notice:         DiskPools will NOT be auto-applied; configure verified raw NVMe IDs first."
    echo "=============================================================================="

    local confirm=""
    read -r -p "Type DEPLOY-MAYASTOR to execute cluster deployment: " confirm || true
    if [[ "${confirm}" != "DEPLOY-MAYASTOR" ]]; then
        log_warn "Confirmation phrase mismatch; deployment cancelled with zero changes."
        exit 1
    fi

    log_info "Applying namespace ${NAMESPACE}..."
    kubectl apply -f "${OPENEBS_DIR}/namespace.yaml"

    log_info "Installing/upgrading ${RELEASE_NAME} Helm release (version ${CHART_VERSION})..."
    helm upgrade --install "${RELEASE_NAME}" "${unpacked_chart}" \
        --namespace "${NAMESPACE}" \
        -f "${OPENEBS_DIR}/values.yaml" \
        --wait \
        --timeout 15m

    if [[ "${SKIP_STORAGECLASSES}" == false ]]; then
        log_info "Applying Mayastor StorageClasses..."
        kubectl apply -f "${EXAMPLES_DIR}/storageclasses.yaml"
    fi

    mkdir -p "${REPORT_DIR}"
    local ts report_file
    ts="$(date '+%Y-%m-%d_%H-%M-%S')"
    report_file="${REPORT_DIR}/mayastor-deployment-${ts}.txt"
    {
        echo "OpenEBS Mayastor Deployment Record"
        echo "Date (UTC):      $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "Chart Version:   ${CHART_VERSION}"
        echo "Engine Version:  ${EXPECTED_APP_VERSION}"
        echo "Namespace:       ${NAMESPACE}"
        echo "Helm Release:"
        helm status "${RELEASE_NAME}" -n "${NAMESPACE}"
        echo ""
        echo "Pods:"
        kubectl get pods -n "${NAMESPACE}" -o wide
    } >"${report_file}"

    log_info "Deployment finished cleanly. Record written to ${report_file}"
    log_info "Next steps: verify target NVMe disks, customize diskpools.yaml, apply pools, and run validate-mayastor-deployment.sh."
}

main() {
    verify_local_artifacts

    local stage_dir
    stage_dir="$(mktemp -d /tmp/openebs-deploy-stage-XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '${stage_dir}'" EXIT

    local rendered_yaml
    prepare_chart_source "${stage_dir}"
    rendered_yaml="${stage_dir}/rendered.yaml"
    validate_rendered_chart "${UNPACKED_CHART_PATH}" "${rendered_yaml}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Helm lint and template rendering verified with 0 errors."
        log_info "[DRY-RUN] Previewing host/cluster readiness cleanly (non-zero prerequisite exit is informational in --dry-run)..."
        "${PREREQ_SCRIPT}" -o "${stage_dir}/prereq" || true
        log_info "[DRY-RUN] No cluster or host resources were modified."
        exit 0
    fi

    enforce_live_safety_gates
    deploy_live "${UNPACKED_CHART_PATH}"
}

main "$@"
