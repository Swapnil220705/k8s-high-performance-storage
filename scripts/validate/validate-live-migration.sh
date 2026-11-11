#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-live-migration.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates KubeVirt live migration readiness and (when --execute is
#          specified on a live >=2 worker cluster) orchestrates and verifies
#          cross-node VM live migration with timeout rollback and post-migration
#          guest agent & storage checks.
#
# Governance:
#   - Refuses live migration execution on single-node / WSL2 hosts.
#   - Verifies VM uses ReadWriteMany storage before attempting live migration.
#   - Distinguishes implemented config vs real multi-node validation honestly.
#   - Archives .txt and .json audit reports under reports/kubevirt/.
# ==============================================================================

set -euo pipefail

COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_BLUE="\033[0;34m"
COLOR_CYAN="\033[0;36m"
COLOR_BOLD="\033[1m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

NAMESPACE="kubevirt-workloads"
VMI_NAME="vm-ubuntu-migration-nfs"
TARGET_NODE=""
TIMEOUT_SEC=300
EXECUTE_MIGRATION=false
DRY_RUN=false
REQUIRE_DEPLOYED=false
QUIET_MODE=false
IS_WSL2=false
REPORT_DIR="${REPO_ROOT}/reports/kubevirt"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

COUNT_PASS=0
COUNT_WARN=0
COUNT_FAIL=0
COUNT_NOT_TESTABLE=0
JSON_ITEMS=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Validates KubeVirt live-migration configuration and executes/verifies cross-node VM migration.

Options:
      --dry-run             Verify migration configs, policy, and cluster preconditions read-only
      --execute             Trigger live migration on target cluster and verify post-migration state
      --require-deployed    Return exit code 1 if multi-node KubeVirt migration runtime is absent
  -v, --vmi NAME            Target VMI name (default: ${VMI_NAME})
  -n, --namespace NS        Target VMI namespace (default: ${NAMESPACE})
      --target-node NODE    Optional Kubernetes worker hostname to pin migration target
      --timeout SEC         Migration convergence timeout seconds (default: ${TIMEOUT_SEC})
  -o, --output-dir DIR      Output report directory (default: reports/kubevirt)
  -q, --quiet               Suppress table console output
  -h, --help                Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    --execute)
        EXECUTE_MIGRATION=true
        shift
        ;;
    --require-deployed)
        REQUIRE_DEPLOYED=true
        shift
        ;;
    -v | --vmi)
        VMI_NAME="${2:-}"
        shift 2
        ;;
    -n | --namespace)
        NAMESPACE="${2:-}"
        shift 2
        ;;
    --target-node)
        TARGET_NODE="${2:-}"
        shift 2
        ;;
    --timeout)
        TIMEOUT_SEC="${2:-}"
        if ! [[ "${TIMEOUT_SEC}" =~ ^[0-9]+$ ]] || [[ "${TIMEOUT_SEC}" -lt 30 ]]; then
            echo "Error: --timeout must be an integer >= 30." >&2
            exit 2
        fi
        shift 2
        ;;
    -o | --output-dir)
        REPORT_DIR="${2:-}"
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
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_GREEN}[PASS]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    WARNING)
        COUNT_WARN=$((COUNT_WARN + 1))
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    FAIL)
        COUNT_FAIL=$((COUNT_FAIL + 1))
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_RED}[FAIL]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    NOT_TESTABLE)
        COUNT_NOT_TESTABLE=$((COUNT_NOT_TESTABLE + 1))
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_BLUE}[N/T]${COLOR_RESET}  %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
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

