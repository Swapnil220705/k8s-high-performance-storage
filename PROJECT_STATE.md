# Project Progress State & Execution Tracker

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Active Branch:** `main`  
**Current Phase:** Phase 1 — Project Foundation & Governance  
**Current Chunk:** Chunk 0 — Project Foundation & Governance  
**Chunk 0 Status:** IN PROGRESS  
**Overall Completion:** 0 / 12 Chunks Completed  

---

> [!IMPORTANT]
> **Single Source of Truth:**  
> This document tracks the precise, factual progress of the project. No feature is marked as complete or verified until empirical evidence is gathered and recorded in the repository. Arbitrary percentage estimations are strictly disallowed.

---

## 1. Chunk Progress Summary

| Chunk | Title / Focus Area | Status | Target Delivery | Verification Level |
| :---: | :--- | :---: | :---: | :---: |
| **0** | **Project Foundation & Governance** | 🟡 **IN PROGRESS** | Current Chunk | Documentation & Git Verification |
| **1** | Target Infrastructure & Linux Host Preparation | ⚪ NOT STARTED | Chunk 1 | Pending Authorization |
| **2** | Kubernetes Multi-Node Cluster Deployment | ⚪ NOT STARTED | Chunk 2 | Pending Authorization |
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

### 2.1 Implemented Artifacts (Chunk 0)
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

### 2.2 Verified Infrastructure Features
*No infrastructure features have been verified yet. Deployment has not commenced.*

### 2.3 Features Awaiting Implementation and Verification
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
| **Local Workstation** | Windows 11 + WSL2 (Ubuntu)<br/>AMD Ryzen 5 7535HS (6C/12T)<br/>8 GB DDR5 RAM, 512 GB NVMe | **ONLINE / OPERATIONAL** | Used strictly for manifest development, script authoring, documentation, and static linting. Not suitable for multi-node cluster hosting due to 8 GB RAM limitation. |
| **Target Remote Lab Nodes** | Minimum 4 Linux Servers<br/>(1 Control Plane + 3 Workers)<br/>Dedicated raw disks, $\ge$16 GB RAM | **PENDING CONFIRMATION** | College laboratory systems unconfirmed. Hardware specifications, network access, and root permissions pending confirmation. |
| **Cloud Infrastructure** | Public cloud instances | **PROHIBITED** | Paid cloud services are excluded to keep the project completely cost-free and reproducible on academic lab hardware. |

---

## 4. Known Technical Risks & Mitigation Strategies

1. **Host Memory Starvation on Worker Nodes:**
   - *Risk:* Running Kubernetes node components, `containerd`, Mayastor SPDK `io-engine` (with 2 GiB pre-allocated HugePages), and KubeVirt guest VMs on memory-constrained nodes may cause Out-Of-Memory (OOM) kills.
   - *Mitigation:* Require minimum 16 GB RAM per worker node on target servers; configure explicit cgroup resource limits and Kubelet eviction thresholds.
2. **KubeVirt Hardware Virtualization (`/dev/kvm`) Requirement:**
   - *Risk:* If target remote nodes run inside nested virtualization layers where Intel VT-x or AMD-V is disabled, KubeVirt will fall back to slow QEMU emulation.
   - *Mitigation:* Pre-flight validation script must assert `kvm-ok` before cluster deployment proceeds.
3. **Storage Access Mode Mismatch for Live Migration (RWO vs. RWX):**
   - *Risk:* Mayastor provides block volumes in `ReadWriteOnce` (RWO) mode. KubeVirt live migration natively demands `ReadWriteMany` (RWX) so both source and destination pods can access the disk simultaneously.
   - *Mitigation:* Implement and test an NFS-backed shared storage gateway layer (or explore experimental dual-attach block mechanisms) specifically for live-migratable VMs.
4. **Network Latency & Rebuilding Overhead:**
   - *Risk:* High latency or packet drop on the storage network will degrade synchronous dual-write acknowledgments, reducing overall VM write IOPS.
   - *Mitigation:* Configure dedicated NICs or VLANs for storage traffic; enable MTU 9000 (Jumbo Frames); benchmark network RTT before deploying Mayastor.

---

## 5. Architectural Decision Status Overview

- **ADR-001:** Hybrid local development and remote deployment $\rightarrow$ `PROPOSED`
- **ADR-002:** Three independent storage-capable worker nodes $\rightarrow$ `PROPOSED`
- **ADR-003:** OpenEBS Mayastor as the replicated storage engine $\rightarrow$ `PROPOSED`
- **ADR-004:** NFS-backed RWX storage proposal for KubeVirt live migration $\rightarrow$ `PROPOSED`
- **ADR-005:** Free college infrastructure as preferred deployment strategy $\rightarrow$ `PROPOSED`
- **ADR-006:** Multiple meaningful Conventional Commits per project chunk $\rightarrow$ `PROPOSED`
- **ADR-007:** Antigravity-assisted, chunk-based development $\rightarrow$ `PROPOSED`

---

## 6. Recent Actions & Audit Log

- **2026-11-04:** Initial repository audit completed. Git environment validated on branch `main` with remote configured to `https://github.com/Swapnil220705/k8s-high-performance-storage`.
- **2026-11-04:** Created 31 empty directory trees with `.gitkeep` and authored multi-tier `.gitignore`. Committed as `chore: establish project directory structure` (`579181f`).
- **2026-11-04:** Authored comprehensive project landing page `README.md` and detailed proposed target architecture `ARCHITECTURE.md`. Committed as `docs: add project overview and proposed architecture` (`7fb7ec9`).
- **2026-11-04:** Authored governance manual `AGENTS.md`, state tracker `PROJECT_STATE.md`, and architectural decision register `DECISIONS.md`.

---

## 7. Next Authorized Action

Complete Chunk 0 governance deliverables:
1. Commit `AGENTS.md`, `PROJECT_STATE.md`, and `DECISIONS.md`.
2. Author technical research tracker (`RESEARCH.md`) and student learning notes (`LEARNING_NOTES.md`).
3. Add MIT license (`LICENSE`).
4. Perform comprehensive validation checklist.
5. Present Chunk 0 Completion Report and await user review.
