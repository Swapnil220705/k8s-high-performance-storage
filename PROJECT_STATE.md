# Project Progress State & Execution Tracker

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Active Branch:** `main`  
**Current Phase:** Final Completion Sprint (Prompt 2 of 3 Completed — Storage Resilience, FIO Benchmarking, Observability & E2E Demo Integration)  
**Current Chunk:** Final Completion Sprint — Prompt 2 of 3  
**Sprint 2 Status:** 🟢 COMPLETED (Mayastor Resilience & Reversible Fault Drills, FIO Benchmark Suite + Python Parser Unit Tests, `kube-prometheus-stack v93.2.0` + `promtool v3.16.0` + 3 Grafana Dashboards, and 9-Stage E2E Demo Orchestrator Implemented & Statically/Safety Validated; Multi-Node Live Execution INFRASTRUCTURE-DEPENDENT)  
**Overall Completion:** M1–M9 Completed + M10 E2E Orchestrator Implemented (Publication Graphs, Final Report, Viva Kit Remaining in Prompt 3 of 3)  

---

> [!IMPORTANT]
> **Single Source of Truth & Governance Alignment:**  
> This document tracks the precise, factual progress of the project. No feature is marked as complete or verified until empirical evidence is gathered and recorded in the repository. In accordance with **ADR-011**, institutional hardware allocation is decoupled from development gating, and every feature is tracked across three explicit states: `IMPLEMENTED`, `VALIDATED`, and `INFRASTRUCTURE-DEPENDENT`.

---

## 1. Chunk Progress Summary

| Chunk | Title / Focus Area | Status | Target Delivery | Verification Level |
| :--- | :--- | :---: | :---: | :---: |
| **0** | **Project Foundation & Governance** | 🟢 **COMPLETED** | Chunk 0 | Documentation, Git & Structural Verification |
| **1** | **Infrastructure Discovery & Technical Feasibility** | 🟢 **COMPLETED** | Chunk 1 | Local WMI/CIM Audit, Literature & Matrix Verification |
| **1.8**| **Technical Research Corrections** | 🟢 **COMPLETED** | Chunk 1.8 | Upstream Lifecycle Reassessment, Native RWX & Port Audit |
| **1.9**| **Final Lifecycle, Compatibility & Resource Audit** | 🟢 **COMPLETED** | Chunk 1.9 | EOL Elimination (k8s 1.34/containerd 1.7), 2-Core SPDK Busy-Poll, GB/GiB Sizing, 20-Port Scopes |
| **1.10**| **Final Compatibility & Resource Reconciliation** | 🟢 **COMPLETED** | Chunk 1.10 | containerd Recommendation Matrix Reconciled, Mayastor 2.12.2 E2E on K8s 1.35.6, Exact Binary Memory Math, Asymmetric Migration Budgets, Authoritative Ports |
| **1.11**| **Final Deployment Baseline and Evidence Closure** | 🟢 **COMPLETED** | Chunk 1.11 | Candidate B Preferred Target, OpenEBS v4.6.x Chart Mapping Verified, MemTotal Memory Sizing & Headroom, Canonical 20-Port Matrix, Single-Writer Migration Protocol, Verified Rebuild Parameters |
| **2.0**| **Infrastructure Readiness & Access Planning** | 🟢 **COMPLETED** | Chunk 2.0 | Evidence-Based Readiness Tracker, Refined College Questionnaire, Administrative Access Matrix, Fallback Hierarchy, Objective Assessment (NOT READY) |
| **2.1**| **Project Strategy Alignment & Environment Assessment** | 🟢 **COMPLETED** | Chunk 2.1 | ADR-011 Strategy Realignment, 12-Component Feasibility Matrix, 5 Execution Pathways, 3-State Completion Framework, 10-Milestone Development Roadmap |
| **M1** | **Milestone 1: Dev Environment Preparation & Automated Tooling** | 🟢 **COMPLETED** | Milestone M1 | Toolchain Installed (12 tools), Linters Configured, Preflight (`01-host-preflight.sh`), Node Prerequisites (`02-node-prerequisites.sh`), Unified Validation (`run-validation.sh`) |
| **M2** | **Milestone 2: Kubernetes Cluster Architecture & Multi-Node Provisioning** | 🟢 **COMPLETED** | Milestone M2 | `kubeadm` v1.36.6 Config Validated, Calico v3.33.0 Validated, Bootstrap Scripts Implemented, Local K3s v1.36.6+k3s1 Dev Cluster Operational (12/12 PASS, 1 WARN, 1 N/T) |
| **M3** | **Milestone 3: OpenEBS Mayastor Storage Engine Deployment** | 🟢 **COMPLETED** | Milestone M3 | OpenEBS `4.6.2` / Mayastor `2.12.2` Values, `DiskPool v1beta3` Schema, StorageClasses, Prereq/Deploy/Validation Automation & Docs (`8/8` validation pass + WSL2 refusal verified) |
| **M4** | **Milestone 4: KubeVirt Virtualization Stack Integration** | 🟢 **COMPLETED** | Sprint 1 (M4) | KubeVirt `v1.9.1`, CDI `v1.66.1`, strict CRD + K8s `v1.36.6` schemas, `06-deploy-kubevirt.sh`, `validate-kubevirt.sh` (`PASS` dry-run/schema/refusal) |
| **M5** | **Milestone 5: Storage Subsystem Integration with Virtual Machines** | 🟢 **COMPLETED** | Sprint 1 (M5) | RWO FS, RWO Block, Default NFS RWX (`csi-driver-nfs v4.9.0`), Opt-In Exp RWX Block, cloud-init, `07-deploy-vm-examples.sh`, `validate-vm-storage.sh` |
| **M6** | **Milestone 6: VM Live Migration & Runtime Resource Hot-Plugging** | 🟡 **CORE IMPLEMENTED** | Sprint 1 (M6 Core) | `MigrationPolicy`, `VMIM`, `vm-ubuntu-hotplug`, `validate-live-migration.sh`, `validate-vm-hotplug.sh`; Multus NIC hot-plug pending Sprint 2–3 |
| **M7** | **Milestone 7: Distributed Storage Failure Recovery & Rebuild Drills** | 🟢 **COMPLETED** | Sprint 2 (M7) | `resilience-scenarios.yaml`, `verify-volume-checksum.sh`, `observe-rebuild-events.sh`, `run-resilience-drills.sh`, `validate-storage-resilience.sh` |
| **M8** | **Milestone 8: Storage Performance Benchmarking (FIO Matrix)** | 🟢 **COMPLETED** | Sprint 2 (M8) | `6` `.fio` profiles, `matrix-config.yaml`, `run-fio-benchmarks.sh`, `summarize-results.py`, `test_summarize_results.py` (`3` unittest pass) |
| **M9** | **Milestone 9: Full-Stack Telemetry, Monitoring & Observability** | 🟢 **COMPLETED** | Sprint 2 (M9) | `kube-prometheus-stack v93.2.0`, `promtool v3.16.0` verified alerts & config, `3` Grafana JSONs, `08-deploy-monitoring.sh`, `validate-observability.sh` |
| **M10**| **Milestone 10: Final System Integration, Evidence & Submission** | 🟡 **INTEGRATION READY** | Sprint 2 (M10 Core) / Sprint 3 | 9-stage `run-project-demo.sh` & `validate-project-integration.sh` done (`Sprint 2`); publication charts, final paper & viva kit pending Sprint 3 |