check_static_migration_manifests() {
    local kv_cr="${REPO_ROOT}/kubevirt/installation/kubevirt-cr.yaml"
    local mig_pol="${REPO_ROOT}/kubevirt/migration/migration-policy.yaml"
    local mig_job="${REPO_ROOT}/kubevirt/migration/live-migration-job.yaml"

    local tls post_copy bw
    tls="$(yq eval '.spec.configuration.migrations.disableTLS' "${kv_cr}")"
    post_copy="$(yq eval '.spec.configuration.migrations.allowPostCopy' "${kv_cr}")"
    bw="$(yq eval '.spec.configuration.migrations.bandwidthPerMigration' "${kv_cr}")"
    if [[ "${tls}" == "false" ]] && [[ "${post_copy}" == "false" ]] && [[ -n "${bw}" ]]; then
        log_check "PASS" "Config" "KubeVirt CR Migration Guardrails" "disableTLS=false, allowPostCopy=false, bandwidthPerMigration=${bw}"
    else
        log_check "FAIL" "Config" "KubeVirt CR Migration Guardrails" "Unexpected migration config: disableTLS=${tls}, allowPostCopy=${post_copy}"
    fi

    local kc_cache="${HOME:-/tmp}/.cache/kubeconform"
    local core_schema_tmpl="${REPO_ROOT}/infrastructure/k8s/schemas/v1.36.6-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json"
    mkdir -p "${kc_cache}"
    if kubeconform -strict -summary \
        -cache "${kc_cache}" \
        -schema-location "${REPO_ROOT}/kubevirt/installation/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
        -schema-location "${core_schema_tmpl}" \
        -schema-location default \
        "${mig_pol}" "${mig_job}" >/dev/null 2>&1; then
        log_check "PASS" "Manifests" "MigrationPolicy & Job Schemas" "MigrationPolicy and VirtualMachineInstanceMigration pass strict CRD schema validation"
    else
        log_check "FAIL" "Manifests" "MigrationPolicy & Job Schemas" "Migration manifest schema validation failed"
    fi
}

mark_live_migration_untestable() {
    local reason="$1"
    if [[ "${IS_WSL2}" == true ]] && [[ "${REQUIRE_DEPLOYED}" == false ]] && [[ "${EXECUTE_MIGRATION}" == false ]]; then
        log_check "WARNING" "Cluster" "Multi-Node Migration Precondition" "${reason}"
    else
        log_check "FAIL" "Cluster" "Multi-Node Migration Precondition" "${reason}"
    fi
    log_check "NOT_TESTABLE" "Migration" "Pre-Migration VMI & RWX PVC Check" "Skipped: ${reason}"
    log_check "NOT_TESTABLE" "Migration" "Live Memory Pre-Copy Execution" "Skipped: Requires >=2 Ready KVM worker nodes & live KubeVirt"
    log_check "NOT_TESTABLE" "Migration" "Post-Migration Node Switch & Health" "Skipped: No live migration executed"
}

