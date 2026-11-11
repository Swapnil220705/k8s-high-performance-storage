# Diagram 02 — Mayastor Storage Architecture, Replication & Rebuild Flow

**Project:** Deploy High-Performance Storage for Kubernetes (`SWFW_5S_08`)  
**Scope Notice:** OpenEBS `4.6.2` / Mayastor `v2.12.2` configuration, `DiskPool v1beta3` schemas, StorageClasses, and safety gates are `IMPLEMENTED` and statically `VALIDATED`; SPDK data-plane execution and replica rebuilds are **`INFRASTRUCTURE-DEPENDENT`** (target `>=3` NVMe workers).

```mermaid
flowchart TB
    subgraph ClientPlane["Consumer Node Data Access (Kernel NVMe-oF TCP Initiator)"]
        APP["KubeVirt virt-launcher Pod or Container Workload<br/>PVCs: mayastor-nvme-r3-block (Raw) / mayastor-nvme-r3-ext4 (ext4)"]
        CSIN["openebs-csi-node DaemonSet<br/>(nvme connect -t tcp -> /dev/nvmeXnY)"]
    end

    subgraph TargetPlane["Target SPDK Nexus Controller (User-Space Polled-Mode Driver)"]
        NEXUS["Mayastor Nexus (io-engine :v2.12.2)<br/>Synchronous Multi-Write Coordinator (2 Dedicated Cores, 2Gi HugePages)"]
    end

    subgraph ReplicaPools["Synchronous 3-Way Replication Across Worker DiskPools (repl=3)"]
        R1[("Replica 1 — Worker 1<br/>mayastor-pool-worker-1 (rack-1)<br/>Local Direct Memory Bdev")]
        R2[("Replica 2 — Worker 2<br/>mayastor-pool-worker-2 (rack-2)<br/>NVMe-oF TCP :8420 / :4421")]
        R3[("Replica 3 — Worker 3<br/>mayastor-pool-worker-3 (rack-3)<br/>NVMe-oF TCP :8420 / :4421")]
    end

    subgraph RebuildFSM["Degraded Volume & Rebuild State Machine (Decoupled from etcd Raft Quorum)"]
        S_ON["Online (3/3 Replicas)"] -->|"Worker / io-engine Fault"| S_DEG["Degraded (2/3)<br/>I/O Continues; Write Log Dirty Extents"]
        S_DEG -->|"3-Node Anti-Affinity Barrier"| S_WAIT["Cannot Allocate 4th Replica on Surviving 2 Nodes"]
        S_DEG -->|"Faulted Child Returns < 10m<br/>(--faulted-child-wait-period=10m)"| S_PART["Partial Rebuild<br/>(Replay Write-Log Delta Only)"]
        S_DEG -->|"Outage > 10m or Log Overflow"| S_FULL["Full Rebuild<br/>(Copy Complete Extent Bitmap)"]
        S_PART --> S_ON
        S_FULL --> S_ON
    end

    APP --> CSIN -->|"NVMe-oF TCP (:8420)"| NEXUS
    NEXUS ==>|"Sync Write #1"| R1
    NEXUS ==>|"Sync Write #2 (TCP :8420)"| R2
    NEXUS ==>|"Sync Write #3 (TCP :8420)"| R3
```

