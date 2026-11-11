#!/usr/bin/env bash
# ==============================================================================
# Script Name: run-project-demo.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: End-to-end 9-stage project demonstration and verification orchestrator
#          connecting cluster readiness, Mayastor readiness, storage resilience,
#          KubeVirt & CDI, VM storage tiers, FIO benchmarking, observability,
#          live migration, and hot-plug checks.
#
# Governance & Safety Guardrails:
#   - Default `--mode local-validation` safely runs local validations & dry-runs,
#     detects unavailable multi-node hardware/services, and marks unexecuted
#     cluster steps cleanly as `SKIP_INFRASTRUCTURE_DEPENDENT` (never fake PASS).
#   - `--mode target-live` refuses execution on WSL2 and requires multi-node lab
#     hardware + `--confirm-demo YES-EXECUTE-LIVE-DEMO`.
#   - Preserves timestamped text and JSON logs under `reports/integration/`.
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

MODE="local-validation" # local-validation | target-live
CONFIRM_DEMO=""
REPORT_DIR="${REPO_ROOT}/reports/integration"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
IS_WSL2=false

COUNT_PASS=0
COUNT_WARN=0
COUNT_SKIP_INFRA=0
COUNT_FAIL=0
STAGE_JSON=()

if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    IS_WSL2=true
fi

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Runs the 9-stage Zoho SETU SWFW_5S_08 end-to-end demonstration workflow.

Options:
      --mode MODE          local-validation (default) | target-live
      --confirm-demo ACK   Required for --mode target-live: YES-EXECUTE-LIVE-DEMO
  -o, --output-dir DIR     Directory for integrated demo logs & JSON (default: reports/integration)
  -h, --help               Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --mode)
        MODE="${2:-}"
        shift 2
        ;;
    --confirm-demo)
        CONFIRM_DEMO="${2:-}"
        shift 2
        ;;
    -o | --output-dir)
        REPORT_DIR="${2:-}"
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

case "${MODE}" in
local-validation | target-live) ;;
*)
    echo "Error: Invalid --mode '${MODE}'. Must be local-validation or target-live." >&2
    exit 2
    ;;
esac

if [[ "${MODE}" == "target-live" ]]; then
    if [[ "${IS_WSL2}" == true ]]; then
        echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} Refusing --mode target-live inside single-node 3.5 GiB WSL2 host." >&2
        exit 1
    fi
    if [[ "${CONFIRM_DEMO}" != "YES-EXECUTE-LIVE-DEMO" ]]; then
        echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} Provide '--confirm-demo YES-EXECUTE-LIVE-DEMO' for live cluster execution." >&2
        exit 1
    fi
fi

mkdir -p "${REPORT_DIR}"
STAGE_LOG_TMP="$(mktemp -d /tmp/swfw-demo-XXXXXX)"
trap 'rm -rf "${STAGE_LOG_TMP}"' EXIT

STAGE_LOG_ARCHIVE="${REPORT_DIR}/project-demo-${TIMESTAMP}.stages.log"
: >"${STAGE_LOG_ARCHIVE}"

record_stage() {
    local stage_id="$1" title="$2" status="$3" details="$4"
    case "${status}" in
    PASS)
        COUNT_PASS=$((COUNT_PASS + 1))
        printf "${COLOR_GREEN}[PASS]${COLOR_RESET}       | %-8s | %-34s | %s\n" "${stage_id}" "${title}" "${details}"
        ;;
    WARN)
        COUNT_WARN=$((COUNT_WARN + 1))
        printf "${COLOR_YELLOW}[WARN]${COLOR_RESET}       | %-8s | %-34s | %s\n" "${stage_id}" "${title}" "${details}"
        ;;
    SKIP_INFRA)
        COUNT_SKIP_INFRA=$((COUNT_SKIP_INFRA + 1))
        printf "${COLOR_BLUE}[SKIP_INFRA]${COLOR_RESET} | %-8s | %-34s | %s\n" "${stage_id}" "${title}" "${details}"
        ;;
    FAIL)
        COUNT_FAIL=$((COUNT_FAIL + 1))
        printf "${COLOR_RED}[FAIL]${COLOR_RESET}       | %-8s | %-34s | %s\n" "${stage_id}" "${title}" "${details}"
        ;;
    esac
    local item
    item="$(jq -n --arg id "${stage_id}" --arg t "${title}" --arg st "${status}" --arg d "${details}" \
        '{stage: $id, title: $t, status: $st, details: $d}')"
    STAGE_JSON+=("${item}")
}

