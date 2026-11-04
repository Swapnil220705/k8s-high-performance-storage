# Storage Architecture & Virtualization Integration Analysis

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Research Date:** 2026-11-04  
**Document Status:** TECHNICAL ARCHITECTURE FEASIBILITY ANALYSIS  
**Focus Area:** OpenEBS Mayastor Block Storage vs. KubeVirt Shared Storage (RWO vs. RWX)  

---

> [!CRITICAL]
> **Core Architectural Dependency:**  
> A fundamental architectural tension exists between low-latency replicated block storage and cloud-native virtual machine live migration. This document rigorously investigates that interface, evaluates two architectural options, and outlines their failure domains.

---

## 1. Mayastor Storage Engine Mechanics

### 1.1 The Volume Lifecycle & Presentation Pipeline
OpenEBS Mayastor disaggregates storage control from high-throughput I/O processing:

```mermaid
flowchart TD
    subgraph ControlPlane["Kubernetes & Mayastor Control Plane"]
        PVC["PersistentVolumeClaim (PVC)<br/>accessModes: [ReadWriteOnce]"]
        SC["StorageClass (mayastor-nvmf)<br/>protocol: nvmf, replicas: 2 or 3"]
        CSI["Mayastor CSI Controller"]
        CoreAgent["Mayastor Core Agent<br/>(Volume & Replica Placement)"]
    end

    subgraph DataPlane["Worker Nodes (SPDK I/O Plane)"]
        subgraph NodeA["Worker Node 1 (Consumer)"]
            AppPod["KubeVirt virt-launcher Pod"]
            HostInit["Kernel nvme-tcp Initiator<br/>(/dev/nvmeXnY)"]
            Nexus["Mayastor Nexus Controller<br/>(SPDK User-Space Target)"]
            Rep1[("Replica 1 (DiskPool 1)<br/>Local SPDK lvol")]
        end

        subgraph NodeB["Worker Node 2 (Remote)"]
            Rep2[("Replica 2 (DiskPool 2)<br/>Remote SPDK lvol")]
        end

        subgraph NodeC["Worker Node 3 (Remote)"]
            Rep3[("Replica 3 (DiskPool 3)<br/>Remote SPDK lvol")]
        end
    end

    PVC -->|Binds to| SC
    SC --> CSI
    CSI --> CoreAgent
    CoreAgent -->|gRPC Instantiate| Nexus
    CoreAgent -->|Carve Replica| Rep1 & Rep2 & Rep3

    AppPod -->|Raw Block / Mount| HostInit
    HostInit ==>|NVMe-oF / TCP (port 8420)| Nexus
    Nexus ==>|Local Memory Write| Rep1
    Nexus ==>|NVMe-oF Synchronous Write| Rep2
    Nexus ==>|NVMe-oF Synchronous Write| Rep3
```

1. **Volume Creation:** When a PVC references a Mayastor StorageClass, the Mayastor CSI Controller notifies the Core Agent. The Core Agent selects healthy `DiskPool` instances across distinct worker nodes to host the requested number of replicas ($N=2$ or $N=3$).
2. **Nexus Instantiation:** When the pod is scheduled onto a node (Worker 1), the CSI Node Plugin instructs Mayastor to spin up a **Nexus** (an SPDK-based virtual controller) on that node. The Nexus establishes network connections to all remote replica endpoints via NVMe-oF over TCP.
3. **Kernel Attachment:** The CSI Node Plugin invokes the Linux kernel `nvme-tcp` driver to connect to the local Nexus NVMe-oF target (`nvme connect -t tcp -a <nexus-ip> -s 8420 -n <subsystem-nqn>`), exposing a standard block device `/dev/nvmeXnY` on the host.
4. **Presentation to VM:** The block device is bound into the `virt-launcher` container and mapped via QEMU's `-device virtio-blk-pci` or `-device virtio-scsi-pci` driver to the guest OS.

---

## 2. KubeVirt Live Migration Storage Semantics

### 2.1 The Shared Storage Mandate
During KubeVirt live migration:
- The virtual machine instance (VMI) on the **Source Node** remains running and continues executing CPU instructions and dirtying RAM.
- A target `virt-launcher` Pod is launched on the **Destination Node**.
- QEMU on the destination node opens the persistent disk volume to prepare the virtual hardware state.
- **Critical Requirement:** Both the source QEMU process and the destination QEMU process must hold open file descriptors to the persistent volume simultaneously during the pre-copy and handover phases.

### 2.2 Access Modes: RWO vs. RWX
- **`ReadWriteOnce` (RWO):** The volume can be mounted as read-write by a single Kubernetes node at a time. Kubernetes attaches the volume via `VolumeAttachment` API. When a pod migrates to another node, the volume cannot be attached to the target node until it has been completely detached from the source node.
- **`ReadWriteMany` (RWX):** The volume can be mounted simultaneously by multiple nodes in read-write mode. KubeVirt natively validates that PVCs attached to live-migratable VMs support `ReadWriteMany`.

---

## 3. Comparison of Architectural Options

### Option A: Mayastor Replicated Block Storage + NFS-Backed RWX Shared Layer

