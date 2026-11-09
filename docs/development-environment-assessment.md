# Development Environment Assessment & Component Feasibility Matrix

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Assessment Date:** 2026-11-05 (Chunk 2.1 Strategy Realignment)  
**Document Status:** EMPIRICALLY VERIFIED AUDIT & FEASIBILITY SPECIFICATION  
**Governance Standard:** Zero Fabricated Claims — Strict Evidence-Based Assessment  

---

> [!IMPORTANT]
> **Strategy Realignment & Architectural Scope Preservation:**  
> This assessment formalizes the project's strategy alignment under the Zoho SETU program. **The complete original technical scope remains strictly preserved**:
> - 4-node Kubernetes cluster topology.
> - OpenEBS Mayastor with SPDK and NVMe-oF.
> - KubeVirt virtual machines with hardware KVM acceleration.
> - Dual-path virtual machine live migration.
> - Dynamic CPU, memory, storage, and network hot-plugging.
> - Failure recovery and replica rebuild drills.
> - FIO benchmarking matrix and Prometheus/Grafana observability.
>
> College infrastructure allocation is **reclassified from a blocking project gate to an optional resource opportunity**. Development, configuration, script authoring, and component testing proceed immediately using locally available resources, while tracking feature completion across three explicit states: `IMPLEMENTED`, `VALIDATED`, and `INFRASTRUCTURE-DEPENDENT`.

---

## 1. Empirical Development Environment Inspection

The development environment was directly inspected using non-destructive PowerShell and WSL2 utilities on 2026-11-05. All metrics reflect direct system queries.

### 1.1 Host Operating System & Physical Hardware
- **Host Machine Model:** HP Victus Gaming Laptop 15-fb1xxx (x86_64).
- **Host Operating System:** Windows 11 Home Single Language (64-bit, Build 26300).
- **Processor (CPU):** AMD Ryzen 5 7535HS with Radeon Graphics (Zen 3+ microarchitecture).
  - Physical Cores: 6.
  - Logical Threads: 12.
  - Base Frequency: ~3.30 GHz (Boost up to ~4.55 GHz).
  - Hardware Virtualization: AMD-V (`svm`) enabled in UEFI firmware.
  - Instruction Extensions: `SSE4.1`, `SSE4.2`, `AVX`, `AVX2`, `FMA`, `AES`, `SHA_NI`.
- **Physical Memory (RAM):**
  - Total Installed: 8,589,934,592 bytes (8.00 GB DDR5 @ 4800 MT/s, single module).
  - Total Visible to Windows (`TotalVisibleMemorySize`): 7,558,520 KB (~7.21 GiB; ~512 MB reserved for integrated GPU).
  - Measured Available Free Memory (`FreePhysicalMemory`): 1,020,288 KB (~996 MB free under standard desktop baseline).
- **Physical Storage Subsystem:**
  - Attached Physical Drives: Exactly 1 NVMe SSD (512 GB class, GPT partition layout).
  - Primary OS Partition (`C:`):
    - Total Capacity: 475.77 GiB (510,860,980,224 bytes).
    - Used Space: 456.46 GiB (96% utilization).
    - Available Free Space: **19.31 GiB** free.

### 1.2 Windows Subsystem for Linux (WSL2) Runtime
- **WSL Status:** WSL 2 active as default version (`Default Version: 2`).
- **Distribution:** Ubuntu 24.04.4 LTS (Noble Numbat).
- **Linux Kernel:** `6.6.87.2-microsoft-standard-WSL2` (x86_64).
- **WSL2 Memory & Swap Allocation:**
  - Total RAM Assigned to WSL2 VM: 3,515 MB (~3.43 GiB).
  - WSL2 Active Memory Used: 629 MB.
  - WSL2 Available Memory: **2,885 MB** (~2.81 GiB).
  - Swap Space Assigned: 1,024 MB (1.00 GiB; 0 MB used).