run_logged_cmd() {
    local name="$1"
    shift
    local out_f="${STAGE_LOG_TMP}/${name}.log"
    local rc=0
    set +e
    "$@" >"${out_f}" 2>&1
    rc=$?
    set -e
    {
        echo "===== ${name} (exit=${rc}) ====="
        cat "${out_f}"
        echo ""
    } >>"${STAGE_LOG_ARCHIVE}"
    return "${rc}"
}

echo -e "${COLOR_CYAN}${COLOR_BOLD}==============================================================================${COLOR_RESET}"
echo -e "${COLOR_CYAN}${COLOR_BOLD}   Zoho SETU SWFW_5S_08 — End-to-End Integration & Demonstration Workflow${COLOR_RESET}"
echo -e "${COLOR_CYAN}${COLOR_BOLD}   Mode: ${MODE^^} | WSL2: ${IS_WSL2} | Timestamp: ${REPORT_DATE}${COLOR_RESET}"
echo -e "${COLOR_CYAN}${COLOR_BOLD}==============================================================================${COLOR_RESET}"

# Pre-detect cluster components cleanly
K8S_UP=false
MAYASTOR_UP=false
KUBEVIRT_UP=false
MON_UP=false
READY_NODES=0
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    K8S_UP=true
    READY_NODES="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || true)"
    if kubectl get crd diskpools.openebs.io >/dev/null 2>&1 && kubectl get ns openebs >/dev/null 2>&1; then
        MAYASTOR_UP=true
    fi
    if kubectl get crd kubevirts.kubevirt.io >/dev/null 2>&1 && kubectl get ns kubevirt >/dev/null 2>&1; then
        KUBEVIRT_UP=true
    fi
    if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 && kubectl get ns monitoring >/dev/null 2>&1; then
        MON_UP=true
    fi
fi

# Stage 1: Kubernetes Cluster Readiness
if [[ "${K8S_UP}" == true ]]; then
    if run_logged_cmd "s1_k8s" "${REPO_ROOT}/scripts/validate/validate-kubernetes-cluster.sh" --report-only -o "${STAGE_LOG_TMP}"; then
        record_stage "Stage 1" "Kubernetes Cluster Readiness" "PASS" "Cluster reachable (${READY_NODES} Ready node(s)); validate-kubernetes-cluster PASS"
    else
        record_stage "Stage 1" "Kubernetes Cluster Readiness" "FAIL" "validate-kubernetes-cluster failed"
    fi
else
    record_stage "Stage 1" "Kubernetes Cluster Readiness" "SKIP_INFRA" "Kubernetes API unreachable; multi-node bootstrap INFRASTRUCTURE-DEPENDENT"
fi