---

## 2. Feature & Implementation Verification Ledger

### 2.1 Implemented Artifacts (Chunk 0 through Chunk 1.10)
- [x] Standardized 31-directory project structure created with `.gitkeep` markers.
- [x] Comprehensive multi-tier `.gitignore` filtering secrets, kubeconfigs, and runtime temp files.
- [x] Project landing page and high-level specification (`README.md`).
- [x] Detailed proposed target architecture and data flow diagrams (`ARCHITECTURE.md`).
- [x] AI agent governance operating directives (`AGENTS.md`).
- [x] Project execution and state tracker (`PROJECT_STATE.md`).
- [x] Architectural Decision Records register (`DECISIONS.md`).
- [x] Technical research and literature tracker (`RESEARCH.md`).
- [x] Student engineering study guide and viva preparation notes (`LEARNING_NOTES.md`).
- [x] Project licensing (`LICENSE`).
- [x] Local machine hardware & OS assessment (`docs/infrastructure-inventory.md`).
- [x] College infrastructure requirements inquiry & questionnaire (`docs/college-infrastructure-questionnaire.md`).
- [x] Software version compatibility matrix & dependency research (`docs/compatibility-matrix.md`).
- [x] Storage architecture & KubeVirt live-migration feasibility analysis (`docs/storage-architecture-analysis.md`).
- [x] Network topology & verified firewall port matrix (`docs/network-and-virtualization-requirements.md`).
- [x] Infrastructure deployment options comparison (`docs/deployment-options.md`).
- [x] Final target deployment architecture proposal (`docs/final-deployment-proposal.md`).
- [x] **Chunk 1.10 Reconciliation: Version Matrix & Lifecycle (`docs/compatibility-matrix.md`):**
  - Reconciled containerd official Kubernetes recommendation matrix: containerd 2.2 for K8s 1.35; containerd 2.3 for K8s 1.36+.
  - Documented containerd 2.2 EOL on November 6, 2026.
  - Evaluated Candidate A (K8s 1.35.x + containerd 2.2/2.3 + Mayastor 2.12.2 + KubeVirt 1.8/1.9 + Calico 3.33) vs. Candidate B (K8s 1.36.x + containerd 2.3 LTS + Mayastor 2.12.2 + KubeVirt 1.9 + Calico 3.33).
  - Verified Mayastor v2.12.2 (OpenEBS chart v4.7.0) automated E2E tests run against Kubernetes v1.35.6. Documented qualification gap for K8s 1.36.
- [x] **Chunk 1.10 Reconciliation: Memory Engineering & Asymmetric Migration Budgets (`docs/network-and-virtualization-requirements.md`):**
  - Calculated exact binary conversion: 16 GB = 14.90 GiB; 32 GB = 29.80 GiB.
  - Formulated separate Source and Destination live-migration budgets.
  - Proved that Case 2 (destination node already hosting a 4 GiB VM) requires 15.30 – 19.60 GiB during cutover, causing guaranteed OOM failure on 16 GB nodes. Enforced 32 GB physical RAM for multi-VM live migration.
  - Audited authoritative Mayastor ports: TCP 10124 (gRPC), TCP 8420 & 4421 (NVMe-oF data plane). Purged TCP 4420. Removed TCP 8011 from mandatory host-to-host firewall. Restricted monitoring ports (9090, 3000, 9100) to internal management access.
- [x] **Chunk 1.10 Reconciliation: Evidence-Based Migration Safety & Rebuild Configuration (`docs/storage-architecture-analysis.md`):**
  - Replaced "0.000 ms proof" with multi-layer evidence-based audit: KubeVirt migration states, QEMU QMP `STOP`/`RESUME` events, Mayastor multi-attach session logs, in-guest strictly monotonic sequence writes ($1 \dots K$), and end-to-end CRC32C verification under documented clock drift boundaries.
  - Clarified Mayastor rebuild configuration: distinguished partial rebuild wait period (`child_wait_period`, default 10m on `io-engine`) from node unreachable grace period (`rebuild.grace_period`, default 5-10m on `mayastor-agent-core`), published vs unpublished volume behavior, and chart configurability.
