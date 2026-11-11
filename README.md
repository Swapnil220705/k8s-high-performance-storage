# Deploy High-Performance Storage for Kubernetes (`SWFW_5S_08`)

**Program:** Zoho SETU — College Student Project Program  
**Branch:** `main`  
**Verification Model:** Three-State Honest Tracking (`IMPLEMENTED` | `VALIDATED` | `INFRASTRUCTURE-DEPENDENT`)  
**Primary Submission Artifacts:** [Technical Report](reports/final/Zoho_SETU_High_Performance_Kubernetes_Storage_Report.md) · [Presentation Deck](reports/final/Zoho_SETU_Project_Presentation.pptx) · [Submission Checklist](reports/final/SUBMISSION_CHECKLIST.md) · [Final Project Status](reports/final/FINAL_PROJECT_STATUS.md)

---

## 1. Problem Statement & Core Capabilities

Running containerized virtual machines (`KubeVirt`) on Kubernetes often forces an uncomfortable trade-off between **near-native NVMe storage performance** (kernel VFS/filesystem overheads vs. SPDK NVMe-oF) and **workload mobility** (`ReadWriteOnce` block storage vs. `ReadWriteMany` live migration).

This project designs, automates, statically validates, and prepares for multi-node evaluation a production-oriented **4-node Kubernetes storage and virtualization stack**:
- **High-Throughput Replicated Storage:** OpenEBS `4.6.2` / Replicated PV Mayastor `v2.12.2` (`SPDK`, `2` dedicated cores + `2Gi` 2MiB HugePages/worker, NVMe-oF TCP `:8420/:4421`, $N=3$ synchronous replication).
- **VM Orchestration & Storage Tiers:** KubeVirt `v1.9.1` + CDI `v1.66.1` supporting RWO Filesystem (`mayastor-nvme-r3-ext4`), direct RWO Raw Block (`mayastor-nvme-r3-block`), **Default Safe NFSv4.1 RWX Migration** (`csi-driver-nfs v4.9.0`), and **Opt-In Experimental Mayastor RWX Block** (`mayastor-nvme-r3-block-rwx`).
- **Live Migration & Hot-Plugging:** TLS-encrypted pre-copy `MigrationPolicy`/`VMIM` plus `LiveUpdate` CPU socket (`2 -> 4`), guest memory (`2Gi -> 4Gi`), and SCSI volume (`virtctl addvolume`/`removevolume`) hot-plugging *(Multus NIC hot-plug deferred)*.
- **Resilience, Benchmarking & Observability:** Reversible fault-recovery drills + SHA-256 checksum pipeline, 6 versioned `fio 3.36` profiles with environment-isolated Python summarization, and `kube-prometheus-stack v93.2.0` (`Prometheus v3.16.0`, `Grafana 13.3.1`) with source-verified alerts and 3 dashboards.

---

## 2. Target Architecture Overview

See standalone architecture diagrams under [`docs/diagrams/`](docs/diagrams/):
1. [Four-Node Kubernetes Architecture](docs/diagrams/01-four-node-kubernetes-architecture.md)
2. [Mayastor Storage & Replication Flow](docs/diagrams/02-mayastor-storage-and-replication.md)
3. [VM Storage Tiers & Live Migration](docs/diagrams/03-vm-storage-and-live-migration.md)
4. [Monitoring & Observability Architecture](docs/diagrams/04-monitoring-and-observability.md)
5. [Deployment & Validation Workflow](docs/diagrams/05-deployment-and-validation-workflow.md)

---

## 3. Technology Stack & Pinned Versions

