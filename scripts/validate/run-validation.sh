#!/usr/bin/env bash
# ==============================================================================
# Script Name: run-validation.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Description: Unified validation runner for local environment, shell scripts,
#              YAML configurations, Kubernetes manifests, and audit reports.
# Verification Scope:
#   1. Required Toolchain Availability
#   2. Script Executable Permissions
#   3. ShellCheck Static Analysis (scripts/**/*.sh)
#   4. shfmt Style & Formatting Check
#   5. yamllint Configuration Validation (.yamllint.yaml)
#   6. kubeconform Kubernetes Manifest Validation
#   7. JSON Parsing Integrity (jq validation across repo & dashboards)
#   8. Host Preflight Report Generation Check
#   9. FIO Benchmark Job-File Parse Validation
#  10. Prometheus & Grafana Observability Validation
#  11. Python Syntax & Unit Test Suite
# ==============================================================================

set -euo pipefail

# ANSI color codes
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_CYAN="\033[0;36m"
COLOR_BOLD="\033[1m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TOTAL_STEPS=11
PASSED_STEPS=0
FAILED_STEPS=0

log_step() {
    local step_num="$1"
    local title="$2"
    echo -e "\n${COLOR_CYAN}${COLOR_BOLD}[Step ${step_num}/${TOTAL_STEPS}] ${title}${COLOR_RESET}"
}

log_pass() {
    PASSED_STEPS=$((PASSED_STEPS + 1))
    echo -e "  ${COLOR_GREEN}✓ PASS:${COLOR_RESET} $1"
}

log_fail() {
    FAILED_STEPS=$((FAILED_STEPS + 1))
    echo -e "  ${COLOR_RED}✗ FAIL:${COLOR_RESET} $1" >&2
}

log_warn() {
    echo -e "  ${COLOR_YELLOW}! WARN:${COLOR_RESET} $1"
}

# ------------------------------------------------------------------------------
# Step 1: Toolchain Verification
# ------------------------------------------------------------------------------
log_step 1 "Verifying Required Development & Linting Toolchain"
REQUIRED_TOOLS=("kubectl" "helm" "kubeconform" "yamllint" "shellcheck" "shfmt" "jq" "yq" "git" "curl" "fio" "virtctl")
TOOL_FAILURES=0

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "${tool}" >/dev/null 2>&1; then
        echo -e "    - ${tool}: ${COLOR_GREEN}found${COLOR_RESET} ($(command -v "${tool}"))"
    else
        echo -e "    - ${tool}: ${COLOR_RED}NOT FOUND${COLOR_RESET}"
        TOOL_FAILURES=$((TOOL_FAILURES + 1))
    fi
done

if [[ "${TOOL_FAILURES}" -eq 0 ]]; then
    log_pass "All 12 required tools are available in PATH."
else
    log_fail "${TOOL_FAILURES} required tool(s) missing from PATH."
fi

# ------------------------------------------------------------------------------
# Step 2: Script Executable Permissions
# ------------------------------------------------------------------------------
log_step 2 "Auditing Shell Script Executable Permissions"
PERM_FAILURES=0
while IFS= read -r script_file; do
    if [[ ! -x "${script_file}" ]]; then
        echo "    Missing executable bit: ${script_file}"
        PERM_FAILURES=$((PERM_FAILURES + 1))
    fi
done < <(find "${REPO_ROOT}/scripts" -type f -name "*.sh")

if [[ "${PERM_FAILURES}" -eq 0 ]]; then
    log_pass "All shell scripts under scripts/ have executable (+x) permissions."
else
    log_fail "${PERM_FAILURES} script(s) lack executable permissions."
fi

# ------------------------------------------------------------------------------
# Step 3: ShellCheck Static Analysis
# ------------------------------------------------------------------------------
log_step 3 "Running ShellCheck Static Analysis"
SHELLCHECK_FAILURES=0
while IFS= read -r script_file; do
    echo "    Analyzing: ${script_file#"${REPO_ROOT}/"}"
    if ! shellcheck "${script_file}"; then
        SHELLCHECK_FAILURES=$((SHELLCHECK_FAILURES + 1))
    fi
done < <(find "${REPO_ROOT}/scripts" -type f -name "*.sh")

if [[ "${SHELLCHECK_FAILURES}" -eq 0 ]]; then
    log_pass "ShellCheck passed with zero warnings or errors."
