# Diagram 03 — KubeVirt VM Storage Tiers, Live Migration & Hot-Plugging

**Project:** Deploy High-Performance Storage for Kubernetes (`SWFW_5S_08`)  
**Scope Notice:** Manifests (`KubeVirt v1.9.1`, `CDI v1.66.1`, `csi-driver-nfs v4.9.0`), strict CRD schemas, and `--dry-run` checks are `VALIDATED`; live VM boot, cross-node migration, and live hot-plug mutations remain **`INFRASTRUCTURE-DEPENDENT`**.

```mermaid
flowchart LR
    subgraph StorageTiers["VM Persistent Storage & Access-Mode Matrix"]
        T1["RWO Filesystem<br/>vm-ubuntu-rwo-fs<br/>SC: mayastor-nvme-r3-ext4<br/>evictionStrategy: None"]
        T2["RWO Raw Block (Peak I/O)<br/>vm-ubuntu-rwo-block<br/>SC: mayastor-nvme-r3-block<br/>evictionStrategy: None"]
        T3["DEFAULT RWX Migration Tier<br/>vm-ubuntu-migration-nfs<br/>SC: nfs-mayastor-rwx (NFSv4.1)<br/>Backed by mayastor-nfs-server -> RWO"]
        T4["OPT-IN Experimental RWX Block<br/>vm-ubuntu-rwx-block-exp (Manual)<br/>SC: mayastor-nvme-r3-block-rwx<br/>QEMU Pre-Copy Fencing Only (No DLM)"]
    end

    subgraph Migration["Live Migration Flow (TCP 49152-49215, TLS Enabled, Auto-Converge)"]
        SRC["Source KVM Worker<br/>virt-launcher (QEMU q35)<br/>+ cloud-init & qemu-guest-agent"]
        DST["Destination KVM Worker<br/>Target virt-launcher<br/>(32 GB RAM Worker Target)"]
        NFS["storage-nfs/mayastor-nfs-server<br/>ClusterIP :2049 (nfsvers=4.1,hard)"]
        T3 --> SRC & DST
        SRC & DST <-->|"Concurrent RWX Mount"| NFS
        SRC ==>|"Encrypted RAM Pre-Copy Stream<br/>64 MiB/s Cap (default Policy)"| DST
    end

    subgraph HotPlug["Runtime LiveUpdate Hot-Plug (vmRolloutStrategy: LiveUpdate)"]
        HP_CPU["CPU Sockets: 2 -> maxSockets 4<br/>(Shrink requires restart)"]
        HP_MEM["Memory guest: 2Gi -> maxGuest 4Gi<br/>(Pod limit 4608Mi prevents OOM)"]
        HP_DSK["Disk Attach: virtctl addvolume<br/>SCSI bus (5Gi FS / Block)<br/>Unmount guest FS before removevolume"]
    end
```