- **WSL2 Virtual Disk:**
  - Virtual Root Partition (`/dev/sdd`): Dynamic VHDX mounted on `/` (16 GB used of dynamic sparse ceiling).
  - Backing Host Storage: Physical `C:` drive with **19.31 GiB actual free space**.
- **Virtualization Support Inside WSL2:**
  - CPU Flags: `svm` (AMD-V) and `sse4_2` are directly visible in `/proc/cpuinfo`.
  - Nested KVM Acceleration: `/dev/kvm` exists (`crw-rw---- 1 root kvm 10, 232 /dev/kvm`) and is operational.
- **Installed Container, Kubernetes & Validation Toolchain (Milestone M1 Empirical Delivery):**
  - `containerd`: Installed (`containerd github.com/containerd/containerd/v2 2.2.1` — retained, untouched per runtime directive).
  - `docker`: Installed (`Docker version 29.1.3, build 29.1.3-0ubuntu3~24.04.2` — retained, untouched).
  - `kubectl`: Installed (`v1.36.0`, official binary, SHA-256 verified).
  - `helm`: Installed (`v3.17.1`, official binary, SHA-256 verified).
  - `kubeconform`: Installed (`v0.8.0`, official binary, SHA-256 verified).
  - `yq`: Installed (`v4.54.3`, official binary, SHA-256 verified).
  - `virtctl`: Installed (`v1.9.0`, official binary, SHA-256 verified).
  - `shellcheck`: Installed (`0.9.0`, Ubuntu APT).
  - `yamllint`: Installed (`1.33.0`, Ubuntu APT).
  - `shfmt`: Installed (`3.8.0`, Ubuntu APT).
  - `jq`: Installed (`1.7.1`, Ubuntu APT).
  - `fio`: Installed (`3.36`, Ubuntu APT).
  - `git`: Installed (`2.43.0`, Ubuntu APT).
  - `curl`: Installed (`8.5.0`, Ubuntu APT).
  - *Reference:* Detailed specifications, delivery channels, and verification commands recorded in [`docs/development-toolchain.md`](development-toolchain.md).
- **Network Connectivity:**
  - Default NAT virtual switch with functional DNS resolution and outbound internet access (verified via HTTP/2 200 response from `https://github.com`).

---

## 2. Component Feasibility Matrix

Every component of the complete target architecture is evaluated below based on its physical requirements, local feasibility on the development machine, and the concrete validation approach:

| Component | Local Feasibility Category | Technical Prerequisites | Concrete Local Limitations | Validation Approach |
| :--- | :--- | :--- | :--- | :--- |
| **Kubernetes Core** | **CAN RUN WITH RESOURCE CONSTRAINTS** | Container runtime, cgroup v2, API server, etcd, kubelet. | Multi-node `kubeadm` cannot run concurrently (exceeds RAM); single-node dev cluster (e.g. lightweight Kind/K3s or constrained single-node kubeadm) consumes 1.5–2.0 GiB of WSL2's 2.8 GiB available RAM. | • **Local:** Validate manifests, RBAC, CRD schemas, and single-node pod scheduling.<br/>• **Target Multi-Node:** Execute multi-node `kubeadm` cluster scripts on dedicated multi-node hardware. |
| **`containerd`** | **CAN RUN LOCALLY** | Systemd cgroup v2, Linux namespaces, overlayfs. | containerd 2.2.1 is already installed in WSL2; containerd 2.3 LTS can be run in standalone namespaces. Memory consumption is modest (~50–100 MB). | • **Local:** Direct runtime validation via `ctr` and CRI socket checks.<br/>• **Target:** Validate containerd 2.3 LTS systemd integration across all cluster nodes. |
| **Calico CNI** | **CAN RUN WITH RESOURCE CONSTRAINTS** | Linux network namespaces, iptables/eBPF, BGP routing daemon. | Routed BGP peering across 4 physical nodes cannot be exercised locally on a single host without virtual network namespaces; VXLAN encapsulation testable in small clusters. | • **Local:** Static YAML manifest validation; CNI plugin binary testing in test network namespaces.<br/>• **Target:** Full inter-node BGP mesh validation across the 4-node switched network. |
| **OpenEBS Mayastor** | **CAN BE DEVELOPED LOCALLY BUT NOT FULLY EXECUTED** | 2 dedicated CPU cores per worker for busy-polling; 2 GiB HugePages; dedicated raw unpartitioned block device. | The development laptop has only 1 physical disk (`C:`), ~1.0 GB free host RAM, and WSL2 has only 2.8 GiB available RAM. Allocating 6 GiB HugePages for 3 workers is mathematically impossible locally. Emulating with loopback devices on NTFS causes severe I/O errors and kernel deadlocks. | • **Local:** Author and lint Helm charts, DiskPool CRDs, StorageClasses, and CSI manifests.<br/>• **Target:** Full live deployment on 3 storage worker nodes with dedicated NVMe drives. |
| **SPDK Engine** | **CAN BE DEVELOPED LOCALLY BUT NOT FULLY EXECUTED** | Dedicated physical CPU pinning; user-space UIO/VFIO drivers; 2 MiB HugePages; raw PCI/NVMe block access. | SPDK Polled Mode Drivers (PMD) saturate allocated CPU cores at 100% continuous utilization; running multiple PMD loops locally starves the host desktop and triggers thermal throttling. | • **Local:** Standalone SPDK unit tests or single-core bdev tests inside a controlled container.<br/>• **Target:** 2-core dedicated PMD execution on dedicated bare-metal storage nodes. |
| **NVMe-oF (TCP)** | **CAN RUN WITH RESOURCE CONSTRAINTS** | Linux kernel `nvme-tcp` initiator module; target daemon; TCP ports 8420 & 4421. | In-tree WSL2 kernel may require loading `nvme-tcp`; loopback NVMe-oF target can be tested between local namespaces on a single IP, but cannot measure real wire latency or multi-path failover. | • **Local:** Test local kernel module loading, loopback NVMe-oF connection, and target discovery.<br/>• **Target:** Wire-speed NVMe-oF benchmarking over 1 Gbps / 10 Gbps physical network. |
| **KubeVirt Hypervisor** | **CAN RUN WITH RESOURCE CONSTRAINTS** | Hardware `/dev/kvm` character device; `virt-handler`, `virt-api`, `virt-controller`; QEMU. | Hardware `/dev/kvm` is confirmed available in WSL2. However, running a 4 GiB guest VM exceeds WSL2's 2.8 GiB available RAM ceiling. Minimal test VMs (e.g. CirrOS / Alpine with 256–512 MB RAM) can run for functional testing. | • **Local:** Verify KubeVirt CRDs, `virt-handler` KVM access, and launch a lightweight 256 MB test VM.<br/>• **Target:** Launch 4 GiB Ubuntu 24.04 database VMs with direct NVMe block attachment. |
| **VM Live Migration** | **CAN BE DEVELOPED LOCALLY BUT NOT FULLY EXECUTED** | Multi-node cluster; RWX shared storage (native Mayastor RWX block or NFS gateway); dedicated migration network (ports 49152+). | Requires at least 2 independent worker nodes and shared storage. Cross-node live migration cannot be executed on a single host without multi-node virtualization, which exceeds host memory limits. | • **Local:** Author migration manifests, migration policy CRDs, and the single-writer verification harness script.<br/>• **Target:** Execute the 6-scenario live migration test suite on physical multi-node hardware. |
| **Dynamic Hot-Plugging** | **CAN RUN WITH RESOURCE CONSTRAINTS** | KubeVirt `virtctl`, guest ACPI driver support, dynamic PVC attachment. | Hot-plugging vCPU, memory ballooning, and secondary disk attachment can be functionally tested on a single local KubeVirt VM, provided total VM RAM remains within 512 MB – 1 GiB. | • **Local:** Execute automated hot-plug scripts on a lightweight local KubeVirt test VM.<br/>• **Target:** Full-scale hot-plug validation on production 4 GiB Ubuntu VMs under Mayastor I/O load. |
| **FIO Benchmarking** | **CAN RUN LOCALLY** | `fio` engine (`libaio`, `io_uring`), target block devices or files. | FIO can be run locally against WSL2 filesystem or local loop devices to validate job files, parsing scripts, and automation harnesses. However, throughput numbers reflect WSL2 virtual disk performance, NOT bare-metal NVMe speed. | • **Local:** Author and syntax-check all FIO job profiles (randread, randwrite, seqread, seqwrite) and output JSON parsers.<br/>• **Target:** Run official empirical benchmark matrices on Mayastor replicated NVMe volumes. |
| **Prometheus Telemetry**| **CAN RUN WITH RESOURCE CONSTRAINTS** | Prometheus server, `node-exporter`, Mayastor metrics exporter, KubeVirt metrics. | Prometheus server consumes 500 MB – 1.5 GiB RAM. Can run locally in a constrained dev configuration with short retention (1 day) and high scrape intervals (30s) to verify metric ingestion. | • **Local:** Validate Prometheus alerting rules, scrape configurations, and exporter manifest syntax.<br/>• **Target:** Full telemetry scraping across all 4 physical nodes during benchmark runs. |
| **Grafana Dashboards** | **CAN RUN LOCALLY** | Grafana container/daemon, datasource configuration, dashboard JSON definitions. | Grafana consumes minimal resources (~100–150 MB RAM). Can comfortably run locally inside WSL2 or via Docker. | • **Local:** Author, import, and test Grafana dashboard JSON files (Mayastor IOPS, KubeVirt VM metrics, node resource dashboards).<br/>• **Target:** Connect to production Prometheus instance on the remote cluster. |

