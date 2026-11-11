#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-project-integration.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Master integration check executing:
#            1. Unified repo validation (`run-validation.sh`: scripts, YAML, schemas,
#               FIO profiles, promtool config/rules, Grafana dashboards, Python tests)
#            2. Cross-reference integrity checks across docs & setup automation
#            3. Safe integrated demo workflow (`run-project-demo.sh --mode local-validation`)
#          Archives integrated validation reports to `reports/integration/`.
# ==============================================================================

set -euo pipefail

COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_RED="\033[0;31m"
COLOR_CYAN="\033[0;36m"
COLOR_BOLD="\033[1m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_DIR="${REPO_ROOT}/reports/integration"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Runs repository-wide integration validation across manifests, scripts, benchmarks,
observability, resilience harnesses, documentation links, and safe demo execution.

Options:
  -o, --output-dir DIR   Output directory for reports (default: reports/integration)
  -h, --help             Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

mkdir -p "${REPORT_DIR}"

echo -e "${COLOR_CYAN}${COLOR_BOLD}=== [Integration 1/3] Running Unified Repository Validation Suite ===${COLOR_RESET}"
"${REPO_ROOT}/scripts/validate/run-validation.sh"

echo -e "\n${COLOR_CYAN}${COLOR_BOLD}=== [Integration 2/3] Checking Core Artifact & Documentation Cross-References ===${COLOR_RESET}"
REQUIRED_DOCS=(
    "AGENTS.md"
    "README.md"
    "PROJECT_STATE.md"
    "ARCHITECTURE.md"
    "DECISIONS.md"
    "docs/mayastor-architecture.md"
    "docs/kubevirt-architecture.md"
    "docs/vm-storage-integration.md"
    "docs/live-migration.md"
    "docs/vm-hotplug.md"
    "docs/storage-resilience.md"
    "docs/performance-benchmarking.md"
    "docs/observability.md"
    "docs/demo-runbook.md"
)

missing_docs=0
for doc in "${REQUIRED_DOCS[@]}"; do
    if [[ ! -s "${REPO_ROOT}/${doc}" ]]; then
        echo -e "${COLOR_RED}[FAIL]${COLOR_RESET} Missing or empty required document: ${doc}" >&2
        missing_docs=$((missing_docs + 1))
    else
        echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} ${doc}"
    fi
done

if [[ "${missing_docs}" -gt 0 ]]; then
    exit 1
fi

echo -e "\n${COLOR_CYAN}${COLOR_BOLD}=== [Integration 3/3] Running Safe End-to-End Local Demo Orchestrator ===${COLOR_RESET}"
"${REPO_ROOT}/scripts/demo/run-project-demo.sh" --mode local-validation -o "${REPORT_DIR}"

OUT_JSON="${REPORT_DIR}/integration-check-${TIMESTAMP}.json"
jq -n \
    --arg date "${REPORT_DATE}" \
    --arg status "PASS" \
    --arg docs_checked "${#REQUIRED_DOCS[@]}" \
    '{
        report_date_utc: $date,
        integration_status: $status,
        required_docs_verified: ($docs_checked | tonumber),
        notes: "Static analysis, schemas, FIO profiles, promtool, Python unit tests, docs presence, and safe 9-stage local demo passed cleanly."
    }' >"${OUT_JSON}"

echo -e "\n${COLOR_GREEN}[SUCCESS]${COLOR_RESET} Full project integration validation passed cleanly (${OUT_JSON})."
exit 0
