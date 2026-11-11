# End-to-End Integration & Demonstration Runbook

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Orchestrators:** [`scripts/demo/run-project-demo.sh`](../scripts/demo/run-project-demo.sh) & [`scripts/validate/validate-project-integration.sh`](../scripts/validate/validate-project-integration.sh)

---

## 1. End-to-End 9-Stage Workflow

```mermaid
flowchart LR
    S1["1. K8s Cluster<br/>Readiness"] --> S2["2. OpenEBS /<br/>Mayastor Ready"]
    S2 --> S3["3. PVC & SHA-256<br/>Integrity"]
    S3 --> S4["4. KubeVirt & CDI<br/>Stack"]
    S4 --> S5["5. VM & Storage<br/>Tiers"]
    S5 --> S6["6. FIO Benchmark<br/>Matrix Pipeline"]
    S6 --> S7["7. Prometheus &<br/>Grafana Telemetry"]
    S7 --> S8["8. Storage Resilience<br/>& Recovery"]
    S8 --> S9["9. Live Migration &<br/>Hot-Plugging"]
```

---

## 2. Operating Modes (Local Validation vs. Multi-Node Target Live)

| Flag / Command | Environment Allowed | Behavior & Exit Semantics |
| :--- | :---: | :--- |
| `./scripts/demo/run-project-demo.sh --mode local-validation` | **WSL2 / Dev Laptop / CI (Default)** | Executes Kubernetes single-node checks, Helm/CRD/FIO/`promtool` dry-runs, and SHA-256 temp-dir integrity cycle. Detects missing Mayastor/KubeVirt/Monitoring/multi-node hardware and records those stages honestly as **`SKIP_INFRA`** (`0` fake passes). Archives logs + JSON under `reports/integration/`. |
| `./scripts/validate/validate-project-integration.sh` | **WSL2 / Dev Laptop / CI** | Executes full 11-step `run-validation.sh` (ShellCheck, shfmt, yamllint, kubeconform strict, promtool, Python `unittest`, FIO `--parse-only`), checks all core docs exist, and executes `run-project-demo.sh --mode local-validation`. |
| `./scripts/demo/run-project-demo.sh --mode target-live --confirm-demo YES-EXECUTE-LIVE-DEMO` | **4-Node Ubuntu Target Only** | Unconditionally refused on WSL2 (`exit 1`). Enforces `--require-deployed` across cluster, Mayastor, KubeVirt, VM storage, monitoring, resilience, live migration preconditions, and live PVC SHA-256 verification. |

---

## 3. Recommended Demonstration Sequence on Multi-Node Target Hardware

1. Run repository preflight and integration checks:
   ```bash
   ./scripts/validate/validate-project-integration.sh
   ```
2. Verify all deployed subsystems (`PASS` across all 9 live stages):
   ```bash
   ./scripts/demo/run-project-demo.sh --mode target-live --confirm-demo YES-EXECUTE-LIVE-DEMO
   ```
3. Run FIO multi-tier matrix (`local-baseline`, `mayastor-rwo-fs`, `mayastor-rwo-block`, `nfs-rwx`) using [`run-fio-benchmarks.sh`](../scripts/benchmark/run-fio-benchmarks.sh) and summarize via [`summarize-results.py`](../scripts/benchmark/summarize-results.py).
4. Execute reversible fault-recovery drill (`run-resilience-drills.sh --scenario io-engine-restart --mode execute --confirm-drill YES-EXECUTE-RESILIENCE-DRILL`), cross-node live migration (`validate-live-migration.sh --execute`), and runtime hot-plugging (`validate-vm-hotplug.sh --execute`), while observing Grafana (`kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:3000`).