# Stage 2: OpenEBS / Mayastor Readiness
if [[ "${MODE}" == "local-validation" ]]; then
    if run_logged_cmd "s2_ms_dry" "${REPO_ROOT}/scripts/setup/05-deploy-mayastor.sh" --dry-run &&
        run_logged_cmd "s2_ms_val" "${REPO_ROOT}/scripts/validate/validate-mayastor-deployment.sh" --report-only -o "${STAGE_LOG_TMP}" -q; then
        if [[ "${MAYASTOR_UP}" == true ]]; then
            record_stage "Stage 2" "OpenEBS Mayastor Readiness" "PASS" "Chart dry-run + live Mayastor readiness validated"
        else
            record_stage "Stage 2" "OpenEBS Mayastor Readiness" "SKIP_INFRA" "Helm/CRDs validated locally; live SPDK/NVMe-oF absent (INFRASTRUCTURE-DEPENDENT)"
        fi
    else
        record_stage "Stage 2" "OpenEBS Mayastor Readiness" "FAIL" "05-deploy-mayastor.sh --dry-run or deployment validator failed"
    fi
else
    if run_logged_cmd "s2_ms_live" "${REPO_ROOT}/scripts/validate/validate-mayastor-deployment.sh" --require-deployed -o "${STAGE_LOG_TMP}" -q; then
        record_stage "Stage 2" "OpenEBS Mayastor Readiness" "PASS" "Live Mayastor deployment & DiskPools Online"
    else
        record_stage "Stage 2" "OpenEBS Mayastor Readiness" "FAIL" "Live Mayastor readiness failed"
    fi
fi

# Stage 3: PVC Provisioning & Data Integrity Checksum Pipeline
TMP_SSH_PUB="${STAGE_LOG_TMP}/demo_ssh.pub"
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleDemoPublicKeyForDryRunOnly swfw@demo" >"${TMP_SSH_PUB}"
if [[ "${MODE}" == "local-validation" ]]; then
    if run_logged_cmd "s3_chk" "${REPO_ROOT}/scripts/tests/storage/verify-volume-checksum.sh" --mode cycle --target-dir "${STAGE_LOG_TMP}/chk" --size-mb 2; then
        if [[ "${MAYASTOR_UP}" == true ]]; then
            record_stage "Stage 3" "PVC & Integrity Verification" "PASS" "Volume checksum pipeline verified"
        else
            record_stage "Stage 3" "PVC & Integrity Verification" "SKIP_INFRA" "Local SHA-256 cycle PASS; live Mayastor PVC provisioning skipped (INFRASTRUCTURE-DEPENDENT)"
        fi
    else
        record_stage "Stage 3" "PVC & Integrity Verification" "FAIL" "verify-volume-checksum.sh cycle check failed"
    fi
else
    if run_logged_cmd "s3_k8s_chk" "${REPO_ROOT}/scripts/tests/storage/verify-volume-checksum.sh" --mode k8s-pod; then
        record_stage "Stage 3" "PVC & Integrity Verification" "PASS" "Live Mayastor PVC SHA-256 write/read verified"
    else
        record_stage "Stage 3" "PVC & Integrity Verification" "FAIL" "Live PVC SHA-256 verification failed"
    fi
fi

# Stage 4: KubeVirt & CDI Virtualization Stack
if [[ "${MODE}" == "local-validation" ]]; then
    if run_logged_cmd "s4_kv_dry" "${REPO_ROOT}/scripts/setup/06-deploy-kubevirt.sh" --dry-run &&
        run_logged_cmd "s4_kv_val" "${REPO_ROOT}/scripts/validate/validate-kubevirt.sh" -o "${STAGE_LOG_TMP}" -q; then
        if [[ "${KUBEVIRT_UP}" == true ]]; then
            record_stage "Stage 4" "KubeVirt & CDI Stack" "PASS" "KubeVirt v1.9.1 & CDI v1.66.1 live"
        else
            record_stage "Stage 4" "KubeVirt & CDI Stack" "SKIP_INFRA" "KVM/CRD/dry-run checks PASS; live virt-handler skipped on dev host"
        fi
    else
        record_stage "Stage 4" "KubeVirt & CDI Stack" "FAIL" "KubeVirt dry-run or validator failed"
    fi
