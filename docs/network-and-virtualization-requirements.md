# Network Topology, Port Verification & Worker Resource Requirements

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Research Date:** 2026-11-05 (Reassessed & Corrected)  
**Document Status:** TECHNICAL SPECIFICATION, PORT MATRIX & RESOURCE BUDGET  
**Classification:** VERIFIED AGAINST UPSTREAM DOCUMENTATION  

---

## 1. Target Network Architecture & Traffic Classifications

The target cluster network must isolate or logically partition four distinct traffic classifications to prevent I/O starvation and latency jitter:
1. **Cluster Management & Control Traffic:** Kubernetes API calls, `etcd` Raft consensus, Kubelet health probes, and operator reconcile loops.
2. **Pod-to-Pod CNI Overlay / Routed Fabric:** General microservice and inter-pod traffic managed by Calico.
3. **Storage Data Fabric (NVMe-oF / TCP):** High-throughput, sub-millisecond block transport carrying NVMe command and completion capsules between the Mayastor Nexus and distributed `DiskPool` replicas.
4. **Live-Migration Memory Streaming:** High-bandwidth TCP socket stream transferring dirty RAM pages between source and destination `virt-handler` hypervisor daemons.

```mermaid
flowchart TD
    subgraph ControlPlane["Control Plane Network Plane"]
        APIServer["kube-apiserver (:6443)"]
        Etcd["etcd cluster (:2379-2380)"]
    end

    subgraph DataPlaneMesh["Worker Node Data & Storage Mesh"]
        subgraph Node1["Worker Node 1"]
            Kubelet1["Kubelet (:10250)"]
            VH1["virt-handler<br/>(Migration: :49152-49215)"]
            MS1["Mayastor io-engine<br/>(NVMe-oF Target: :8420, gRPC: :10124)"]
        end

        subgraph Node2["Worker Node 2"]
            Kubelet2["Kubelet (:10250)"]
            VH2["virt-handler<br/>(Migration: :49152-49215)"]
            MS2["Mayastor io-engine<br/>(NVMe-oF Target: :8420, gRPC: :10124)"]
        end

        subgraph Node3["Worker Node 3"]
            Kubelet3["Kubelet (:10250)"]
            MS3["Mayastor io-engine<br/>(NVMe-oF Target: :8420, gRPC: :10124)"]
        end
    end

    APIServer <==>|Node Management| Kubelet1 & Kubelet2 & Kubelet3
    VH1 <==>|Live Migration RAM Stream (:49152-49215)| VH2
    MS1 <===>|Synchronous NVMe-oF Replication (:8420)| MS2
    MS1 <===>|Synchronous NVMe-oF Replication (:8420)| MS3
```

---

## 2. Rigorously Validated Port & Protocol Matrix

Every port has been verified against official upstream documentation, with strict segregation between control planes and data fabrics:

