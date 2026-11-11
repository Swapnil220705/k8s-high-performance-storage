#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-observability.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates Prometheus scrape configuration (`promtool check config`),
#          PrometheusRule PromQL expressions (`promtool check rules`), ServiceMonitor/
#          PrometheusRule CRD schemas (`kubeconform -strict`), Grafana JSON
#          dashboards, and live monitoring stack health when deployed.
#
# Governance:
#   - Strictly non-destructive.
#   - Distinguishes PASS, WARNING, FAIL, and NOT_TESTABLE honestly.
#   - Archives .txt and .json audit reports under reports/monitoring/.
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

PROM_DIR="${REPO_ROOT}/monitoring/prometheus"
GRAFANA_DIR="${REPO_ROOT}/monitoring/grafana"
CORE_SCHEMA_TMPL="${REPO_ROOT}/infrastructure/k8s/schemas/v1.36.6-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json"
PROM_SCHEMA_TMPL="${PROM_DIR}/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

NAMESPACE="monitoring"
REPORT_DIR="${REPO_ROOT}/reports/monitoring"
REQUIRE_DEPLOYED=false
QUIET_MODE=false
IS_WSL2=false
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

COUNT_PASS=0
COUNT_WARN=0
COUNT_FAIL=0
COUNT_NOT_TESTABLE=0
JSON_ITEMS=()

resolve_promtool() {
    if command -v promtool >/dev/null 2>&1; then
        command -v promtool
    elif [[ -x "${HOME}/.local/bin/promtool" ]]; then
        echo "${HOME}/.local/bin/promtool"
    else
        echo ""
    fi
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Validates Prometheus configuration, alerting rules, Grafana dashboards, and runtime telemetry.

Options:
      --require-deployed    Return exit code 1 if Prometheus/Grafana pods are absent
  -n, --namespace NS        Monitoring namespace (default: ${NAMESPACE})
  -o, --output-dir DIR      Output directory for reports (default: reports/monitoring)
  -q, --quiet               Suppress console table rows
  -h, --help                Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --require-deployed)
        REQUIRE_DEPLOYED=true
        shift
        ;;
    -n | --namespace)
        NAMESPACE="${2:-}"
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

record_check() {
    local status="$1" category="$2" title="$3" details="$4"
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
        [[ "${QUIET_MODE}" == false ]] && printf "${COLOR_BLUE}[N/T] ${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    esac
    local item_json
    item_json="$(jq -n --arg st "${status}" --arg cat "${category}" --arg t "${title}" --arg d "${details}" \
        '{status: $st, category: $cat, title: $t, details: $d}')"
    JSON_ITEMS+=("${item_json}")
}

if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    IS_WSL2=true
fi

mkdir -p "${REPORT_DIR}"

if [[ "${QUIET_MODE}" == false ]]; then
    echo -e "${COLOR_CYAN}${COLOR_BOLD}==============================================================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}     Observability (Prometheus v3.16.0 & Grafana 13.3.1) Validator${COLOR_RESET}"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}==============================================================================${COLOR_RESET}"
    printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
    echo "------------------------------------------------------------------------------"
fi

# 1. promtool check config
PROMTOOL_BIN="$(resolve_promtool)"
if [[ -z "${PROMTOOL_BIN}" ]]; then
    record_check "FAIL" "Prometheus" "promtool Scrape Config Check" "promtool binary missing (expected in PATH or ~/.local/bin)"