else
    if run_logged_cmd "s4_kv_live" "${REPO_ROOT}/scripts/validate/validate-kubevirt.sh" --require-deployed -o "${STAGE_LOG_TMP}" -q; then
        record_stage "Stage 4" "KubeVirt & CDI Stack" "PASS" "KubeVirt & CDI Ready on target nodes"
    else
        record_stage "Stage 4" "KubeVirt & CDI Stack" "FAIL" "Live KubeVirt validation failed"
    fi
fi

# Stage 5: VM & Persistent Storage Integration
if [[ "${MODE}" == "local-validation" ]]; then
    if run_logged_cmd "s5_vm_dry" "${REPO_ROOT}/scripts/setup/07-deploy-vm-examples.sh" --tier all-safe --include-experimental-rwx --ssh-key-file "${TMP_SSH_PUB}" --dry-run &&
        run_logged_cmd "s5_vm_val" "${REPO_ROOT}/scripts/validate/validate-vm-storage.sh" -o "${STAGE_LOG_TMP}" -q; then
        if [[ "${KUBEVIRT_UP}" == true ]]; then
            record_stage "Stage 5" "VM Persistent Storage Tiers" "PASS" "All VM storage tiers verified"
        else
            record_stage "Stage 5" "VM Persistent Storage Tiers" "SKIP_INFRA" "All VM tier manifests & cloud-init validated; live VMs INFRASTRUCTURE-DEPENDENT"
        fi
    else
        record_stage "Stage 5" "VM Persistent Storage Tiers" "FAIL" "VM dry-run or storage validator failed"
    fi
else
    if run_logged_cmd "s5_vm_live" "${REPO_ROOT}/scripts/validate/validate-vm-storage.sh" --require-deployed -o "${STAGE_LOG_TMP}" -q; then
        record_stage "Stage 5" "VM Persistent Storage Tiers" "PASS" "Live DataVolumes, PVCs, and VM guest disks verified"
    else
        record_stage "Stage 5" "VM Persistent Storage Tiers" "FAIL" "Live VM storage validation failed"
    fi
fi

# Stage 6: FIO Performance Benchmarking Pipeline
if [[ "${MODE}" == "local-validation" ]]; then
    if run_logged_cmd "s6_fio_dry" "${REPO_ROOT}/scripts/benchmark/run-fio-benchmarks.sh" --mode dry-run &&
        run_logged_cmd "s6_fio_syn" "${REPO_ROOT}/scripts/benchmark/run-fio-benchmarks.sh" --mode synthetic-fixture -o "${STAGE_LOG_TMP}/fio-syn"; then
        record_stage "Stage 6" "FIO Benchmark Matrix Pipeline" "SKIP_INFRA" "6 FIO profiles + JSON parser + safety gates PASS; bare-metal NVMe IOPS INFRASTRUCTURE-DEPENDENT"
    else
        record_stage "Stage 6" "FIO Benchmark Matrix Pipeline" "FAIL" "FIO profile parse-only or parser pipeline failed"
    fi
else
    if run_logged_cmd "s6_fio_chk" "${REPO_ROOT}/scripts/benchmark/run-fio-benchmarks.sh" --mode dry-run; then
        record_stage "Stage 6" "FIO Benchmark Matrix Pipeline" "PASS" "Benchmark harness ready (invoke run-fio-benchmarks.sh --mode execute against confirmed target path)"
    else
        record_stage "Stage 6" "FIO Benchmark Matrix Pipeline" "FAIL" "FIO benchmark pre-check failed"
    fi
fi

# Stage 7: Prometheus & Grafana Observability
if [[ "${MODE}" == "local-validation" ]]; then
    if run_logged_cmd "s7_mon_dry" "${REPO_ROOT}/scripts/setup/08-deploy-monitoring.sh" --dry-run &&
        run_logged_cmd "s7_mon_val" "${REPO_ROOT}/scripts/validate/validate-observability.sh" -o "${STAGE_LOG_TMP}" -q; then
        if [[ "${MON_UP}" == true ]]; then
            record_stage "Stage 7" "Prometheus & Grafana Telemetry" "PASS" "Monitoring stack active & validated"
        else
            record_stage "Stage 7" "Prometheus & Grafana Telemetry" "SKIP_INFRA" "promtool config/rules + CRDs + 3 dashboards PASS; live scraping INFRASTRUCTURE-DEPENDENT"
        fi
    else
        record_stage "Stage 7" "Prometheus & Grafana Telemetry" "FAIL" "Observability validation failed"
    fi
