# Project Progress State & Execution Tracker

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Active Branch:** `main`  
**Current Phase:** Phase 2 — Target Infrastructure Preparation & Kubernetes Cluster Bootstrap  
**Current Chunk:** Chunk 2.0 — Infrastructure Readiness & Access Planning  
**Chunk 2.0 Status:** 🟢 COMPLETED (Readiness Assessment: NOT READY — Awaiting Lab Allocation & Permissions)  
**Overall Completion:** 6 / 15 Milestones Completed (Foundation, Feasibility, Lifecycle & Reconciliation Audits, Baseline Closure, Infrastructure Readiness Planning)  

---

> [!IMPORTANT]
> **Single Source of Truth:**  
> This document tracks the precise, factual progress of the project. No feature is marked as complete or verified until empirical evidence is gathered and recorded in the repository. Arbitrary percentage estimations are strictly disallowed.

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
| **2.1**| Host Pre-flight Verification & Linux Environment Setup | ⚪ NOT STARTED | Chunk 2.1 | Awaiting College Hardware Allocation & Administrative Sudo Grant |
| **2.2**| Kubernetes Cluster Bootstrap via kubeadm | ⚪ NOT STARTED | Chunk 2.2 | Awaiting Host Pre-flight Completion & Network Setup |
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
- [x] Synchronized `docs/infrastructure-readiness-tracker.md`, `docs/college-infrastructure-questionnaire.md`, and `PROJECT_STATE.md`.

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
| **Target Remote Lab Nodes** | Minimum 4 Linux Servers<br/>(1 Control Plane + 3 Workers)<br/>Dedicated raw disks, $\ge$6 physical cores, $\ge$16 GB RAM (32 GB pref) | **QUESTIONNAIRE PREPARED** | College laboratory systems unconfirmed. Specifications, network access, and root permissions pending formal inquiry via `docs/college-infrastructure-questionnaire.md`. |
| **Cloud Infrastructure** | Public cloud instances | **PROHIBITED** | Paid cloud services are excluded to keep the project completely cost-free and reproducible on academic lab hardware. |

---

## 4. Known Technical Risks & Mitigation Strategies

1. **Host Memory Starvation on Worker Nodes:**
   - *Risk:* Mayastor SPDK `io-engine` requires pre-allocating 2 GiB HugePages per storage node; QEMU process overhead consumes 0.6–1.2 GiB above guest RAM; live migration requires 4.8–5.7 GiB transient allocation on target. Case 2 (target node already loaded) triggers fatal OOM on 16 GB hosts ($-0.60\text{ to }-5.20\text{ GiB}$ deficit).
   - *Mitigation:* Require 32 GB physical RAM per worker node on target servers for multi-VM live migration (documented in `docs/final-deployment-proposal.md`).
2. **KubeVirt Hardware Virtualization (`/dev/kvm`) Requirement:**
   - *Risk:* If target remote nodes run inside nested virtualization layers without nested virtualization enabled, KubeVirt falls back to slow QEMU emulation (TCG).
   - *Mitigation:* Pre-flight validation scripts must verify `/dev/kvm` hardware acceleration before cluster deployment proceeds.
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

---

## 6. Recent Actions & Audit Log

