# Deploy High-Performance Storage for Kubernetes

**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Category:** Cloud Infrastructure / Kubernetes / Virtualization / Distributed Storage / Systems Engineering  
**Repository Branch:** `main`  
**Status:** In Progress (Phase 2–3 Complete: M2 Kubernetes, M3 Mayastor & Sprint 1 KubeVirt/Migration/Hot-Plug Implemented & Statically Validated; Live Multi-Node Deployment & Benchmarks Pending)  

---

## 1. Executive Summary & Problem Statement

Modern cloud-native environments increasingly converge containerized microservices and virtual machine workloads onto unified orchestration platforms. Kubernetes, through extensions like **KubeVirt**, enables organizations to run legacy and monolithic virtual machines alongside containers. However, running I/O-intensive virtualized workloads inside Kubernetes introduces critical storage architectural challenges:

- **Kernel I/O Bottlenecks:** Traditional Linux kernel storage stacks (VFS, block layer, context switching, interrupt handling) introduce latency overheads that degrade high-throughput, low-latency NVMe performance.
- **Data Replication & Fault Tolerance:** Cloud-native storage must provide synchronous replication across failure domains without sacrificing NVMe wire speeds.
- **Workload Portability & Migration:** Virtual machine live migration requires persistent storage volumes to be accessible across nodes, creating architectural tension between high-speed local NVMe replicated block storage (typically ReadWriteOnce / RWO) and cluster-wide shared storage (ReadWriteMany / RWX) requirements.
- **Dynamic Resource Adaptation:** Production virtualization requires dynamic resource adjustments (CPU, memory, storage, and network interface hot-plugging) without VM restarts or workload interruptions.

This project investigates, designs, deploys, and benchmarks a high-performance cloud-native storage architecture centered on **OpenEBS Mayastor**, leveraging the **Storage Performance Development Kit (SPDK)** and **NVMe over Fabrics (NVMe-oF)** to service **KubeVirt** virtual machine workloads on a multi-node Kubernetes cluster.

> [!IMPORTANT]
> **Project Phase & Strategic Alignment (ADR-011):** This project has completed **Phase 1 Infrastructure Discovery (Chunks 0 through 1.11)**, **Chunk 2.0 Readiness Planning**, **Chunk 2.1 Strategy Realignment**, **Milestone M1 Development Environment Preparation & Automated Tooling**, **Milestone M2 Kubernetes Cluster Architecture & Multi-Node Provisioning**, and **Milestone M3 OpenEBS Mayastor Storage Engine & Volume Provisioning**. In accordance with **ADR-011**, the complete 4-node Mayastor/KubeVirt architecture remains fully preserved as the target specification, while development and validation proceed decoupled from institutional hardware gating per the 10-milestone roadmap ([`docs/development-roadmap.md`](docs/development-roadmap.md)). Local K3s single-node validation (`v1.36.6+k3s1`) and static/Helm/schema checks (`openebs 4.6.2` / Mayastor `2.12.2`) are empirical on WSL2; multi-node bootstrap, Calico BGP mesh, live Mayastor SPDK/NVMe-oF pools, and KubeVirt remain `INFRASTRUCTURE-DEPENDENT` until target deployment.

---

## 2. Motivation and Objectives

### 2.1 Motivation
Enterprise workloads demanding virtualization within Kubernetes require storage engines capable of saturating modern NVMe hardware while maintaining cloud-native elasticity. Traditional distributed file systems often suffer from protocol overheads and kernel context switching. By leveraging user-space polling-mode drivers via SPDK and NVMe-oF transport protocols within Mayastor, near-bare-metal I/O performance can theoretically be achieved for KubeVirt VMs.