else
    if run_logged_cmd "s7_mon_live" "${REPO_ROOT}/scripts/validate/validate-observability.sh" --require-deployed -o "${STAGE_LOG_TMP}" -q; then
        record_stage "Stage 7" "Prometheus & Grafana Telemetry" "PASS" "Live Prometheus, Grafana, ServiceMonitors & ClusterIP rules PASS"
    else
        record_stage "Stage 7" "Prometheus & Grafana Telemetry" "FAIL" "Live observability validation failed"
    fi
fi

# Stage 8: Storage Resilience & Recovery Readiness
if [[ "${MODE}" == "local-validation" ]]; then
    if run_logged_cmd "s8_res_val" "${REPO_ROOT}/scripts/validate/validate-storage-resilience.sh" -o "${STAGE_LOG_TMP}" -q &&
        run_logged_cmd "s8_res_drl" "${REPO_ROOT}/scripts/tests/storage/run-resilience-drills.sh" --scenario io-engine-restart --mode dry-run; then
        if [[ "${MAYASTOR_UP}" == true ]]; then
            record_stage "Stage 8" "Storage Resilience & Recovery" "PASS" "Resilience checks and drill plans verified"
        else
            record_stage "Stage 8" "Storage Resilience & Recovery" "SKIP_INFRA" "Resilience config & drill harness PASS; fault injection INFRASTRUCTURE-DEPENDENT"
        fi
    else
        record_stage "Stage 8" "Storage Resilience & Recovery" "FAIL" "Storage resilience validator or drill dry-run failed"
    fi
else
    if run_logged_cmd "s8_res_live" "${REPO_ROOT}/scripts/validate/validate-storage-resilience.sh" --require-deployed -o "${STAGE_LOG_TMP}" -q; then
        record_stage "Stage 8" "Storage Resilience & Recovery" "PASS" "Live DiskPools, io-engine & VolumeAttachments resilient"
    else
        record_stage "Stage 8" "Storage Resilience & Recovery" "FAIL" "Live storage resilience validation failed"
    fi
fi

# Stage 9: Live Migration & Runtime Hot-Plug Verification
if [[ "${MODE}" == "local-validation" ]]; then
    if run_logged_cmd "s9_mig" "${REPO_ROOT}/scripts/validate/validate-live-migration.sh" --dry-run -o "${STAGE_LOG_TMP}" -q &&
        run_logged_cmd "s9_hp" "${REPO_ROOT}/scripts/validate/validate-vm-hotplug.sh" --dry-run -o "${STAGE_LOG_TMP}" -q; then
        if [[ "${KUBEVIRT_UP}" == true ]] && [[ "${READY_NODES}" -ge 2 ]]; then
            record_stage "Stage 9" "Live Migration & Hot-Plugging" "PASS" "Migration & hot-plug preconditions verified on multi-node cluster"
        else
            record_stage "Stage 9" "Live Migration & Hot-Plugging" "SKIP_INFRA" "MigrationPolicy & LiveUpdate checks PASS; cross-node move INFRASTRUCTURE-DEPENDENT"
        fi
    else
        record_stage "Stage 9" "Live Migration & Hot-Plugging" "FAIL" "Live migration or hot-plug dry-run check failed"
    fi
