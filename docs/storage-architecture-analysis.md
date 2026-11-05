# Storage Architecture & Virtualization Integration Analysis

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Audit Date:** 2026-11-05 (Chunk 1.9 Final Audit)  
**Document Status:** TECHNICAL ARCHITECTURE & RECOVERY SPECIFICATION  
**Focus Area:** Native OpenEBS Mayastor RWX Block Volumes vs. NFS Gateway, Replica Rebuild Mechanics, and Live-Migration Test Suite  

---

> [!CRITICAL]
> **Core Architectural Principles & Clarifications:**  
> 1. **Native RWX Block Support:** OpenEBS Mayastor v2.11+ / OpenEBS v4.6+ introduces **native experimental ReadWriteMany (RWX) block volumes** designed specifically to enable KubeVirt virtual machine live migration without an intermediate NFS layer.
> 2. **Quorum Decoupling:** Mayastor storage data replication, Nexus controller failover, and replica fault tolerance operate as independent data-plane mechanisms and are **completely decoupled** from Kubernetes control-plane (`etcd`) Raft consensus.
> 3. **Degraded State Semantics ($N=3$ on 3-Node Cluster):** In a 3-node cluster with volume replica count $N=3$, failure of a single node leaves the volume in a **Degraded** state (2 surviving replicas). Mayastor **cannot place a replacement replica** because only 2 nodes remain and anti-affinity prevents colocation.
> 4. **Write Log Rebuild Mechanism:** Mayastor utilizes a **write log** tracking dirty ranges/extents (not an in-memory dirty-block bitmap) with a default 10-minute grace period (`--faulted-child-wait-period=10m`) for partial rebuilds.

---

## 1. Storage Replication, Failure Tolerance & Quorum Mechanics

A common architectural misconception is assuming that 3 Mayastor storage replicas participate in or depend on Kubernetes control-plane quorum. In reality, these are two entirely decoupled distributed systems layers operating at different architectural tiers:

```mermaid
flowchart TD
    subgraph ControlPlaneQuorum["Layer 1: Kubernetes Control-Plane Consensus (etcd)"]
        direction TB
        ETCD1["etcd Member 1<br/>(Node 0)"]
        ETCD_NOTE["Consensus Engine: Raft<br/>Quorum Rule: Q = floor(N/2) + 1<br/>Scope: Kubernetes API objects & CRD metadata"]
        ETCD1 --- ETCD_NOTE
    end

    subgraph MayastorDataReplication["Layer 2: Mayastor Volume Data Plane (SPDK / NVMe-oF)"]
        direction TB
        Nexus["Mayastor Nexus Controller<br/>(SPDK User-Space Target on Node 1)"]
        Rep1[("Replica 1<br/>DiskPool 1 (Node 1)")]
        Rep2[("Replica 2<br/>DiskPool 2 (Node 2)")]
        Rep3[("Replica 3<br/>DiskPool 3 (Node 3)")]

        Nexus ==>|Local Memory Direct Write| Rep1
        Nexus ==>|NVMe-oF Synchronous Network Write| Rep2
        Nexus ==>|NVMe-oF Synchronous Network Write| Rep3
        
        REPL_NOTE["Replication Engine: SPDK Nexus Synchronous Multi-Write<br/>Failure Tolerance: Tolerates up to 2 replica failures (for N=3)<br/>Scope: High-throughput NVMe raw block data path"]
        Nexus --- REPL_NOTE
    end
```

### 1.1 Kubernetes Control-Plane Quorum (`etcd`)
- **Consensus Engine:** `etcd` implements the Raft consensus algorithm.
- **Quorum Rule:** Requires an odd number of voting members: $Q = \lfloor M/2 \rfloor + 1$. A 3-node control plane requires 2 members to maintain quorum, tolerating 1 failure. In our candidate architecture with a single dedicated control plane (Node 0), there is **zero control-plane fault tolerance**: losing Node 0 halts API scheduling and pod mutation, regardless of worker node health.
- **Independence from Storage:** If `etcd` loses quorum or Node 0 fails, existing worker pods, KubeVirt virtual machines, and Mayastor SPDK data-plane I/O **continue executing uninterrupted**. The SPDK Nexus communicates directly with NVMe-oF target pools across worker nodes without consulting `etcd` for active I/O transactions.