### 2.2 Core Project Objectives
1. **Multi-Node Cluster Deployment:** Establish a 4-node Kubernetes cluster (1 Control Plane + 3 dedicated Worker nodes) using `kubeadm` and `containerd`.
2. **High-Performance Replicated Block Storage:** Deploy OpenEBS Mayastor utilizing dedicated block devices to construct multi-node `DiskPools`, provisioning synchronous replicated storage via NVMe-oF.
3. **Cloud-Native Virtualization Integration:** Install and configure KubeVirt, provisioning virtual machines backed by high-performance persistent volumes.
4. **Live Migration & Shared Storage Evaluation:** Evaluate live migration mechanics for KubeVirt VMs across worker nodes, comparing replicated block storage (RWO) with shared filesystem (RWX via NFS gateway) semantics.
5. **Runtime Resource Hot-Plugging:** Systematically test and validate dynamic hot-plugging of vCPU, memory, storage volumes, and network interfaces on running KubeVirt guest VMs.
6. **Empirical Benchmarking & Failure Analysis:** Execute comprehensive `fio` benchmarking matrices (IOPS, throughput, latency percentiles) across raw disk, container volumes, and virtual machines, followed by simulated disk and node failure recovery drills.
7. **Comprehensive Observability:** Deploy Prometheus and Grafana dashboards capturing node, storage pool, engine, and virtual machine metrics in real time.

---

## 3. Proposed Technology Stack

| Domain | Technology / Component | Planned Version / Spec | Role & Architectural Function |
| :--- | :--- | :--- | :--- |
| **Host Operating System** | Ubuntu Server 24.04 LTS | Linux 6.8 LTS kernel | Base OS across all bare-metal / virtual cluster nodes |
| **Cluster Orchestration** | Kubernetes (`kubeadm`) | v1.36.x (Candidate B preferred) / v1.35.x (Candidate A comparison) | Core container orchestration and resource scheduling |
| **Container Runtime** | `containerd` | v2.3.x LTS | OCI-compliant container runtime officially recommended for K8s 1.36+ |
| **Cluster Networking** | Calico v3.33 (CNI) | Pure routed BGP mode | Pod-to-Pod and Node-to-Pod networking fabric without VXLAN overhead |
| **Storage Engine** | OpenEBS Mayastor | `openebs/openebs` v4.6.2 (Mayastor v2.12.2) | SPDK-based high-performance distributed block storage engine (Ports 8420 & 4421; canonical 20-port matrix) |
| **I/O Acceleration** | SPDK (User Space) | Integrated with Mayastor | Polled-mode NVMe driver (2 dedicated cores), zero-copy user-space I/O pipeline |
| **Storage Protocol** | NVMe-oF (TCP) | NVMe over Fabrics | High-throughput, low-latency block transport across cluster nodes |
| **Virtualization Layer** | KubeVirt + CDI | `KubeVirt v1.9.1` + `CDI v1.66.1` (`virtctl v1.9.0`) | Kubernetes CRD controller & DataVolume importer managing QEMU/KVM VM pods (`ADR-013`) |
| **Hypervisor / Emulator** | QEMU / KVM | Linux KVM module (`/dev/kvm`) | Hardware-assisted virtualization within VM launcher pods |
| **Shared Storage Gateway** | NFS Server / RWX Provisioner | `csi-driver-nfs` v4.9.0 | Comparative fallback mechanism for RWX live-migration shared storage |
| **Benchmarking Suite** | Flexible I/O Tester (`fio`) | v3.30+ | Multi-pattern synthetic I/O workload generation & measurement |
| **Metrics & Monitoring** | Prometheus & Grafana | `kube-prometheus-stack` v62.x | Cluster, storage engine, and guest VM telemetry (Internal management network only) |

---

## 4. Proposed High-Level Architecture

The target architecture decouples the Kubernetes control plane from storage-capable worker nodes. Worker nodes dedicate physical storage partitions to Mayastor DiskPools, while KubeVirt schedules VM launcher pods accessing volumes over NVMe-oF.