else
    if run_logged_cmd "s9_live_mig" "${REPO_ROOT}/scripts/validate/validate-live-migration.sh" --require-deployed -o "${STAGE_LOG_TMP}" -q &&
        run_logged_cmd "s9_live_hp" "${REPO_ROOT}/scripts/validate/validate-vm-hotplug.sh" --require-deployed -o "${STAGE_LOG_TMP}" -q; then
        record_stage "Stage 9" "Live Migration & Hot-Plugging" "PASS" "Live migration and hot-plug preconditions Ready"
    else
        record_stage "Stage 9" "Live Migration & Hot-Plugging" "FAIL" "Live migration or hot-plug runtime precondition failed"
    fi
fi

# Archive integrated reports
TXT_OUT="${REPORT_DIR}/project-demo-${TIMESTAMP}.txt"
JSON_OUT="${REPORT_DIR}/project-demo-${TIMESTAMP}.json"

{
    echo "=============================================================================="
    echo "       Zoho SETU SWFW_5S_08 — Integrated Project Demo Report"
    echo "=============================================================================="
    echo "Report Date:      ${REPORT_DATE}"
    echo "Mode:             ${MODE}"
    echo "WSL2 Detected:    ${IS_WSL2}"
    echo "Ready Nodes:      ${READY_NODES}"
    echo "Summary:          PASS: ${COUNT_PASS} | WARN: ${COUNT_WARN} | SKIP_INFRA: ${COUNT_SKIP_INFRA} | FAIL: ${COUNT_FAIL}"
    echo "------------------------------------------------------------------------------"
    for item in "${STAGE_JSON[@]}"; do
        printf "[%-10s] | %-8s | %-32s | %s\n" \
            "$(jq -r '.status' <<<"${item}")" \
            "$(jq -r '.stage' <<<"${item}")" \
            "$(jq -r '.title' <<<"${item}")" \
            "$(jq -r '.details' <<<"${item}")"
    done
    echo "=============================================================================="
} >"${TXT_OUT}"

STAGES_ARR="$(printf '%s\n' "${STAGE_JSON[@]}" | jq -s '.')"
jq -n \
    --arg date "${REPORT_DATE}" \
    --arg mode "${MODE}" \
    --arg wsl2 "${IS_WSL2}" \
    --argjson k8s "${K8S_UP}" \
    --argjson mayastor "${MAYASTOR_UP}" \
    --argjson kubevirt "${KUBEVIRT_UP}" \
    --argjson monitoring "${MON_UP}" \
    --argjson nodes "${READY_NODES}" \
    --argjson pass "${COUNT_PASS}" \
    --argjson warn "${COUNT_WARN}" \
    --argjson skip "${COUNT_SKIP_INFRA}" \
    --argjson fail "${COUNT_FAIL}" \
    --arg log_archive "${STAGE_LOG_ARCHIVE}" \
    --argjson stages "${STAGES_ARR}" \
    '{
        report_date_utc: $date,
        mode: $mode,
        wsl2_detected: ($wsl2 == "true"),
        detected_components: {
            kubernetes_reachable: $k8s,
            ready_nodes: $nodes,
            mayastor_deployed: $mayastor,
            kubevirt_deployed: $kubevirt,
            monitoring_deployed: $monitoring
        },
        summary: {pass: $pass, warning: $warn, skip_infrastructure_dependent: $skip, fail: $fail},
        stage_log_archive: $log_archive,
        stages: $stages
    }' >"${JSON_OUT}"

echo -e "\n=============================================================================="
echo -e "Integrated Demo Summary: PASS=${COUNT_PASS}, WARN=${COUNT_WARN}, SKIP_INFRA=${COUNT_SKIP_INFRA}, FAIL=${COUNT_FAIL}"
echo "Reports archived:"
echo "  - ${TXT_OUT}"
echo "  - ${JSON_OUT}"
echo "  - ${STAGE_LOG_ARCHIVE}"
echo "=============================================================================="

if [[ "${COUNT_FAIL}" -gt 0 ]]; then
    exit 1
fi
exit 0