- [x] **Chunk 1.11 Final Deployment Baseline & Evidence Closure:**
  - **Preferred Qualification Target (Candidate B):** Established Kubernetes 1.36.x + containerd 2.3.x LTS + KubeVirt 1.9.x + Calico 3.33 + OpenEBS v4.6.x (Mayastor subchart v2.12.2) as the preferred experimental qualification target due to lifecycle alignment (supported through June 2027 / April 2028).
  - **Comparison Baseline (Candidate A):** Retained Kubernetes 1.35.x + containerd 2.2.x strictly as a storage-tested comparison configuration (containerd 2.2 EOL on Nov 6, 2026 makes it unviable for new deployments). Excluded Kubernetes 1.37 due to missing qualification.
  - **OpenEBS Chart Mapping Verified:** Confirmed published umbrella chart `openebs` v4.6.x (e.g. v4.6.1/v4.6.2) officially packages Mayastor subchart v2.12.2 (`io-engine:v2.12.2`). Formally purged unreleased "v4.7.0" references.
  - **MemTotal Usable Memory Headroom:** Recalculated headroom subtracting static base and VM overheads from usable `MemTotal` ($14.40 - 14.70\text{ GiB}$ for 16 GB, $29.30 - 29.60\text{ GiB}$ for 32 GB). Proved that loaded destination (Case 2) on 16 GB hosts yields a fatal deficit of **$-0.60\text{ to }-5.20\text{ GiB}$**, making migration impossible under loaded conditions. Headroom on 32 GB hosts remains $+9.70\text{ to }+14.30\text{ GiB}$.
  - **Single-Writer Concurrency Verification Protocol:** Formulated rigorous verification protocol with 512-byte fixed binary record layout, unique writer IDs, writer epochs, atomic sequence counters, duplicate/stale/gap detection, CRC32C verification, QEMU QMP `STOP`/`RESUME` event correlation, and physical clock drift limits.
  - **Rebuild Configuration Verified:** Verified `--faulted-child-wait-period` (default 10m / 600s) on `mayastor-agent-core`; clarified that a standalone `--node-unreachable-timeout` flag does not exist in upstream Mayastor (governed by Kubernetes node eviction tolerations and NVMe `ctrl_loss_tmo`).
  - **Canonical 20-Port Matrix:** Built reconciled 20-port table (10 physical host firewall rules, 10 cluster-internal/loopback services); purged TCP 4420; confirmed Multus CNI requires 0 network ports.
- [x] **Chunk 2.0 Infrastructure Readiness & Access Planning:**
  - **Refined Infrastructure Questionnaire (`docs/college-infrastructure-questionnaire.md`):** Professional inquiry formulated for laboratory administrators, structured into node specs, dedicated raw disks, KVM virtualization, HugePages, static networking, and administrative access.
  - **Infrastructure Readiness Tracker (`docs/infrastructure-readiness-tracker.md`):** Complete tracking matrix established across 17 technical items (HW, ACC, NET, INS) using strict governance statuses (`UNKNOWN`, `REQUESTED`, `CONFIRMED`, `UNAVAILABLE`, `BLOCKED`).
  - **Hardware Allocation Ledger:** Set up candidate machine tracking for Node 0 and Workers 1–3, retaining planning standards (6-core min, 16 GB RAM baseline, 32 GB preferred, 2 dedicated SPDK cores, 2 GiB HugePages, dedicated raw SSD/NVMe).
  - **Administrative Access Matrix:** Formalized requirements for root/sudo, SSH, HugePages, kernel modules (`nvme-tcp`), firewall rules, reboot permissions, and explicit raw disk wipe/format permissions.
  - **Network Readiness Checklist:** Mapped Layer-2 subnet, static IP, DNS, NTP, and firewall communication paths.
  - **Infrastructure Fallback Hierarchy:** Documented 4 fallback tiers prioritizing physical college servers and lab desktops over nested virtualization, with commercial cloud prohibited and development laptop excluded.
  - **Readiness Verdict (NOT READY):** Established objective assessment criteria; formally declared environment **NOT READY** due to pending machine allocation, sudo grants, IP assignments, and disk dedications.
- [x] **Chunk 2.1 Project Strategy Alignment & Development Environment Assessment:**
  - **Empirical Environment Assessment (`docs/development-environment-assessment.md`):** Directly audited host Windows 11 (AMD Ryzen 5 7535HS, 6C/12T, 8 GB DDR5, ~1.0 GB free, 19.3 GB disk free) and WSL2 Ubuntu 24.04 (3.4 GiB RAM, 2.8 GiB avail, kernel 6.6.87); verified `svm` and `sse4_2` CPU flags; verified active `/dev/kvm` hardware acceleration inside WSL2; detected Docker v29.1 and containerd v2.2.1.
  - **12-Component Feasibility Matrix:** Evaluated all 12 target components across 5 standardized feasibility categories, establishing clear boundaries between real execution, independent testing, configuration authoring, and simulation.
  - **Alternative Execution Infrastructure Evaluation:** Evaluated 5 execution pathways (WSL2, local dev cluster, alternative workstation, college servers, temporary final testing window) maintaining the zero-cost mandate.
  - **Three-State Feature Completion Framework:** Formalized `IMPLEMENTED`, `VALIDATED`, and `INFRASTRUCTURE-DEPENDENT` tracking standards to maintain complete scientific integrity.
  - **Comprehensive Development Roadmap (`docs/development-roadmap.md`):** Formulated authoritative 10-milestone execution architecture eliminating artificial subchunks while preserving all dependencies.
  - **Architectural Decision Record (`DECISIONS.md`):** Recorded ADR-011 formally adopting scope preservation, institutional decoupling, and the 3-state evidence framework.
  - **Agent Governance Directives (`AGENTS.md`):** Updated Section 2 with 12 mandatory rules and Section 6 with the 3-state framework.