```mermaid
flowchart TD
    subgraph Management["Management & Orchestration Plane"]
        CP["Kubernetes Control Plane Node<br/>(API Server, etcd, Controller Manager, Scheduler)"]
        Prom["Prometheus & Grafana<br/>(Metrics & Telemetry)"]
    end

    subgraph DataPlane["Storage & Virtualization Worker Fleet"]
        subgraph Worker1["Worker Node 1"]
            KVM1["KubeVirt Launcher Pod<br/>(Guest VM: Ubuntu)"]
            MS1["Mayastor I/O Engine (SPDK)<br/>(Nexus / Controller)"]
            Pool1["DiskPool 1<br/>(Dedicated NVMe/SSD)"]
        end

        subgraph Worker2["Worker Node 2"]
            KVM2["Target KubeVirt Pod<br/>(Migration Target)"]
            MS2["Mayastor I/O Engine (SPDK)<br/>(Replica Host)"]
            Pool2["DiskPool 2<br/>(Dedicated NVMe/SSD)"]
        end

        subgraph Worker3["Worker Node 3"]
            MS3["Mayastor I/O Engine (SPDK)<br/>(Replica Host)"]
            Pool3["DiskPool 3<br/>(Dedicated NVMe/SSD)"]
        end
    end

    subgraph StorageInterconnect["High-Speed Cluster Fabric (NVMe-oF / TCP)"]
        Fabric((NVMe-oF Network Mesh))
    end

    CP -->|Schedule & Manage| Worker1
    CP -->|Schedule & Manage| Worker2
    CP -->|Schedule & Manage| Worker3

    KVM1 -.->|NVMe-oF Mount| MS1
    MS1 <==>|Synchronous Replication| Fabric
    Fabric <==> Pool1
    Fabric <==> Pool2
    Fabric <==> Pool3

    Prom -.->|Scrape Metrics| MS1
    Prom -.->|Scrape Metrics| MS2
    Prom -.->|Scrape Metrics| MS3
```

---

## 5. Planned Capabilities Matrix

All capabilities below represent project targets and will be updated as implementation proceeds:

| # | Capability Area | Specific Target Feature | Verification Status (3-State) | Implementation Phase |
| :-: | :--- | :--- | :---: | :---: |
| 1 | **Cluster Core** | Multi-node `kubeadm` + Calico Kubernetes deployment | 🛠️ `IMPLEMENTED` / 🧪 Local K3s `v1.36.6` `VALIDATED` / 🔒 4-node `INFRASTRUCTURE-DEPENDENT` | M2 |
| 2 | **Storage Engine** | OpenEBS `4.6.2` / Mayastor `2.12.2` deployment & HugePages validation | 🛠️ `IMPLEMENTED` / 🧪 Chart/Schema/Refusal `VALIDATED` / 🔒 Live SPDK `INFRASTRUCTURE-DEPENDENT` | M3 |
| 3 | **Storage Pools** | Multi-node `DiskPool` (`openebs.io/v1beta3`) across raw NVMe | 🛠️ `IMPLEMENTED` / 🧪 CRD Schema `VALIDATED` / 🔒 Hardware `INFRASTRUCTURE-DEPENDENT` | M3 |
| 4 | **Replication** | Synchronous 3-way NVMe-oF TCP StorageClasses & integrity verification | 🛠️ `IMPLEMENTED` / 🧪 Static CSI `VALIDATED` / 🔒 Multi-Node `INFRASTRUCTURE-DEPENDENT` | M3 |
| 5 | **Virtualization** | KubeVirt `v1.9.1` + CDI `v1.66.1` operator & CRs | 🛠️ `IMPLEMENTED` / 🧪 CRD Schema & KVM Preflight `VALIDATED` / 🔒 Cluster `INFRASTRUCTURE-DEPENDENT` | Sprint 1 (M4) |
| 6 | **VM Workloads** | Cloud-init Ubuntu VMs (RWO FS, RWO Block, NFS RWX, Exp RWX Block) | 🛠️ `IMPLEMENTED` / 🧪 Strict Schema & Dry-Run `VALIDATED` / 🔒 Live Boot `INFRASTRUCTURE-DEPENDENT` | Sprint 1 (M4–M5) |
| 7 | **Live Migration** | Default NFS RWX migration (`MigrationPolicy`, `VMIM`, rollback/checks) | 🛠️ `IMPLEMENTED` / 🧪 Policy Schema & Runner `VALIDATED` / 🔒 Multi-Node `INFRASTRUCTURE-DEPENDENT` | Sprint 1 (M6) |
| 8 | **CPU Hot-Plug** | Dynamic vCPU socket scaling (`LiveUpdate`, `maxSockets: 4`) | 🛠️ `IMPLEMENTED` / 🧪 Manifest/Bounds `VALIDATED` / 🔒 Live Patch `INFRASTRUCTURE-DEPENDENT` | Sprint 1 (M6) |
| 9 | **Memory Hot-Plug** | Dynamic guest RAM scaling (`guest: 2Gi -> maxGuest: 4Gi`) | 🛠️ `IMPLEMENTED` / 🧪 Manifest/Bounds `VALIDATED` / 🔒 Live Patch `INFRASTRUCTURE-DEPENDENT` | Sprint 1 (M6) |
| 10 | **Storage Hot-Plug** | Dynamic SCSI volume attach/detach (`virtctl addvolume`/`removevolume`) | 🛠️ `IMPLEMENTED` / 🧪 Schema & Script `VALIDATED` / 🔒 Live Attach `INFRASTRUCTURE-DEPENDENT` | Sprint 1 (M6) |
| 11 | **NIC Hot-Plug** | Attaching dynamic Multus secondary interface | ⏳ NOT STARTED | Remaining Sprint |
| 12 | **Benchmarking** | Matrix testing using `fio` across R/W profiles | ⏳ NOT STARTED | M7–M8 |
| 13 | **Failure Recovery** | Degraded pool rebuild and node offline failover | ⏳ NOT STARTED | M7 |
| 14 | **Observability** | Real-time dashboards for IOPS, latency, and health | ⏳ NOT STARTED | M8 |

