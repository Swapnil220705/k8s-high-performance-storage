# Project Progress State & Execution Tracker

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Active Branch:** `main`  
**Current Phase:** Phase 1 — Infrastructure Discovery & Technical Feasibility  
**Current Chunk:** Chunk 1.9 — Final Lifecycle, Compatibility and Resource Audit  
**Chunk 1.9 Status:** 🟢 COMPLETED (Ready for User Review & Approval)  
**Overall Completion:** 3 / 13 Chunks Completed (Foundation, Feasibility, Lifecycle & Resource Audits)  

---

> [!IMPORTANT]
> **Single Source of Truth:**  
> This document tracks the precise, factual progress of the project. No feature is marked as complete or verified until empirical evidence is gathered and recorded in the repository. Arbitrary percentage estimations are strictly disallowed.

---

## 1. Chunk Progress Summary

| Chunk | Title / Focus Area | Status | Target Delivery | Verification Level |
| :---: | :--- | :---: | :---: | :---: |
| **0** | **Project Foundation & Governance** | 🟢 **COMPLETED** | Chunk 0 | Documentation, Git & Structural Verification |
| **1** | **Infrastructure Discovery & Technical Feasibility** | 🟢 **COMPLETED** | Chunk 1 | Local WMI/CIM Audit, Literature & Matrix Verification |
| **1.8**| **Technical Research Corrections** | 🟢 **COMPLETED** | Chunk 1.8 | Upstream Lifecycle Reassessment, Native RWX & Port Audit |
| **1.9**| **Final Lifecycle, Compatibility & Resource Audit** | 🟢 **COMPLETED** | Chunk 1.9 | EOL Elimination (k8s 1.34/containerd 1.7), 2-Core SPDK Busy-Poll, GB/GiB Sizing, 20-Port Scopes, Write Log Rebuild, 6-Scenario RWX Test Suite |
| **2** | Target Infrastructure Preparation & Kubernetes Cluster Bootstrap | ⚪ NOT STARTED | Chunk 2 | Pending User Authorization & Server Allocation |
| **3** | OpenEBS Mayastor Storage Engine Deployment | ⚪ NOT STARTED | Chunk 3 | Pending Authorization |
| **4** | Storage Pools, Replication & Volume Provisioning | ⚪ NOT STARTED | Chunk 4 | Pending Authorization |
| **5** | KubeVirt Virtualization Stack Integration | ⚪ NOT STARTED | Chunk 5 | Pending Authorization |
| **6** | Virtual Machine Live Migration Implementation | ⚪ NOT STARTED | Chunk 6 | Pending Authorization |
| **7** | Dynamic Resource Hot-Plugging (CPU, Mem, Disk, Net) | ⚪ NOT STARTED | Chunk 7 | Pending Authorization |
| **8** | Storage Performance Benchmarking (FIO Matrix) | ⚪ NOT STARTED | Chunk 8 | Pending Authorization |
| **9** | Storage Failure, Fault Injection & Recovery Drills | ⚪ NOT STARTED | Chunk 9 | Pending Authorization |
| **10** | Metrics, Telemetry & Full-Stack Observability | ⚪ NOT STARTED | Chunk 10 | Pending Authorization |
| **11** | Final Project Report, Analysis & Viva Preparation | ⚪ NOT STARTED | Chunk 11 | Pending Authorization |

---

## 2. Feature & Implementation Verification Ledger

### 2.1 Implemented Artifacts (Chunk 0, Chunk 1, Chunk 1.8 & Chunk 1.9)
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
- [x] **Chunk 1.9 Audit: Software Lifecycle Matrix (`docs/compatibility-matrix.md`):**
  - Removed Kubernetes v1.34 as supported fallback (EOL Oct 27, 2026).
  - Established Kubernetes v1.35.x as time-limited primary candidate (EOL Feb 28, 2027); documented qualification gap for v1.36 and v1.37.
  - Removed containerd 1.7.22 (EOL Sept 30, 2026); adopted containerd 2.3 LTS (supported through April 30, 2028), alternative containerd 2.4.
  - Upgraded Calico to v3.33 (officially tested for Kubernetes v1.35–v1.37).