---

## 3. Alternative Execution Infrastructure Evaluation

To ensure the project can reach complete validation without violating the zero-cost academic mandate or depending indefinitely on college bureaucracy, five execution pathways are systematically analyzed:

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                               EXECUTION INFRASTRUCTURE PATHWAYS                                 │
│                                                                                                 │
│  [Path 1] Local WSL2 Environment (Active) ──► Dev, linting, light tests, CRDs, scripts         │
│  [Path 2] Local Linux VM / Micro-Cluster  ──► Single-node validation, 256MB KubeVirt VM          │
│  [Path 3] Alternative Institutional Machine──► 16-32 GB workstation for multi-node dev           │
│  [Path 4] Dedicated College Lab Servers   ──► Preferred target: 4 physical nodes, NVMe benchmark │
│  [Path 5] Temporary Final Testing Access  ──► Reserved multi-node lab block for final evidence   │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Pathway 1: Local WSL2 Environment (Current Baseline)
- **Resource Requirements:** 6 CPU cores, ~3.4 GiB assigned RAM, ~19.3 GiB free disk space.
- **Technical Prerequisites:** Windows 11 + WSL2, Ubuntu 24.04, `/dev/kvm` active.
- **Advantages:** Immediate zero-cost access; full root control; rapid feedback loop; zero administrative approvals required.
- **Limitations:** Cannot run multi-node cluster, 6 GiB HugePages, dedicated raw NVMe drives, or concurrent 4 GiB VMs.
- **Cost Implications:** Free ($0.00).
- **Supported Scope:** All code/manifest/script authoring; static schema validation; Docker/containerd operations; lightweight single-node tooling; FIO job authoring; Grafana dashboard design.

### 3.2 Pathway 2: Local Lightweight Dev Cluster (Constrained Single-Node)
- **Resource Requirements:** 1.5–2.0 GiB RAM allocated to a lightweight Kubernetes distribution (e.g., Kind or K3s with systemd cgroups).
- **Technical Prerequisites:** Docker or containerd in WSL2; custom memory limits in `.wslconfig` (to prevent Windows host thrashing).
- **Advantages:** Allows deploying Kubernetes CRDs, validating KubeVirt operator deployment, testing `virtctl` commands, and running a micro-VM (CirrOS / Alpine, 256 MB RAM) with `/dev/kvm`.
- **Limitations:** Cannot run Mayastor `io-engine` (insufficient RAM for 2 GiB HugePages); cannot perform multi-node live migration.
- **Cost Implications:** Free ($0.00).
- **Supported Scope:** KubeVirt operator validation, VM lifecycle state machine testing, dynamic hot-plug ACPI testing, Prometheus/Grafana integration testing.