---

## 6. Repository Layout

```text
k8s-high-performance-storage/
├── AGENTS.md               # Strict governance instructions for AI-assisted development
├── README.md               # Project landing page, overview, and roadmap
├── PROJECT_STATE.md        # Persistent single source of truth for progress tracking
├── ARCHITECTURE.md         # Detailed target architecture and technical design specifications
├── RESEARCH.md             # Theoretical foundations, API references, and open inquiries
├── LEARNING_NOTES.md       # Student engineering reference guide and interview preparation
├── DECISIONS.md            # Architectural Decision Records (ADRs) tracking design choices
├── .gitignore              # Exclusion rules preventing leakage of credentials, logs, and caches
├── LICENSE                 # Project open-source license (MIT)
│
├── infrastructure/         # Cluster manifests, node configs, networking, and storage primitives
│   ├── kubernetes/         # kubeadm configs, cluster initialization manifests
│   ├── networking/         # CNI configurations (Calico/Flannel)
│   └── storage/            # DiskPool CRDs, StorageClasses, and PVC templates
│
├── kubevirt/               # KubeVirt operator configs, VM specs, and migration policies
│   ├── installation/       # Operator and Subresource deployment manifests
│   ├── virtualmachines/    # VirtualMachine and VirtualMachineInstance specifications
│   ├── migration/          # VirtualMachineInstanceMigration CRDs and policies
│   └── hotplug/            # Configurations for CPU, memory, volume, and NIC hot-plugging
│
├── storage/                # Engine-specific configurations and experimental topologies
│   ├── mayastor/           # Mayastor Helm values, daemonsets, and engine settings
│   ├── nfs/                # NFS server and provisioner configs for RWX migration tests
│   └── experiments/        # Manifests for specialized storage testing scenarios
│
├── monitoring/             # Observability manifests and dashboards
│   ├── prometheus/         # Scrape configs, ServiceMonitors, and alert rules
│   └── grafana/            # Pre-configured JSON dashboards for Mayastor and KubeVirt
│
├── benchmarks/             # Storage benchmarking harness
│   ├── fio/                # FIO job profiles (sequential, random, variable block sizes)
│   ├── scripts/            # Automated benchmark runner scripts
│   └── results/            # Measured raw performance outputs, metrics, and JSON data
│
├── scripts/                # Reusable operational shell scripts
│   ├── setup/              # Cluster pre-flight, kernel module loading, HugePage config
│   ├── validation/         # Smoke tests and environment verification scripts
│   ├── tests/              # Automated functional testing scripts
│   └── cleanup/            # Teardown and resource reset scripts
│
├── tests/                  # Automated and manual verification suites
│   ├── storage/            # Mayastor PVC creation, IO stress, and integrity tests
│   ├── migration/          # KubeVirt live migration test sequences
│   └── recovery/           # Disk unplugging, engine crash, and pool rebuild tests
│
├── docs/                   # Extended project documentation
│   ├── architecture/       # Deep-dive design notes and network flow diagrams
│   ├── installation/       # Step-by-step reproduction runbooks
│   ├── experiments/        # Documented test methodology and hypothesis logs
│   └── submission/         # Zoho SETU program deliverables and project presentation
│
└── reports/                # Project reporting assets
    ├── screenshots/        # Verified terminal output captures and UI views
    ├── graphs/             # Performance comparison charts (IOPS, Latency vs Block Size)
    └── final-report/       # Compiled final engineering project report
```

