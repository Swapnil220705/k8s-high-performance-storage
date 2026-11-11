# Diagram 05 — Project Deployment, Validation & End-to-End Demo Workflow

**Project:** Deploy High-Performance Storage for Kubernetes (`SWFW_5S_08`)  
**Scope Notice:** All 11 `run-validation.sh` checks, 9-stage `run-project-demo.sh --mode local-validation`, and WSL2 refusal gates passed on WSL2 (`v1.36.6+k3s1`); full `target-live` deployment requires multi-node Ubuntu hardware.

```mermaid
flowchart TB
    subgraph LocalGate["Tier 1: Local Verification & CI Gate (VALIDATED on WSL2)"]
        V1["11-Step scripts/validate/run-validation.sh<br/>Tools, +x, ShellCheck (26), shfmt, yamllint (39),<br/>kubeconform -strict (44 CRs/Manifests), jq (38 JSONs),<br/>Preflight, 6 FIO --parse-only, promtool v3.16.0, unittest (3/3)"]
        DEMO_LOC["scripts/demo/run-project-demo.sh --mode local-validation<br/>Stage 1 K3s PASS | Stages 2-9 Local Checks PASS + SKIP_INFRA"]
        SAFE["Hard WSL2 & Destructive Safety Refusal Gates (exit 1)<br/>Blocks 03..08 live apply, --mode execute drills, & unconfirmed FIO"]
    end

    subgraph TargetSeq["Tier 2: Target 4-Node Ubuntu 24.04 Deployment Sequence (INFRASTRUCTURE-DEPENDENT)"]
        S0["1. 02-node-prerequisites.sh --apply (HugePages 2Mi, nvme_tcp, swap off)"]
        S1["2. 03-bootstrap-control-plane.sh & 04-join-worker-node.sh (kubeadm + Calico BGP)"]
        S2["3. 05-deploy-mayastor.sh + operator-verified diskpools.yaml"]
        S3["4. 06-deploy-kubevirt.sh --install-nfs-fallback + 07-deploy-vm-examples.sh"]
        S4["5. 08-deploy-monitoring.sh --grafana-password-file <path>"]
        S5["6. run-project-demo.sh --mode target-live --confirm-demo YES-EXECUTE-LIVE-DEMO"]
        S6["7. run-fio-benchmarks.sh + run-resilience-drills.sh + Live Migration/Hot-Plug"]
        S0 --> S1 --> S2 --> S3 --> S4 --> S5 --> S6
    end

    V1 --> DEMO_LOC
    DEMO_LOC -.->|"Identical Scripts Promoted After Hardware Ready"| S0
```