check_and_run_live_migration() {
    if ! kubectl version -o json >/dev/null 2>&1; then
        mark_live_migration_untestable "Kubernetes API unreachable"
        return 0
    fi

    local ready_nodes kv_phase
    ready_nodes="$(kubectl get nodes -o json | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')"
    kv_phase="$(kubectl get kubevirt kubevirt -n kubevirt -o jsonpath='{.status.phase}' 2>/dev/null || echo 'absent')"

    if [[ "${ready_nodes}" -lt 2 ]] || [[ "${kv_phase}" != "Deployed" ]]; then
        mark_live_migration_untestable "Cluster has ${ready_nodes} Ready node(s) and KubeVirt phase='${kv_phase}' (requires >=2 KVM workers + KubeVirt Deployed)"
        return 0
    fi
    log_check "PASS" "Cluster" "Multi-Node Migration Precondition" "${ready_nodes} Ready nodes and KubeVirt phase=Deployed"

    # Inspect target VMI
    local vmi_json vmi_phase src_node migratable
    if ! vmi_json="$(kubectl -n "${NAMESPACE}" get vmi "${VMI_NAME}" -o json 2>/dev/null)"; then
        log_check "WARNING" "Migration" "Pre-Migration VMI & RWX PVC Check" "Target VMI '${NAMESPACE}/${VMI_NAME}' not deployed yet"
        log_check "NOT_TESTABLE" "Migration" "Live Memory Pre-Copy Execution" "Skipped: VMI '${VMI_NAME}' not present"
        log_check "NOT_TESTABLE" "Migration" "Post-Migration Node Switch & Health" "Skipped: VMI '${VMI_NAME}' not present"
        return 0
    fi

    vmi_phase="$(echo "${vmi_json}" | jq -r '.status.phase // "Unknown"')"
    src_node="$(echo "${vmi_json}" | jq -r '.status.nodeName // "Unknown"')"
    migratable="$(echo "${vmi_json}" | jq -r '.status.conditions[]? | select(.type=="LiveMigratable") | .status' || echo "Unknown")"
    if [[ "${vmi_phase}" == "Running" ]] && [[ "${migratable}" == "True" ]]; then
        log_check "PASS" "Migration" "Pre-Migration VMI & RWX PVC Check" "${VMI_NAME} Running on '${src_node}' with LiveMigratable=True"
    else
        log_check "FAIL" "Migration" "Pre-Migration VMI & RWX PVC Check" "${VMI_NAME} phase=${vmi_phase}, LiveMigratable=${migratable} (check RWX PVC / NonMigratable reason)"
        return 0
    fi

    if [[ "${EXECUTE_MIGRATION}" == false ]] || [[ "${DRY_RUN}" == true ]]; then
        log_check "NOT_TESTABLE" "Migration" "Live Memory Pre-Copy Execution" "Skipped: Passive check mode (--execute not passed)"
        log_check "NOT_TESTABLE" "Migration" "Post-Migration Node Switch & Health" "Skipped: Passive check mode"
        return 0
    fi

    # Live execution on verified >=2 node target cluster
    local mig_name
    mig_name="${VMI_NAME}-mig-$(date +%s)"
    if [[ -n "${TARGET_NODE}" ]]; then
        cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstanceMigration
metadata:
  name: ${mig_name}
  namespace: ${NAMESPACE}
spec:
  vmiName: ${VMI_NAME}
  addedNodeSelector:
    kubernetes.io/hostname: "${TARGET_NODE}"
EOF
    else
        cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstanceMigration
metadata:
  name: ${mig_name}
  namespace: ${NAMESPACE}
spec:
  vmiName: ${VMI_NAME}
EOF
    fi

    local elapsed=0 phase="" final_ok=false
    while [[ "${elapsed}" -lt "${TIMEOUT_SEC}" ]]; do
        phase="$(kubectl -n "${NAMESPACE}" get vmim "${mig_name}" -o jsonpath='{.status.phase}' 2>/dev/null || echo 'Unknown')"
        if [[ "${phase}" == "Succeeded" ]]; then
            final_ok=true
            break
        elif [[ "${phase}" == "Failed" ]]; then
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [[ "${final_ok}" == false ]]; then
        log_check "FAIL" "Migration" "Live Memory Pre-Copy Execution" "Migration '${mig_name}' did not succeed within ${TIMEOUT_SEC}s (phase=${phase}); rolling back"
        kubectl -n "${NAMESPACE}" delete vmim "${mig_name}" --ignore-not-found=true >/dev/null 2>&1 || true
        return 0
    fi

    local dst_node post_phase
    dst_node="$(kubectl -n "${NAMESPACE}" get vmi "${VMI_NAME}" -o jsonpath='{.status.nodeName}')"
    post_phase="$(kubectl -n "${NAMESPACE}" get vmi "${VMI_NAME}" -o jsonpath='{.status.phase}')"
    if [[ "${post_phase}" == "Running" ]] && [[ "${dst_node}" != "${src_node}" ]]; then
        log_check "PASS" "Migration" "Live Memory Pre-Copy Execution" "${mig_name} completed in <=${elapsed}s (${src_node} -> ${dst_node})"
    else
        log_check "FAIL" "Migration" "Live Memory Pre-Copy Execution" "Post-migration state anomalous: phase=${post_phase}, src=${src_node}, dst=${dst_node}"
        return 0
    fi

    if virtctl guestosinfo -n "${NAMESPACE}" "${VMI_NAME}" >/dev/null 2>&1; then
        log_check "PASS" "Migration" "Post-Migration Node Switch & Health" "VMI healthy on '${dst_node}' and qemu-guest-agent responsive"
    else
        log_check "WARNING" "Migration" "Post-Migration Node Switch & Health" "VMI Running on '${dst_node}' but qemu-guest-agent unresponsive"
    fi
}