### 1.2 Mayastor Volume Replication & Target Availability
- **Replica Count ($N=3$):** An $N=3$ volume maintains 3 synchronous copies of raw block data distributed across independent worker nodes' `DiskPools` (Worker 1, Worker 2, Worker 3).
- **Synchronous Write Acknowledgment:** The Nexus (SPDK user-space virtual storage controller) dispatches write commands concurrently across all registered healthy replicas. A write is acknowledged to the client (`virt-launcher` / QEMU) only after all healthy replicas commit the data to non-volatile storage.
- **Single Node Failure Behavior ($N=3$ on a 3-Node Cluster):**
  - If Worker 3 abruptly crashes or suffers network disconnection, the Nexus detects I/O timeout, marks Replica 3 as `Faulted`, and removes it from the active replica set.
  - The volume transitions to **Degraded** status (health state: `DEGRADED`, 2/3 replicas online).
  - **Crucial Engineering Reality:** The volume is **not** in a fully protected state. Client I/O continues uninterrupted on Replicas 1 and 2, but the volume is now operating with reduced redundancy. A second node failure before recovery will reduce the volume to 1 replica (critical degradation).
- **Anti-Affinity & Inability to Place Replacement Replicas:**
  - Mayastor enforces a strict **node and pool anti-affinity policy**: multiple replicas belonging to the same persistent volume cannot be colocated on the same physical host or the same `DiskPool`.
  - In a 3-node worker cluster where 1 node fails, exactly **2 worker nodes remain online**.
  - Because Replica 1 and Replica 2 already occupy DiskPools on Worker 1 and Worker 2, **Mayastor cannot allocate a replacement replica**. The volume must remain in `Degraded` status until Worker 3 is restored or a 4th worker node is joined to the cluster.

---

## 2. Mayastor Rebuild Mechanics: Write Log vs. Discredited Bitmap

When a faulted replica reconnects or a new replica is carved, Mayastor restores volume redundancy through the **Nexus Rebuild Engine**.

```mermaid
sequenceDiagram
    autonumber
    participant Client as Guest VM / QEMU
    participant Nexus as Mayastor Nexus Controller
    participant RepOnline as Replicas 1 & 2 (Healthy)
    participant RepOffline as Replica 3 (Faulted / Recovering)

    Note over Nexus,RepOffline: Worker 3 Disconnects / Network Failure
    Nexus->>Nexus: Mark Replica 3 as Faulted
    Nexus->>Nexus: Start Wait Timer (--faulted-child-wait-period=10m)
    Nexus->>Nexus: Initialize Write Log (Track Dirty Extent Ranges)
    
    Client->>Nexus: Write Block I/O (Sectors 1024-2047)
    Nexus->>RepOnline: Synchronous Write (Success)
    Nexus->>Nexus: Record Extent [1024-2047] in Write Log
    
    Note over Nexus,RepOffline: Worker 3 Reconnects within Grace Period (e.g., at 3m)
    RepOffline->>Nexus: Reconnect NVMe-oF Initiator
    Nexus->>Nexus: Verify Child Identity & Generation Counter
    Nexus->>RepOffline: Replay Extents from Write Log (Partial Rebuild)
    Nexus->>Nexus: Mark Replica 3 Healthy (Status: Online 3/3)
```

### 2.1 The Write Log Mechanism
- **Architecture:** Upstream Mayastor (v2.x / v4.x) tracks uncommitted modifications to faulted replicas using a **Nexus write log** recording dirty address ranges and extents.
- **Clarification:** Earlier community documentation colloquially referred to an "in-memory dirty-block bitmap". The actual SPDK-based Mayastor implementation manages an extent-based range write log in memory on the Nexus node.
- **Default Grace Period (`--faulted-child-wait-period`):**
  - When a replica disconnects, the Nexus does not immediately discard it. It retains the child's registration and accumulates dirty range entries in its write log for a default period of **10 minutes** (`600s`).
  - If the node recovers and reconnects before this timer expires, Mayastor performs a **Partial Rebuild**, transferring only the specific extents recorded in the write log. This minimizes network traffic and restores $N=3$ redundancy in seconds.

### 2.2 Conditions Triggering a Full Rebuild
A **Full Rebuild** (streaming the complete raw block volume byte-for-byte across NVMe-oF) is triggered under any of the following four conditions:
1. **Grace Period Expiration:** The disconnected replica fails to reconnect within the 10-minute `--faulted-child-wait-period`. The Nexus disowns the child, purges the write log, and removes the replica registration.
2. **Device / Pool Destruction:** The underlying NVMe device, partition, or `DiskPool` on the failed node suffered catastrophic corruption or hardware replacement, requiring a completely new, blank replica to be provisioned.
3. **Nexus Host Failure During Child Fault:** If the node hosting the Nexus controller crashes while Replica 3 is already faulted, the in-memory write log is lost upon Nexus recreation. When the new Nexus starts on a surviving node, it cannot verify dirty ranges and must force a full resynchronization.
4. **Write Log Capacity Exhaustion:** If continuous high-throughput random write workloads exhaust allocated write log buffer capacity before child reconnection, the Nexus marks the child for full resynchronization.

