# Proposed Target Architecture Specification

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Document Status:** PROPOSED (Target Architecture — Not Yet Deployed or Experimentally Validated)  
**Last Updated:** Chunk 0 (Project Foundation & Governance)  

---

> [!WARNING]
> **Architectural Status & Disclaimer:**  
> The system design documented here represents the **target architectural proposal** formulated during the initial project design phase. None of the components, node topologies, or inter-service protocols described below have been deployed, configured, or benchmarked at this stage. All performance characteristics and operational behaviors reflect documented upstream technology capabilities and remain **UNVERIFIED ASSUMPTIONS** until empirical validation occurs in subsequent chunks.

---

## 1. Architectural Overview & Design Tenets

The primary objective of this architecture is to bridge high-performance user-space storage engines with cloud-native virtual machine orchestration. The target deployment unifies:
1. **Low-Latency Storage Plane:** User-space block storage processing via OpenEBS Mayastor and SPDK to bypass Linux kernel VFS and context-switch overheads.
2. **Synchronous Data Resiliency:** Cluster-wide data durability using multi-replica NVMe-oF targets across independent failure domains.
3. **Cloud-Native Virtualization:** KubeVirt-managed virtual machines running guest operating systems with near-native hardware access.
4. **Workload Portability:** Virtual machine live migration and runtime resource adaptability (CPU, memory, disk, and network hot-plugging).

```mermaid
flowchart TB
    subgraph ControlPlane["Kubernetes Control Plane Node (Node 0)"]
        K8sMaster["kube-apiserver<br/>etcd cluster<br/>kube-controller-manager<br/>kube-scheduler"]
        MSControl["Mayastor Control Plane<br/>(Core Agent, REST API, CSI Controller)"]
        KVControl["KubeVirt Control Plane<br/>(virt-controller, virt-api)"]
    end

    subgraph WorkerFleet["Distributed Worker Fleet (Nodes 1, 2, 3)"]
        subgraph Node1["Worker Node 1"]
            Kubelet1["Kubelet + containerd"]
            VH1["virt-handler (DaemonSet)"]
            IOE1["Mayastor io-engine (SPDK)<br/>[Nexus Controller]"]
            DP1[("DiskPool 1<br/>Raw NVMe/SSD")]
            VMPod1["virt-launcher Pod<br/>(Source VM)"]
        end

        subgraph Node2["Worker Node 2"]
            Kubelet2["Kubelet + containerd"]
            VH2["virt-handler (DaemonSet)"]
            IOE2["Mayastor io-engine (SPDK)<br/>[Replica Target]"]
            DP2[("DiskPool 2<br/>Raw NVMe/SSD")]
            VMPod2["virt-launcher Pod<br/>(Target VM - Migration)"]
        end

        subgraph Node3["Worker Node 3"]
            Kubelet3["Kubelet + containerd"]
            VH3["virt-handler (DaemonSet)"]
            IOE3["Mayastor io-engine (SPDK)<br/>[Replica Target]"]
            DP3[("DiskPool 3<br/>Raw NVMe/SSD")]
        end
    end

    subgraph StorageFabric["High-Speed Data Mesh"]
        NVMeMesh{{"NVMe-oF / TCP Storage Mesh<br/>(Synchronous Multi-Path Replication)"}}
    end

    K8sMaster -->|Node Management| WorkerFleet
    MSControl -->|gRPC Control RPCs| IOE1 & IOE2 & IOE3
    KVControl -->|Virt-Subresources| VH1 & VH2 & VH3

    VMPod1 -->|Local Block Device Mount| IOE1
    IOE1 <==>|Synchronous I/O Dual-Write| NVMeMesh
    NVMeMesh <==> DP1
    NVMeMesh <==> DP2
    NVMeMesh <==> DP3
```

---

## 2. Infrastructure Layer Specification

### 2.1 Host Hardware & Operating System
- **Host Operating System:** Ubuntu Server 22.04 LTS (Jammy Jellyfish) or 24.04 LTS (Noble Numbat).
- **Kernel Architecture:** Linux 5.15+ or 6.x standard kernel.
- **CPU Architecture:** x86_64, minimum 4 physical cores per worker node. Hardware virtualization support (`vmx` for Intel, `svm` for AMD) is mandatory for hardware-accelerated KVM.
- **Memory Requirements:** Minimum 16 GB RAM per worker node on target remote hardware.
  - *HugePages Allocation:* Dedicated pre-allocated HugePages (2 MiB pages, minimum 1024 pages = 2 GiB reserved per node) specifically dedicated to SPDK memory pools.