```mermaid
flowchart LR
    subgraph StorageLayer["Tier 1: High-Performance Block Plane"]
        MSVol["Mayastor RWO Block Volume<br/>(3-Way Replicated NVMe-oF)"]
    end

    subgraph GatewayLayer["Tier 2: Clustered NFS Gateway"]
        NFS["NFS Ganesha / Kernel Server Pod<br/>(Mounts Mayastor RWO PV)"]
        NFSSvc["Kubernetes ClusterIP Service<br/>(port 2049)"]
        NFS --- NFSSvc
        MSVol -->|Formatted XFS/ext4| NFS
    end

    subgraph VirtualizationLayer["Tier 3: KubeVirt Workloads (RWX)"]
        SrcVM["Source virt-launcher Pod<br/>(Worker Node 1)"]
        TgtVM["Target virt-launcher Pod<br/>(Worker Node 2)"]
    end

    NFSSvc ===>|NFSv4 Mount (RWX)| SrcVM
    NFSSvc ===>|Simultaneous Mount (RWX)| TgtVM
```

- **Mechanism:** A centralized NFS server pod consumes a high-performance, 3-way replicated Mayastor RWO persistent volume. The NFS server formats the volume (e.g., ext4/xfs) and exports it via NFSv4. KubeVirt VMs consume this export as an RWX PVC using the Kubernetes `csi-driver-nfs`.
- **Feasibility:** **HIGHLY FEASIBLE & STABLE**. Directly compliant with official KubeVirt live migration specifications.
- **Performance Trade-off:** Layering NFSv4 over NVMe block introduces Linux VFS overhead, network RPC translation, and file locking latency, reducing peak IOPS compared to direct NVMe access.
- **Failure Mode & SPOF:** The NFS server pod represents a **Single Point of Failure (SPOF)**. If the node hosting the NFS gateway crashes, all connected VMs experience I/O hangs until the NFS pod is rescheduled and restarted by Kubernetes.

---

### Option B: Native Mayastor RWX Block Volume Integration

- **Mechanism:** Direct simultaneous attachment of a single Mayastor volume to multiple worker nodes without an intermediate filesystem layer.
- **Status in Mayastor v2.5 / v2.6:** **NOT SUPPORTED FOR GENERAL PRODUCTION / HIGHLY EXPERIMENTAL**.
- **Investigation of Upstream Capabilities:**
  - Mayastor is fundamentally an NVMe block storage provider. NVMe-oF multi-pathing allows multiple paths to a target, but multi-initiator concurrent read/write to a raw block device without a clustered distributed lock manager (like DLM or OCFS2) leads to instantaneous filesystem corruption.
  - While experimental NVMe-oF reservation capabilities (`NVMe PR` - Persistent Reservations) are being researched in upstream SPDK/Mayastor, Mayastor's CSI driver explicitly rejects `ReadWriteMany` requests for standard block volumes.
- **Feasibility:** **UNSUITABLE / EXPERIMENTALLY BLOCKED** for stable live-migration demonstrations in this project milestone.

---

## 4. Technical Trade-Off & Evaluation Matrix

| Architectural Evaluation Criteria | Option A: Mayastor + NFS RWX Gateway | Option B: Native Mayastor RWX Block |
| :--- | :--- | :--- |
| **Official KubeVirt Compatibility** | Fully supported (`accessModes: [ReadWriteMany]`) | Incompatible (Mayastor CSI rejects RWX block PVCs) |
| **Software Complexity** | Moderate (Requires NFS server deployment & CSI NFS driver) | Extremely High (Requires custom NVMe multi-attach controllers) |
| **Peak 4k Random Write IOPS** | Moderate (~25,000 – 45,000 IOPS due to NFS RPC latency) | Maximum (~150,000 – 300,000+ IOPS near raw NVMe wire speed) |
| **Tail Latency ($p_{99}$)** | 2.5 ms – 6.0 ms | Sub-millisecond (< 0.8 ms) |
| **Data Replication & Durability** | Handled natively by Mayastor underneath the NFS mount | Handled natively by Mayastor |
| **Live Migration Downtime** | Minimal (< 150 ms handover pause) | Not achievable without storage migration |
| **Gateway SPOF Risk** | High (NFS server pod failure halts VM disk I/O) | Zero (Nexus controller handles multi-pathing) |
| **Suitability for Project Deliverable** | **RECOMMENDED PRIMARY STRATEGY** | **RETAINED AS COMPARATIVE THEORETICAL STUDY** |

---

## 5. Architectural Recommendation & Dual-Evaluation Strategy

To satisfy both the high-performance storage objective and the virtual machine live-migration requirement, this project adopts a **Dual-Tier Storage Strategy**:

1. **Tier 1 (High-Performance Dedicated VMs — RWO Mode):**
   - High-throughput database or benchmarking virtual machines attach directly to raw Mayastor RWO persistent volumes (`volumeMode: Block`).
   - *Purpose:* Evaluated in Chunk 8 (FIO Benchmarking) to measure raw SPDK user-space performance, NVMe-oF throughput, and minimum latency percentiles.
   - *Limitation:* These VMs are pinned to their host node and do not undergo live migration.

2. **Tier 2 (Live-Migratable Elastic VMs — RWX Mode via NFS Gateway):**
   - Clustered virtual machines requiring dynamic rebalancing and zero-downtime maintenance attach to RWX PVCs backed by the NFS Gateway running on a Mayastor replicated volume.
   - *Purpose:* Evaluated in Chunk 6 (Live Migration) and Chunk 7 (Resource Hot-Plugging).
   - *Benchmarking Value:* Quantifies the exact "virtualization tax"—the measured performance differential between direct Mayastor block I/O vs. shared NFS gateway storage.

---

## 6. Unresolved Storage Questions for Lab Deployment

1. *NFS Recovery Time:* What is the exact guest VM recovery duration (TCP timeout and I/O resumption) when the NFS gateway pod is intentionally killed during a failure drill?
2. *Direct I/O Cache Flags:* Does mounting NFS with `cache=none` prevent page cache bloat inside the NFS server container under sustained 10 GB sequential writes?