- [x] Synchronized `docs/infrastructure-readiness-tracker.md`, `docs/deployment-options.md`, `RESEARCH.md`, `ARCHITECTURE.md`, `README.md`, and `PROJECT_STATE.md`.
- [x] **Milestone M1 Deliverables (Development Environment Preparation & Automated Tooling):**
  - Automated toolchain installer (`scripts/setup/install-dev-tools.sh`) installing and cryptographically verifying 12 development tools (`kubectl` v1.36.0, `helm` v3.17.1, `kubeconform` v0.8.0, `yq` v4.54.3, `virtctl` v1.9.0, `yamllint` 1.33.0, `shellcheck` 0.9.0, `shfmt` 3.8.0, `jq` 1.7.1, `fio` 3.36, `git` 2.43.0, `curl` 8.5.0; containerd 2.2.1 and docker 29.1.3 retained).
  - Non-destructive host preflight script (`scripts/setup/01-host-preflight.sh`) auditing CPU flags, HugePages, `/dev/kvm`, storage, network, and toolchain with dual text and JSON reporting in `reports/environment/`.
  - Node prerequisite detection script (`scripts/setup/02-node-prerequisites.sh`) with report-only default mode and safe `--apply` interactive controls.
  - Unified validation runner (`scripts/validate/run-validation.sh`) executing an 8-step verification suite (permissions, ShellCheck, shfmt, yamllint, kubeconform, jq JSON parsing, preflight execution).
  - Repository-wide YAML lint configuration (`.yamllint.yaml`).
  - Development toolchain specification and runbook (`docs/development-toolchain.md`).
  - Generated environment audit reports: `reports/environment/host-preflight-*.txt/.json` and `reports/environment/node-prerequisites-*.txt/.json`.
- [x] **Milestone M2 Deliverables (Kubernetes Cluster Architecture & Multi-Node Provisioning):**
  - Target `kubeadm` initialization configuration (`infrastructure/k8s/kubeadm-init-config.yaml`) using `kubeadm.k8s.io/v1beta4`, Pod CIDR `10.244.0.0/16`, Service CIDR `10.96.0.0/12`, CRI `unix:///run/containerd/containerd.sock`, and `SystemdCgroup` kubelet config (validated `ok` via `kubeadm v1.36.6 config validate`).
  - Target `containerd` 2.3.x LTS schema v3 reference (`infrastructure/k8s/containerd-config-v3.toml`).
  - Calico `v3.33.0` Tigera Operator custom resources (`infrastructure/k8s/calico/installation.yaml`, `infrastructure/k8s/calico/bgp-configuration.yaml`) using `encapsulation: None` (Pure BGP), `nodeAddressAutodetectionV4: kubernetes: NodeInternalIP`, plus extracted official CRD schemas (`infrastructure/k8s/calico/schemas/`) validated via `kubeconform -strict` (3/3 resources + 7/7 operator resources valid).
  - Target server bootstrap scripts (`scripts/setup/03-bootstrap-control-plane.sh`, `scripts/setup/04-join-worker-node.sh`) with WSL2 safety refusal, root/swap/sysctl/CRI checks, and secure token handling (refusal verified in WSL2; live multi-node execution `INFRASTRUCTURE-DEPENDENT`).
  - Local single-node K3s (`v1.36.6+k3s1`, embedded `containerd v2.3.7-k3s1.36`) lifecycle automation (`scripts/setup/dev-cluster-local.sh`) with RAM ($\ge 1500\text{ MiB}$) and disk ($\ge 2\text{ GiB}$) pre-checks.
  - Kubernetes cluster validation automation (`scripts/validate/validate-kubernetes-cluster.sh`) supporting `--report-only` and active scheduling/CoreDNS/Pod-to-Pod probes, archiving `.txt` and `.json` reports in `reports/kubernetes/`.
  - Updated unified validation suite (`scripts/validate/run-validation.sh`) to validate `kubeadm-init-config.yaml` and Calico CRDs (8/8 steps PASS).
  - Authored `docs/kubernetes-architecture.md`, `docs/kubernetes-deployment-guide.md`, and `docs/calico-networking.md`; synchronized `docs/development-roadmap.md`, `ARCHITECTURE.md`, and `README.md`.

### 2.2 Verified Infrastructure Features
- [x] **Local Hardware Capability:** Verified AMD Ryzen 5 7535HS (6C/12T), AMD-V enabled, 8 GB DDR5 RAM (~623 MB free on Windows), 1x 512 GB NVMe (~11.77 GB free on C:), WSL2 Ubuntu 24.04 installed.
- [x] **Local Virtualization Acceleration:** Verified `/dev/kvm` character device (`crw-rw---- 1 root kvm 10, 232`) is present and functional inside WSL2 Ubuntu 24.04.
- [x] **Local Container Runtimes:** Verified pre-installed Docker v29.1.3 and containerd v2.2.1 preserved untouched; K3s isolated embedded `containerd v2.3.7-k3s1.36` operational.
- [x] **Local Single-Node Kubernetes Dev Cluster (`VALIDATED`):** Verified K3s `v1.36.6+k3s1` (`wsl2-dev-node` `Ready`), CoreDNS/metrics-server/local-path-provisioner `Running`, Flannel CNI `PodCIDR: 10.244.0.0/24`, Pod scheduling, DNS lookup, Pod-to-Pod HTTP connectivity, and `stop`/`start` restart persistence (~341 MiB RAM, ~626 MB K3s footprint).
- [x] **Local Workload Boundary:** Formally confirmed that hosting a 4-node cluster with Mayastor SPDK and KubeVirt locally is impossible due to memory, HugePage, and dedicated block device deficits.