- **Storage Subsystem:**
  - Dedicated OS disk (`/dev/sda` or primary NVMe) for root filesystem and container runtime state.
  - Dedicated, unpartitioned, non-formatted block device (`/dev/sdb` or `/dev/nvme1n1`) per worker node exclusively bound to Mayastor `DiskPool`.

### 2.2 Network Topology & Segmentation
The intended deployment separates cluster traffic into logical or physical planes:
1. **Cluster Management & Pod Network:** Standard 1 Gbps / 10 Gbps Ethernet for Kubernetes API communication, pod-to-pod CNI traffic, and management queries.
2. **Storage Data Fabric (NVMe-oF):** Low-latency network mesh carrying NVMe over TCP frames between Mayastor Nexus and remote replicas.
   - *Target Configuration:* MTU 9000 (Jumbo Frames) enabled across storage interfaces to minimize packet fragmentation overhead under high-throughput I/O bursts.
   - *Latency Objective:* Sub-millisecond node-to-node round-trip time (RTT) to prevent replication acknowledgment stalls.

---

## 3. Kubernetes Orchestration Layer

- **Cluster Deployment Engine:** `kubeadm` v1.35.x (or v1.34.x fallback) providing standard, upstream-compliant Kubernetes lifecycle management.
- **Target Software Baseline Specification (ADR-010):**
  - **Host Operating System:** Ubuntu Server 24.04 LTS (Noble Numbat).
  - **Linux Kernel:** 6.8.0 LTS with optimized in-tree `nvme-tcp` and `/dev/kvm`.
  - **Kubernetes Version:** v1.35.x (Active support through Feb 2027; fallback v1.34.x).
  - **Container Runtime:** `containerd` v1.7.22 (systemd cgroup driver).
  - **CNI Plugin:** Calico v3.28+ (native routed BGP without VXLAN overhead).
  - **Storage Engine:** OpenEBS v4.6.x (Mayastor v2.11+) with native experimental RWX block volume support.
  - **Virtualization Engine:** KubeVirt v1.8.x + CDI v1.61.x.
- **Node Topology:**
  - **1 Dedicated Control Plane Node:** Hosts API server, `etcd` (Raft consensus), controller manager, scheduler, and Mayastor control plane agents.
  - **3 Dedicated Worker Nodes:** Labeled and configured for storage and virtualization workloads (`openebs.io/engine=mayastor`, `kubevirt.io/schedulable=true`), each with 2 GiB HugePages pre-allocated and dedicated NVMe/SSD raw block devices. Minimum planning target: 16 GB RAM per worker (32 GB preferred).

---

## 4. Virtualization Layer (KubeVirt)

### 4.1 KubeVirt Core Components
KubeVirt extends Kubernetes to manage virtual machines as native declarative resources:
- **`virt-operator`:** Manages the lifecycle and version upgrades of KubeVirt system components.
- **`virt-api`:** An aggregated API server providing validation, admission webhooks, and KubeVirt-specific subresources (VNC, console, start/stop).
- **`virt-controller`:** Monitors `VirtualMachine` (VM) and `VirtualMachineInstance` (VMI) Custom Resource Definitions (CRDs) and coordinates scheduling.
- **`virt-handler` (DaemonSet):** Runs on every worker node; communicates directly with the local container runtime and hypervisor to launch and manage VM processes.
- **`virt-launcher` (Pod):** The pod wrapper containing the QEMU/KVM process. Each VM runs inside its own `virt-launcher` pod, inheriting Kubernetes cgroups, namespaces, and security contexts.

### 4.2 Hardware Virtualization & KVM Integration
The `virt-handler` detects the `/dev/kvm` character device on the host. If `/dev/kvm` is absent (e.g., in un-nested virtual machines), KubeVirt falls back to software emulation (TCG), which drastically degrades performance. Hardware KVM pass-through is therefore a mandatory pre-condition for valid benchmarking.

---

## 5. Storage Layer (OpenEBS Mayastor & SPDK)

### 5.1 The Mayastor Storage Pipeline
OpenEBS Mayastor operates as a cloud-native, containerized distributed block storage system written in Rust and C, built on top of the **Storage Performance Development Kit (SPDK)**.

```mermaid
sequenceDiagram
    autonumber
    participant App as Guest VM / virt-launcher
    participant NVMeClient as Host nvme-tcp Driver
    participant Nexus as Mayastor Nexus (SPDK Controller)
    participant RepLocal as Local Replica Bdev
    participant RepRemote as Remote Replica Bdev (Worker 2)

    App->>NVMeClient: POSIX Block I/O Request
    NVMeClient->>Nexus: NVMe-oF / TCP Command Capsule
    activate Nexus
    par Parallel Synchronous Write
        Nexus->>RepLocal: Write Bdev (Direct DMA / Memory Map)
    and
        Nexus->>RepRemote: Write NVMe-oF Command over TCP
    end
    RepLocal-->>Nexus: Local Write Ack
    RepRemote-->>Nexus: Remote Write Ack
    deactivate Nexus
    Nexus-->>NVMeClient: NVMe Completion Response
    NVMeClient-->>App: I/O Complete
```

