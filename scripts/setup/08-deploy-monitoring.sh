#!/usr/bin/env bash
# ==============================================================================
# Script Name: 08-deploy-monitoring.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates observability manifests (promtool, kubeconform, jq/Grafana)
#          and deploys pinned kube-prometheus-stack v93.2.0 (Prometheus v3.16.0 +
#          Grafana 13.3.1), custom ServiceMonitors, PrometheusRules, and 3 custom
#          Grafana dashboards onto target Kubernetes clusters.
#
# Governance & Safety Guardrails:
#   - Unconditionally REFUSES live deployment inside WSL2 (3.5 GiB dev host).
#   - Never hardcodes Grafana passwords in Git; reads --grafana-password-file.
#   - Keeps Prometheus (:9090) & Grafana (:3000) ClusterIP-internal only.
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

PROM_DIR="${REPO_ROOT}/monitoring/prometheus"
GRAFANA_DIR="${REPO_ROOT}/monitoring/grafana"
CORE_SCHEMA_TMPL="${REPO_ROOT}/infrastructure/k8s/schemas/v1.36.6-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json"
PROM_SCHEMA_TMPL="${PROM_DIR}/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

NAMESPACE="monitoring"
RELEASE_NAME="kube-prometheus-stack"
CHART_REPO_URL="https://prometheus-community.github.io/helm-charts"
CHART_VERSION="93.2.0"

DRY_RUN=false
LIGHTWEIGHT=false
CHART_DIR=""
GRAFANA_PASSWORD_FILE=""

IS_WSL2=false
if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    IS_WSL2=true
fi

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

Validates and deploys kube-prometheus-stack v${CHART_VERSION} + storage/VM dashboards.

Options:
      --dry-run                    Validate Prometheus config, rules, CRDs, and Grafana dashboards
      --lightweight                Include monitoring/prometheus/values-dev-lightweight.yaml overlay
      --chart-dir PATH             Local pre-pulled kube-prometheus-stack v${CHART_VERSION} directory
      --grafana-password-file PATH File containing initial Grafana admin password (never committed)
  -h, --help                       Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    --lightweight)
        LIGHTWEIGHT=true
        shift
        ;;
    --chart-dir)
        CHART_DIR="${2:-}"
        shift 2
        ;;
    --grafana-password-file)
        GRAFANA_PASSWORD_FILE="${2:-}"
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

for bin in helm kubectl kubeconform yamllint yq jq python3; do
    if ! command -v "${bin}" >/dev/null 2>&1; then
        log_error "Required binary '${bin}' not found in PATH."
        exit 2
    fi
done

run_static_checks() {
    log_info "Linting monitoring YAML manifests with yamllint..."
    yamllint -c "${REPO_ROOT}/.yamllint.yaml" \
        "${REPO_ROOT}/monitoring/release-metadata.yaml" \
        "${PROM_DIR}/namespace.yaml" \
        "${PROM_DIR}/values.yaml" \
        "${PROM_DIR}/values-dev-lightweight.yaml" \
        "${PROM_DIR}/prometheus.yml" \
        "${PROM_DIR}/servicemonitors.yaml" \
        "${PROM_DIR}/prometheus-rules.yaml" \
        "${GRAFANA_DIR}/provisioning/datasources/prometheus.yaml" \
        "${GRAFANA_DIR}/provisioning/dashboards/dashboards.yaml"

    log_info "Validating monitoring Kubernetes manifests & Prometheus Operator CRDs..."
    kubeconform -strict -summary \
        -schema-location "${PROM_SCHEMA_TMPL}" \
        -schema-location "${CORE_SCHEMA_TMPL}" \
        -schema-location default \
        "${PROM_DIR}/namespace.yaml" \
        "${PROM_DIR}/servicemonitors.yaml" \
        "${PROM_DIR}/prometheus-rules.yaml"

    local promtool_bin
    promtool_bin="$(resolve_promtool)"
    if [[ -z "${promtool_bin}" ]]; then
        log_error "promtool binary not found in PATH or ~/.local/bin."
        exit 1
    fi

    log_info "Running $(basename "${promtool_bin}") check config & check rules..."
    "${promtool_bin}" check config "${PROM_DIR}/prometheus.yml"

    local tmp_rules
    tmp_rules="$(mktemp /tmp/prom-rules-XXXXXX.yaml)"
    yq eval '.spec' "${PROM_DIR}/prometheus-rules.yaml" >"${tmp_rules}"
    "${promtool_bin}" check rules "${tmp_rules}"
    rm -f "${tmp_rules}"

    log_info "Validating Grafana dashboard JSON structures..."
    for dash in "${GRAFANA_DIR}/dashboards/"*.json; do
        jq empty "${dash}"
        python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d.get("uid") and d.get("title") and isinstance(d.get("panels"), list) and len(d["panels"]) >= 5, sys.argv[1]
' "${dash}"
        echo "    [OK] $(basename "${dash}")"
    done
}