- [x] **Chunk 1.9 Audit: Worker CPU & Memory Engineering (`docs/network-and-virtualization-requirements.md`):**
  - Researched SPDK Polled Mode Driver busy-polling behavior (continuous 100% CPU utilization by design).
  - Allocated mandatory 2 dedicated CPU cores for Mayastor `io-engine`.
  - Recalculated worker CPU budget: minimum 6 physical cores (2 SPDK + 2 OS/system + 2 VM), preferred 8–16 cores; 4 physical cores rejected as comfortable baseline.
  - Differentiated decimal GB ($10^9$ B) vs binary GiB ($2^{30}$ B): 16 GB physical RAM yields $\approx 14.3$ GiB usable, 32 GB physical RAM yields $\approx 29.3$ GiB usable.
  - Itemized full worker memory budget: 2.0 GiB HugePages locked out, 1.0–1.5 GiB heap, 3.5–4.0 GiB OS/daemons, 4.0 GiB guest VM, 0.6–1.2 GiB QEMU overhead, 4.5 GiB transient migration allocation.
  - Audited all 20 firewall ports individually with traffic scopes, source/dest, and official documentation references; clarified Multus operates via local UNIX domain sockets without ports.
- [x] **Chunk 1.9 Audit: Rebuild Semantics & Migration Test Suite (`docs/storage-architecture-analysis.md`):**
  - Clarified volume degradation on 3-node cluster ($N=3$): 1 node failure leaves volume in Degraded state; anti-affinity prevents replacement replica placement.
  - Replaced "in-memory dirty-block bitmap" with documented Nexus write log tracking dirty extents.
  - Stated 10-minute default partial rebuild grace period (`--faulted-child-wait-period=10m`) and 4 triggers for full rebuild.
  - Formulated comprehensive 6-Scenario Live-Migration Test Suite: (1) Clean live migration, (2) Cancellation & retry, (3) Source node crash, (4) Network partition, (5) Target pod eviction recovery, (6) Exclusive write safety audit.
- [x] Synchronized ADR-010, `ARCHITECTURE.md`, `docs/final-deployment-proposal.md`, `docs/deployment-options.md`, and `RESEARCH.md`.

### 2.2 Verified Infrastructure Features
- [x] **Local Hardware Capability:** Verified AMD Ryzen 5 7535HS (6C/12T), AMD-V enabled, 8 GB DDR5 RAM (~750 MB free), 1x 512 GB NVMe (~17 GB free on C:), WSL2 Ubuntu installed.
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
| **Local Workstation** | Windows 11 Home (Build 26300) + WSL2<br/>AMD Ryzen 5 7535HS (6C/12T)<br/>8 GB DDR5 RAM, 1x 512 GB NVMe SSD | **AUDITED & VERIFIED** | **Restricted strictly to development and governance.** Available RAM (< 1 GB free) and disk (~17 GB free) prevent running multi-node clusters, HugePages, or SPDK locally. |
| **Target Remote Lab Nodes** | Minimum 4 Linux Servers<br/>(1 Control Plane + 3 Workers)<br/>Dedicated raw disks, $\ge$6 physical cores, $\ge$16 GB RAM | **QUESTIONNAIRE PREPARED** | College laboratory systems unconfirmed. Specifications, network access, and root permissions pending formal inquiry via `docs/college-infrastructure-questionnaire.md`. |
| **Cloud Infrastructure** | Public cloud instances | **PROHIBITED** | Paid cloud services are excluded to keep the project completely cost-free and reproducible on academic lab hardware. |

---

## 4. Known Technical Risks & Mitigation Strategies

1. **Host Memory Starvation on Worker Nodes:**
   - *Risk:* Mayastor SPDK `io-engine` requires pre-allocating 2 GiB HugePages per storage node; QEMU process overhead consumes 0.6–1.2 GiB above guest RAM; live migration requires 4.5 GiB transient allocation.
   - *Mitigation:* Require minimum 16 GB physical RAM (32 GB preferred) per worker node on target servers (documented in `docs/final-deployment-proposal.md`).
2. **KubeVirt Hardware Virtualization (`/dev/kvm`) Requirement:**
   - *Risk:* If target remote nodes run inside nested virtualization layers without nested virtualization enabled, KubeVirt falls back to slow QEMU emulation (TCG).
   - *Mitigation:* Pre-flight validation scripts must verify `/dev/kvm` hardware acceleration before cluster deployment proceeds.
3. **Storage Access Mode Mismatch for Live Migration (RWO vs. RWX):**
   - *Risk:* Mayastor natively provisions RWO block volumes, whereas KubeVirt live migration requires RWX shared storage.
   - *Mitigation:* Comparative Dual-Path Strategy (ADR-008 & ADR-010): native Mayastor RWX block volumes as primary innovation target (evaluated across 6 failure scenarios), and an NFS gateway over Mayastor RWO as the conservative fallback baseline.
4. **SPDK Core Starvation & Busy-Polling:**
   - *Risk:* SPDK threads run continuous busy-polling loops consuming 100% of assigned CPU cores. On systems with $\le$4 physical cores, OS daemons and KubeVirt VMs experience severe scheduling latency.
   - *Mitigation:* Enforce minimum 6 physical cores per worker node, explicitly reserving 2 cores exclusively for the Mayastor `io-engine`.

