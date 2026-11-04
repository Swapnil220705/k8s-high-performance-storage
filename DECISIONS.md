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
- [ADR-009: Target Software Stack Baseline Specification](#adr-009-target-software-stack-baseline-specification)

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

- **Status:** PROPOSED (Pending Target Hardware Confirmation)
- **Date:** 2026-11-04
- **Context:**  
  Distributed storage engines and KubeVirt live migration require genuine multi-node failure domains to validate quorum, synchronous replication, and cross-node VM live migration.
- **Options Considered:**
  1. *Single-Node Development Cluster:* Run a single worker node with virtual loopback devices.
  2. *Two-Node Worker Cluster:* Run two worker nodes with 2-way replication.
  3. *Three-Node Storage Worker Cluster + 1 Control Plane:* Run a dedicated control plane with three storage-capable worker nodes.
- **Decision:**  
  Adopt Option 3: Standard 3-worker topology with dedicated block devices on each worker.
- **Reasoning:**  
  A 3-node storage pool allows true 3-way synchronous replication ($N=3$), provides a tie-breaking quorum during network partitions, and enables live migration from Node A to Node B while maintaining an active third replica on Node C.
- **Consequences:**  
  - *Positive:* Meets production distributed systems standards; enables complete failure drill matrix.
  - *Negative:* Increases target hardware requirement (minimum 4 physical or virtual servers).
- **Validation Evidence:**  
  Pending validation during Chunk 2 and Chunk 4.

---

## ADR-003: OpenEBS Mayastor as the Distributed Replicated Storage Engine

- **Status:** PROPOSED (Pending Deployment & Benchmarking)
- **Date:** 2026-11-04
- **Context:**  
  KubeVirt virtual machines running database and high-throughput workloads require sub-millisecond block storage access. Traditional distributed storage engines (e.g., Ceph RBD, Longhorn, OpenEBS cStor) route I/O through the Linux kernel block layer and VFS, introducing context switching and interrupt processing overheads.
- **Options Considered:**
  1. *Longhorn:* Feature-rich and simple, but operates in kernel space via iSCSI/NVMf, yielding moderate latency under high IOPS.
  2. *Rook-Ceph:* Robust and mature, but heavy resource footprint (demanding significant CPU and RAM per OSD) and complex operational surface.
  3. *OpenEBS Mayastor:* Built on SPDK (C/Rust), leverages user-space polling-mode drivers and NVMe-oF (TCP), delivering near-bare-metal I/O performance.
- **Decision:**  
  Adopt Option 3: OpenEBS Mayastor as the primary high-performance block storage engine.
- **Reasoning:**  
  Directly aligns with the project's core problem statement of maximizing NVMe performance in cloud-native virtualization.
- **Consequences:**  
  - *Positive:* High IOPS, sub-millisecond latency, lockless user-space architecture.
  - *Negative:* Requires dedicated CPU cores for SPDK polling threads, pre-allocated 2 MiB HugePages, and specific kernel modules (`nvme-tcp`).
- **Validation Evidence:**  
  Pending benchmark results in Chunk 8.

---

## ADR-004: NFS-Backed RWX Storage Layer for KubeVirt VM Live Migration

- **Status:** PROPOSED (Pending Empirical Feasibility Study)
- **Date:** 2026-11-04
- **Context:**  
  KubeVirt live migration requires persistent volumes to be mounted simultaneously on both source and destination `virt-launcher` pods during memory streaming, requiring `ReadWriteMany` (RWX) access mode. OpenEBS Mayastor natively provisions block volumes as `ReadWriteOnce` (RWO) NVMe targets.
- **Options Considered:**
  1. *Direct Mayastor RWO with Storage Migration:* Migrate both VM memory and disk blocks during migration. (Extremely slow and disruptive).
  2. *NFS Gateway over Mayastor RWO:* Deploy an NFS server instance backed by a Mayastor RWO volume, exporting an RWX filesystem to KubeVirt VMs.
  3. *Experimental Dual-Initiator Mayastor Nexus:* Attempt multi-attach at the NVMe-oF layer.
- **Decision:**  
  Adopt Option 2: Deploy an NFS-backed shared storage gateway layer backed by Mayastor high-performance block storage for live-migration workloads, while comparing its performance against raw Mayastor RWO block volumes.
- **Reasoning:**  
  Provides a stable, standards-compliant RWX filesystem required by KubeVirt live migration without risking filesystem corruption.
- **Consequences:**  
  - *Positive:* Enables zero-downtime KubeVirt live migration; provides a direct baseline for performance trade-off analysis (RWO vs RWX).
  - *Negative:* Introduces an NFS layer overhead (protocol translation, cache coherency) and a potential single point of failure in the gateway pod.
- **Validation Evidence:**  
  Pending live migration testing in Chunk 6 and comparative benchmarking in Chunk 8.

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

- **Status:** PROPOSED (Evaluated in Chunk 1)
- **Date:** 2026-11-04
- **Context:**  
  KubeVirt live migration requires `ReadWriteMany` (RWX) shared storage so both source and destination `virt-launcher` pods can access the disk during RAM streaming. OpenEBS Mayastor natively provisions high-performance NVMe volumes in `ReadWriteOnce` (RWO) block mode. Native Mayastor RWX block volumes are not production-ready in Mayastor v2.5/v2.6.
- **Options Considered:**
  1. *Solely Direct RWO Block:* Maximum NVMe performance, but zero live-migration capability.
  2. *Solely NFS-Backed RWX Storage:* Enables live migration, but masks raw NVMe throughput behind NFS protocol translation.
  3. *Dual-Tier Storage Strategy:* Deploy direct Mayastor RWO block volumes for I/O-intensive benchmarking VMs and deploy an NFS gateway over a Mayastor RWO volume for live-migratable VMs.
- **Decision:**  
  Adopt Option 3: Dual-Tier Storage Strategy.
- **Reasoning:**  
  Permits evaluating both extremes: pure NVMe wire speeds via SPDK for static VMs, and zero-downtime live migration over RWX shared storage for elastic VMs.
- **Consequences:**  
  - *Positive:* Validates all required project deliverables without architectural compromise.
  - *Negative:* Increases configuration complexity; NFS gateway acts as a single point of failure for live-migratable VMs.
- **Validation Evidence:**  
  Documented in `docs/storage-architecture-analysis.md`; to be empirically measured in Chunks 6 and 8.

---

## ADR-009: Target Software Stack Baseline Specification

- **Status:** PROPOSED (Evaluated in Chunk 1)
- **Date:** 2026-11-04
- **Context:**  
  Software version incompatibilities between Linux kernel versions, Kubernetes releases, containerd CRI changes, and Mayastor SPDK drivers are a primary failure mode in cloud-native storage projects.
- **Options Considered:**
  1. *Bleeding Edge:* Latest versions of everything (Ubuntu 24.04, Linux 6.8, Kubernetes 1.31, containerd 2.0). High risk of unresolvable CRI/CSI breaking changes.
  2. *Conservative Proven LTS Baseline:* Ubuntu Server 22.04 LTS (Kernel 5.15), Kubernetes v1.28.8, containerd v1.7.15, OpenEBS Mayastor v2.5.0, KubeVirt v1.1.1, Calico v3.27.3.
- **Decision:**  
  Adopt Option 2: The Conservative Proven LTS Baseline (Candidate Stack A).
- **Reasoning:**  
  Every component in this combination has documented, verified compatibility. Kernel 5.15 contains the required `nvme-tcp` and `/dev/kvm` drivers, and Mayastor v2.5 is fully validated on Kubernetes 1.28.
- **Consequences:**  
  - *Positive:* Maximum deployment predictability and reduced debugging overhead.
  - *Negative:* Reaches upstream end-of-support earlier than modern v1.30+ releases.
- **Validation Evidence:**  
  Documented in `docs/compatibility-matrix.md`.