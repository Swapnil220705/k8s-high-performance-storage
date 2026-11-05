# Architectural Decision Records (ADRs)

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Repository Branch:** `main`  
**Governance Scope:** Architectural & Engineering Strategy  

---

> [!NOTE]
> **Decision Status Classification:**  
> All decisions in this document represent the architectural foundation formulated during the initial design phase. Every decision is currently marked as **PROPOSED** or **PENDING VALIDATION**. As deployment and benchmarking proceed across subsequent chunks, decisions will be updated to **ACCEPTED**, **SUPERSEDED**, or **REJECTED** based on empirical evidence.

---

## ADR Index

- [ADR-001: Hybrid Local Development and Remote Deployment Architecture](#adr-001-hybrid-local-development-and-remote-deployment-architecture)
- [ADR-002: Three Independent Storage-Capable Worker Nodes](#adr-002-three-independent-storage-capable-worker-nodes)
- [ADR-003: OpenEBS Mayastor as the Distributed Replicated Storage Engine](#adr-003-openebs-mayastor-as-the-distributed-replicated-storage-engine)
- [ADR-004: NFS-Backed RWX Storage Layer for KubeVirt VM Live Migration](#adr-004-nfs-backed-rwx-storage-layer-for-kubevirt-vm-live-migration)
- [ADR-005: Free College Infrastructure as the Primary Deployment Target](#adr-005-free-college-infrastructure-as-the-primary-deployment-target)
- [ADR-006: Multiple Meaningful Conventional Commits per Project Chunk](#adr-006-multiple-meaningful-conventional-commits-per-project-chunk)
- [ADR-007: Antigravity-Assisted Chunk-Based Development Methodology](#adr-007-antigravity-assisted-chunk-based-development-methodology)
- [ADR-008: Dual-Tier Storage Architecture for High-Performance Block and Live Migration](#adr-008-dual-tier-storage-architecture-for-high-performance-block-and-live-migration)
- [ADR-009: Target Software Stack Baseline Specification (SUPERSEDED)](#adr-009-target-software-stack-baseline-specification)
- [ADR-010: Supported Modern Software Stack Baseline (Ubuntu 24.04 LTS, Kubernetes 1.35.x/1.34.x, OpenEBS 4.6.x, KubeVirt 1.8.x)](#adr-010-supported-modern-software-stack-baseline)

---

## ADR-001: Hybrid Local Development and Remote Deployment Architecture

- **Status:** PROPOSED (Pending Target Hardware Confirmation)
- **Date:** 2026-11-04
- **Context:**  
  The developer workstation is a Windows 11 laptop equipped with an AMD Ryzen 5 7535HS (6 cores / 12 threads), 8 GB RAM, and a 512 GB SSD. Deploying a full 4-node Kubernetes cluster with OpenEBS Mayastor (demanding 2 GiB HugePages per storage node), KubeVirt, and concurrent guest virtual machines would rapidly exceed the 8 GB host memory boundary, resulting in severe thrashing or OOM panics.
- **Options Considered:**
  1. *All-in-One Local Cluster:* Run a nested Minikube or KinD cluster entirely inside Windows 11 WSL2.
  2. *Hybrid Workflow:* Use the local machine for repository management, manifest authoring, script linting, and documentation, while targeting external Linux servers for physical deployment and benchmarking.
  3. *Cloud-Only Development:* Develop and run everything on paid cloud virtual machines (AWS, GCP, Azure).
- **Decision:**  
  Adopt Option 2: The Hybrid Model. Local machine acts as the development and governance workstation; external Linux nodes host the distributed runtime.
- **Reasoning:**  
  Preserves local machine responsiveness, prevents memory exhaustion, and matches enterprise DevOps workflows where code is authored locally and deployed to remote target environments via Git.
- **Consequences:**  
  - *Positive:* Safe development environment; zero risk of local laptop lockup; realistic multi-node network latency and failure domain testing.
  - *Negative:* Dependent on network connectivity to remote target nodes; requires automated synchronization scripts.
- **Validation Evidence:**  
  Pending deployment in Chunk 1 and Chunk 2.

---

## ADR-002: Three Independent Storage-Capable Worker Nodes

- **Status:** PROPOSED / AMENDED (Clarified in Chunk 1.8)
- **Date:** 2026-11-04 (Amended 2026-11-05)
- **Context:**  
  Distributed storage engines and KubeVirt live migration require genuine multi-node failure domains. Note that storage data replication (Mayastor) is an entirely independent layer from Kubernetes control-plane consensus (etcd Raft quorum).
- **Options Considered:**
  1. *Single-Node Development Cluster:* Run a single worker node with virtual loopback devices.
  2. *Two-Node Worker Cluster:* Run two worker nodes with 2-way replication.
  3. *Three-Node Storage Worker Cluster + 1 Control Plane:* Run a dedicated control plane with three storage-capable worker nodes.
- **Decision:**  
  Adopt Option 3: Standard 3-worker topology with dedicated block devices on each worker.
- **Reasoning:**  
  A 3-node storage pool allows 3-way synchronous volume replication ($N=3$), tolerating up to 2 sequential storage replica failures while keeping the volume readable/writable. It enables cross-node VM live migration from Node A to Node B while preserving an active third replica on Node C. (Control-plane etcd quorum resides separately on control plane nodes).
- **Consequences:**  
  - *Positive:* Meets production distributed storage standards; enables complete failure drill matrix.
  - *Negative:* Increases target hardware requirement (minimum 4 physical or virtual servers).
- **Validation Evidence:**  
  Pending validation during Chunk 2 and Chunk 4; documented in `docs/storage-architecture-analysis.md`.

---

## ADR-003: OpenEBS Mayastor as the Distributed Replicated Storage Engine

- **Status:** PROPOSED / AMENDED (Updated in Chunk 1.8)
- **Date:** 2026-11-04 (Amended 2026-11-05)
- **Context:**  
  KubeVirt virtual machines running database and high-throughput workloads require sub-millisecond block storage access. Traditional distributed storage engines (e.g., Ceph RBD, Longhorn, OpenEBS cStor) route I/O through the Linux kernel block layer and VFS, introducing context switching and interrupt processing overheads.
- **Options Considered:**
  1. *Longhorn:* Feature-rich and simple, but operates in kernel space via iSCSI/NVMf, yielding moderate latency under high IOPS.
  2. *Rook-Ceph:* Robust and mature, but heavy resource footprint (demanding significant CPU and RAM per OSD) and complex operational surface.
  3. *OpenEBS Mayastor (OpenEBS 4.6.x / Mayastor v2.11+):* Built on SPDK (C/Rust), leverages user-space polling-mode drivers, NVMe-oF (TCP), and introduces native experimental RWX block volume support for KubeVirt live migration.
- **Decision:**  
  Adopt Option 3: OpenEBS Mayastor (targeting OpenEBS v4.6.x / Mayastor v2.11+) as the primary storage engine.
- **Reasoning:**  
  Directly aligns with the project's core problem statement of maximizing NVMe performance in cloud-native virtualization and allows evaluating native RWX block live migration without an intermediate NFS layer.
- **Consequences:**  
  - *Positive:* High IOPS, sub-millisecond latency, lockless user-space architecture, native RWX block capabilities.
  - *Negative:* Requires dedicated CPU cores for SPDK polling threads, pre-allocated 2 MiB HugePages (2 GiB locked out per storage node), and specific kernel modules (`nvme-tcp`).
- **Validation Evidence:**  
  Documented in `docs/storage-architecture-analysis.md`; pending benchmark results in Chunk 8.

---

## ADR-004: NFS-Backed RWX Storage Layer for KubeVirt VM Live Migration

- **Status:** PROPOSED / AMENDED (Retained as Fallback Baseline in Chunk 1.8)
- **Date:** 2026-11-04 (Amended 2026-11-05)
- **Context:**  
  KubeVirt live migration requires shared access during memory streaming. While native Mayastor RWX block volumes are now available (OpenEBS 4.6+), they carry an experimental designation. An NFS gateway backed by a Mayastor RWO volume provides a proven, standards-compliant POSIX fallback.
- **Options Considered:**
  1. *Rely Solely on Experimental Native RWX Block:* High performance, but carries risk of unhandled edge cases during network partitions.
  2. *Rely Solely on NFS Gateway:* Proven and safe, but masks NVMe SPDK performance benefits behind NFS RPC translation.
  3. *Comparative Dual-Path Strategy:* Implement Native Mayastor RWX Block as the primary experimental target and deploy the NFS Gateway as the conservative fallback baseline.
- **Decision:**  
  Adopt Option 3: Retain the NFS-backed shared storage gateway as the comparative baseline and conservative fallback.
- **Reasoning:**  
  Enables measuring the exact performance tax of NFS translation against direct NVMe block I/O, while guaranteeing a stable live-migration demo if native RWX exhibits failure drill anomalies.
- **Consequences:**  
  - *Positive:* Safe fallback; enables rigorous scientific comparison of RWO vs Native RWX Block vs NFS RWX.
  - *Negative:* NFS server pod represents a temporary single point of failure (SPOF) if its host node crashes.
- **Validation Evidence:**  
  Documented in `docs/storage-architecture-analysis.md`; to be tested in Chunks 6 and 8.

---

## ADR-005: Free College Infrastructure as the Primary Deployment Target

- **Status:** PROPOSED (Pending Department Coordination)
- **Date:** 2026-11-04
- **Context:**  
  Cloud infrastructure providers (AWS, Azure, GCP) incur high recurring costs for multi-node clusters with dedicated NVMe storage and high-spec VMs. The project operates under the academic Zoho SETU program with a constraint to avoid paid cloud services.
- **Options Considered:**
  1. *Public Cloud Free Tiers:* Severely constrained (e.g., AWS t2.micro / t4g.small) and cannot support 4-node Kubernetes with Mayastor and KubeVirt.
  2. *College Laboratory Servers:* Dedicated bare-metal or hypervisor-hosted Linux systems available within the college institution.
  3. *Local Virtualization:* Limited by 8 GB RAM laptop.
- **Decision:**  
  Adopt Option 2: Prioritize college laboratory physical or hypervisor infrastructure as the deployment target.
- **Reasoning:**  
  Guarantees zero financial overhead, allows direct access to raw disk devices, and offers realistic systems engineering exposure.
- **Consequences:**  
  - *Positive:* Free, sustainable, zero vendor lock-in.
  - *Negative:* Requires negotiation for administrator/root privileges, static IP assignments, and physical access.
- **Validation Evidence:**  
  Pending institutional resource confirmation in Chunk 1.

---

## ADR-006: Multiple Meaningful Conventional Commits per Project Chunk

- **Status:** PROPOSED (Enforced in Chunk 0)
- **Date:** 2026-11-04
- **Context:**  
  Infrastructure engineering projects frequently fail auditability when large batches of heterogeneous changes are committed as single monolithic commits.
- **Options Considered:**
  1. *Single Monolithic Commit per Chunk:* Commit everything at the end of a chunk.
  2. *Atomic Conventional Commits:* Group logical units of work (e.g., directory scaffold, architecture docs, governance policies) into separate, reviewable commits using Conventional Commits.
- **Decision:**  
  Adopt Option 2: Enforce multiple meaningful, atomic Conventional Commits for each chunk.
- **Reasoning:**  
  Ensures clear Git bisectability, precise peer review, and transparent changelogs.
- **Consequences:**  
  - *Positive:* High audit quality, professional engineering standards.
  - *Negative:* Requires disciplined staging and review before every commit.
- **Validation Evidence:**  
  Demonstrated in Chunk 0 repository commit history.

---

## ADR-007: Antigravity-Assisted Chunk-Based Development Methodology

- **Status:** PROPOSED (Enforced in Chunk 0)
- **Date:** 2026-11-04
- **Context:**  
  AI-assisted software development on complex systems infrastructure can easily lead to hallucinations, premature claims of completion, and out-of-order execution if not strictly constrained.
- **Options Considered:**
  1. *End-to-End Autonomous Generation:* Allow AI to generate all 11 chunks simultaneously.
  2. *Strict Chunk-Based Incremental Development:* Work strictly within the current authorized chunk, stop at chunk boundaries, and require explicit user validation before advancing.
- **Decision:**  
  Adopt Option 2: Strict chunk-based incremental development.
- **Reasoning:**  
  Guarantees that no synthetic claims are made, code quality is maintained, and the student retains complete comprehension of every step.
- **Consequences:**  
  - *Positive:* 100% technical accuracy, full alignment with user oversight.
  - *Negative:* Requires interactive review turns between chunks.
- **Validation Evidence:**  
  Enforced via `AGENTS.md` and verified in Chunk 0.


---

## ADR-008: Dual-Tier Storage Architecture for High-Performance Block and Live Migration

- **Status:** PROPOSED / AMENDED (Updated in Chunk 1.8)
- **Date:** 2026-11-04 (Amended 2026-11-05)
- **Context:**  
  The project requires evaluating both maximum NVMe throughput (benchmarking) and virtual machine live migration. With the discovery of native Mayastor RWX block volume support in OpenEBS 4.6+, the live-migration tier can now be evaluated via direct block multi-attach as well as via the NFS gateway.
- **Options Considered:**
  1. *Direct RWO Block Only:* High performance, but live migration disabled.
  2. *NFS Gateway Only:* Live migration enabled, but lower IOPS.
  3. *Three-Tier Comparative Strategy:*
     - Tier 1: Direct Mayastor RWO Block (Control Group: maximum NVMe performance).
     - Tier 2: Native Mayastor RWX Block (Experimental Primary: live migration over raw NVMe).
     - Tier 3: NFS-Backed RWX Filesystem (Conservative Fallback: live migration over NFS).
- **Decision:**  
  Adopt Option 3: Three-Tier Comparative Strategy.
- **Reasoning:**  
  Provides the richest possible scientific and engineering comparison for the student project evaluation.
- **Consequences:**  
  - *Positive:* Delivers comprehensive benchmarking data across all three cloud-native storage patterns.
  - *Negative:* Requires managing test PVCs across both block and filesystem modes.
- **Validation Evidence:**  
  Detailed in `docs/storage-architecture-analysis.md`.

---

## ADR-009: Target Software Stack Baseline Specification (SUPERSEDED)

- **Status:** SUPERSEDED BY ADR-010 (Rejected in Chunk 1.8 Reassessment)
- **Date:** 2026-11-04 (Superseded 2026-11-05)
- **Context:**  
  The initial Chunk 1 proposal selected Kubernetes v1.28.8 on Ubuntu 22.04 LTS with Mayastor v2.5.0.
- **Reason for Supersession:**  
  In the current operational timeframe (November 2026), **Kubernetes 1.28 reached official End-of-Life on October 22, 2024**, and Kubernetes 1.29 is also EOL. Deploying EOL releases violates project standards by introducing unmaintained dependencies and security vulnerabilities.
- **Superseded By:**  
  [ADR-010: Supported Modern Software Stack Baseline](#adr-010-supported-modern-software-stack-baseline).

---

## ADR-010: Supported Modern Software Stack Baseline

- **Status:** PROPOSED / AUDITED & RECONCILED (Chunk 1.11 Final Baseline & Evidence Closure)
- **Date:** 2026-11-05
- **Context:**  
  The project requires a currently supported, technically defensible software stack in late 2026. The intersection between Kubernetes supported lifecycle, KubeVirt compatibility, OpenEBS Mayastor release testing, container runtimes, and Linux kernel drivers must be established without relying on EOL software or unvalidated bleeding-edge releases. Upstream containerd's official Kubernetes matrix recommends containerd 2.2 for K8s 1.35 and containerd 2.3 for K8s 1.36+. Importantly, containerd 2.2 reached upstream EOL on November 6, 2026. Kubernetes 1.37 is excluded due to lack of KubeVirt/Mayastor qualification. Published OpenEBS umbrella chart mappings must also be verified against official release artifacts.
- **Options Considered:**
  1. *Candidate B (Preferred Experimental Qualification Target):*
     - Kubernetes: v1.36.x (Active support through late June 2027).
     - Container Runtime: `containerd` 2.3.x LTS (supported through April 30, 2028; officially recommended for K8s 1.36+).
     - Virtualization: KubeVirt v1.9.x (built for K8s 1.36) + CDI v1.61.x.
     - CNI: Calico v3.33 (officially tested for K8s 1.35–1.37).
     - Storage Engine: OpenEBS v4.6.x (subchart Mayastor v2.12.2, `io-engine:v2.12.2`; qualification gap: untested on K8s 1.36, to be experimentally evaluated).
  2. *Candidate A (Storage-Tested Comparison Baseline Only):*
     - Kubernetes: v1.35.x (Active support through February 28, 2027; verified by Mayastor v2.12.2 CI E2E on v1.35.6).
     - Container Runtime: `containerd` 2.2.x (matches containerd matrix for 1.35, but reached upstream EOL on November 6, 2026; unviable for new production deployments).
     - Storage Engine: OpenEBS v4.6.x (Mayastor subchart v2.12.2).
     - Virtualization: KubeVirt v1.8.x / v1.9.x + CDI v1.61.x.
     - CNI: Calico v3.33.
  3. *Candidate C (Kubernetes 1.37.x + containerd 2.4.x):* Excluded; KubeVirt 1.9 and Mayastor 2.12.2 have no documented qualification on K8s 1.37.
  4. *EOL Releases (Kubernetes 1.28 / 1.29 / 1.34, containerd 1.7.x):* Deprecated and unmaintained upstream; rejected.
- **Decision:**  
  Establish **Candidate B as the preferred experimental qualification target** for deployment. Candidate A is retained strictly as an upstream storage-tested comparison baseline. Published OpenEBS chart mapping is verified as **OpenEBS umbrella chart v4.6.x** (bundling Mayastor subchart v2.12.2, `io-engine:v2.12.2`), formally correcting previous unreleased "v4.7.0" references.
- **Reasoning:**  
  Because containerd 2.2 reached upstream EOL on November 6, 2026, Candidate A cannot be recommended as a new deployment target. containerd 2.3 LTS is explicitly recommended by containerd maintainers for Kubernetes 1.36+, and KubeVirt 1.9 is compiled for Kubernetes 1.36. Candidate B offers healthy lifecycle alignment through mid-2027/2028. The only qualification gap is Mayastor 2.12.2 CI testing on Kubernetes 1.36 (documented up to 1.35.6), which will be transparently evaluated and tested during Chunk 2 deployment rather than masked with false claims.
- **Consequences:**  
  - *Positive:* 100% compliant with zero-EOL governance; aligns with upstream containerd and KubeVirt support lifecycles; establishes clear experimental qualification objectives.
  - *Negative:* Mayastor CRI/CSI interaction on Kubernetes 1.36 requires empirical verification in Chunk 2 pre-flight.
- **Validation Evidence:**  
  Documented in `docs/compatibility-matrix.md`, `docs/network-and-virtualization-requirements.md`, `docs/storage-architecture-analysis.md`, and `docs/final-deployment-proposal.md`.

---

## ADR-011: Project Strategy Realignment & Decoupling from Institutional Gating

- **Status:** ACCEPTED / ACTIVE
- **Date:** 2026-11-05 (Chunk 2.1 Strategy Realignment)
- **Context:**  
  Previously, college laboratory hardware allocation and institutional administrative permissions were treated as mandatory blocking gates before proceeding beyond Chunk 2.0. However, in an academic systems engineering project under the Zoho SETU program, project progress must not stall due to institutional delays or lab scheduling constraints. The project must demonstrate substantial engineering understanding, implementation capability, experimentation, and documentation without compromising its original technical ambition or inventing fabricated results.
- **Options Considered:**
  1. *Option A (Halt Pipeline on Institutional Gate):* Stop all forward progress until college administration signs off and provisions physical servers. (Rejected: causes indefinite stalls and blocks engineering development).
  2. *Option B (Downscale Technical Architecture to Fit Laptop):* Replace multi-node Mayastor, SPDK, and KubeVirt with a trivial single-node container deployment. (Rejected: violates SETU project problem statement and destroys technical rigor).
  3. *Option C (Preserve Full Scope, Decouple Gating, Adopt 3-State Evidence Framework):* Maintain the complete 4-node Mayastor and KubeVirt target architecture. Reclassify college infrastructure allocation as an optional resource opportunity. Develop and test all manifests, automation scripts, and test harnesses locally (leveraging verified `/dev/kvm` in WSL2), tracking features as `IMPLEMENTED`, `VALIDATED`, or `INFRASTRUCTURE-DEPENDENT`. (Selected).
- **Decision:**  
  Adopt Option C:
  1. The complete original technical scope (4-node K8s, OpenEBS Mayastor SPDK, NVMe-oF, KubeVirt, dual-path live migration, hot-plugging, fault drills, FIO benchmarks, and observability) remains 100% intact.
  2. Institutional infrastructure allocation is decoupled from development gating.
  3. Every feature is tracked under the 3-state framework (`IMPLEMENTED`, `VALIDATED`, `INFRASTRUCTURE-DEPENDENT`). A manifest or script is an artifact, never proof of validation.
  4. Local WSL2 Ubuntu 24.04 (with confirmed `/dev/kvm`) is utilized for local development, linting, toolchain automation, and lightweight single-node validation.
- **Reasoning:**  
  Ensures continuous engineering progress, reproducible automation authoring, and transparent scientific reporting. The project is staged so that when physical hardware or a dedicated lab testing window is accessed, the automated pipeline can be executed in a turn-key manner.
- **Consequences:**  
  - *Positive:* Immediate forward momentum; complete production-grade manifests, Helm values, and test harnesses are authored and version-controlled; eliminates project stalls.
  - *Negative:* Full-scale bare-metal NVMe benchmarks and multi-node live migration remain marked `INFRASTRUCTURE-DEPENDENT` until remote cluster execution occurs.
- **Validation Evidence:**  
  Documented in `docs/development-environment-assessment.md` and `docs/development-roadmap.md`.
