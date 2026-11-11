#!/usr/bin/env bash
# ==============================================================================
# Script Name: validate-kubernetes-cluster.sh
# Project: Deploy High-Performance Storage for Kubernetes (SWFW_5S_08)
# Purpose: Validates an active Kubernetes cluster across API compatibility,
#          node readiness, roles, CoreDNS, CNI, system health, resource
#          capacity, and scheduling/networking (optional active probe).
#
# Governance:
#   - Distinguishes PASS, FAIL, WARNING, and NOT TESTABLE.
#   - Explicitly distinguishes single-node local dev clusters from the target
#     four-node production topology (never overclaims multi-node readiness).
#   - Supports strict read-only --report-only mode.
#   - Saves human-readable (.txt) and machine-readable (.json) audit reports under
#     reports/kubernetes/.
# ==============================================================================

set -euo pipefail

# ANSI colors
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_BLUE="\033[0;34m"
COLOR_CYAN="\033[0;36m"
COLOR_BOLD="\033[1m"

REPORT_ONLY=false
REPORT_DIR="reports/kubernetes"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
TEST_NS="k8s-val-probe"

COUNT_PASS=0
COUNT_WARN=0
COUNT_FAIL=0
COUNT_NOT_TESTABLE=0
JSON_ITEMS=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Validates Kubernetes cluster health, networking, DNS, and scheduling readiness.

Options:
  --report-only          Run strictly read-only inspections (skips live Pod probe tests)
  -o, --output-dir DIR   Directory to write audit reports (default: ${REPORT_DIR})
  -h, --help             Display this help message

Exit Codes:
  0 - All core checks passed (warnings or NOT TESTABLE multi-node checks allowed)
  1 - One or more fatal FAIL conditions detected
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --report-only)
        REPORT_ONLY=true
        shift
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

log_check() {
    local status="$1"
    local category="$2"
    local title="$3"
    local details="$4"

    case "${status}" in
    PASS)
        COUNT_PASS=$((COUNT_PASS + 1))
        printf "${COLOR_GREEN}[PASS]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    WARNING)
        COUNT_WARN=$((COUNT_WARN + 1))
        printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    FAIL)
        COUNT_FAIL=$((COUNT_FAIL + 1))
        printf "${COLOR_RED}[FAIL]${COLOR_RESET} %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    NOT_TESTABLE)
        COUNT_NOT_TESTABLE=$((COUNT_NOT_TESTABLE + 1))
        printf "${COLOR_BLUE}[N/T]${COLOR_RESET}  %-14s | %-34s | %s\n" "[${category}]" "${title}" "${details}"
        ;;
    esac

    local sanitized_details
    sanitized_details="$(echo "${details}" | tr '"' "'" | tr '\n' ' ')"
    local json_entry
    json_entry=$(printf '{"category":"%s","status":"%s","title":"%s","details":"%s"}' \
        "${category}" "${status}" "${title}" "${sanitized_details}")
    JSON_ITEMS+=("${json_entry}")
}

check_api_and_versions() {
    if ! command -v kubectl >/dev/null 2>&1; then
        log_check "FAIL" "API" "kubectl Binary" "kubectl CLI binary not found in PATH"
        return 1
    fi

    local version_json
    if ! version_json="$(kubectl version -o json 2>/dev/null)"; then
        log_check "FAIL" "API" "Cluster API Reachability" "Unable to communicate with Kubernetes API server"
        return 1
    fi

    local client_ver server_ver
    client_ver="$(echo "${version_json}" | jq -r '.clientVersion.gitVersion')"
    server_ver="$(echo "${version_json}" | jq -r '.serverVersion.gitVersion')"

    log_check "PASS" "API" "API Server Connectivity" "Connected cleanly to ${server_ver} (kubectl ${client_ver})"

    if [[ "${server_ver}" =~ ^v1\.36\. ]]; then
        log_check "PASS" "Version" "Target Minor Release (1.36.x)" "Server ${server_ver} aligns with Candidate B target"
    else
        log_check "WARNING" "Version" "Target Minor Release (1.36.x)" "Server ${server_ver} differs from Candidate B (1.36.x)"
    fi
}