---

## 3. KubeVirt Live Migration Storage Semantics

### 3.1 The Shared Storage Requirement
During KubeVirt live migration:
1. The virtual machine instance (VMI) executes on the **Source Worker Node** (Worker 1).
2. A target `virt-launcher` pod is scheduled on the **Destination Worker Node** (Worker 2).
3. Target QEMU initializes virtual hardware and opens the volume to receive CPU register state and dirty RAM pages.
4. **The Live-Migration Invariant:** Both the source QEMU process and the destination QEMU process must access the same underlying persistent storage simultaneously during memory pre-copy and final state handover.

```mermaid
sequenceDiagram
    autonumber
    participant SrcQEMU as Source QEMU (Worker 1)
    participant TgtQEMU as Target QEMU (Worker 2)
    participant MayastorNexus as Mayastor Nexus Target
    participant RepPools as Replicas (DiskPools 1, 2, 3)

    Note over SrcQEMU,MayastorNexus: Normal Execution (Source VM running)
    SrcQEMU->>MayastorNexus: Active Read/Write I/O
    MayastorNexus->>RepPools: Synchronous Replication

    Note over SrcQEMU,TgtQEMU: Live Migration Initiated (RAM Pre-Copy Phase)
    TgtQEMU->>MayastorNexus: Multi-Attach NVMe-oF Connect (RWX Mode)
    SrcQEMU->>TgtQEMU: Iterative Dirty RAM Page Transfer (TCP)
    SrcQEMU->>MayastorNexus: Active Writes Continue from Source Only

    Note over SrcQEMU,TgtQEMU: Handover Phase (Convergence Reached)
    SrcQEMU->>SrcQEMU: Pause Guest vCPUs (<100ms)
    SrcQEMU->>MayastorNexus: Flush In-Flight I/O (fsync/drain)
    SrcQEMU->>TgtQEMU: Transfer Final CPU Registers & Device State
    TgtQEMU->>MayastorNexus: Resume Active Read/Write I/O from Target
    SrcQEMU->>MayastorNexus: Detach / Disconnect NVMe-oF Initiator
    Note over TgtQEMU,MayastorNexus: Target VM Running (Migration Complete)
```

### 3.2 Coordination & Concurrency Safety
- **No Distributed Lock Manager (DLM):** Mayastor does *not* incorporate a clustered distributed lock manager (such as DLM or OCFS2). Uncoordinated concurrent writes from two unmanaged initiators to a raw block device will cause catastrophic filesystem corruption.
- **Hypervisor Serialization Guarantee:** Concurrency safety is guaranteed strictly by **QEMU and KubeVirt**:
  - During memory pre-copy, the target QEMU process is passive (`-incoming defer`), issuing zero write commands.
  - At cutover, source QEMU stops issuing writes, flushes pending blocks, and transfers state.
  - Target QEMU resumes execution only after source execution is halted.
  - At no point do two running guest kernels write simultaneously to the storage target.

---

## 4. Native Mayastor RWX Live-Migration Test Plan

To validate the stability, safety, and failure recovery of experimental Native RWX block volumes with KubeVirt, the project defines an explicit **6-Scenario Test Plan**:

```mermaid
flowchart TD
    subgraph TestSuite["Native RWX Live-Migration Test Suite"]
        direction TB
        S1["Scenario 1: Clean Live Migration<br/>(Baseline Performance & Handover Duration)"]
        S2["Scenario 2: Migration Cancellation & Retry<br/>(Aborted Pre-Copy & Multi-Attach Cleanup)"]
        S3["Scenario 3: Source Node Crash During Migration<br/>(Host Death, Lease Expiry & Failover)"]
        S4["Scenario 4: Inter-Node Network Partition<br/>(Split-Brain Resistance & QEMU Timeout)"]
        S5["Scenario 5: Interrupted Migration Recovery<br/>(Target Pod Termination & Lock Cleanup)"]
        S6["Scenario 6: Exclusive Write Safety Verification<br/>(I/O Counter Audit Across Pre-Copy & Cutover)"]
        
        S1 --> S2 --> S3 --> S4 --> S5 --> S6
    end
```