| Subsystem | Pinned Version | Notes & Compatibility Basis |
| :--- | :--- | :--- |
| **Target OS / Kernel** | Ubuntu Server `24.04 LTS` (`Linux 6.8 LTS`) | Dev audited on WSL2 `Ubuntu 24.04.4 LTS` (`6.6.87.2`) |
| **Kubernetes** | `v1.36.6` (`kubeadm.k8s.io/v1beta4`) | Active until June 2027; local API sandbox on `K3s v1.36.6+k3s1` |
| **Container Runtime** | `containerd 2.3.x LTS` | Supported through April 2028 (`v2.3.7-k3s1.36` local K3s) |
| **CNI Networking** | Project Calico `v3.33.0` (`tigera/operator v1.44.0`) | Pure BGP (`encapsulation: None`), Pod CIDR `10.244.0.0/16` |
| **Storage Engine** | OpenEBS `4.6.2` / Mayastor `v2.12.2` | CI E2E tested up to `v1.35.6` (`v1.36` live execution pending) |
| **Virtualization** | KubeVirt `v1.9.1` + CDI `v1.66.1` (`virtctl v1.9.0`) | `>=1.35 <1.37`; `/dev/kvm` enforced (`useEmulation: false`) |
| **RWX Fallback** | `csi-driver-nfs v4.9.0` + `nfs-server-alpine:12` | `nfs-mayastor-rwx` backed by 30Gi Mayastor RWO PVC |
| **Observability** | `kube-prometheus-stack v93.2.0` (`Prom v3.16.0`, `Grafana 13.3.1`) | Strictly internal `ClusterIP` (`:9090` / `:3000`); `promtool v3.16.0` |
| **Benchmarking & QA** | `fio 3.36`, `Python 3.12.3`, `kubeconform v0.8.0`, `yq v4.54.3`, `shellcheck 0.9.0` | Verified offline schemas & `unittest` parser checks |

---

## 4. Repository Structure

```text
k8s-high-performance-storage/
├── AGENTS.md, PROJECT_STATE.md, ARCHITECTURE.md, DECISIONS.md, RESEARCH.md, LEARNING_NOTES.md
├── infrastructure/   # kubeadm, containerd, Calico BGP, OpenEBS 4.6.2 values, DiskPool v1beta3 & StorageClasses
├── kubevirt/         # KubeVirt v1.9.1 & CDI v1.66.1 CRs, CRD schemas, cloud-init, VMs, MigrationPolicy, hot-plug specs
├── storage/nfs/      # NFSv4.1 RWX fallback server & csi-driver-nfs StorageClass
├── monitoring/       # kube-prometheus-stack v93.2.0 values, ServiceMonitors, PrometheusRules & 3 Grafana dashboards
├── benchmarks/       # Versioned 4k/64k/1M FIO profiles & multi-tier matrix config
├── scripts/          # Setup (install-dev-tools, 01..08, dev-cluster-local), validate/*, benchmark/*, demo/*, tests/storage/*
├── tests/            # Resilience scenarios YAML & Python unittest suite for FIO parser
├── docs/             # Detailed subsystem runbooks, feasibility audits & docs/diagrams/*.md
└── reports/          # Archived empirical validation reports + reports/final/ submission deliverables
```

---

## 5. Prerequisites & Quick Local Validation

**Development Platform Audited:** WSL2 Ubuntu `24.04.4 LTS` (`3515 MiB` RAM, single-node `K3s v1.36.6+k3s1`, `/dev/kvm`, `fio 3.36`, `promtool v3.16.0`).  
**Target Cluster Prerequisites:** `>= 4` Ubuntu `24.04` `x86_64` nodes (`1` Control Plane + `>= 3` workers with `>= 6` CPU cores, `32 GB` RAM preferred for migration headroom, `2 GiB` 2MiB HugePages, blank raw `/dev/disk/by-id/*` NVMe/SSD drives).

```bash
# Install pinned validation/dev toolchain inside Ubuntu 24.04 (optional if already present)
sudo ./scripts/setup/install-dev-tools.sh

# Run full 11-step static/tooling suite, docs check & safe 9-stage demo orchestrator
./scripts/validate/validate-project-integration.sh
```

### Subsystem Setup, Benchmark, Monitoring, Resilience & Demo Commands
- **Dry-Run Deployment Gates (Safe Locally):**
  `./scripts/setup/05-deploy-mayastor.sh --dry-run` · `./scripts/setup/06-deploy-kubevirt.sh --dry-run` · `./scripts/setup/07-deploy-vm-examples.sh --tier all-safe --ssh-key-file ~/.ssh/id_ed25519.pub --dry-run` · `./scripts/setup/08-deploy-monitoring.sh --dry-run`