### 3.3 Pathway 3: Alternative Personal or Laboratory Workstation
- **Resource Requirements:** A single desktop PC with $\ge 16\text{ GB}$ (preferably 32 GB) RAM and a modern x86_64 CPU with virtualization enabled.
- **Technical Prerequisites:** Clean Ubuntu Linux install or hypervisor (Proxmox VE / KVM).
- **Advantages:** Sufficient memory to host multiple local virtual machines with nested KVM; can emulate a multi-node cluster with virtual disks.
- **Limitations:** Storage performance will reflect local SATA/NVMe virtualized bdevs rather than distributed bare-metal NVMe-oF network wire speeds.
- **Cost Implications:** Free ($0.00).
- **Supported Scope:** Multi-node cluster emulation, functional live-migration drills, failure recovery testing.

### 3.4 Pathway 4: Dedicated College Laboratory Servers (Preferred Infrastructure Target)
- **Resource Requirements:** 4 networked Linux servers (1 Control Plane + 3 Workers), $\ge 6$ cores, 16–32 GB RAM, dedicated raw NVMe drives.
- **Technical Prerequisites:** College questionnaire approval, root/sudo access, static IP assignment, Layer-2 switch access.
- **Advantages:** Enables true empirical benchmarking of SPDK busy-polling, NVMe-oF network throughput, multi-node live migration, and hardware fault injection.
- **Limitations:** Subject to institutional scheduling, bureaucratic delays, and lab operating hours.
- **Cost Implications:** Free ($0.00).
- **Supported Scope:** 100% full-scale validation of all 12 project components and final benchmark evidence collection.

### 3.5 Pathway 5: Temporary Dedicated Final Testing Window
- **Resource Requirements:** 2 to 3 days of exclusive access to high-specification college lab machines (or borrowed lab systems) during weekends or semester breaks.
- **Technical Prerequisites:** All deployment scripts, manifests, test harnesses, and FIO automation scripts must be pre-authored and validated in advance.
- **Advantages:** Eliminates the need for long-term multi-week machine reservations; minimizes institutional friction; allows rapid execution of automated benchmark suites and log harvesting.
- **Limitations:** Requires high operational discipline and automated, push-button deployment scripts.
- **Cost Implications:** Free ($0.00).
- **Supported Scope:** High-throughput FIO benchmarking, physical disk failure injection drills, final graph generation, and submission evidence collection.

---

## 4. Project Completion and Evidence Framework