### Scenario 1: Clean Live Migration Between Worker Nodes
- **Objective:** Quantify baseline migration handover duration, network bandwidth consumption, and verify zero I/O error or guest crash.
- **Pre-Conditions:**
  - 3 healthy worker nodes.
  - VM running on Worker 1 with a Mayastor Native RWX block PVC (`volumeMode: Block`, `accessModes: [ReadWriteMany]`).
  - Active synthetic workload running inside guest: `fio --rw=randwrite --bs=4k --ioengine=libaio --direct=1 --verify=crc32c --do_verify=1`.
- **Execution Steps:**
  1. Record baseline IOPS, latency, and guest uptime.
  2. Execute `virtctl migrate <vm-name>`.
  3. Monitor `kubectl get vmi <vm-name> -o wide --watch`.
  4. Track dual NVMe-oF initiator attachments on Worker 1 and Worker 2 via `nvme list-subsys`.
  5. Measure cutover pause time (sub-second target: $< 150\text{ ms}$).
  6. Confirm migration reaches `Succeeded` state and VMI node changes to Worker 2.
- **Pass Criteria:**
  - `fio` completes with zero checksum verification failures (`crc32c` match).
  - VM uptime remains continuous without guest OS reboot.
  - NVMe-oF connection on Worker 1 cleanly tears down after migration completion.

### Scenario 2: Migration Cancellation and Retry
- **Objective:** Verify system stability and resource cleanup when a user or controller cancels an active migration mid-flight.
- **Pre-Conditions:**
  - VM generating dirty memory pages at high rate (`stress-ng --vm 2 --vm-bytes 1G --vm-hang 0`).
  - Storage workload generating continuous NVMe-oF writes.
- **Execution Steps:**
  1. Initiate migration: `virtctl migrate <vm-name>`.
  2. While migration status is in `Running` (iterative pre-copy phase), trigger cancellation: `virtctl cancel-migration <vm-name>`.
  3. Monitor target `virt-launcher` pod termination on Worker 2.
  4. Verify Worker 2 unmounts and detaches the Mayastor volume cleanly.
  5. Re-trigger migration: `virtctl migrate <vm-name>`.
- **Pass Criteria:**
  - Active source VM experiences zero interruption or crash upon cancellation.
  - Target pod terminates without leaving orphaned NVMe-oF initiator sessions on Worker 2.
  - Subsequent migration attempt succeeds cleanly.

### Scenario 3: Source Node Crash During Active Migration
- **Objective:** Evaluate failure isolation and data safety if the source physical node abruptly dies during active memory pre-copy.
- **Pre-Conditions:**
  - VM actively migrating from Worker 1 to Worker 2.
  - Workload issuing continuous writes with data checksumming.
- **Execution Steps:**
  1. During active memory transfer, inject a hard kernel panic on Worker 1:
     `echo c > /proc/sysrq-trigger` (or physical host power-off).
  2. Observe Kubernetes node controller detect Worker 1 `NotReady` upon lease expiration.
  3. Observe KubeVirt mark the in-flight migration as `Failed`.
  4. Observe automated rescheduling / pod cleanup behavior on surviving nodes.
  5. Verify surviving Mayastor DiskPools (Worker 2 & Worker 3) maintain replica consistency.
  6. Restart VM on Worker 2 and execute volume integrity check (`e2fsck -f` / `xfs_repair -n`).
- **Pass Criteria:**
  - Storage volume data on surviving Mayastor replicas is uncorrupted up to the last confirmed synchronous write.
  - Target partial `virt-launcher` does not attempt conflicting writes.
  - Volume successfully attaches to new VM instance upon node recovery.

### Scenario 4: Inter-Node Network Partition During Migration
- **Objective:** Verify split-brain prevention when inter-node migration traffic is severed while storage traffic remains active.
- **Pre-Conditions:**
  - Live migration in progress between Worker 1 and Worker 2.
- **Execution Steps:**
  1. Inject an `iptables` drop rule blocking QEMU migration port (`TCP 49152+`) between Worker 1 and Worker 2.
  2. Keep NVMe-oF storage network (`TCP 8420 / 4420`) intact.
  3. Observe QEMU migration timeout handling.
- **Pass Criteria:**
  - KubeVirt detects QEMU migration socket timeout and marks migration `Failed`.
  - Source VM on Worker 1 retains exclusive authority and continues servicing guest I/O.
  - Target QEMU process on Worker 2 aborts without asserting write access to the Mayastor volume.
  - Mayastor volume exhibits zero metadata corruption.

### Scenario 5: Interrupted Migration Recovery (Target Pod Eviction)
- **Objective:** Test recovery when the destination node suffers resource exhaustion or target pod eviction mid-migration.
- **Pre-Conditions:**
  - Migration actively transferring memory pages.