else
    log_fail "ShellCheck reported issues in ${SHELLCHECK_FAILURES} file(s)."
fi

# ------------------------------------------------------------------------------
# Step 4: shfmt Formatting Validation
# ------------------------------------------------------------------------------
log_step 4 "Running shfmt Style & Formatting Check (-i 4)"
SHFMT_DIFFS=0
while IFS= read -r script_file; do
    if ! shfmt -d -i 4 "${script_file}"; then
        echo "    Formatting diff found in: ${script_file#"${REPO_ROOT}/"}"
        SHFMT_DIFFS=$((SHFMT_DIFFS + 1))
    fi
done < <(find "${REPO_ROOT}/scripts" -type f -name "*.sh")

if [[ "${SHFMT_DIFFS}" -eq 0 ]]; then
    log_pass "All shell scripts conform to standard 4-space indentation."
else
    log_fail "shfmt detected indentation differences in ${SHFMT_DIFFS} file(s)."
fi

# ------------------------------------------------------------------------------
# Step 5: yamllint YAML Linting
# ------------------------------------------------------------------------------
log_step 5 "Running yamllint on Project YAML Files"
YAMLLINT_CONF="${REPO_ROOT}/.yamllint.yaml"
YAML_FILES=()
while IFS= read -r yfile; do
    YAML_FILES+=("${yfile}")
done < <(find "${REPO_ROOT}" -maxdepth 5 -type f \( -name "*.yaml" -o -name "*.yml" \) ! -path "*/.git/*")

if [[ "${#YAML_FILES[@]}" -eq 0 ]]; then
    log_warn "No YAML files found for linting."
else
    if yamllint -c "${YAMLLINT_CONF}" "${YAML_FILES[@]}"; then
        log_pass "yamllint passed cleanly across ${#YAML_FILES[@]} YAML file(s)."
    else
        log_fail "yamllint reported syntax or style errors."
    fi
fi

# ------------------------------------------------------------------------------
# Step 6: kubeconform & kubeadm Schema Validation
# ------------------------------------------------------------------------------
log_step 6 "Validating Kubernetes Manifests with kubeconform & kubeadm"
SCHEMA_STEP_OK=true

if [[ -f "${REPO_ROOT}/infrastructure/k8s/kubeadm-init-config.yaml" ]]; then
    if command -v kubeadm >/dev/null 2>&1; then
        if kubeadm config validate --config "${REPO_ROOT}/infrastructure/k8s/kubeadm-init-config.yaml"; then
            echo "    kubeadm config validate: infrastructure/k8s/kubeadm-init-config.yaml [ok]"
        else
            echo "    kubeadm config validate failed on kubeadm-init-config.yaml" >&2
            SCHEMA_STEP_OK=false
        fi
    else
        log_warn "kubeadm binary not found in PATH; skipping kubeadm-init-config.yaml schema validation."
    fi
fi

K8S_MANIFESTS=()
while IFS= read -r kfile; do
    K8S_MANIFESTS+=("${kfile}")
done < <(find "${REPO_ROOT}/infrastructure" "${REPO_ROOT}/kubevirt" "${REPO_ROOT}/storage" "${REPO_ROOT}/monitoring/prometheus" -maxdepth 3 -type f \( -name "*.yaml" -o -name "*.yml" \) ! -name "kubeadm-init-config.yaml" ! -name "chart-metadata.yaml" ! -name "values*.yaml" ! -name "release-metadata.yaml" ! -name "prometheus.yml" 2>/dev/null || true)

if [[ "${#K8S_MANIFESTS[@]}" -gt 0 ]]; then
    CALICO_SCHEMA_TMPL="${REPO_ROOT}/infrastructure/k8s/calico/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    MAYASTOR_SCHEMA_TMPL="${REPO_ROOT}/infrastructure/storage/mayastor/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    KUBEVIRT_SCHEMA_TMPL="${REPO_ROOT}/kubevirt/installation/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    PROM_SCHEMA_TMPL="${REPO_ROOT}/monitoring/prometheus/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    CORE_K8S_SCHEMA_TMPL="${REPO_ROOT}/infrastructure/k8s/schemas/v1.36.6-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json"
    KUBECONFORM_CACHE="${HOME:-/tmp}/.cache/kubeconform"
    mkdir -p "${KUBECONFORM_CACHE}"
    if ! kubeconform -strict -summary -cache "${KUBECONFORM_CACHE}" -schema-location "${CALICO_SCHEMA_TMPL}" -schema-location "${MAYASTOR_SCHEMA_TMPL}" -schema-location "${KUBEVIRT_SCHEMA_TMPL}" -schema-location "${PROM_SCHEMA_TMPL}" -schema-location "${CORE_K8S_SCHEMA_TMPL}" -schema-location default "${K8S_MANIFESTS[@]}"; then
        SCHEMA_STEP_OK=false
    fi