To ensure complete scientific integrity and prevent conflating code authoring with empirical validation, every project capability is categorized under three independent, non-overlapping completion states:

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                               FEATURE COMPLETION GOVERNANCE LEDGER                              │
├──────────────────────────┬──────────────────────────────────────────────────────────────────────┤
│ 1. IMPLEMENTED           │ Complete, syntactically valid YAML manifests, Helm configurations,    │
│                          │ bash automation scripts, and test harnesses are authored and committed│
│                          │ in the repository.                                                   │
├──────────────────────────┼──────────────────────────────────────────────────────────────────────┤
│ 2. VALIDATED             │ The implementation has been executed on live hardware or an active   │
│                          │ environment; all assertions passed; raw logs and terminal outputs    │
│                          │ are recorded in the repository.                                      │
├──────────────────────────┼──────────────────────────────────────────────────────────────────────┤
│ 3. INFRASTRUCTURE-       │ The component is fully implemented, but complete validation requires │
│    DEPENDENT             │ multi-node clustering, physical NVMe-oF networking, or dedicated     │
│                          │ hardware resources unavailable in the local development environment. │
└──────────────────────────┴──────────────────────────────────────────────────────────────────────┘
```

### Feature Tracking Ledger Structure

For every major project capability, the project maintains:
- **Feature Name & Scope:** Exact architectural boundary.
- **Implementation Status:** `IMPLEMENTED` vs `IN PROGRESS` vs `PENDING`.
- **Validation Status:** `VALIDATED` vs `NOT VALIDATED` vs `PARTIALLY VALIDATED`.
- **Infrastructure Dependency:** `LOCAL (WSL2)` vs `INFRASTRUCTURE-DEPENDENT`.
- **Test Procedure:** Exact reproducible script or command sequence.
- **Evidence Location:** Explicit file path in `benchmarks/results/`, `tests/logs/`, or `reports/`.
- **Known Limitations:** Documented deviations from full bare-metal behavior.
- **Remaining Work:** Concrete tasks needed for full closure.

> [!WARNING]
> **Strict Verification Invariant:**  
> A manifest, configuration file, or shell script is an artifact, not evidence of functionality. **A feature must NEVER be marked as `VALIDATED` solely because its YAML manifest or script exists.**

### 4.2 Milestone M1 Active Feature Ledger

| Feature / Subsystem | Implementation Status | Validation Status | Environment Scope | Test Procedure & Verification Evidence | Known Limitations / Remaining Work |
| :--- | :---: | :---: | :---: | :--- | :--- |
| **Development Toolchain** (`kubectl`, `helm`, `virtctl`, `fio`, `yq`, etc.) | **`IMPLEMENTED`** | **`VALIDATED`** | `LOCAL (WSL2)` | Automated by `scripts/setup/install-dev-tools.sh`; verified via `scripts/validate/run-validation.sh`; CLI versions verified. | None for client tooling; all 12 tools operational. |
| **Static Analysis Linters** (`shellcheck`, `shfmt`, `yamllint`, `kubeconform`) | **`IMPLEMENTED`** | **`VALIDATED`** | `LOCAL (WSL2)` | Executed via `run-validation.sh` across all scripts and YAML files (8/8 steps pass). | None; zero warnings or errors. |
| **Automated Host Preflight** (`01-host-preflight.sh`) | **`IMPLEMENTED`** | **`VALIDATED`** | `LOCAL (WSL2)` | Executed on WSL2; generated `reports/environment/host-preflight-*.txt` and `.json` (27 PASS, 8 WARN, 0 FAIL). | WSL2 limitations explicitly identified; physical NVMe drive tests marked `NOT TESTABLE`. |
| **Node Prerequisite Detection** (`02-node-prerequisites.sh`) | **`IMPLEMENTED`** | **`VALIDATED`** | `LOCAL (WSL2)` | Executed in report-only mode; generated `reports/environment/node-prerequisites-*.txt` and `.json` (10 MET, 5 WARN, 0 UNMET). | HugePages allocation (1024 pages) and secondary raw disk configuration remain infrastructure-dependent. |
| **Hardware KVM Character Device** (`/dev/kvm`) | **`IMPLEMENTED`** | **`VALIDATED`** | `LOCAL (WSL2)` | Inspected via preflight and node prerequisite audits; character device mode `10, 232` confirmed. | Unprivileged local user requires `kvm` group membership; full KubeVirt virt-handler validation scheduled in M4. |

---

## 5. Strategic Summary & Next Action

This assessment confirms that development can proceed immediately without waiting for college administrative approvals:
1. **Local Capabilities:** Development environment preparation, manifest authoring, static linting, schema validation, container operations, FIO profile generation, and Grafana dashboard authoring can all be completed locally.
2. **KVM Acceleration:** The presence of `/dev/kvm` in WSL2 enables local functional testing of lightweight KubeVirt virtual machines and hot-plugging mechanisms.
3. **Target Architecture Intact:** All 12 architectural capabilities remain 100% intact as the project's permanent design objectives.
4. **Roadmap Execution:** We now establish a streamlined, 10-milestone development roadmap to guide implementation systematically.