check_nodes_and_roles() {
    local nodes_json
    nodes_json="$(kubectl get nodes -o json)"

    local node_count ready_count
    node_count="$(echo "${nodes_json}" | jq '.items | length')"
    ready_count="$(echo "${nodes_json}" | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')"

    if [[ "${node_count}" -eq 0 ]]; then
        log_check "FAIL" "Nodes" "Cluster Node Inventory" "Zero nodes registered in cluster"
        return 1
    fi

    if [[ "${ready_count}" -eq "${node_count}" ]]; then
        log_check "PASS" "Nodes" "Node Ready Condition" "${ready_count}/${node_count} node(s) reporting Ready=True"
    else
        log_check "FAIL" "Nodes" "Node Ready Condition" "Only ${ready_count}/${node_count} node(s) reporting Ready=True"
    fi

    # Distinguish local single-node dev cluster vs target 4-node multi-node cluster
    if [[ "${node_count}" -lt 4 ]]; then
        log_check "WARNING" "Topology" "4-Node Target Architecture" "Single/dev topology (${node_count} node); multi-node control/worker separation not active"
        log_check "NOT_TESTABLE" "Topology" "Inter-Node Pod & BGP Mesh" "Multi-node networking and scheduling require >= 2 cluster nodes"
    else
        log_check "PASS" "Topology" "4-Node Target Architecture" "${node_count} nodes registered matching multi-node architecture"
    fi

    # Node pressure & container runtime audit
    local node_idx=0
    while [[ "${node_idx}" -lt "${node_count}" ]]; do
        local nname nroles runtime kernel pod_cidr pressure_issues cpu_alloc mem_alloc
        nname="$(echo "${nodes_json}" | jq -r ".items[${node_idx}].metadata.name")"
        nroles="$(echo "${nodes_json}" | jq -r "[.items[${node_idx}].metadata.labels | keys[] | select(startswith(\"node-role.kubernetes.io/\")) | sub(\"node-role.kubernetes.io/\"; \"\")] | join(\",\")")"
        [[ -z "${nroles}" ]] && nroles="worker"
        runtime="$(echo "${nodes_json}" | jq -r ".items[${node_idx}].status.nodeInfo.containerRuntimeVersion")"
        kernel="$(echo "${nodes_json}" | jq -r ".items[${node_idx}].status.nodeInfo.kernelVersion")"
        pod_cidr="$(echo "${nodes_json}" | jq -r ".items[${node_idx}].spec.podCIDR // \"unassigned\"")"
        cpu_alloc="$(echo "${nodes_json}" | jq -r ".items[${node_idx}].status.allocatable.cpu")"
        mem_alloc="$(echo "${nodes_json}" | jq -r ".items[${node_idx}].status.allocatable.memory")"

        log_check "PASS" "NodeRoles" "Node Role Assignment (${nname})" "Roles: ${nroles}"

        pressure_issues="$(echo "${nodes_json}" | jq -r "[.items[${node_idx}].status.conditions[] | select(.type != \"Ready\" and .status == \"True\") | .type] | join(\",\")")"
        if [[ -z "${pressure_issues}" ]]; then
            log_check "PASS" "NodeHealth" "Node Pressure (${nname})" "No Memory/Disk/PID pressure; Allocatable CPU=${cpu_alloc}, Mem=${mem_alloc}"
        else
            log_check "FAIL" "NodeHealth" "Node Pressure (${nname})" "Active pressure condition(s): ${pressure_issues}"
        fi

        if [[ "${runtime}" =~ containerd://2\.3\. ]]; then
            log_check "PASS" "Runtime" "Node CRI Runtime (${nname})" "${runtime} (aligned with Candidate B containerd 2.3.x LTS)"
        else
            log_check "WARNING" "Runtime" "Node CRI Runtime (${nname})" "${runtime} (target Candidate B requires containerd 2.3.x LTS)"
        fi

        if [[ "${pod_cidr}" != "unassigned" ]]; then
            log_check "PASS" "CNI" "Node PodCIDR (${nname})" "PodCIDR assigned: ${pod_cidr} (kernel ${kernel})"
        else
            log_check "WARNING" "CNI" "Node PodCIDR (${nname})" "Node spec.podCIDR unassigned"
        fi

        node_idx=$((node_idx + 1))
    done
}

check_system_pods_coredns_and_cni() {
    local pods_json
    pods_json="$(kubectl get pods -n kube-system -o json)"

    local total_sys running_sys non_ready
    total_sys="$(echo "${pods_json}" | jq '.items | length')"
    running_sys="$(echo "${pods_json}" | jq '[.items[] | select(.status.phase=="Running" or .status.phase=="Succeeded")] | length')"
    non_ready="$(echo "${pods_json}" | jq -r '[.items[] | select(.status.phase!="Succeeded" and ([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length)==0) | .metadata.name] | join(",")')"

    if [[ -z "${non_ready}" ]] && [[ "${total_sys}" -gt 0 ]]; then
        log_check "PASS" "SystemPods" "kube-system Pod Health" "All ${running_sys}/${total_sys} system pod(s) healthy and Ready"
    else
        log_check "FAIL" "SystemPods" "kube-system Pod Health" "Unready system pods: ${non_ready:-none running}"
    fi

    # CoreDNS readiness
    local coredns_ready
    coredns_ready="$(kubectl -n kube-system get deployment coredns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    [[ -z "${coredns_ready}" ]] && coredns_ready=0
    if [[ "${coredns_ready}" -ge 1 ]]; then
        log_check "PASS" "DNS" "CoreDNS Deployment" "${coredns_ready} CoreDNS replica(s) Ready in kube-system"
    else
        log_check "FAIL" "DNS" "CoreDNS Deployment" "Zero CoreDNS replicas Ready"
    fi

    # CNI inspection (Calico vs Flannel)
    if kubectl get ns tigera-operator >/dev/null 2>&1 || kubectl get daemonset -n kube-system calico-node >/dev/null 2>&1; then
        local cal_ready
        cal_ready="$(kubectl get pods -A -l k8s-app=calico-node --no-headers 2>/dev/null | grep -c "Running" || echo 0)"
        if [[ "${cal_ready}" -ge 1 ]]; then
            log_check "PASS" "CNI" "Calico CNI Status" "${cal_ready} calico-node pod(s) Running"
        else
            log_check "FAIL" "CNI" "Calico CNI Status" "Calico pods present but not Running"
        fi
    else
        # K3s / Flannel integrated CNI check
        if ip link show flannel.1 >/dev/null 2>&1 || ip link show cni0 >/dev/null 2>&1; then
            log_check "PASS" "CNI" "Local Flannel CNI Bridge" "Local Flannel CNI active (cni0/flannel.1); target Calico BGP remains INFRASTRUCTURE-DEPENDENT"
        else
            log_check "WARNING" "CNI" "CNI Interface Detection" "No active calico-node or cni0 interface observed until first pod schedules"
        fi
    fi
}

check_active_scheduling_and_network() {
    if [[ "${REPORT_ONLY}" == true ]]; then
        log_check "NOT_TESTABLE" "Scheduling" "Live Pod Scheduling Probe" "Skipped (--report-only mode specified)"
        log_check "NOT_TESTABLE" "Network" "Pod-to-Pod & CoreDNS Probe" "Skipped (--report-only mode specified)"
        return 0
    fi

    # shellcheck disable=SC2317
    cleanup_probe() {
        kubectl delete ns "${TEST_NS}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
    }
    trap cleanup_probe EXIT

    kubectl create ns "${TEST_NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

    # Deploy a super-lightweight 2-pod HTTP/DNS connectivity probe (tiny busybox)
    local probe_image="busybox:1.36"
    local server_ver
    server_ver="$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' || echo "")"
    if [[ "${server_ver}" == *"+k3s"* ]]; then
        probe_image="rancher/mirrored-library-busybox:1.37.0"
    fi

    cat <<EOF | kubectl -n "${TEST_NS}" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: probe-server
  labels:
    app: val-server
spec:
  terminationGracePeriodSeconds: 1
  containers:
    - name: httpd
      image: ${probe_image}
      imagePullPolicy: IfNotPresent
      command: ["sh", "-c", "mkdir -p /www && echo OK > /www/index.html && httpd -f -p 8080 -h /www"]
      ports:
        - containerPort: 8080
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 32Mi
---
apiVersion: v1
kind: Service
metadata:
  name: probe-svc
spec:
  selector:
    app: val-server
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: probe-client
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 1
  containers:
    - name: curl-test
      image: ${probe_image}
      imagePullPolicy: IfNotPresent
      command:
        - sh
        - -c
        - |
          for i in \$(seq 1 25); do
            if nslookup "probe-svc.${TEST_NS}.svc.cluster.local" >/dev/null 2>&1; then
              resp=\$(wget -T 3 -qO- "http://probe-svc.${TEST_NS}.svc.cluster.local/" 2>/dev/null || true)
              if [ "\${resp}" = "OK" ]; then
                echo "DNS_AND_HTTP_OK"
                exit 0
              fi
            fi
            sleep 1
          done
          exit 1
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 32Mi
EOF

    if kubectl -n "${TEST_NS}" wait --for=condition=Ready pod/probe-server --timeout=90s >/dev/null 2>&1; then
        log_check "PASS" "Scheduling" "Live Pod Scheduling Probe" "Scheduled and started probe-server cleanly using ${probe_image}"
    else
        log_check "FAIL" "Scheduling" "Live Pod Scheduling Probe" "probe-server failed to reach Ready state within 90s"
        kubectl delete ns "${TEST_NS}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
        return 1
    fi

    local client_ok=false
    for _ in $(seq 1 30); do
        local phase
        phase="$(kubectl -n "${TEST_NS}" get pod probe-client -o jsonpath='{.status.phase}' 2>/dev/null || echo "")"
        if [[ "${phase}" == "Succeeded" ]]; then
            client_ok=true
            break
        elif [[ "${phase}" == "Failed" ]]; then
            break
        fi
        sleep 2
    done

    if [[ "${client_ok}" == true ]]; then
        log_check "PASS" "Network" "Pod-to-Pod & CoreDNS Probe" "probe-client resolved probe-svc via CoreDNS and fetched HTTP 200 over CNI"
    else
        log_check "FAIL" "Network" "Pod-to-Pod & CoreDNS Probe" "probe-client failed Service DNS resolution or Pod-to-Pod HTTP test"
    fi

    kubectl delete ns "${TEST_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
}

generate_reports() {
    mkdir -p "${REPORT_DIR}"
    local text_file="${REPORT_DIR}/k8s-cluster-validation-${TIMESTAMP}.txt"
    local json_file="${REPORT_DIR}/k8s-cluster-validation-${TIMESTAMP}.json"

    {
        echo "=============================================================================="
        echo "       Kubernetes Cluster Architecture Validation Report"
        echo "=============================================================================="
        echo "Report Date:    ${REPORT_DATE}"
        echo "Report Mode:    $([[ "${REPORT_ONLY}" == true ]] && echo "REPORT-ONLY" || echo "ACTIVE-PROBE")"
        echo "Summary:        PASS: ${COUNT_PASS} | WARN: ${COUNT_WARN} | FAIL: ${COUNT_FAIL} | N/T: ${COUNT_NOT_TESTABLE}"
        echo "------------------------------------------------------------------------------"
        printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
        echo "------------------------------------------------------------------------------"
        for item in "${JSON_ITEMS[@]}"; do
            local status category title details
            status="$(echo "${item}" | jq -r '.status')"
            category="$(echo "${item}" | jq -r '.category')"
            title="$(echo "${item}" | jq -r '.title')"
            details="$(echo "${item}" | jq -r '.details')"
            printf "%-6s | %-14s | %-34s | %s\n" "[${status:0:4}]" "[${category}]" "${title}" "${details}"
        done
        echo "=============================================================================="
    } >"${text_file}"

    {
        echo "{"
        echo "  \"metadata\": {"
        echo "    \"reportDate\": \"${REPORT_DATE}\","
        echo "    \"reportOnly\": ${REPORT_ONLY},"
        echo "    \"summary\": {"
        echo "      \"pass\": ${COUNT_PASS},"
        echo "      \"warning\": ${COUNT_WARN},"
        echo "      \"fail\": ${COUNT_FAIL},"
        echo "      \"notTestable\": ${COUNT_NOT_TESTABLE}"
        echo "    }"
        echo "  },"
        echo "  \"checks\": ["
        local first=true
        for item in "${JSON_ITEMS[@]}"; do
            if [[ "${first}" == true ]]; then
                echo "    ${item}"
                first=false
            else
                echo "   ,${item}"
            fi
        done
        echo "  ]"
        echo "}"
    } >"${json_file}"

    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} Reports written to:"
    echo "  - ${text_file}"
    echo "  - ${json_file}"
}

main() {
    echo -e "${COLOR_CYAN}${COLOR_BOLD}=============================================================================="
    echo -e "       Kubernetes High-Performance Storage — Cluster Validation"
    echo -e "==============================================================================${COLOR_RESET}"
    printf "%-6s | %-14s | %-34s | %s\n" "STATUS" "CATEGORY" "CHECK" "DETAILS"
    echo -e "${COLOR_CYAN}------------------------------------------------------------------------------${COLOR_RESET}"

    if check_api_and_versions; then
        check_nodes_and_roles
        check_system_pods_coredns_and_cni
        check_active_scheduling_and_network
    fi

    generate_reports

    echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    echo -e "${COLOR_BOLD}Cluster Validation Summary:${COLOR_RESET}"
    echo -e "  ${COLOR_GREEN}PASS:${COLOR_RESET}         ${COUNT_PASS}"
    echo -e "  ${COLOR_YELLOW}WARNING:${COLOR_RESET}      ${COUNT_WARN}"
    echo -e "  ${COLOR_RED}FAIL:${COLOR_RESET}         ${COUNT_FAIL}"
    echo -e "  ${COLOR_BLUE}NOT TESTABLE:${COLOR_RESET} ${COUNT_NOT_TESTABLE}"
    echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"

    if [[ "${COUNT_FAIL}" -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
