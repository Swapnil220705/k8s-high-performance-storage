# Infrastructure Deployment Options & Feasibility Trade-Off Analysis

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Audit Date:** 2026-11-05 (Chunk 2.1 Strategy Realignment & Execution Pathways)  
**Document Status:** TECHNICAL COMPARISON & DEPLOYMENT STRATEGY  
**Governance Scope:** Resource Viability & Institutional Alignment  

---

> [!NOTE]
> **Evaluation Objective:**  
> To determine the most scientifically valid, cost-effective, and operationally viable infrastructure environment for developing, testing, and deploying a 4-node Kubernetes cluster with OpenEBS Mayastor and KubeVirt.
>
> In accordance with **ADR-011**, college laboratory allocation is decoupled from development gating. The project authors, lints, and validates all configurations locally while staging physical hardware tests for remote execution.

---

## 1. Comprehensive Deployment Options Matrix

| Evaluation Dimension | Option A: College Physical Linux Servers | Option B: College Lab Desktop PCs | Option C: College Campus Hypervisor (Nested VMs) | Option D: Public Cloud Free-Tier (AWS/GCP/Oracle) | Option E: Personal Laptop (Windows 11 / WSL2) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Financial Cost** | **Zero ($0.00)** | **Zero ($0.00)** | **Zero ($0.00)** | Limited Free Tier / Rapidly Incurs Charges | **Zero ($0.00)** |
| **Node Count Potential** | 4 Dedicated Nodes (1 CP + 3 Workers) | 4+ Physical Desktop PCs | 4 Virtual Machines on single host | Typically 1–2 small instances free | 1 Physical Host |
| **CPU Resources** | **8–16+ Cores per Server** (Xeon/EPYC) | **6+ Cores per PC** (Core i5/i7) | 16–32 vCPUs carved from hypervisor | 1–2 vCPUs per free instance | 6 Cores / 12 Threads (AMD Ryzen 5) |
| **RAM per Node** | **16 GB – 64+ GB DDR4/DDR5** | **16 GB DDR4 (8 GB Unviable)** | **16 GB – 32 GB per VM** (if host has $\ge$64GB) | 1 GB – 4 GB max free RAM | 8 GB Total (~7.2 GB visible, ~1.0 GB free) |
| **Dedicated Raw Storage** | High (Dedicated SAS/SATA/NVMe drives) | Moderate (Secondary SSD or unpartitioned space) | Virtual Disks (emulated block via hypervisor) | Small EBS/Persistent Disks ($\le$30 GB) | Single 512 GB NVMe (OS drive, ~19 GB free) |
| **Hardware KVM (`/dev/kvm`)** | **Native Bare-Metal Access** | **Native Bare-Metal Access** | Requires Nested Virt (`host-passthrough`) | Typically blocked or premium instance required | AMD-V enabled; `/dev/kvm` verified inside WSL2 |
| **Network Fabric** | 1 Gbps / 10 Gbps switched LAN | 1 Gbps standard lab LAN | Virtual Switch (high virtual throughput) | Cloud VPC (bandwidth throttled on free tier) | Internal virtual bridge only |
| **Mayastor SPDK Feasibility** | **FEASIBLE (Meets all prerequisites)** | **FEASIBLE (Only if $\ge$16 GB RAM & 6 cores)** | **FEASIBLE (With virtual raw disks)** | **IMPOSSIBLE (Insufficient RAM & HugePages)** | **IMPOSSIBLE (Memory & storage deficit)** |
| **Live Migration Feasibility** | **FEASIBLE (Real multi-node network)** | **FEASIBLE (Real multi-node network)** | **FEASIBLE (Across nested VMs)** | **IMPOSSIBLE (Resource starvation)** | **IMPOSSIBLE (Single physical node)** |
| **Administrative Access** | Requires department root/sudo approval | Subject to lab reboot policies / freeze software | Requires hypervisor admin access | Full root access via SSH | Full local administrative access |
| **Overall Recommendation** | **PRIMARY PREFERRED TARGET** | **SECONDARY PHYSICAL FALLBACK** | **PRIMARY VIRTUAL FALLBACK** | **REJECTED (Technically Infeasible)** | **ACTIVE LOCAL DEVELOPMENT & LINTING** |

---

## 2. In-Depth Option Evaluations

### Option A: College Physical Linux Servers (Primary Target)
- **Advantages:** Direct bare-metal hardware access; raw NVMe/SATA performance without hypervisor abstraction; true multi-node network latency; zero financial expense. Easily accommodates the mandatory **6-core minimum (8–16 preferred)** and **16–32 GB RAM** requirements.
- **Disadvantages:** Dependent on institutional approval and laboratory operating hours; requires scheduling hardware access with college systems administrators.
- **Technical Blockers:** Must confirm availability of 4 machines with root access and unformatted secondary drives.