### 5.2 Key Mayastor Architectural Primitives
1. **`DiskPool` CRD:** Defines storage capacity on a node backed by a designated block device (e.g., `/dev/sdb`). Mayastor formats and manages this pool using SPDK's `lvol` (logical volume) subsystem.
2. **Replicas:** A thin- or thick-provisioned logical block device created inside a `DiskPool`. A volume with a replication factor of $N=2$ or $N=3$ maintains active replicas across distinct nodes.
3. **Nexus:** The dynamic storage controller. A Nexus is instantiated (typically on the node where the consumer pod resides) and aggregates the volume's replicas. It acts as an NVMe-oF target, receiving I/O from the client and issuing simultaneous synchronous writes to all replicas.
4. **CSI Controller & Node Plugin:**
   - *CSI Controller:* Interacts with the Mayastor REST API to provision volumes and arrange replicas across pools.
   - *CSI Node Plugin:* Mounts the Mayastor volume on the consumer node using the Linux kernel's in-tree `nvme-tcp` initiator driver, creating a local `/dev/nvmeXnY` block device exposed to the pod.

### 5.3 SPDK & NVMe-oF Acceleration Mechanisms
- **User-Space Execution:** The `io-engine` runs in user space, avoiding system call and kernel context-switch overheads for every I/O operation.
- **Polled-Mode Driver (PMD):** Instead of relying on CPU hardware interrupts upon I/O completion, dedicated CPU cores run polling loops to detect completion queues instantly, drastically reducing latency variance.
- **Lockless Concurrency:** SPDK employs message-passing ring buffers and thread-local data structures, eliminating lock contention between processing cores.

---

## 6. Shared Storage & KubeVirt Live Migration

### 6.1 The Live Migration Architectural Dilemma
KubeVirt live migration transfers a running virtual machine from a source worker node to a target worker node with minimal guest downtime (typically < 100 ms). During migration:
1. QEMU on the target node initializes and creates an identical memory map.
2. RAM pages are streamed iteratively over a dedicated migration network connection.
3. Once dirty page transfer reaches convergence, the source VM is paused, final registers are transferred, and the target VM is resumed.

**Storage Requirement:** For stateful VMs, the persistent disk volume must remain accessible to **both the source and destination pods simultaneously** during the handover. This natively requires a **ReadWriteMany (RWX)** volume access mode.

```mermaid
flowchart LR
    subgraph SourceWorker["Source Worker Node"]
        SrcPod["Source virt-launcher Pod"]
        SrcQEMU["Source QEMU Instance"]
        SrcPod --- SrcQEMU
    end

    subgraph TargetWorker["Target Worker Node"]
        TgtPod["Target virt-launcher Pod"]
        TgtQEMU["Target QEMU Instance"]
        TgtPod --- TgtQEMU
    end

    subgraph MigrationFabric["Migration Plane"]
        MemoryStream["Iterative Memory Page Transfer<br/>(virt-handler to virt-handler TCP socket)"]
    end

    subgraph StorageLayer["Shared Storage Access (RWX)"]
        NFSGate["NFS Gateway / Shared Volume<br/>(Backed by Mayastor PV)"]
        SharedDisk[("Virtual Disk Image<br/>(disk.img / raw block)")]
    end

    SrcQEMU ==> MemoryStream ==> TgtQEMU
    SrcPod ==>|Mount (RWX)| NFSGate
    TgtPod ==>|Simultaneous Mount (RWX)| NFSGate
    NFSGate --- SharedDisk
```

### 6.2 Proposed RWX Integration Strategies
KubeVirt live migration requires concurrent volume access during memory streaming. To evaluate both high performance and stability, two distinct pathways are investigated:

1. **Option A: Native Mayastor RWX Block Volumes (Primary Innovation Target — OpenEBS 4.6+ / Mayastor v2.11+)**
   - *Mechanism:* Mayastor exposes an NVMe-oF target capable of accepting simultaneous attachments from both source and destination worker node `nvme-tcp` initiators (`volumeMode: Block`, `accessModes: [ReadWriteMany]`).
   - *Concurrency & Fencing:* There is no distributed lock manager (DLM); concurrency safety relies on **QEMU / KubeVirt hypervisor serialization** (only the active guest VM issues writes; the target VM is in pre-copy receive mode until cutover).
   - *Performance:* Delivers near-bare-metal NVMe wire throughput and sub-millisecond tail latency.
   - *Status:* Upstream **EXPERIMENTAL**. Behavior during sudden network splits requires empirical evaluation in Chunk 9.