fi

if [[ -f "${REPO_ROOT}/infrastructure/storage/openebs/chart-metadata.yaml" ]] && [[ -f "${REPO_ROOT}/infrastructure/storage/openebs/values.yaml" ]]; then
    if ! yq eval 'true' "${REPO_ROOT}/infrastructure/storage/openebs/chart-metadata.yaml" >/dev/null || ! yq eval 'true' "${REPO_ROOT}/infrastructure/storage/openebs/values.yaml" >/dev/null; then
        echo "    Helm metadata/values YAML structural parse failed" >&2
        SCHEMA_STEP_OK=false
    elif grep -qE '^\s*tag:\s*["'\'']?latest["'\'']?' "${REPO_ROOT}/infrastructure/storage/openebs/values.yaml"; then
        echo "    Forbidden :latest image tag detected in OpenEBS values.yaml" >&2
        SCHEMA_STEP_OK=false
    else
        echo "    OpenEBS chart-metadata.yaml & values.yaml parse/version check [ok]"
    fi
fi

if [[ -f "${REPO_ROOT}/kubevirt/installation/release-metadata.yaml" ]]; then
    if ! yq eval 'true' "${REPO_ROOT}/kubevirt/installation/release-metadata.yaml" >/dev/null; then
        echo "    KubeVirt release-metadata.yaml structural parse failed" >&2
        SCHEMA_STEP_OK=false
    elif grep -rnE '^\s*image:\s*["'\'']?[^"'\'' ]*:latest' "${REPO_ROOT}/kubevirt" "${REPO_ROOT}/storage" 2>/dev/null; then
        echo "    Forbidden :latest image tag detected in kubevirt/ or storage/ manifests" >&2
        SCHEMA_STEP_OK=false
    else
        echo "    KubeVirt release-metadata.yaml & image pinning check [ok]"
    fi
fi

if [[ "${SCHEMA_STEP_OK}" == true ]]; then
    log_pass "All Kubernetes and kubeadm manifests passed schema validation."
else
    log_fail "Schema validation failed on one or more manifests."
fi

# ------------------------------------------------------------------------------
# Step 7: JSON & YAML Parsing Integrity
# ------------------------------------------------------------------------------
log_step 7 "Validating JSON Parsing Integrity with jq"
JSON_FILES=()
while IFS= read -r jfile; do
    JSON_FILES+=("${jfile}")
done < <(find "${REPO_ROOT}/reports" "${REPO_ROOT}/infrastructure" "${REPO_ROOT}/kubevirt" "${REPO_ROOT}/monitoring" -type f -name "*.json" 2>/dev/null || true)

JSON_ERRORS=0
if [[ "${#JSON_FILES[@]}" -gt 0 ]]; then
    for jf in "${JSON_FILES[@]}"; do
        if ! jq empty "${jf}" 2>/dev/null; then
            echo "    Malformed JSON: ${jf#"${REPO_ROOT}/"}"
            JSON_ERRORS=$((JSON_ERRORS + 1))
        fi
    done
    if [[ "${JSON_ERRORS}" -eq 0 ]]; then
        log_pass "All ${#JSON_FILES[@]} JSON environment report(s) are valid JSON."
    else
        log_fail "${JSON_ERRORS} JSON file(s) failed parsing."
    fi
else
    log_warn "No JSON report files found yet."
fi

# ------------------------------------------------------------------------------
# Step 8: Preflight Report Generation Verification
# ------------------------------------------------------------------------------
log_step 8 "Verifying Preflight Automation Execution"
TEST_TMP="$(mktemp -d /tmp/val-preflight-XXXXXX)"
if "${REPO_ROOT}/scripts/setup/01-host-preflight.sh" -q -o "${TEST_TMP}"; then
    rm -rf "${TEST_TMP}"
    log_pass "01-host-preflight.sh executed cleanly and generated reports."
else
    rm -rf "${TEST_TMP}"
    log_fail "01-host-preflight.sh encountered fatal failure."
fi

# ------------------------------------------------------------------------------
# Step 9: FIO Benchmark Job-File Parse Validation
# ------------------------------------------------------------------------------
log_step 9 "Validating FIO Job Profiles (--parse-only)"
FIO_ERR=0
FIO_CNT=0
while IFS= read -r fio_file; do
    FIO_CNT=$((FIO_CNT + 1))
    if ! fio --parse-only "${fio_file}" >/dev/null 2>&1; then
        echo "    FIO parse failed: ${fio_file#"${REPO_ROOT}/"}" >&2
        FIO_ERR=$((FIO_ERR + 1))
    fi
done < <(find "${REPO_ROOT}/benchmarks/fio" -type f -name "*.fio" 2>/dev/null || true)

if [[ "${FIO_CNT}" -gt 0 ]] && [[ "${FIO_ERR}" -eq 0 ]]; then
    log_pass "All ${FIO_CNT} FIO profile(s) passed fio --parse-only validation."
else
    log_fail "FIO job validation failed (count=${FIO_CNT}, errors=${FIO_ERR})."
fi

# ------------------------------------------------------------------------------
# Step 10: Prometheus & Grafana Observability Validation
# ------------------------------------------------------------------------------
log_step 10 "Validating Prometheus Config/Rules (promtool) & Grafana Dashboards"
PROMTOOL_BIN=""
if command -v promtool >/dev/null 2>&1; then
    PROMTOOL_BIN="$(command -v promtool)"
elif [[ -x "${HOME}/.local/bin/promtool" ]]; then
    PROMTOOL_BIN="${HOME}/.local/bin/promtool"
fi

OBS_OK=true
if [[ -z "${PROMTOOL_BIN}" ]]; then
    echo "    promtool binary missing in PATH / ~/.local/bin" >&2
    OBS_OK=false
else
    if ! "${PROMTOOL_BIN}" check config "${REPO_ROOT}/monitoring/prometheus/prometheus.yml" >/dev/null 2>&1; then
        echo "    promtool check config failed on monitoring/prometheus/prometheus.yml" >&2
        OBS_OK=false
    fi
    TMP_RULES="$(mktemp /tmp/val-rules-XXXXXX.yaml)"
    yq eval '.spec' "${REPO_ROOT}/monitoring/prometheus/prometheus-rules.yaml" >"${TMP_RULES}"
    if ! "${PROMTOOL_BIN}" check rules "${TMP_RULES}" >/dev/null 2>&1; then
        echo "    promtool check rules failed on monitoring/prometheus/prometheus-rules.yaml" >&2
        OBS_OK=false
    fi
    rm -f "${TMP_RULES}"
fi

if [[ "${OBS_OK}" == true ]]; then
    log_pass "Prometheus config, alerting rules (promtool), and Grafana JSONs passed."
else
    log_fail "Observability promtool/dashboard checks failed."
fi

# ------------------------------------------------------------------------------
# Step 11: Python Syntax & Unit Test Suite
# ------------------------------------------------------------------------------
log_step 11 "Running Python Syntax & Benchmark Parser Unit Tests"
if command -v python3 >/dev/null 2>&1 &&
    python3 -m py_compile "${REPO_ROOT}/scripts/benchmark/summarize-results.py" &&
    python3 -m unittest discover -s "${REPO_ROOT}/tests/benchmarks" -p "test_*.py" >/dev/null 2>&1; then
    log_pass "Python benchmark parser syntax & unit tests passed."
else
    log_fail "Python syntax check or unit tests failed."
fi

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
echo -e "\n${COLOR_CYAN}==============================================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}Development Validation Suite Summary:${COLOR_RESET}"
echo -e "  ${COLOR_GREEN}Passed Steps:${COLOR_RESET} ${PASSED_STEPS} / ${TOTAL_STEPS}"
echo -e "  ${COLOR_RED}Failed Steps:${COLOR_RESET} ${FAILED_STEPS} / ${TOTAL_STEPS}"
echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"

if [[ "${FAILED_STEPS}" -gt 0 ]]; then
    echo -e "${COLOR_RED}[ERROR] Validation suite finished with ${FAILED_STEPS} failure(s).${COLOR_RESET}" >&2
    exit 1
fi

echo -e "${COLOR_GREEN}[SUCCESS] All development validation checks passed cleanly.${COLOR_RESET}"
exit 0