---

## 7. Development Environment & Hybrid Workflow

Development follows a strict **hybrid infrastructure model**:

1. **Local Workstation (Windows 11 + WSL2 Ubuntu):**
   - **Hardware:** AMD Ryzen 5 7535HS (6 cores / 12 threads), 8 GB RAM, 512 GB NVMe SSD.
   - **Role:** Manifest authoring, shell script development, static analysis, documentation maintenance, and repository governance.
   - **Constraint:** Due to memory (8 GB) and nested virtualization limitations, the full multi-node cluster (requiring 3+ worker nodes with dedicated storage devices and HugePages) will **not** be hosted locally.

2. **Target Infrastructure (College Lab Servers / Remote Linux Environment):**
   - **Role:** Physical deployment of the 4-node Kubernetes cluster, allocation of raw block devices for Mayastor pools, KVM hardware acceleration for KubeVirt, and physical failure drills.
   - **Status:** Hardware confirmation and laboratory access are pending evaluation.

3. **Source of Truth:**
   - GitHub (`k8s-high-performance-storage`) maintains all versioned configuration, scripts, and documentation. No ad-hoc manual modifications occur on target nodes without matching version-controlled manifests.

---

## 8. Documentation Navigation

- [Architecture Specification (ARCHITECTURE.md)](ARCHITECTURE.md): Comprehensive system layers, SPDK/NVMe-oF pipelines, and KubeVirt live migration workflows.
- [Project Governance & Rules (AGENTS.md)](AGENTS.md): Operational guardrails, chunk development rules, and quality standards.
- [Project Progress State (PROJECT_STATE.md)](PROJECT_STATE.md): Real-time tracker for chunk completions, blockers, and verification evidence.
- [Technical Research Tracker (RESEARCH.md)](RESEARCH.md): Up-to-date theoretical investigations, kernel parameters, and official documentation links.
- [Student Learning Notes (LEARNING_NOTES.md)](LEARNING_NOTES.md): Step-by-step conceptual explanations, interview Q&A, and systems engineering concepts.
- [Architectural Decision Records (DECISIONS.md)](DECISIONS.md): Justifications and trade-off analyses for structural design choices.

### Infrastructure Discovery & Feasibility Reports (Chunk 1 Deliverables)
- [Local Infrastructure Inventory (docs/infrastructure-inventory.md)](docs/infrastructure-inventory.md): Hardware detection, memory limitations, and WSL2 assessment on the dev laptop.
- [College Infrastructure Questionnaire (docs/college-infrastructure-questionnaire.md)](docs/college-infrastructure-questionnaire.md): Formal inquiry and hardware sizing for lab administrators.
- [Software Version Compatibility Matrix (docs/compatibility-matrix.md)](docs/compatibility-matrix.md): Lifecycle research establishing Candidate B (`Ubuntu 24.04 LTS`, `K8s 1.36.x`, `containerd 2.3.x LTS`, `OpenEBS 4.6.2` / `Mayastor 2.12.2`, `KubeVirt 1.9.x`, `Calico 3.33`).
- [Storage Architecture Analysis (docs/storage-architecture-analysis.md)](docs/storage-architecture-analysis.md): RWO vs. RWX evaluation, Mayastor SPDK volume pipeline, and dual-tier storage strategy.
- [Network & Virtualization Requirements (docs/network-and-virtualization-requirements.md)](docs/network-and-virtualization-requirements.md): Canonical 20-port audit, network topology, and hardware KVM pass-through requirements.
- [Deployment Options Evaluation (docs/deployment-options.md)](docs/deployment-options.md): Comparative evaluation of physical servers, lab PCs, hypervisor nested VMs, and cloud options.
- [Final Deployment Proposal (docs/final-deployment-proposal.md)](docs/final-deployment-proposal.md): Complete research-backed engineering blueprint for cluster deployment.