---

## 5. Architectural Decision Status Overview

- **ADR-001:** Hybrid local development and remote deployment $\rightarrow$ `PROPOSED`
- **ADR-002:** Three independent storage-capable worker nodes $\rightarrow$ `AMENDED` (Storage replication decoupled from etcd quorum)
- **ADR-003:** OpenEBS Mayastor as the replicated storage engine $\rightarrow$ `AMENDED` (OpenEBS 4.6+ / Mayastor v2.11+ for native RWX)
- **ADR-004:** NFS-backed RWX storage layer for KubeVirt live migration $\rightarrow$ `AMENDED` (Retained as conservative fallback)
- **ADR-005:** Free college infrastructure as preferred deployment strategy $\rightarrow$ `PROPOSED`
- **ADR-006:** Multiple meaningful Conventional Commits per project chunk $\rightarrow$ `PROPOSED`
- **ADR-007:** Antigravity-assisted, chunk-based development $\rightarrow$ `PROPOSED`
- **ADR-008:** Dual-Tier storage architecture for high-performance block and live migration $\rightarrow$ `AMENDED` (Comparative 3-tier strategy)
- **ADR-009:** Target software stack baseline specification (K8s 1.28 / Ubuntu 22.04) $\rightarrow$ `SUPERSEDED` (Rejected due to EOL)
- **ADR-010:** Supported modern software stack baseline (Ubuntu 24.04, K8s 1.35.x time-limited, containerd 2.3 LTS, Calico v3.33, OpenEBS 4.6+, KubeVirt 1.8) $\rightarrow$ `PROPOSED / AUDITED`

---

## 6. Recent Actions & Audit Log

- **2026-11-04:** Completed Chunk 0 deliverables. Initialized directory structure, authored core governance documents (`AGENTS.md`, `README.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `RESEARCH.md`, `LEARNING_NOTES.md`, `LICENSE`), and pushed 5 commits to GitHub.
- **2026-11-04:** Completed Chunk 1 Infrastructure Discovery: local WMI/CIM assessment, questionnaire, compatibility matrix, storage architecture analysis, network requirements, deployment options, and final proposal (7 commits pushed).
- **2026-11-05:** Completed Chunk 1.8 Technical Research Corrections: reassessed lifecycles, investigated native RWX block volumes, and validated 20 firewall ports (`c457aac`, `aea2292`, `9c9b187`, `87fb562`).
- **2026-11-05:** Implemented Chunk 1.9 Final Lifecycle, Compatibility and Resource Audit:
  - Commit 1 (`5271f31`): `docs: update kubernetes, containerd, and calico compatibility` — Eliminated EOL k8s 1.34 and containerd 1.7.22; established k8s 1.35.x (time-limited) and containerd 2.3 LTS; upgraded Calico to v3.33.
  - Commit 2 (`ce716e2`): `docs: audit worker cpu, memory, and port requirements` — Researched SPDK busy-polling; allocated 2 dedicated cores (6-core min); audited GB vs GiB memory breakdown (16 GB min / 32 GB pref); audited 20 ports individually with traffic scopes and official doc links.
  - Commit 3 (`7883dcf`): `docs: specify replica rebuild semantics and rwx migration test plan` — Documented 3-node volume degradation, lack of replacement placement due to anti-affinity, Nexus write log extent tracking (10m grace period), 4 full rebuild triggers, and formulated explicit 6-scenario live migration test suite.
  - Commit 4: `docs: align architecture proposal and decisions with chunk 1.9 audit` — Synchronized `docs/final-deployment-proposal.md`, `docs/deployment-options.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `RESEARCH.md`, and `PROJECT_STATE.md`.

---

## 7. Next Authorized Action

Chunk 1.9 is fully complete and validated. **STOP AND AWAIT USER APPROVAL.**  
Next step upon explicit user authorization:
- **Chunk 2 — Target Infrastructure Preparation & Kubernetes Cluster Bootstrap:**
  - Submit `docs/college-infrastructure-questionnaire.md` to laboratory administration to secure 4 nodes meeting audited specs ($\ge$6 cores, $\ge$16 GB RAM).
  - Author automated Linux host pre-flight verification scripts (`scripts/setup/01-host-preflight.sh`) checking HugePages, `nvme-tcp`, containerd 2.3 LTS, and `/dev/kvm`.
  - Author reproducible `kubeadm` cluster initialization manifests and bootstrap scripts.
  - **Do not proceed to Chunk 2 until user review and authorization are given.**
