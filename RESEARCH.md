# Technical Research Tracker & Literature Review

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Document Status:** ACTIVE RESEARCH REPOSITORY  
**Governance Scope:** Theoretical Foundations, Standards, and Verification Questions  

---

> [!NOTE]
> **Research Integrity Standard:**  
> This tracker documents technical topics, architectural invariants, official documentation references, and specific empirical questions that must be resolved across project chunks. Research statuses reflect verified theoretical review vs. questions requiring empirical lab confirmation.

---

## Topic Research Matrix

### 1. Kubernetes Architecture & Control Plane Mechanics
- **What Needs to be Researched:** Component topology of `kube-apiserver`, `etcd`, `kube-scheduler`, and `kube-controller-manager`. Specifically, leader election in etcd, API resource versioning, and reconciliation loop mechanics.
- **Why It Matters to Our Project:** Mayastor and KubeVirt both register Custom Resource Definitions (CRDs) and run custom controllers that rely heavily on the Kubernetes API server and watch streams.
- **Official Documentation:** [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- **Important Implementation Questions:** What are the minimum API server request rate limits (`--max-requests-inflight`) needed to prevent throttling when KubeVirt and Mayastor controllers reconcile concurrently?
- **Research Status:** Theoretical review complete; cluster tuning pending Chunk 2.

### 2. Cluster Bootstrapping via `kubeadm`
- **What Needs to be Researched:** Cluster initialization via `kubeadm init`, worker join tokens, certificate rotation, and configuration file structures (`ClusterConfiguration`, `KubeletConfiguration`).
- **Why It Matters to Our Project:** Ensures repeatable, scriptable bare-metal cluster creation that adheres strictly to upstream Kubernetes specifications.
- **Official Documentation:** [kubeadm Overview & Reference](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- **Important Implementation Questions:** How should the `KubeletConfiguration` be structured to guarantee cgroup v2 integration with `systemd` and preserve HugePages for SPDK?
- **Research Status:** Theoretical review complete; pre-flight scripting pending Chunk 1.

### 3. Container Runtime (`containerd`)
- **What Needs to be Researched:** Container Runtime Interface (CRI) plugins, `systemd` cgroup management, image layer caching, and storage drivers in `containerd` v1.7+.
- **Why It Matters to Our Project:** KubeVirt launches `virt-launcher` pods through containerd; improper cgroup driver alignment (`systemd` vs `cgroupfs`) causes kubelet node instability.
- **Official Documentation:** [containerd Documentation](https://containerd.io/docs/)
- **Important Implementation Questions:** Does `containerd` require custom stream server settings or runtime handler registrations to support KubeVirt's virtualization containers?
- **Research Status:** Theoretical review complete; host configuration pending Chunk 1.

### 4. Kubernetes Networking & CNI (Calico / Flannel)
- **What Needs to be Researched:** Pod CIDR allocation, overlay network encapsulation (VXLAN vs. IP-in-IP vs. native BGP routing), and MTU overhead.
- **Why It Matters to Our Project:** NVMe-oF storage traffic and KubeVirt live migration memory streaming require sustained high throughput. Incorrect MTU configuration causes packet fragmentation and severe I/O penalties.
- **Official Documentation:** [Kubernetes Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- **Important Implementation Questions:** Should NVMe-oF traffic use the standard CNI overlay network or a dedicated secondary host network interface to bypass encapsulation overhead?
- **Research Status:** Under active evaluation; network topology design pending Chunk 1.

### 5. KubeVirt Architecture & Controller Subsystem
- **What Needs to be Researched:** Internal interactions between `virt-api`, `virt-controller`, `virt-handler`, and the `virt-launcher` pod wrapper.
- **Why It Matters to Our Project:** KubeVirt is the virtualization engine running guest operating systems as first-class Kubernetes primitives.
- **Official Documentation:** [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- **Important Implementation Questions:** How does `virt-handler` pass host `/dev/kvm` and dynamic storage block devices through to the QEMU process inside `virt-launcher`?
- **Research Status:** Theoretical review complete; operator manifests pending Chunk 5.

### 6. QEMU and Linux KVM Hypervisor
- **What Needs to be Researched:** Kernel-based Virtual Machine (`/dev/kvm`) ioctl interface, hardware virtualization extensions (Intel VT-x / AMD-V), vCPU thread scheduling, and virtio device emulation.
- **Why It Matters to Our Project:** Hardware KVM acceleration is critical to achieving near-native guest VM performance; software emulation (TCG) ruins benchmark validity.
- **Official Documentation:** [KVM Kernel Documentation](https://www.kernel.org/doc/html/latest/virt/kvm/index.html)
- **Important Implementation Questions:** What guest virtio driver settings (`cache=none`, `io=native`) yield optimal latency when backed by an NVMe block volume?
- **Research Status:** Theoretical review complete; hardware validation pending Chunk 1.

### 7. OpenEBS Mayastor Architecture
- **What Needs to be Researched:** Mayastor control plane (REST API, core agent, CSI controller) and data plane (`io-engine` daemonset, SPDK integration, Nexus, DiskPools).
- **Why It Matters to Our Project:** Mayastor is the foundational storage engine responsible for synchronous block replication and NVMe-oF transport.
- **Official Documentation:** [OpenEBS Documentation](https://openebs.io/docs/) | [Mayastor GitHub Repository](https://github.com/openebs/mayastor)
- **Important Implementation Questions:** How does Mayastor handle metadata consensus and dynamic Nexus migration if a storage node hosting the active Nexus fails, and how is this decoupled from Kubernetes etcd Raft quorum?
- **Research Status:** Theoretical review and quorum decoupling clarified in Chunk 1.8 (2026-11-05). Native RWX block volume support investigated in OpenEBS 4.6.x (Mayastor v2.11+). Deployment manifests pending Chunk 3.

### 8. Storage Performance Development Kit (SPDK)
- **What Needs to be Researched:** User-space device drivers, Polled Mode Drivers (PMD), lockless ring buffers, hugepage memory mapping, and zero-copy I/O queues.
- **Why It Matters to Our Project:** SPDK eliminates the Linux kernel context-switch and interrupt handling overhead, providing the theoretical low-latency engine for Mayastor.
- **Official Documentation:** [SPDK Official Documentation](https://spdk.io/)
- **Important Implementation Questions:** How many dedicated CPU cores must be pinned to the SPDK polling loop to saturate a 10 Gbps NVMe-oF network without starving Kubernetes node daemons?
- **Research Status:** Theoretical review complete; core pinning strategy pending Chunk 3.

### 9. NVMe over Fabrics (NVMe-oF / TCP)
- **What Needs to be Researched:** NVMe-oF protocol specifications, transport bindings (RDMA vs. TCP), submission/completion queue mechanics, and the Linux kernel `nvme-tcp` initiator module.
- **Why It Matters to Our Project:** NVMe-oF over TCP serves as the wire protocol carrying block commands between Mayastor Nexus and worker node replicas.
- **Official Documentation:** [NVM Express Standards](https://nvmexpress.org/specifications/)
- **Important Implementation Questions:** What kernel parameters (`nvme_core.multipath`, TCP socket buffer sizes) must be tuned on worker nodes to prevent connection timeouts during sustained heavy writes?
- **Research Status:** Protocol specifications and kernel initiator requirements verified in Chunk 1 (2026-11-04). Documented in docs/network-and-virtualization-requirements.md.

### 10. DiskPools & Cloud-Native Storage Provisioning
- **What Needs to be Researched:** Mayastor `DiskPool` CRD lifecycle, SPDK Logical Volume (`lvol`) allocation, pool exhaustion thresholds, and block device discovery.
- **Why It Matters to Our Project:** DiskPools manage the physical storage capacity on each node and carve out individual volume replicas.
- **Official Documentation:** [OpenEBS Mayastor Storage Pools](https://openebs.io/docs/user-guides/mayastor/diskpools)
- **Important Implementation Questions:** Can a DiskPool safely span multiple physical drives, or should pools strictly map 1:1 to dedicated physical devices?
- **Research Status:** Theoretical review complete; pool CRD design pending Chunk 4.

### 11. Synchronous Volume Replication & Rebuild Mechanics
- **What Needs to be Researched:** Synchronous multi-target writing via Mayastor Nexus, degraded volume states, fast rebuild bitmap algorithms, and full rebuilding.
- **Why It Matters to Our Project:** Ensures zero data loss (RPO = 0) and high availability during node or disk failure events.
- **Official Documentation:** [Mayastor Replicas & Volumes](https://openebs.io/docs/user-guides/mayastor/replicas)
- **Important Implementation Questions:** What is the measured write latency penalty when switching from 2-way replication ($N=2$) to 3-way replication ($N=3$) under 4k random writes?
- **Research Status:** Empirical testing pending Chunk 4 and Chunk 8.

### 12. Kubernetes Container Storage Interface (CSI)
- **What Needs to be Researched:** CSI specification (`CreateVolume`, `NodePublishVolume`, `NodeStageVolume`), VolumeAttachment lifecycle, and dynamic provisioning.
- **Why It Matters to Our Project:** Mayastor's CSI driver bridges Kubernetes PVC requests to Mayastor volume provisioning and host NVMe-oF attachments.
- **Official Documentation:** [Kubernetes CSI Developer Documentation](https://kubernetes-csi.github.io/docs/)
- **Important Implementation Questions:** How does the CSI driver respond when a pod is rescheduled onto a node where the local NVMe-oF target connection was dropped?
- **Research Status:** Theoretical review complete; StorageClass templates pending Chunk 4.

### 13. KubeVirt Virtual Machine Live Migration
- **What Needs to be Researched:** QEMU live migration algorithm (pre-copy iteration, dirty memory page tracking, convergence criteria, and max-downtime thresholds).
- **Why It Matters to Our Project:** Live migration is the cornerstone virtualization capability that allows workload balancing without guest downtime.
- **Official Documentation:** [KubeVirt Live Migration Guide](https://kubevirt.io/user-guide/compute/live_migration/)
- **Important Implementation Questions:** What network bandwidth is required to ensure migration convergence for a VM generating dirty memory pages at 200 MB/s?
- **Research Status:** Theoretical review complete; live migration experiments pending Chunk 6.

### 14. Storage Access Modes: RWX vs. RWO Semantics
- **What Needs to be Researched:** POSIX filesystem concurrency vs. raw block multi-attach; Kubernetes `ReadWriteOnce` vs. `ReadWriteMany` enforcement.
- **Why It Matters to Our Project:** Identifies the fundamental architectural challenge: Mayastor provides RWO block devices, while KubeVirt live migration requires RWX storage access.
- **Official Documentation:** [Kubernetes Persistent Volumes - Access Modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)
- **Important Implementation Questions:** How does Mayastor's native experimental RWX block volume support (introduced in v2.11 / OpenEBS 4.6) coordinate multi-attach without an in-band distributed lock manager, and how does QEMU hypervisor serialization guarantee write safety?
- **Research Status:** Corrected and clarified in Chunk 1.8 (2026-11-05). Detailed findings documented in `docs/storage-architecture-analysis.md` and formalized in ADR-008 and ADR-010. Empirical live-migration testing pending Chunk 6.

### 15. Shared Storage via NFS Gateway Integration
- **What Needs to be Researched:** NFSv4 server export settings, synchronous locking (`sync`, `no_wdelay`), client mount options (`cache=none`, `hard`, `intr`), and CSI NFS drivers.
- **Why It Matters to Our Project:** Implements the proposed RWX shared storage tier for KubeVirt live migration backed by Mayastor PVs.
- **Official Documentation:** [NFS Ganesha / Linux NFS Documentation](https://linux-nfs.org/wiki/index.php/Main_Page)
- **Important Implementation Questions:** What is the throughput and IOPS degradation percentage when layering NFSv4 over a Mayastor NVMe volume compared to direct block mount?
- **Research Status:** Architecture and failure mode analysis completed in Chunk 1 (2026-11-04). Documented in docs/storage-architecture-analysis.md and ADR-004/ADR-008. Gateway recovery drills pending Chunk 6 and Chunk 9.

### 16. CPU Hot-Plugging in Virtualized Environments
- **What Needs to be Researched:** ACPI CPU hot-plug events, Linux guest kernel `cpu/cpu*/online` interfaces, and KubeVirt `vCPU` dynamic scaling specs.
- **Why It Matters to Our Project:** Validates zero-downtime compute elasticity on live virtual machines under variable load.
- **Official Documentation:** [KubeVirt CPU Hotplug](https://kubevirt.io/user-guide/compute/hotplug_cpu/)
- **Important Implementation Questions:** Does CPU hot-unplug work reliably across modern Linux guest kernels, or is hot-plug strictly additive without a restart?
- **Research Status:** Theoretical review complete; test scripts pending Chunk 7.

### 17. Memory Hot-Plugging
- **What Needs to be Researched:** ACPI memory hot-add, Linux guest memory block onlining (`/sys/devices/system/memory`), and Virtio-balloon memory reclamation.
- **Why It Matters to Our Project:** Allows dynamic memory expansion for memory-intensive guest applications without service interruption.
- **Official Documentation:** [KubeVirt Memory Hotplug](https://kubevirt.io/user-guide/compute/hotplug_memory/)
- **Important Implementation Questions:** What are the minimum memory block alignment boundaries (e.g., 128 MiB) enforced by the Linux guest kernel during dynamic memory addition?
- **Research Status:** Theoretical review complete; test scripts pending Chunk 7.

### 18. Persistent Storage Volume Hot-Plugging
- **What Needs to be Researched:** KubeVirt `virtctl addvolume` subresource, dynamic SCSI/virtio-blk controller discovery, and guest kernel block device detection.
- **Why It Matters to Our Project:** Enables attaching high-performance secondary data disks to operational virtual machines on demand.
- **Official Documentation:** [KubeVirt Volume Hotplug](https://kubevirt.io/user-guide/storage/hotplug_volumes/)
- **Important Implementation Questions:** How does Mayastor's CSI driver interact with dynamic volume attachment while the VM launcher pod is already executing?
- **Research Status:** Theoretical review complete; test scripts pending Chunk 7.

### 19. Network Interface Hot-Plugging
- **What Needs to be Researched:** Multus CNI dynamic attachment, virtio-net hot-plugging, and guest interface configuration.
- **Why It Matters to Our Project:** Allows attaching dedicated storage or management networks to running VMs dynamically.
- **Official Documentation:** [KubeVirt Dynamic Network Interface Binding](https://kubevirt.io/user-guide/network/dynamic_interface_binding/)
- **Important Implementation Questions:** Does dynamic interface hot-plug require SR-IOV, or is it supported on standard Linux bridges and Macvlan interfaces?
- **Research Status:** Theoretical review complete; test scripts pending Chunk 7.

### 20. Synthetic Storage Benchmarking via FIO
- **What Needs to be Researched:** `fio` job profiles: direct I/O (`direct=1`), asynchronous engines (`ioengine=libaio` or `ioengine=io_uring`), queue depths (qd=1, 16, 64), block sizes (4k, 64k, 1M), and workload patterns (randread, randwrite, seqread, seqwrite).
- **Why It Matters to Our Project:** Provides standardized, reproducible scientific metrics for IOPS, throughput (MB/s), and tail latency ($p_{95}$, $p_{99}$, $p_{99.9}$).
- **Official Documentation:** [FIO Official Repository & Documentation](https://github.com/axboe/fio)
- **Important Implementation Questions:** What benchmark run time and warmup duration are necessary to ensure steady-state results on NVMe flash devices?
- **Research Status:** Job profiles designed; test automation pending Chunk 8.

### 21. Distributed Fault Injection & Failure Recovery Testing
- **What Needs to be Researched:** Chaos engineering principles for storage: simulated disk pulling, worker node sudden power-off, network partition injection, and Nexus rebuild rate limiting.
- **Why It Matters to Our Project:** Verifies that Mayastor maintains data consistency and recovers automatically without data corruption.
- **Official Documentation:** [OpenEBS Mayastor Troubleshooting & Diagnostics](https://openebs.io/docs/user-guides/mayastor/troubleshooting)
- **Important Implementation Questions:** How long does the Mayastor control plane take to detect an offline replica and initiate rebuild onto a standby pool?
- **Research Status:** Test scenarios planned; test execution pending Chunk 9.

### 22. Observability, Telemetry & Dashboard Engineering
- **What Needs to be Researched:** Prometheus scraping protocols, Mayastor metrics exporters, KubeVirt Prometheus service monitors, and Grafana dashboard design.
- **Why It Matters to Our Project:** Gives real-time visual proof of system health, IOPS spikes, latency histograms, and live-migration progress.
- **Official Documentation:** [Prometheus Documentation](https://prometheus.io/docs/) | [Grafana Documentation](https://grafana.com/docs/)
- **Important Implementation Questions:** What scrape interval balances real-time metric fidelity with minimal CPU scraping overhead on the storage nodes?
- **Research Status:** Architecture planned; dashboard deployment pending Chunk 10.