run_static_checks

if [[ "${DRY_RUN}" == true ]]; then
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_warn "[DRY-RUN] No active cluster reachable; offline checks passed cleanly."
    else
        node_cnt="$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)"
        log_info "[DRY-RUN] Connected cluster server: $(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // "unknown"') (${node_cnt} node(s))."
        if [[ "${IS_WSL2}" == true ]] || [[ "${node_cnt}" -lt 2 ]]; then
            log_warn "[DRY-RUN] WSL2/single-node environment: full kube-prometheus-stack live deploy remains INFRASTRUCTURE-DEPENDENT."
        fi
    fi
    log_info "[DRY-RUN] All monitoring config, rule, CRD, and dashboard checks passed with zero mutations."
    exit 0
fi

# ------------------------------------------------------------------------------
# Live Target Cluster Guardrails
# ------------------------------------------------------------------------------
if [[ "${IS_WSL2}" == true ]]; then
    log_error "WSL2 environment detected. Refusing live kube-prometheus-stack deployment on 3.5 GiB WSL2 dev host."
    exit 1
fi

if [[ -z "${GRAFANA_PASSWORD_FILE}" ]] || [[ ! -s "${GRAFANA_PASSWORD_FILE}" ]]; then
    log_error "Provide a non-empty --grafana-password-file for live Grafana credential provisioning."
    exit 2
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Kubernetes cluster unreachable."
    exit 1
fi

read -r -p "Type 'DEPLOY-MONITORING' to install kube-prometheus-stack v${CHART_VERSION} into '${NAMESPACE}': " ack
if [[ "${ack}" != "DEPLOY-MONITORING" ]]; then
    log_error "Aborted by operator."
    exit 1
fi

kubectl apply -f "${PROM_DIR}/namespace.yaml"
kubectl -n "${NAMESPACE}" create secret generic grafana-admin-credentials \
    --from-literal=admin-user=admin \
    --from-file=admin-password="${GRAFANA_PASSWORD_FILE}" \
    --dry-run=client -o yaml | kubectl apply -f -

local_chart="${CHART_DIR}"
if [[ -z "${local_chart}" ]]; then
    helm repo add prometheus-community "${CHART_REPO_URL}" >/dev/null 2>&1 || true
    helm repo update prometheus-community
    local_chart="prometheus-community/kube-prometheus-stack"
fi

values_args=(-f "${PROM_DIR}/values.yaml")
if [[ "${LIGHTWEIGHT}" == true ]]; then
    values_args+=(-f "${PROM_DIR}/values-dev-lightweight.yaml")
fi

helm upgrade --install "${RELEASE_NAME}" "${local_chart}" \
    --namespace "${NAMESPACE}" \
    --version "${CHART_VERSION}" \
    "${values_args[@]}" \
    --wait --timeout 10m

for dash in "${GRAFANA_DIR}/dashboards/"*.json; do
    cm_name="grafana-dash-$(basename "${dash}" .json)"
    kubectl -n "${NAMESPACE}" create configmap "${cm_name}" \
        --from-file="$(basename "${dash}")=${dash}" \
        --dry-run=client -o yaml |
        kubectl label --local -f - grafana_dashboard="1" -o yaml |
        kubectl apply -f -
done

kubectl apply -f "${PROM_DIR}/servicemonitors.yaml"
kubectl apply -f "${PROM_DIR}/prometheus-rules.yaml"

log_info "Observability stack deployed (internal ClusterIP ONLY). Access via:"
log_info "  kubectl -n ${NAMESPACE} port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
log_info "  kubectl -n ${NAMESPACE} port-forward svc/kube-prometheus-stack-grafana 3000:3000"
exit 0