- **Execution Steps:**
  1. Force-kill the target `virt-launcher` pod on Worker 2: `kubectl delete pod <target-pod> --force --grace-period=0`.
  2. Observe KubeVirt migration reconciliation loop.
  3. Verify Mayastor CSI node unstage and unpublish hooks release the target node connection.
- **Pass Criteria:**
  - Source VM recovers automatically and resumes full execution on Worker 1.
  - Mayastor CSI driver cleanly releases volume attachment on Worker 2 (no stuck multi-attach locks).
  - Storage volume remains healthy and operational.

### Scenario 6: Exclusive Write Safety Verification (Hypervisor Serialization Audit)
- **Objective:** Provide empirical proof that despite multi-attach NVMe-oF capabilities, only one node writes to the block volume at any single point in time.
- **Execution Steps:**
  1. Deploy an eBPF trace script or `iostat -x 1` logging on both Worker 1 and Worker 2 targeting the raw block devices (`/dev/nvmeXnY`).
  2. Trigger clean live migration under heavy write load.
  3. Collate timestamped write sector counts (`wkB/s`, `w/s`) from both worker nodes across all 4 phases:
     - Phase A: Pre-migration execution.
     - Phase B: Iterative memory pre-copy.
     - Phase C: QEMU pause & cutover window.
     - Phase D: Post-migration execution on destination.
- **Pass Criteria:**
  - Phase A & B: 100% of write I/O originates from Worker 1; Worker 2 write rate is exactly **0 kB/s**.
  - Phase C: Write rate on both nodes drops to **0 kB/s** during QEMU guest pause.
  - Phase D: 100% of write I/O originates from Worker 2; Worker 1 write rate drops to exactly **0 kB/s**.
  - Overlap verification: Total duration where both nodes issue writes simultaneously is exactly **0.000 milliseconds**.

---

## 5. Architectural Evaluation & Trade-Off Matrix

| Architectural Evaluation Dimension | Architecture 1: Native Mayastor RWX Block | Architecture 2: NFS-Backed RWX Gateway |
| :--- | :--- | :--- |
| **Upstream Support Status** | **EXPERIMENTAL** (OpenEBS 4.6+ / Mayastor v2.11+) | **DOCUMENTED / STABLE** (CSI NFS Driver) |
| **Supported Volume Mode** | Raw Block Only (`volumeMode: Block`) | Filesystem Only (`volumeMode: Filesystem`) |
| **Protocol Overhead** | **Zero:** Direct kernel NVMe-oF initiator $\rightarrow$ SPDK target | **High:** Linux VFS + RPC encoding + NFS Server $\rightarrow$ NVMe-oF |
| **Estimated 4k Random Write IOPS** | **High:** ~120,000 – 250,000+ IOPS (Near wire speed) | **Moderate:** ~25,000 – 45,000 IOPS |
| **Tail Latency ($p_{99}$)** | **Sub-millisecond:** < 0.8 ms | **Elevated:** 3.0 ms – 7.0 ms |
| **Concurrency Protection** | Hypervisor-level serialization (QEMU/KubeVirt) | POSIX File Locking (NFS server) |
| **Storage Architecture SPOF** | Zero (Nexus controller handles multi-pathing) | High (NFS server pod failure halts all VM I/O) |
| **Suitability for This Project** | **PRIMARY EXPERIMENTAL EVALUATION TARGET** | **CONSERVATIVE FALLBACK BASELINE** |

---

## 6. Strategic Project Deployment Recommendation

To maximize engineering value and academic rigor, the project adopts a **Comparative Dual-Path Strategy**:

1. **Path A — Native Mayastor RWX Block Live Migration (Primary Innovation Focus):**
   - Configure Mayastor StorageClass with `protocol: nvmf` and deploy native `ReadWriteMany` block PVCs for KubeVirt VMs.
   - Execute the complete **6-Scenario Test Plan** to rigorously validate stability, cutover duration, and failure recovery.
   - Quantify raw block performance using FIO.
2. **Path B — NFS-Backed RWX Gateway (Comparative Baseline & Fallback):**
   - Deploy an NFS gateway backed by a Mayastor RWO volume.
   - Run the identical FIO benchmarks and live-migration test suite over NFS.
   - Quantify the exact **"NFS Translation Tax"**: comparing raw NVMe block IOPS, throughput, and tail latency vs. NFS-mediated shared storage.
   - If Path A exhibits irrecoverable bugs during network partition drills, Path B serves as the proven fallback for final project submission.