- **2026-11-04:** Completed Chunk 0 deliverables. Initialized directory structure, authored core governance documents (`AGENTS.md`, `README.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `RESEARCH.md`, `LEARNING_NOTES.md`, `LICENSE`), and pushed 5 commits to GitHub.
- **2026-11-04:** Completed Chunk 1 Infrastructure Discovery: local WMI/CIM assessment, questionnaire, compatibility matrix, storage architecture analysis, network requirements, deployment options, and final proposal (7 commits pushed).
- **2026-11-05:** Completed Chunk 1.8 Technical Research Corrections: reassessed lifecycles, investigated native RWX block volumes, and validated 20 firewall ports (`c457aac`, `aea2292`, `9c9b187`, `87fb562`).
- **2026-11-05:** Completed Chunk 1.9 Final Lifecycle, Compatibility and Resource Audit: eliminated EOL k8s 1.34 and containerd 1.7; allocated 2 dedicated SPDK busy-polling cores; audited 20 ports; specified write log rebuild and 6-scenario live migration (`5271f31`, `ce716e2`, `7883dcf`, `368e8e8`).
- **2026-11-05:** Completed Chunk 1.10 Final Compatibility and Resource Reconciliation: containerd matrix reconciled; memory calculations and asymmetric migration budgets audited; evidence-based RWX migration safety formulated (`b616ead`, `25cebbe`, `fac476d`, `302b1f8`).
- **2026-11-05:** Implemented Chunk 1.11 Final Deployment Baseline and Evidence Closure:
  - Commit 1 (`b361cc6`): `docs: establish candidate b as preferred baseline and verify openebs chart mapping` — Established Candidate B as preferred experimental qualification baseline, Candidate A as comparison baseline; verified published umbrella chart `openebs` v4.6.x (Mayastor subchart v2.12.2); excluded K8s 1.37.
  - Commit 2 (`ac03852`): `docs: update canonical port matrix and calculate memtotal headroom` — Recalculated memory headroom from usable `MemTotal` (14.40–14.70 GiB on 16 GB, 29.30–29.60 GiB on 32 GB); demonstrated loaded-destination Case 2 fatal deficit ($-0.60\text{ to }-5.20\text{ GiB}$); built canonical 20-port matrix.
  - Commit 3 (`00ca169`): `docs: specify migration single-writer protocol and rebuild configuration evidence` — Formulated single-writer protocol with 512-byte record layout, sequence numbers, writer IDs/epochs, CRC32C, QMP events, and clock drift bounds; verified `--faulted-child-wait-period` (10m default) and clarified node unreachable governance.
  - Commit 4 (`525563f`): `docs: finalize deployment proposal and synchronize project state for chunk 1.11` — Synchronized `docs/final-deployment-proposal.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `README.md`, `RESEARCH.md`, and `PROJECT_STATE.md`.
- **2026-11-05:** Implemented Chunk 2.0 Infrastructure Readiness & Access Planning:
  - Commit 1 (`7349098`): `docs: refine college infrastructure questionnaire` — Enhanced inquiry document into a professional, concise allocation request covering node topology, secondary raw block devices, KVM hardware acceleration, HugePages, static networking, and administrative permissions.
  - Commit 2 (`ace13f6`): `docs: create infrastructure readiness tracker and access planning` — Created authoritative readiness tracker (`docs/infrastructure-readiness-tracker.md`) across 17 technical items using strict governance statuses (`UNKNOWN`, `REQUESTED`, `CONFIRMED`, `UNAVAILABLE`, `BLOCKED`); defined hardware allocation ledger, administrative access matrix, network readiness, institutional operational constraints, fallback hierarchy, and objective readiness assessment (`NOT READY`).
  - Commit 3: `docs: update project state and readiness tracker synchronization` — Synchronized `PROJECT_STATE.md` and repository status.

---

## 7. Next Authorized Action

Chunk 2.0 is fully complete and validated. **STOP AND AWAIT USER APPROVAL.**  
Current Readiness State: **`NOT READY`** (Awaiting formal laboratory machine allocation and administrative credentials).

Next steps upon explicit user authorization and laboratory response:
1. Deliver `docs/college-infrastructure-questionnaire.md` to Department Laboratory Administration.
2. Upon return of completed questionnaire and credential issuance:
   - Record assigned hostnames, CPU models, RAM sizes, and disk paths in `docs/infrastructure-readiness-tracker.md`.
   - Update readiness status to `CONDITIONALLY READY` or `READY FOR HOST PREFLIGHT`.
3. Proceed to **Chunk 2.1 — Host Pre-flight Verification & Linux Environment Setup**:
   - Author non-destructive inspection scripts (`scripts/setup/01-host-preflight.sh`) to verify `/dev/kvm`, HugePages, and `nvme-tcp`.
   - Author prerequisite configuration scripts (`scripts/setup/02-node-prerequisites.sh`).
4. **DO NOT start host preflight scripts or cluster bootstrap until college hardware is allocated and user authorization is granted.**