### Option B: College Laboratory Desktop Computers (Secondary Physical Fallback)
- **Advantages:** Readily available in institutional computer labs; free of charge; physical gigabit switching.
- **Disadvantages:** Desktop PCs frequently run lab freeze software (Deep Freeze) or dual-boot Windows; lab sessions may disrupt long-running cluster jobs. **Crucial Limitation:** Desktop PCs configured with only 8 GB RAM are **technically unviable** for storage worker nodes because SPDK HugePages (2 GiB) + Mayastor heap (1.5 GiB) + OS/K8s daemons (4.0 GiB) exhausts available memory before launching a guest VM. Workstations must possess at least 16 GB RAM and 6 physical CPU cores (to accommodate 2-core SPDK busy-polling).
- **Technical Blockers:** Requires reserving specific workstations meeting the 16 GB / 6-core threshold with permissions to boot Ubuntu Server from secondary drives.

### Option C: College Campus Hypervisor / Nested Virtualization (Virtual Fallback)
- **Advantages:** A single high-spec departmental server (e.g., 64 GB RAM, 16-core Xeon) can easily host 4 nested Ubuntu virtual machines with dedicated virtual disks; snapshotting and quick cluster resets are straightforward.
- **Disadvantages:** Storage benchmarking reflects hypervisor caching and virtual disk driver latency rather than pure bare-metal NVMe saturation; requires nested virtualization enabled on the host hypervisor.
- **Technical Blockers:** Must ensure the hypervisor administrator enables CPU host-passthrough and nested virtualization (`/dev/kvm`).

### Option D: Public Cloud Free-Tier (AWS / GCP / Oracle Cloud)
- **Advantages:** Publicly accessible via internet SSH; independent of college laboratory hours.
- **Disadvantages:** Free tiers provide small burstable instances (e.g., AWS `t2.micro` has 1 vCPU and 1 GB RAM; GCP `e2-micro` has 1 GB RAM). Running Mayastor requires pre-allocating 2 GiB HugePages per worker node, immediately crashing free-tier instances. Bare-metal or large memory instances with dedicated NVMe and nested virtualization (e.g., AWS `i3en.metal` or GCP `c2-standard-16`) cost hundreds of dollars per month and violate our zero-cost mandate.
- **Technical Verdict:** **REJECTED**. Technically unviable on free tiers; paid cloud is prohibited.

### Option E: Personal Development Laptop (Windows 11 / WSL2)
- **Advantages:** Immediate, unrestricted administrative access; zero dependency on external network policies; verified `/dev/kvm` nested virtualization active inside WSL2 Ubuntu 24.04.
- **Disadvantages:** Insufficient RAM (8 GB total with ~1.0 GB available); single NVMe disk with ~19.3 GB free space; cannot host 3 storage workers, Mayastor, and KubeVirt VMs simultaneously.
- **Technical Verdict:** **ACTIVE DEVELOPMENT & VERIFICATION PLATFORM** for manifest authoring, linting, toolchain preparation, lightweight single-node dev cluster testing, and harness unit testing.

---

## 3. Explicit Conditions for Considering Cloud Resources

Paid cloud infrastructure remains **strictly disallowed** by project governance directives. Cloud resources would only be considered if:
1. The college department issues a formal written notification that zero physical servers, desktop PCs, or hypervisor allocations can be provided.
2. The user or academic program explicitly provisions a fully sponsored, non-billed academic educational cloud grant (e.g., AWS Educate or Google Cloud for Students).
3. Explicit user approval is granted in writing prior to any account registration.

---

## 4. Alternative Execution Pathways (Chunk 2.1 Alignment)

To maintain continuous development velocity, execution is organized into five complementary pathways documented in [`docs/development-environment-assessment.md`](development-environment-assessment.md):
1. **Pathway 1 (Local WSL2):** Author all Kubernetes manifests, Helm values, shell scripts, and FIO job profiles.
2. **Pathway 2 (Local Dev Cluster):** Deploy lightweight single-node cluster in WSL2 (< 2.0 GiB RAM) to validate CRDs, KubeVirt operator, and launch a micro-VM (256 MB RAM) via verified `/dev/kvm`.
3. **Pathway 3 (Alternative Lab Workstation):** Utilize 16–32 GB lab workstation for multi-node virtual testing if available.
4. **Pathway 4 (Dedicated College Servers):** Preferred baseline for wire-speed NVMe-oF benchmarks and full 3-way replicated Mayastor validation.
5. **Pathway 5 (Temporary Testing Window):** Reserve lab systems for a dedicated 2–3 day benchmark run to harvest final evidence.