- **Target Cluster Deployment Sequence:** See [`reports/final/Zoho_SETU_High_Performance_Kubernetes_Storage_Report.md`](reports/final/Zoho_SETU_High_Performance_Kubernetes_Storage_Report.md#o-reproduction-guide) (`02`–`08`).
- **FIO Benchmarks ([Guide](docs/performance-benchmarking.md)):** `./scripts/benchmark/run-fio-benchmarks.sh --mode dry-run` | `--mode synthetic-fixture` | `--mode execute --target-tier mayastor-rwo-block --target-path /dev/vdb --confirm-target YES-I-CONFIRMED-TARGET`
- **Observability ([Guide](docs/observability.md)):** `./scripts/validate/validate-observability.sh` (`promtool`, CRDs, 3 dashboards) · `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:3000`
- **Storage Resilience ([Guide](docs/storage-resilience.md)):** `./scripts/validate/validate-storage-resilience.sh` · `./scripts/tests/storage/run-resilience-drills.sh --scenario io-engine-restart --mode simulate`
- **Integrated Demo ([Runbook](docs/demo-runbook.md)):** `./scripts/demo/run-project-demo.sh --mode local-validation` *(safe anywhere)* or `--mode target-live --confirm-demo YES-EXECUTE-LIVE-DEMO` *(target cluster)*

---

## 6. Honest Validation Summary & Limitations

- **Locally `VALIDATED`:**
  - `validate-project-integration.sh` passes **`11/11`** `run-validation.sh` steps (`26` scripts ShellCheck/shfmt clean, `39` YAML `0` warnings/errors, **`44/44`** `kubeconform -strict` + `kubeadm config validate`, `38` JSONs `jq`, `6/6` FIO `--parse-only`, `promtool v3.16.0` config & 10 rules, Python `unittest 3/3`), verifies all docs, and executes the 9-stage demo (`PASS=1, SKIP_INFRA=8, FAIL=0`).
  - Local `K3s v1.36.6+k3s1` (`12 PASS, 1 WARN, 0 FAIL, 1 N/T`), host preflight (`27/8/0/1`), SHA-256 integrity cycle, and `12/12` WSL2/destructive safety refusal gates (`exit 1`) are empirically verified.
- **`INFRASTRUCTURE-DEPENDENT` Limitations (NOT Executed Locally):**
  - This project has **NOT** been deployed on a physical 4-node production cluster and contains **NO fabricated or locally measured physical NVMe FIO benchmarks**.
  - Live SPDK/NVMe-oF `DiskPool` I/O, Mayastor replica rebuilds under node fault, 4 GiB KVM VM workloads, cross-node live migration, live CPU/RAM/SCSI hot-plugging, and cluster-wide Prometheus scraping require multi-node target hardware. Multus secondary NIC hot-plugging is deferred.

---

## 7. Documentation Index & License

- **Core Submission & Governance:** [Final Technical Report](reports/final/Zoho_SETU_High_Performance_Kubernetes_Storage_Report.md) · [Presentation (15 Slides)](reports/final/Zoho_SETU_Project_Presentation.pptx) · [Final Status](reports/final/FINAL_PROJECT_STATUS.md) · [Submission Checklist](reports/final/SUBMISSION_CHECKLIST.md) · [PROJECT_STATE.md](PROJECT_STATE.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [DECISIONS.md](DECISIONS.md) · [LEARNING_NOTES.md](LEARNING_NOTES.md)
- **Subsystem Runbooks (`docs/`):** [Kubernetes Deployment](docs/kubernetes-deployment-guide.md) · [Calico BGP](docs/calico-networking.md) · [Mayastor Architecture](docs/mayastor-architecture.md) · [KubeVirt Architecture](docs/kubevirt-architecture.md) · [VM Storage Integration](docs/vm-storage-integration.md) · [Live Migration](docs/live-migration.md) · [Runtime Hot-Plugging](docs/vm-hotplug.md) · [Storage Resilience](docs/storage-resilience.md) · [Performance Benchmarking](docs/performance-benchmarking.md) · [Observability](docs/observability.md) · [Demo Runbook](docs/demo-runbook.md)
- **License:** Released under the [MIT License](LICENSE).