else
    if "${PROMTOOL_BIN}" check config "${PROM_DIR}/prometheus.yml" >/dev/null 2>&1; then
        jobs_cnt="$(yq eval '.scrape_configs | length' "${PROM_DIR}/prometheus.yml")"
        record_check "PASS" "Prometheus" "promtool Scrape Config Check" "promtool check config PASS (${jobs_cnt} scrape job(s) validated)"
    else
        record_check "FAIL" "Prometheus" "promtool Scrape Config Check" "promtool check config failed on monitoring/prometheus/prometheus.yml"
    fi

    # 2. promtool check rules
    tmp_rules="$(mktemp /tmp/val-prom-rules-XXXXXX.yaml)"
    yq eval '.spec' "${PROM_DIR}/prometheus-rules.yaml" >"${tmp_rules}"
    if rule_out="$("${PROMTOOL_BIN}" check rules "${tmp_rules}" 2>&1)"; then
        rule_cnt="$(grep -oE '[0-9]+ rules' <<<"${rule_out}" | head -n 1 || echo "valid rules")"
        record_check "PASS" "Alerts" "promtool Alert Rule & PromQL Check" "promtool check rules PASS (${rule_cnt} checked)"
    else
        record_check "FAIL" "Alerts" "promtool Alert Rule & PromQL Check" "promtool check rules failed: ${rule_out}"
    fi
    rm -f "${tmp_rules}"
fi

# 3. Strict kubeconform on monitoring CRDs
if kubeconform -strict \
    -schema-location "${PROM_SCHEMA_TMPL}" \
    -schema-location "${CORE_SCHEMA_TMPL}" \
    -schema-location default \
    "${PROM_DIR}/namespace.yaml" \
    "${PROM_DIR}/servicemonitors.yaml" \
    "${PROM_DIR}/prometheus-rules.yaml" >/dev/null 2>&1; then
    record_check "PASS" "Schemas" "Monitoring CRD Schema Validation" "Namespace, ServiceMonitors, and PrometheusRule pass kubeconform -strict"
else
    record_check "FAIL" "Schemas" "Monitoring CRD Schema Validation" "kubeconform -strict failed on monitoring/prometheus manifests"
fi

# 4. Grafana Dashboard JSON & Query Audit
dash_ok=true
dash_count=0
for dash in "${GRAFANA_DIR}/dashboards/"*.json; do
    dash_count=$((dash_count + 1))
    if ! python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d.get("schemaVersion") == 39
assert isinstance(d.get("panels"), list) and len(d["panels"]) >= 8
for p in d["panels"]:
    assert p.get("title")
' "${dash}" 2>/dev/null; then
        dash_ok=false
    fi
done
if [[ "${dash_ok}" == true ]] && [[ "${dash_count}" -eq 3 ]]; then
    record_check "PASS" "Grafana" "Grafana Dashboard JSON Audit" "All ${dash_count} custom dashboards valid JSON with >=8 panels each"
else
    record_check "FAIL" "Grafana" "Grafana Dashboard JSON Audit" "Dashboard JSON validation failed (count=${dash_count})"
fi

# 5. Live Monitoring Runtime Checks
if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
    record_check "$([[ "${REQUIRE_DEPLOYED}" == true ]] && echo FAIL || echo WARNING)" "Runtime" "Monitoring Stack Deployment State" "Kubernetes API unreachable"
    for title in "Prometheus & Grafana Pod Health" "Internal ClusterIP Security Audit" "Live Mayastor & KubeVirt Targets"; do
        record_check "NOT_TESTABLE" "Runtime" "${title}" "Skipped: Kubernetes API unreachable"
    done
elif ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
    record_check "$([[ "${REQUIRE_DEPLOYED}" == true ]] && echo FAIL || echo WARNING)" "Runtime" "Monitoring Stack Deployment State" "Namespace '${NAMESPACE}' absent (intentional on 3.5 GiB WSL2 dev host)"
    for title in "Prometheus & Grafana Pod Health" "Internal ClusterIP Security Audit" "Live Mayastor & KubeVirt Targets"; do
        record_check "NOT_TESTABLE" "Runtime" "${title}" "Skipped: kube-prometheus-stack not deployed"
    done