generate_reports() {
    mkdir -p "${REPORT_DIR}"
    local text_file="${REPORT_DIR}/live-migration-validation-${TIMESTAMP}.txt"
    local json_file="${REPORT_DIR}/live-migration-validation-${TIMESTAMP}.json"

    {
        echo "=============================================================================="
        echo "             KubeVirt Live Migration Validation Report"
        echo "=============================================================================="
        echo "Report Date:    ${REPORT_DATE}"
        echo "Target VMI:     ${NAMESPACE}/${VMI_NAME}"
        echo "Mode:           $([[ "${EXECUTE_MIGRATION}" == true && "${DRY_RUN}" == false ]] && echo "LIVE-EXECUTE" || echo "CHECK-ONLY")"
        echo "WSL2 Detected:  ${IS_WSL2}"
        echo "Summary:        PASS: ${COUNT_PASS} | WARN: ${COUNT_WARN} | FAIL: ${COUNT_FAIL} | N/T: ${COUNT_NOT_TESTABLE}"
        echo "------------------------------------------------------------------------------"
        printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo "------------------------------------------------------------------------------"
        for item in "${JSON_ITEMS[@]}"; do
            printf "%-6s | %-14s | %-34s | %s\n" \
                "[$(echo "${item}" | jq -r '.status' | cut -c1-4)]" \
                "[$(echo "${item}" | jq -r '.category')]" \
                "$(echo "${item}" | jq -r '.title')" \
                "$(echo "${item}" | jq -r '.details')"
        done
        echo "=============================================================================="
    } >"${text_file}"

    local checks_json="[]"
    [[ "${#JSON_ITEMS[@]}" -gt 0 ]] && checks_json="$(printf '%s\n' "${JSON_ITEMS[@]}" | jq -s '.')"
    jq -n \
        --arg reportDate "${REPORT_DATE}" \
        --arg vmi "${NAMESPACE}/${VMI_NAME}" \
        --argjson execute "${EXECUTE_MIGRATION}" \
        --argjson wsl2 "${IS_WSL2}" \
        --argjson pass "${COUNT_PASS}" \
        --argjson warn "${COUNT_WARN}" \
        --argjson fail "${COUNT_FAIL}" \
        --argjson nt "${COUNT_NOT_TESTABLE}" \
        --argjson checks "${checks_json}" \
        '{metadata:{reportDate:$reportDate,vmi:$vmi,execute:$execute,wsl2Detected:$wsl2,summary:{pass:$pass,warning:$warn,fail:$fail,notTestable:$nt}},checks:$checks}' >"${json_file}"

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "\n${COLOR_GREEN}[INFO]${COLOR_RESET} Reports archived to:"
        echo "  - ${text_file}"
        echo "  - ${json_file}"
    fi
}

main() {
    for req in kubectl yq jq kubeconform virtctl; do
        if ! command -v "${req}" >/dev/null 2>&1; then
            echo "Error: Required binary '${req}' missing from PATH." >&2
            exit 2
        fi
    done

    grep -qiE "microsoft|wsl" /proc/version 2>/dev/null && IS_WSL2=true

    if [[ "${EXECUTE_MIGRATION}" == true ]] && [[ "${IS_WSL2}" == true ]]; then
        echo "[ERROR] Refusing --execute live migration inside single-node WSL2 dev environment." >&2
        exit 1
    fi

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}${COLOR_BOLD}=============================================================================="
        echo -e "             KubeVirt Live Migration — Configuration & Test Runner"
        echo -e "==============================================================================${COLOR_RESET}"
        printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"
    fi

    check_static_migration_manifests
    check_and_run_live_migration
    generate_reports

    if [[ "${QUIET_MODE}" == false ]]; then
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
        echo -e "${COLOR_BOLD}Live Migration Validation Summary:${COLOR_RESET}"
        echo -e "  ${COLOR_GREEN}PASS:${COLOR_RESET}         ${COUNT_PASS}"
        echo -e "  ${COLOR_YELLOW}WARNING:${COLOR_RESET}      ${COUNT_WARN}"
        echo -e "  ${COLOR_RED}FAIL:${COLOR_RESET}         ${COUNT_FAIL}"
        echo -e "  ${COLOR_BLUE}NOT TESTABLE:${COLOR_RESET} ${COUNT_NOT_TESTABLE}"
        echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    fi

    [[ "${COUNT_FAIL}" -gt 0 ]] && exit 1
    exit 0
}

main "$@"