| Component / Subsystem | Port / Range | Protocol | Traffic Category | Source | Destination | Official Architectural Purpose | Documentation Source |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Kubernetes API** | `6443` | TCP | Control Plane | Workers, Admins, Controllers | Control Plane | Core Kubernetes API Server entry point | [K8s Ports Reference](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) |
| **etcd Database** | `2379` | TCP | Control Plane | kube-apiserver | Control Plane | etcd client API queries | [K8s Ports Reference](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) |
| **etcd Peer** | `2380` | TCP | Control Plane | etcd peers | Control Plane | etcd Raft peer consensus | [K8s Ports Reference](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) |
| **Kubelet API** | `10250` | TCP | Control Plane | Control Plane, Metrics Server | All Nodes | Pod lifecycle, stats, logs, exec streams | [K8s Ports Reference](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) |
| **Controller Manager**| `10257` | TCP | Control Plane | Localhost / Self | Control Plane | kube-controller-manager health | [K8s Ports Reference](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) |
| **Scheduler** | `10259` | TCP | Control Plane | Localhost / Self | Control Plane | kube-scheduler health | [K8s Ports Reference](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) |
| **Calico BGP** | `179` | TCP | CNI Fabric | Worker Nodes | Worker Nodes | Calico native routed pod mesh (BGP peer) | [Calico Network Requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) |
| **Calico VXLAN** | `4789` | UDP | CNI Fabric | Worker Nodes | Worker Nodes | Fallback overlay encapsulation | [Calico Network Requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) |
| **Calico Typha** | `5473` | TCP | CNI Fabric | Calico Nodes | Calico Typha | Datastore proxy in larger clusters | [Calico Network Requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) |
| **Mayastor NVMe-oF**| `8420` | TCP | Storage Data | Worker Initiators | Worker Nexus / Replicas | Primary NVMf target (NVMe over TCP data transport) | [Mayastor Prerequisites](https://openebs.io/docs/user-guides/mayastor/prerequisites) |
| **Mayastor NVMf (Alt)**| `4421` | TCP | Storage Data | Worker Initiators | Worker Nexus / Replicas | Secondary/alternative NVMf target data transport | [Mayastor Prerequisites](https://openebs.io/docs/user-guides/mayastor/prerequisites) |
| **Mayastor gRPC** | `10124` | TCP | Storage Control| Mayastor Core Agent | Worker `io-engine` | Internal SPDK daemon pool management | [Mayastor Architecture](https://openebs.io/docs/user-guides/mayastor/architecture) |
| **Mayastor REST API**| `8080` / `8081`| TCP | Storage Control| Admin / CLI / CSI | Core Agent Pods | Mayastor REST API and CSI controller | [Mayastor Architecture](https://openebs.io/docs/user-guides/mayastor/architecture) |
| **Mayastor Metrics** | `9502` | TCP | Observability | Prometheus Server | Worker `io-engine` | Storage engine Prometheus metrics exporter | [Mayastor Monitoring](https://openebs.io/docs/user-guides/mayastor/monitoring) |
| **KubeVirt API** | `8443` | TCP | Virt Control | kube-apiserver | `virt-api` Pods | Aggregated API server webhook & console router | [KubeVirt Install Guide](https://kubevirt.io/user-guide/operations/installation/) |
| **KubeVirt Operator** | `8444` | TCP | Virt Control | kube-apiserver | `virt-operator` Pods | Operator metrics and webhook admission | [KubeVirt Install Guide](https://kubevirt.io/user-guide/operations/installation/) |
| **KubeVirt Migration**| `49152–49215`| TCP | Virt Data | Source `virt-handler` | Target `virt-handler` | QEMU pre-copy live migration socket stream | [KubeVirt Live Migration](https://kubevirt.io/user-guide/compute/live_migration/) |
| **KubeVirt Metrics** | `8186` | TCP | Observability | Prometheus Server | `virt-handler` Pods | Hypervisor and VM runtime metrics | [KubeVirt Monitoring](https://kubevirt.io/user-guide/operations/monitoring/) |
| **NFS Gateway** | `2049` | TCP | Shared Storage | KubeVirt VMs, Workers | NFS Server Pod | Shared filesystem mount for RWX fallback VMs | [Linux NFS Documentation](https://linux-nfs.org/wiki/index.php/Main_Page) |
| **RPCbind (NFS)** | `111` | TCP/UDP | Shared Storage | KubeVirt VMs, Workers | NFS Server Pod | RPC port mapper for NFS client mounts | [Linux NFS Documentation](https://linux-nfs.org/wiki/index.php/Main_Page) |

### Multus CNI Network Port Clarification
- **Important Architectural Finding:** Multus CNI does **not** listen on any TCP or UDP network port.
- Multus is a meta-plugin that executes as an in-process binary invoked directly by `containerd` via the standard Linux CNI domain socket (`/run/containerd/containerd.sock` and `/etc/cni/net.d/`). Secondary interfaces attached by Multus (e.g., bridge, macvlan, or host-device) operate directly at Layer 2 or Layer 3 according to their respective network definitions.

---

## 3. Virtualization Feasibility & Hypervisor Primitives

1. **Hardware Virtualization Flag:** Processors on worker nodes must expose hardware virtualization extensions:
   - Intel: `VT-x` (`vmx` flag in `/proc/cpuinfo`).
   - AMD: `AMD-V` (`svm` flag in `/proc/cpuinfo`).
2. **KVM Character Device (`/dev/kvm`):** Must be accessible with read/write permissions for container virtualization (`chmod 666 /dev/kvm`).
3. **Software Emulation (TCG) Unacceptability:** If `/dev/kvm` is missing, KubeVirt can fall back to QEMU Tiny Code Generator (TCG) emulation (`developerConfiguration: useEmulation: true`). Under TCG, CPU instruction translation reduces throughput by **10x to 50x**, rendering synthetic storage benchmarks invalid. Hardware KVM pass-through is therefore a mandatory gating requirement.

---

## 4. Worker Node Resource Dimensioning & Capacity Planning

To prevent Out-Of-Memory (OOM) evictions and CPU starvation on storage nodes, worker node memory and CPU allocations were rigorously dimensioned:

### 4.1 Granular Worker Node Memory Budget Breakdown

| Subsystem Component | Memory Required per Worker Node | Architectural Sizing Justification |
| :--- | :--- | :--- |
| **Linux Host OS & Kernel** | **1.5 – 2.0 GiB** | Ubuntu Server 24.04 kernel structures, page tables, systemd, SSH, and buffer caches. |
| **Kubernetes Node Daemons** | **1.5 – 2.0 GiB** | `kubelet` (~500 MB), `containerd` runtime (~800 MB), Calico CNI agent (`calico-node` ~300 MB), `kube-proxy` (~100 MB). |
| **Pre-Allocated HugePages (SPDK)**| **2.0 GiB (Mandatory Lockout)** | **1024 pages of 2 MiB HugePages** pre-allocated for SPDK memory pools. *Crucial:* Linux removes HugePages entirely from available OS physical memory. Standard pods cannot allocate this memory. |
| **Mayastor `io-engine` Heap** | **1.0 – 1.5 GiB** | User-space process heap, gRPC buffers, NVMe-oF queue metadata, and SPDK thread-local memory. |
| **KubeVirt Hypervisor Daemons** | **0.8 – 1.0 GiB** | `virt-handler` DaemonSet (~400 MB) plus QEMU `virt-launcher` container cgroup overhead (~256–512 MB per VM instance). |
| **Monitoring & Logging Agents** | **0.5 GiB** | `node-exporter` (~150 MB), Mayastor stats exporter (~150 MB), Promtail/Fluentd (~200 MB). |
| **NFS Gateway Pod (If Co-located)**| **0.5 – 1.0 GiB** | NFS Ganesha / kernel-server pod plus XFS/ext4 directory metadata caches (applicable on the worker hosting the gateway). |
| **Subtotal (Idle Infrastructure Node):**| **~8.5 GiB RAM** | **Absolute baseline required just to run the host, storage engine, and virtualization daemons without any guest VM workloads.** |

### 4.2 Workload Allocations & Live-Migration Sizing Impact

When active guest virtual machines and live migrations are introduced:
1. **Single 4 GB Guest Virtual Machine:**
   - 4.0 GiB guest RAM + 0.5 GiB QEMU overhead = **4.5 GiB**.
   - Total Node Load: $8.5 + 4.5 =$ **13.0 GiB RAM**.
2. **Transient Live-Migration Handover Impact:**
   - During live migration, the **Destination Worker Node** must allocate the full memory footprint of the incoming VM *while the source VM is still alive and running on the source node*.
   - Destination Node Memory Required: $8.5 \text{ GiB (Base)} + 4.5 \text{ GiB (Incoming VM)} =$ **13.0 GiB RAM**.
3. **Single 8 GB Guest Virtual Machine (or Two 4 GB VMs):**
   - 8.0 GiB guest RAM + 1.0 GiB QEMU overhead = **9.0 GiB**.
   - Total Node Load: $8.5 + 9.0 =$ **17.5 GiB RAM**.

---

### 4.3 Sizing Targets & Planning Guidance

- **Minimum Planning Target: 16 GB RAM per Worker Node**
  - *Viability:* **MINIMUM FUNCTIONAL BASELINE**.
  - *Capacity:* Supports the idle infrastructure stack (~8.5 GiB) plus **one 4 GB guest virtual machine** (13.0 GiB total). Leaves ~3.0 GiB headroom for live migration buffer and burstable caches.
  - *Constraint:* Cannot run two concurrent VMs on the same worker node without risking memory pressure or Kubelet eviction.
- **Preferred Target: 32 GB RAM per Worker Node**
  - *Viability:* **RECOMMENDED BENCHMARK BASELINE**.
  - *Capacity:* Comfortably supports 8 GB workload VMs, concurrent multi-VM test matrices, live-migration transient dual-allocations, the NFS gateway, and high-throughput FIO I/O ring buffers without any memory pressure.
- **CPU Allocation Targets:**
  - *Minimum:* **4 Physical CPU Cores** (1 core dedicated to SPDK polling, 1 core for OS/Kubernetes, 2 cores for guest vCPUs).
  - *Preferred:* **8 Physical CPU Cores** (2 cores dedicated to SPDK polling, 2 cores for OS/Kubernetes, 4 cores for guest vCPUs).