else
    non_ready="$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | grep -cvE 'Running|Completed' || true)"
    total_pods="$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l || echo 0)"
    if [[ "${total_pods}" -gt 0 ]] && [[ "${non_ready}" -eq 0 ]]; then
        record_check "PASS" "Runtime" "Prometheus & Grafana Pod Health" "${total_pods}/${total_pods} monitoring pods Running"
    else
        record_check "FAIL" "Runtime" "Prometheus & Grafana Pod Health" "total=${total_pods}, non_ready=${non_ready}"
    fi

    external_svcs="$(kubectl get svc -n "${NAMESPACE}" -o json 2>/dev/null | jq '[.items[] | select(.spec.type != "ClusterIP")] | length')"
    if [[ "${external_svcs}" -eq 0 ]]; then
        record_check "PASS" "Security" "Internal ClusterIP Security Audit" "All services in '${NAMESPACE}' strictly ClusterIP"
    else
        record_check "FAIL" "Security" "Internal ClusterIP Security Audit" "Found ${external_svcs} non-ClusterIP service(s) in '${NAMESPACE}'"
    fi

    sm_cnt="$(kubectl get servicemonitors -n "${NAMESPACE}" -o name 2>/dev/null | wc -l || echo 0)"
    if [[ "${sm_cnt}" -ge 2 ]]; then
        record_check "PASS" "Runtime" "Live Mayastor & KubeVirt Targets" "Detected ${sm_cnt} active ServiceMonitor resources"
    else
        record_check "WARNING" "Runtime" "Live Mayastor & KubeVirt Targets" "Found ${sm_cnt} ServiceMonitor(s)"
    fi
fi

TXT_REPORT="${REPORT_DIR}/observability-validation-${TIMESTAMP}.txt"
JSON_REPORT="${REPORT_DIR}/observability-validation-${TIMESTAMP}.json"

{
    echo "=============================================================================="
    echo "              Observability Stack Validation Report"
    echo "=============================================================================="
    echo "Report Date:    ${REPORT_DATE}"
    echo "WSL2 Detected:  ${IS_WSL2}"
    echo "Summary:        PASS: ${COUNT_PASS} | WARN: ${COUNT_WARN} | FAIL: ${COUNT_FAIL} | N/T: ${COUNT_NOT_TESTABLE}"
    echo "------------------------------------------------------------------------------"
    printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
    echo "------------------------------------------------------------------------------"
    for item in "${JSON_ITEMS[@]}"; do
        printf "[%-4s] | [%-12s] | %-34s | %s\n" \
            "$(jq -r '.status' <<<"${item}" | cut -c1-4)" \
            "$(jq -r '.category' <<<"${item}")" \
            "$(jq -r '.title' <<<"${item}")" \
            "$(jq -r '.details' <<<"${item}")"
    done
    echo "=============================================================================="
} >"${TXT_REPORT}"

CHECKS_JSON="$(printf '%s\n' "${JSON_ITEMS[@]}" | jq -s '.')"
jq -n \
    --arg report_date "${REPORT_DATE}" \
    --arg namespace "${NAMESPACE}" \
    --arg wsl2 "${IS_WSL2}" \
    --argjson pass "${COUNT_PASS}" \
    --argjson warn "${COUNT_WARN}" \
    --argjson fail "${COUNT_FAIL}" \
    --argjson nt "${COUNT_NOT_TESTABLE}" \
    --argjson checks "${CHECKS_JSON}" \
    '{
        report_date_utc: $report_date,
        namespace: $namespace,
        wsl2_detected: ($wsl2 == "true"),
        summary: {pass: $pass, warning: $warn, fail: $fail, not_testable: $nt},
        checks: $checks
    }' >"${JSON_REPORT}"

if [[ "${QUIET_MODE}" == false ]]; then
    echo -e "\n[INFO] Reports archived to:"
    echo "  - ${TXT_REPORT}"
    echo "  - ${JSON_REPORT}"
    echo "=============================================================================="
    echo -e "Observability Validation Summary: PASS=${COUNT_PASS}, WARN=${COUNT_WARN}, FAIL=${COUNT_FAIL}, N/T=${COUNT_NOT_TESTABLE}"
    echo "=============================================================================="
fi

if [[ "${COUNT_FAIL}" -gt 0 ]]; then
    exit 1
fi
exit 0