### Milestone M2–M3 & KubeVirt Sprint 1 Implementation Guides
- [Kubernetes Deployment Guide (docs/kubernetes-deployment-guide.md)](docs/kubernetes-deployment-guide.md): 4-node `kubeadm` + Calico BGP bootstrap and WSL2 single-node K3s verification workflow.
- [Mayastor Storage Architecture (docs/mayastor-architecture.md)](docs/mayastor-architecture.md): OpenEBS `4.6.2` / Mayastor `v2.12.2` chart layout, CSI `StorageClass` specs, `DiskPool` (`v1beta3`) design, and compatibility boundaries.
- [Mayastor Networking Design (docs/mayastor-networking.md)](docs/mayastor-networking.md): NVMe-oF TCP ports (`10124`, `8420`, `4421`), Calico data-path flow, and MTU/rebuild window tuning.
- [Mayastor Testing Plan (docs/mayastor-testing-plan.md)](docs/mayastor-testing-plan.md): Two-tier verification protocol (static/WSL2 checks vs. live 4-node NVMe integrity testing).
- [KubeVirt Architecture & Deployment (docs/kubevirt-architecture.md)](docs/kubevirt-architecture.md): KubeVirt `v1.9.1` & CDI `v1.66.1` operator architecture, KVM preflight gates, and schema validation.
- [VM Persistent Storage Integration (docs/vm-storage-integration.md)](docs/vm-storage-integration.md): RWO Filesystem, RWO Raw Block, Default NFS RWX (`csi-driver-nfs v4.9.0`), Opt-In Experimental RWX Block, and cloud-init verification.
- [Live Migration Runbook (docs/live-migration.md)](docs/live-migration.md): `MigrationPolicy`, network/RAM budgets, `validate-live-migration.sh`, timeout rollback, and post-migration verification.
- [Runtime Hot-Plugging Guide (docs/vm-hotplug.md)](docs/vm-hotplug.md): CPU sockets, memory `maxGuest`, SCSI disk attach/detach (`virtctl addvolume`), guest OS & restart limits.

---

## 9. Implementation Roadmap

```mermaid
flowchart LR
    P1["Phase 1<br/>Chunks 0-2.1"] --> M1["M1: Dev Tooling<br/>& Preflight"]
    M1 --> M2["M2: K8s Cluster<br/>& Calico"]
    M2 --> M3["M3: OpenEBS<br/>Mayastor Engine"]
    M3 --> M4["Sprint 1 (M4-M6 Core):<br/>KubeVirt, VM Storage,<br/>Migration & Hot-Plug"]
    M4 --> M7["Sprint 2-3:<br/>NIC Hot-Plug, Faults,<br/>FIO, Telemetry & Report"]

    classDef done fill:#2da44e,stroke:#1b7c3a,color:#fff;
    classDef pending fill:#8c959f,stroke:#6e7781,color:#fff;

    class P1,M1,M2,M3,M4 done;
    class M7 pending;
```

*Current Phase: Final Completion Sprint 1 Completed (KubeVirt `v1.9.1`, CDI `v1.66.1`, VM Storage Tiers, Live Migration, and CPU/Memory/Disk Hot-Plug Implemented & Statically Validated; Live Multi-Node Deployment Pending Target Hardware). Next Authorized Step: Final Completion Sprint — Prompt 2 of 3.*