2. **Option B: Clustered NFS Gateway RWX Layer (Conservative Fallback Baseline)**
   - *Mechanism:* An NFS server pod mounts a Mayastor RWO volume, formats it (ext4/XFS), and exports an RWX filesystem via `csi-driver-nfs`.
   - *Trade-off:* Introduces Linux VFS overhead and NFSv4 RPC latency (~25,000–45,000 IOPS vs >150,000 IOPS on block), but provides proven, standards-compliant POSIX file locking.
   - *SPOF Risk:* The NFS server pod represents a temporary single point of failure if its host node crashes.

### 6.3 Decoupling Storage Fault Tolerance from Control-Plane Quorum
- **Control-Plane Quorum:** Handled exclusively by `etcd` Raft ($Q = \lfloor M/2 
\rfloor + 1$). In a 1-node control plane, etcd has zero quorum redundancy.
- **Storage Volume Fault Tolerance:** Handled by the Mayastor Nexus controller. For a 3-way replicated volume ($N=3$), writes are synchronously mirrored across 3 storage workers. If 1 worker node drops offline, the Nexus continues serving I/O on the remaining 2 healthy replicas. The volume remains operational as long as at least 1 healthy replica remains online.

### 6.4 Adopted Comparative Dual-Path Strategy (ADR-008 & ADR-010)
1. **Tier 1 (Direct Block / Maximum Throughput Control):** Benchmarking VMs bind directly to raw Mayastor RWO block volumes (`volumeMode: Block`). Pinned to node; live migration disabled.
2. **Tier 2 (Native RWX Block Live Migration):** Elastic VMs bind to native Mayastor RWX block volumes to evaluate zero-overhead NVMe live migration.
3. **Tier 3 (NFS Gateway RWX Fallback):** Live migration is benchmarked over NFS to quantify the exact "NFS Translation Tax" and serve as a proven fallback.

---

## 7. Runtime Resource Hot-Plugging Architecture

KubeVirt supports dynamically mutating the virtual machine specification while the VM remains operational:
- **vCPU Hot-Plug:** Scaling allocated CPU cores dynamically via ACPI CPU hot-plug events inside the guest OS.
- **Memory Hot-Plug:** Expanding allocated RAM using ACPI memory hot-add or virtio-balloon mechanisms.
- **Storage Volume Hot-Plug:** Dynamically attaching a secondary block PVC to a running VM instance via the `virtctl addvolume` subresource command without dismounting the root volume.
- **Network Interface Hot-Plug:** Attaching secondary network interfaces (e.g., via Multus CNI) into a running guest via dynamic virtio-net binding.

---

## 8. Observability & Telemetry Framework

To provide empirical evidence and validate architectural claims, an integrated Prometheus and Grafana stack will be established:
1. **Node & Kernel Metrics:** `node-exporter` gathering CPU utilization, memory pressure, context switches, interrupt rates, and disk I/O stats.
2. **Storage Engine Metrics:** Mayastor Prometheus metrics endpoint exposing:
   - Volume read/write IOPS.
   - Latency histograms (p50, p95, p99).
   - Nexus state and rebuild progress during replica degradation.
   - SPDK core CPU utilization.
3. **Hypervisor & VM Metrics:** KubeVirt metrics server exposing guest CPU usage, memory ballooning state, and virtual disk I/O queue depths.

---

## 9. Architectural Reality Matrix: Facts vs. Assumptions

| Architectural Area | Confirmed Documented Capability | Intended Project Implementation | Unverified Assumption / Risk |
| :--- | :--- | :--- | :--- |
| **SPDK / NVMe-oF** | SPDK delivers sub-10 µs latency on bare-metal NVMe. | Mayastor running in Kubernetes worker pods. | Lab hardware NVMe performance under containerized SPDK polling threads. |
| **Replication** | Mayastor supports 2-way and 3-way synchronous mirroring. | Replicas across 3 worker nodes. | Rebuild overhead and latency impact during network saturation. |
| **KubeVirt VM Launch** | KubeVirt runs Linux guest OS inside QEMU pods. | Ubuntu 22.04 cloud images booted from Mayastor PV. | Driver compatibility between guest OS and NVMe-attached virtio-scsi/virtio-blk. |
| **Live Migration** | KubeVirt supports live migration over RWX volumes. | Live migration tested over NFS gateway and block volume. | Feasibility of zero-downtime migration on lab network bandwidth. |
| **Hot-Plugging** | KubeVirt supports CPU, memory, and volume hot-plug. | Scripted test harness evaluating guest kernel event recognition. | Guest kernel ACPI responsiveness without VM reboot. |