### 2.3 Features Awaiting Target Infrastructure & Execution
- [ ] 4-node Kubernetes cluster (1 control plane, 3 worker nodes) via `kubeadm`.
- [ ] HugePages (2 MiB) configuration and NVMe-oF kernel module loading across worker nodes.
- [ ] OpenEBS Mayastor deployment with SPDK `io-engine` daemonset.
- [ ] Mayastor `DiskPool` creation on raw physical NVMe/SSD partitions.
- [ ] Synchronous multi-replica volume provisioning via Mayastor CSI.
- [ ] KubeVirt operator, CRDs, and `virt-handler` deployment with hardware KVM pass-through.
- [ ] Persistent cloud-init Ubuntu virtual machine launch backed by Mayastor PV.
- [ ] KubeVirt live migration over RWX shared storage across worker nodes.
- [ ] Dynamic vCPU hot-plug validation without guest OS restart.
- [ ] Dynamic memory hot-plug validation without guest OS restart.
- [ ] Dynamic secondary volume hot-plug via `virtctl` subresource.
- [ ] Dynamic network interface hot-plug via Multus.
- [ ] Comprehensive FIO benchmark test suite execution (IOPS, throughput, latency p95/p99).
- [ ] Automated disk failure injection, replica degradation, and pool rebuild recovery.
- [ ] Prometheus scraping and Grafana dashboard visualization of storage and VM metrics.

---

## 3. Infrastructure Availability & Constraints

| Resource Tier | Environment Details | Current Operational Status | Constraints & Architectural Impact |
| :--- | :--- | :--- | :--- |
| **Local Workstation** | Windows 11 Home (Build 26300) + WSL2<br/>AMD Ryzen 5 7535HS (6C/12T)<br/>8 GB DDR5 RAM, 1x 512 GB NVMe SSD | **AUDITED & VERIFIED** | **Active development & verification platform.** Operates client tooling, linters, preflight scripts, manifest generation, and micro-VM tests via `/dev/kvm`. Multi-node Mayastor and 4 GiB VMs cannot run locally. |
| **Target Remote Lab Nodes** | Minimum 4 Linux Servers<br/>(1 Control Plane + 3 Workers)<br/>Dedicated raw disks, $\ge$6 physical cores, $\ge$16 GB RAM (32 GB pref) | **QUESTIONNAIRE SUBMITTED** | College laboratory systems unconfirmed. Tracked as an optional resource opportunity for wire-speed NVMe-oF benchmarks and full 3-way replicated Mayastor validation. |
| **Cloud Infrastructure** | Public cloud instances | **PROHIBITED** | Paid cloud services are excluded to keep the project completely cost-free and reproducible on academic lab hardware. |

---

## 4. Known Technical Risks & Mitigation Strategies

1. **Host Memory Starvation on Worker Nodes:**
   - *Risk:* Mayastor SPDK `io-engine` requires pre-allocating 2 GiB HugePages per storage node; QEMU process overhead consumes 0.6–1.2 GiB above guest RAM; live migration requires 4.8–5.7 GiB transient allocation on target. Case 2 (target node already loaded) triggers fatal OOM on 16 GB hosts ($-0.60\text{ to }-5.20\text{ GiB}$ deficit).
   - *Mitigation:* Require 32 GB physical RAM per worker node on target servers for multi-VM live migration (documented in `docs/final-deployment-proposal.md`).
2. **KubeVirt Hardware Virtualization (`/dev/kvm`) Requirement:**
   - *Risk:* If target remote nodes run inside nested virtualization layers without nested virtualization enabled, KubeVirt falls back to slow QEMU emulation (TCG).
   - *Mitigation:* Pre-flight validation scripts (`01-host-preflight.sh`) audit `/dev/kvm` hardware acceleration before cluster deployment proceeds.
3. **Storage Access Mode Mismatch for Live Migration (RWO vs. RWX):**
   - *Risk:* Mayastor natively provisions RWO block volumes, whereas KubeVirt live migration requires RWX shared storage.
   - *Mitigation:* Comparative Dual-Path Strategy (ADR-008 & ADR-010): native Mayastor RWX block volumes as primary innovation target (evaluated across 6 evidence-based failure scenarios), and an NFS gateway over Mayastor RWO as the conservative fallback baseline.
4. **SPDK Core Starvation & Busy-Polling:**
   - *Risk:* SPDK threads run continuous busy-polling loops consuming 100% of assigned CPU cores. On systems with $\le$4 physical cores, OS daemons and KubeVirt VMs experience severe scheduling latency.
   - *Mitigation:* Enforce minimum 6 physical cores per worker node, explicitly reserving 2 cores exclusively for the Mayastor `io-engine`.

---

## 5. Architectural Decision Status Overview

- **ADR-001:** Hybrid local development and remote deployment $\rightarrow$ `PROPOSED`
- **ADR-002:** Three independent storage-capable worker nodes $\rightarrow$ `AMENDED` (Storage replication decoupled from etcd quorum)
- **ADR-003:** OpenEBS Mayastor as the replicated storage engine $\rightarrow$ `AMENDED` (OpenEBS v4.6.x / Mayastor subchart v2.12.2 for native RWX)
- **ADR-004:** NFS-backed RWX storage layer for KubeVirt live migration $\rightarrow$ `AMENDED` (Retained as conservative fallback)
- **ADR-005:** Free college infrastructure as preferred deployment strategy $\rightarrow$ `PROPOSED`
- **ADR-006:** Multiple meaningful Conventional Commits per project chunk $\rightarrow$ `PROPOSED`
- **ADR-007:** Antigravity-assisted, chunk-based development $\rightarrow$ `PROPOSED`
- **ADR-008:** Dual-Tier storage architecture for high-performance block and live migration $\rightarrow$ `AMENDED` (Comparative 3-tier strategy)
- **ADR-009:** Target software stack baseline specification (K8s 1.28 / Ubuntu 22.04) $\rightarrow$ `SUPERSEDED` (Rejected due to EOL)
- **ADR-010:** Supported modern software stack baseline (Candidate B: K8s 1.36.x + containerd 2.3 LTS preferred qualification target vs. Candidate A: K8s 1.35.x comparison baseline; OpenEBS v4.6.x chart mapping) $\rightarrow$ `PROPOSED / AUDITED & RECONCILED`
- **ADR-011:** Project strategy realignment & decoupling from institutional gating $\rightarrow$ `ACCEPTED / ACTIVE`
- **ADR-012:** OpenEBS 4.6.2 / Mayastor v2.12.2 umbrella scoping, `DiskPool v1beta3` schema & CSI parameter enforcement $\rightarrow$ `ACCEPTED (M3)`
- **ADR-013:** KubeVirt `v1.9.1` & CDI `v1.66.1` stack selection, `LiveUpdate` strategy & default NFS RWX migration path $\rightarrow$ `ACCEPTED (Sprint 1)`
- **ADR-014:** Reproducible storage resilience drills & FIO multi-tier comparability protocol $\rightarrow$ `ACCEPTED (Sprint 2)`
- **ADR-015:** Pin `kube-prometheus-stack` `v93.2.0` & explicit exporter metric-gap transparency $\rightarrow$ `ACCEPTED (Sprint 2)`

---

## 6. Recent Actions & Audit Log

- **2026-11-04:** Completed Chunk 0 deliverables. Initialized directory structure, authored core governance documents (`AGENTS.md`, `README.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `RESEARCH.md`, `LEARNING_NOTES.md`, `LICENSE`), and pushed 5 commits to GitHub.
- **2026-11-04:** Completed Chunk 1 Infrastructure Discovery: local WMI/CIM assessment, questionnaire, compatibility matrix, storage architecture analysis, network requirements, deployment options, and final proposal (7 commits pushed).
- **2026-11-05:** Completed Chunk 1.8 Technical Research Corrections: reassessed lifecycles, investigated native RWX block volumes, and validated 20 firewall ports (`c457aac`, `aea2292`, `9c9b187`, `87fb562`).
- **2026-11-05:** Completed Chunk 1.9 Final Lifecycle, Compatibility and Resource Audit: eliminated EOL k8s 1.34 and containerd 1.7; allocated 2 dedicated SPDK busy-polling cores; audited 20 ports; specified write log rebuild and 6-scenario live migration (`5271f31`, `ce716e2`, `7883dcf`, `368e8e8`).
- **2026-11-05:** Completed Chunk 1.10 Final Compatibility and Resource Reconciliation: containerd matrix reconciled; memory calculations and asymmetric migration budgets audited; evidence-based RWX migration safety formulated (`b616ead`, `25cebbe`, `fac476d`, `302b1f8`).
- **2026-11-05:** Completed Chunk 1.11 Final Deployment Baseline and Evidence Closure: Candidate B preferred baseline; OpenEBS v4.6.x verified; MemTotal headroom recalculated; canonical 20-port matrix finalized; single-writer protocol specified (`b361cc6`, `ac03852`, `00ca169`, `525563f`).
- **2026-11-05:** Completed Chunk 2.0 Infrastructure Readiness & Access Planning: refined college infrastructure questionnaire; created infrastructure readiness tracker across 17 items (`7349098`, `ace13f6`, `35cdf71`).
- **2026-11-05:** Implemented Chunk 2.1 Project Strategy Alignment & Development Environment Assessment:
  - Commit 1 (`d2aa1b0`): `docs: create development environment assessment and component feasibility matrix` — Audited local Windows 11 & WSL2 Ubuntu 24.04 environment (verified `/dev/kvm`, 6C/12T AMD CPU, 3.4 GiB WSL RAM); created 12-component feasibility matrix; evaluated 5 execution pathways; formalized 3-state completion framework (`IMPLEMENTED`, `VALIDATED`, `INFRASTRUCTURE-DEPENDENT`).
  - Commit 2 (`c0dba97`): `docs: establish comprehensive development roadmap` — Formulated authoritative 10-milestone execution architecture (`docs/development-roadmap.md`) covering toolchain, cluster setup, Mayastor, KubeVirt, storage integration, live migration, fault injection, FIO benchmarks, observability, and final report.
  - Commit 3 (`1d71f63`): `docs: record adr-011 for strategy realignment and institutional decoupling` — Recorded ADR-011 in `DECISIONS.md`.
  - Commit 4 (`b39029f`): `docs: update governance operating directives for strategy alignment` — Updated `AGENTS.md` with 12 operating rules and 3-state completion standards.
  - Commit 5 (`e66f265`): `docs: synchronize project state and tracking documents for chunk 2.1` — Synchronized `PROJECT_STATE.md`, `README.md`, `ARCHITECTURE.md`, `RESEARCH.md`, `docs/infrastructure-readiness-tracker.md`, and `docs/deployment-options.md`.
- **2026-11-09:** Completed Milestone M1 Development Environment Preparation & Automated Tooling:
  - Installed and verified 12 development tools in WSL2 Ubuntu 24.04: `kubectl` v1.36.0, `helm` v3.17.1, `kubeconform` v0.8.0, `yq` v4.54.3, `virtctl` v1.9.0, `shellcheck` 0.9.0, `yamllint` 1.33.0, `shfmt` 3.8.0, `jq` 1.7.1, `fio` 3.36, `git` 2.43.0, `curl` 8.5.0; containerd 2.2.1 and docker 29.1.3 retained.
  - Implemented reproducible tool installer: `scripts/setup/install-dev-tools.sh`.
  - Implemented non-destructive host preflight script: `scripts/setup/01-host-preflight.sh` (audited CPU, RAM, HugePages, `/dev/kvm`, block devices, networking, toolchain; generated text/JSON reports).
  - Implemented node prerequisite detection script: `scripts/setup/02-node-prerequisites.sh` (report-only default mode; audited 15 node requirements).
  - Implemented unified validation suite: `scripts/validate/run-validation.sh` (8/8 steps pass).
  - Configured repository YAML lint rules: `.yamllint.yaml`.
  - Documented toolchain delivery, verification, and audit reports in `docs/development-toolchain.md`.
  - Updated `docs/development-environment-assessment.md` with active M1 feature completion ledger.
- **2026-11-11:** Completed Milestone M2 Kubernetes Cluster Architecture & Multi-Node Provisioning:
  - Installed standalone verified `kubeadm` v1.36.6 schema validator CLI (static binary, zero kubelet service).
  - Authored `infrastructure/k8s/kubeadm-init-config.yaml` (`kubeadm.k8s.io/v1beta4`, validated `ok`), `infrastructure/k8s/containerd-config-v3.toml`, and `infrastructure/k8s/calico/` (`installation.yaml`, `bgp-configuration.yaml`, extracted v3.33.0 CRD schemas; validated `kubeconform -strict`).
  - Authored target bootstrap scripts (`scripts/setup/03-bootstrap-control-plane.sh`, `scripts/setup/04-join-worker-node.sh`); verified WSL2 refusal protection.
  - Deployed and validated local single-node `k3s v1.36.6+k3s1` (`containerd v2.3.7-k3s1.36`) via `scripts/setup/dev-cluster-local.sh` (~341 MiB RAM, ~626 MB K3s footprint); tested `stop`/`start` persistence while preserving Docker containers (`rakshakgis-*`).
  - Authored and executed `scripts/validate/validate-kubernetes-cluster.sh` (12 PASS, 1 WARN, 0 FAIL, 1 NOT TESTABLE; `--report-only` tested).
  - Authored `docs/kubernetes-architecture.md`, `docs/kubernetes-deployment-guide.md`, and `docs/calico-networking.md`; updated `docs/development-roadmap.md`, `ARCHITECTURE.md`, `README.md`, and `PROJECT_STATE.md`.

---

## 7. Next Authorized Action

Final Completion Sprint — Prompt 2 of 3 (`Storage Resilience, Performance Benchmarking, Observability & Integration Testing`) is complete, committed cleanly on `main` (building on pushed Sprint 1 commit `7c8c98f`), statically validated (`11/11` validation suite, `promtool v3.16.0` config & 10 rules, `44/44` K8s/CRD resources, `6` FIO `--parse-only` profiles, Python `unittest`, 9-stage `run-project-demo.sh`), and safety-verified on WSL2. **STOP AND AWAIT USER APPROVAL FOR PROMPT 3 OF 3.**

---

### Milestone M3 Completion Record (OpenEBS Mayastor Storage Engine & Volume Provisioning — 2026-11-11, Pushed to `origin/main`)
- **Milestone Status:** `🟢 COMPLETED` (`f044b3d`, `777e328`, `587c7c2` — verified pushed on `origin/main` prior to Sprint 1)
- **Version Baseline & Gap Honesty:** Pinned `openebs/openebs` **`4.6.2`** bundling **`mayastor` `2.12.2`** (zero `:latest` image tags; unused LVM/ZFS/rawfile/Loki/Alloy/callhome disabled; internal `localpv-provisioner:4.6.0` retained exclusively for `mayastor-etcd-localpv`). Recorded explicitly that upstream Mayastor `v2.12.2` CI E2E coverage ends at Kubernetes `v1.35.6`, leaving Candidate B (`v1.36.6+`) live execution explicitly classified `INFRASTRUCTURE-DEPENDENT`.
- **Empirical Tier-1/WSL2 Reports:** `reports/storage/mayastor-prerequisites-2026-11-11_11-15-43.{txt,json}` and `reports/storage/mayastor-deployment-validation-2026-11-11_11-16-16.{txt,json}`.

---

### Final Completion Sprint — Prompt 1 of 3 Completion Record (2026-11-11, Pushed to `origin/main`)
- **Sprint Scope Status:** `🟢 COMPLETED` (KubeVirt Deployment, VM Workloads & Persistent Storage Integration, Live Migration, and CPU/Memory/Disk Hot-Plugging)
- **Recorded Git Commits (`origin/main` verified pushed prior to Prompt 2):**
  - `9a13516` — `feat(kubevirt): add KubeVirt v1.9.1, CDI v1.66.1, NFS RWX gateway, VMs, migration and hotplug manifests`
  - `ce40d69` — `feat(validate): add KubeVirt deployment, VM storage, live migration, and hotplug scripts and reports`
  - `7c8c98f` — `docs(sprint1): add KubeVirt, VM storage, migration, and hotplug guides and sync project state`
- **Artifacts Created / Updated:**
  - Offline K8s `v1.36.6` core strict schemas (`infrastructure/k8s/schemas/v1.36.6-standalone-strict/*.json`) + KubeVirt/CDI/Migration schemas (`kubevirt/installation/schemas/{kubevirt.io,migrations.kubevirt.io,cdi.kubevirt.io}/*.json`).
  - KubeVirt `v1.9.1` & CDI `v1.66.1` configs: `kubevirt/installation/{release-metadata.yaml,namespaces.yaml,kubevirt-cr.yaml,cdi-cr.yaml}`.
  - NFS RWX fallback gateway: `storage/nfs/{nfs-server-mayastor.yaml,nfs-storageclass.yaml}` (`csi-driver-nfs v4.9.0`, `docker.io/itsthenetwork/nfs-server-alpine:12` over `mayastor-nvme-r3-ext4` RWO).
  - VM workloads & cloud-init: `kubevirt/virtualmachines/{cloud-init-secret.yaml,vm-ubuntu-rwo-filesystem.yaml,vm-ubuntu-mayastor-rwo-block.yaml,vm-ubuntu-rwx-nfs-migration.yaml,vm-ubuntu-rwx-block-experimental.yaml,vm-cirros-dev-minimal.yaml}`.
  - Live migration & hot-plug specs: `kubevirt/migration/{migration-policy.yaml,live-migration-job.yaml}` and `kubevirt/hotplug/{vm-ubuntu-hotplug-ready.yaml,hotplug-data-volume.yaml}`.
  - Automation & validators: `scripts/setup/{06-deploy-kubevirt.sh,07-deploy-vm-examples.sh}`, `scripts/validate/{validate-kubevirt.sh,validate-vm-storage.sh,validate-live-migration.sh,validate-vm-hotplug.sh}`, `docs/{kubevirt-architecture.md,vm-storage-integration.md,live-migration.md,vm-hotplug.md}`.
  - Archived WSL2/static reports (`reports/kubevirt/`): `kubevirt-validation-2026-11-11_12-07-04.{txt,json}`, `vm-storage-validation-2026-11-11_12-07-07.{txt,json}`, `live-migration-validation-2026-11-11_12-07-08.{txt,json}`, `vm-hotplug-validation-2026-11-11_12-07-10.{txt,json}`.

---

### Final Completion Sprint — Prompt 2 of 3 Completion Record (2026-11-11)
- **Sprint Scope Status:** `🟢 COMPLETED` (Mayastor Storage Resilience, FIO Performance Benchmarking, Prometheus/Grafana Observability, and 9-Stage Integrated Project Demo)
- **Recorded Git Commits (`main`, ahead of `origin/main` pending push):**
  - `eb64164` — `test(resilience,benchmark): add Mayastor resilience drills, FIO benchmark suite, and unit tests`
  - `7176b47` — `feat(monitoring,demo): add kube-prometheus-stack v93.2.0 observability, dashboards, and 9-stage E2E demo`
  - Plus `docs(sprint2)` documentation & state synchronization commit.
- **Artifacts Created / Updated:**
  - **Storage Resilience:** `tests/storage/resilience-scenarios.yaml`, `scripts/validate/validate-storage-resilience.sh`, `scripts/tests/storage/{verify-volume-checksum.sh,observe-rebuild-events.sh,run-resilience-drills.sh}`, `docs/storage-resilience.md`.
  - **FIO Benchmarking:** `benchmarks/fio/{4k-randread.fio,4k-randwrite.fio,4k-randrw-70-30.fio,64k-seqread.fio,64k-seqwrite.fio,1m-bandwidth.fio,matrix-config.yaml}`, `scripts/benchmark/{run-fio-benchmarks.sh,summarize-results.py}`, `tests/benchmarks/test_summarize_results.py`, `docs/performance-benchmarking.md`.
  - **Prometheus & Grafana Observability:** `monitoring/release-metadata.yaml`, `monitoring/prometheus/{namespace.yaml,values.yaml,values-dev-lightweight.yaml,prometheus.yml,servicemonitors.yaml,prometheus-rules.yaml}`, CRD schemas (`monitoring/prometheus/schemas/monitoring.coreos.com/*.json`), `monitoring/grafana/provisioning/{datasources/prometheus.yaml,dashboards/dashboards.yaml}`, `monitoring/grafana/dashboards/{mayastor-storage-performance.json,kubevirt-vm-telemetry.json,cluster-node-resources.json}`, `scripts/setup/08-deploy-monitoring.sh`, `scripts/validate/validate-observability.sh`, `docs/observability.md`.
  - **Integrated Demo & Governance:** `scripts/demo/run-project-demo.sh`, `scripts/validate/validate-project-integration.sh`, updated `scripts/validate/run-validation.sh` (11 steps), `docs/demo-runbook.md`, `.gitattributes`, updated `README.md`, `ARCHITECTURE.md`, `DECISIONS.md` (`ADR-014`, `ADR-015`), `docs/development-roadmap.md`, and `PROJECT_STATE.md`.
  - **Archived Validation Reports:** `reports/storage/storage-resilience-2026-11-11_12-35-48.{txt,json}`, `reports/monitoring/observability-validation-2026-11-11_12-29-40.{txt,json}`, `reports/integration/project-demo-2026-11-11_12-36-44.{txt,json}`, `reports/integration/integration-check-2026-11-11_12-36-23.json`.
- **Three-State Breakdown:**
  - `IMPLEMENTED`: Complete resilience scenarios/drills, FIO benchmark profiles & Python comparability parser, `kube-prometheus-stack v93.2.0` + 3 dashboards + 10 alerts, and 9-stage E2E demo orchestrator.
  - `VALIDATED` (Local/Static & Safety): `validate-project-integration.sh` (`11/11` `run-validation.sh` PASS: 12 tools, 26 scripts ShellCheck/shfmt 0 warnings, 39 YAML files 0 warnings/errors, `kubeconform -strict` 44/44 resources across 26 files, `jq` 36/36 JSONs, 6 FIO `--parse-only`, `promtool v3.16.0` config & 10 rules, Python `unittest` 3/3); all 14 required docs verified; 9-stage `local-validation` demo PASS (`PASS=1, SKIP_INFRA=8, FAIL=0`); SHA-256 local cycle PASS; all 6 Sprint 2 live/destructive WSL2 refusal gates return `exit 1`.
  - `INFRASTRUCTURE-DEPENDENT`: Live Mayastor replica fault drills (`io-engine-restart`, `worker-cordon-drain`), bare-metal NVMe / KubeVirt / NFS FIO benchmark measurements, live Prometheus scraping (`metrics-exporter-io-engine:9502`, KubeVirt `:8443`), Grafana UI visualization, and multi-node live migration execution.
- **Next Authorized Action:** **STOPPED after Final Completion Sprint — Prompt 2 of 3.** Await explicit user review and authorization before starting **Final Completion Sprint — Prompt 3 of 3**.
