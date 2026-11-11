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
- **What Needs to be Researched:** Container Runtime Interface (CRI) plugins, `systemd` cgroup management, image layer caching, and storage drivers in `containerd` 2.3 LTS and 2.2.
- **Why It Matters to Our Project:** KubeVirt launches `virt-launcher` pods through containerd; improper cgroup driver alignment (`systemd` vs `cgroupfs`) causes kubelet node instability. Upstream containerd 1.7 reached EOL on September 30, 2026. Official containerd matrix recommends containerd 2.2 for K8s 1.35 and 2.3 for K8s 1.36+.
- **Official Documentation:** [containerd Documentation](https://containerd.io/docs/)
- **Important Implementation Questions:** Does `containerd` 2.3 LTS operate seamlessly with Kubernetes 1.35 under CRI v1 despite being outside the 1.35 recommendation matrix, and how does containerd 2.2's November 6, 2026 EOL affect deployment?
- **Research Status:** Reconciled in Chunk 1.10 and finalized in Chunk 1.11 (2026-11-05). Because containerd 2.2 reached upstream EOL on November 6, 2026, Candidate B (Kubernetes 1.36.x + containerd 2.3.x LTS) is established as the preferred experimental qualification target; Candidate A (Kubernetes 1.35.x) is retained strictly as an upstream storage-tested comparison baseline.

### 4. Kubernetes Networking & CNI (Calico)
- **What Needs to be Researched:** Pod CIDR allocation, routed BGP networking vs encapsulation, MTU overhead, and Calico v3.33 compatibility.
- **Why It Matters to Our Project:** NVMe-oF storage traffic and KubeVirt live migration memory streaming require sustained high throughput. Incorrect MTU configuration causes packet fragmentation and severe I/O penalties.
- **Official Documentation:** [Calico Documentation](https://docs.tigera.io/calico/latest/about) | [Kubernetes Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- **Important Implementation Questions:** Should NVMe-oF traffic use the standard CNI overlay network or a dedicated secondary host network interface to bypass encapsulation overhead?
- **Research Status:** Calico v3.33 officially qualified for Kubernetes v1.35–v1.37 in Chunk 1.9 (2026-11-05). Native routed BGP mode selected.

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
- **Research Status:** Mayastor v2.12.2 evaluated in Chunk 1.10 and verified in Chunk 1.11 (2026-11-05) as bundled in official published OpenEBS umbrella chart v4.6.x (Mayastor subchart v2.12.2, `io-engine:v2.12.2`). E2E verification confirmed on Kubernetes 1.35.6; qualification on Kubernetes 1.36 to be evaluated in Chunk 2. Decoupling from etcd Raft quorum verified. 6-scenario live migration test suite formulated.

### 8. Storage Performance Development Kit (SPDK)
- **What Needs to be Researched:** User-space device drivers, Polled Mode Drivers (PMD), lockless ring buffers, hugepage memory mapping, and zero-copy I/O queues.
- **Why It Matters to Our Project:** SPDK eliminates the Linux kernel context-switch and interrupt handling overhead, providing the theoretical low-latency engine for Mayastor.
- **Official Documentation:** [SPDK Official Documentation](https://spdk.io/)
- **Important Implementation Questions:** How many dedicated CPU cores must be pinned to the SPDK polling loop to saturate a 10 Gbps NVMe-oF network without starving Kubernetes node daemons?
- **Research Status:** SPDK busy-polling behavior (continuous 100% CPU utilization by design) researched and documented in Chunk 1.9. Dedicated 2-core reservation per worker established; 6-core minimum worker CPU budget enforced.

### 9. NVMe over Fabrics (NVMe-oF / TCP)
- **What Needs to be Researched:** NVMe-oF protocol specifications, transport bindings (RDMA vs. TCP), submission/completion queue mechanics, and the Linux kernel `nvme-tcp` initiator module.
- **Why It Matters to Our Project:** NVMe-oF over TCP serves as the wire protocol carrying block commands between Mayastor Nexus and worker node replicas on TCP 8420 and 4421.
- **Official Documentation:** [NVM Express Standards](https://nvmexpress.org/specifications/)
- **Important Implementation Questions:** What kernel parameters (`nvme_core.multipath`, TCP socket buffer sizes) must be tuned on worker nodes to prevent connection timeouts during sustained heavy writes?
- **Research Status:** Protocol specifications and kernel initiator requirements verified in Chunk 1. Reconciled in Chunk 1.11 into the canonical 20-port matrix (10 host firewall rules including TCP 8420 & 4421, 10 cluster-internal/loopback services; TCP 4420 purged).

### 10. DiskPools & Cloud-Native Storage Provisioning
- **What Needs to be Researched:** Mayastor `DiskPool` CRD lifecycle, SPDK Logical Volume (`lvol`) allocation, pool exhaustion thresholds, and block device discovery.
- **Why It Matters to Our Project:** DiskPools manage the physical storage capacity on each node and carve out individual volume replicas.
- **Official Documentation:** [OpenEBS Mayastor Storage Pools](https://openebs.io/docs/user-guides/mayastor/diskpools)
- **Important Implementation Questions:** Can a DiskPool safely span multiple physical drives, or should pools strictly map 1:1 to dedicated physical devices?
- **Research Status:** Theoretical review complete; pool CRD design pending Chunk 4.

### 11. Synchronous Volume Replication & Rebuild Mechanics
- **What Needs to be Researched:** Synchronous multi-target writing via Mayastor Nexus, degraded volume states, write log dirty extent tracking, grace period timers, and full rebuild triggers.
- **Why It Matters to Our Project:** Ensures zero data loss (RPO = 0) and high availability during node or disk failure events.
- **Official Documentation:** [Mayastor Replicas & Volumes](https://openebs.io/docs/user-guides/mayastor/replicas)
- **Important Implementation Questions:** What is the measured write latency penalty when switching from 2-way replication ($N=2$) to 3-way replication ($N=3$) under 4k random writes? How does Mayastor handle replica replacement when only 2 nodes remain in a 3-node cluster?
- **Research Status:** Rebuild mechanics and configuration timers audited in Chunk 1.11 (2026-11-05). Verified `--faulted-child-wait-period` (default 10m / 600s) on `mayastor-agent-core`; clarified that a standalone `--node-unreachable-timeout` flag does not exist in upstream Mayastor (node loss is governed by Kubernetes node eviction tolerations and NVMe `ctrl_loss_tmo`); documented published vs unpublished volume behavior; anti-affinity barrier prevents replacement on 3-node clusters.

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
- **Important Implementation Questions:** How does Mayastor's native experimental RWX block volume support (bundled in OpenEBS v4.6.x / Mayastor v2.12.2) coordinate multi-attach without an in-band distributed lock manager, and how does QEMU hypervisor serialization guarantee write safety?
- **Research Status:** Audited and formalized in Chunk 1.10 and completed in Chunk 1.11 (2026-11-05). Detailed 6-scenario live-migration test suite (Clean migration, cancellation/retry, source crash, network partition, target eviction, and evidence-based concurrency audit) documented in `docs/storage-architecture-analysis.md` and formalized in ADR-008 and ADR-010. Rigorous single-writer protocol specified with 512-byte fixed binary records, strictly monotonic sequence IDs, writer epochs, CRC32C checksums, QEMU QMP `STOP`/`RESUME` event correlation, and transparent NTP clock drift limitations. Empirical live-migration testing pending Chunk 6.

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

### 23. Local Development Tooling & Lightweight Single-Node Validation Harness
- **What Needs to be Researched:** Development toolchain in WSL2 Ubuntu 24.04 (Docker, containerd, `kubeconform`, `yamllint`, `shellcheck`, lightweight single-node dev cluster via Kind/K3s) with hardware `/dev/kvm` acceleration.
- **Why It Matters to Our Project:** Enables continuous engineering progress, syntax checking, and micro-VM lifecycle testing locally while preserving the full 4-node target architecture for remote hardware deployment.
- **Official Documentation:** [Kubeconform](https://github.com/yannh/kubeconform) | [KubeVirt on Kind](https://kubevirt.io/user-guide/operations/installation/)
- **Important Implementation Questions:** How can KubeVirt's `virt-handler` be configured within a lightweight dev container to reliably access `/dev/kvm` without host memory exhaustion?
- **Research Status:** Local environment verified in Chunk 2.1 (2026-11-05). `/dev/kvm` confirmed active in WSL2 Ubuntu 24.04; Docker v29.1 and containerd v2.2.1 detected. Manifest linting and micro-VM test harness integrated into Milestone 1 and 2.

---

## 24. Milestone M3 Empirical Chart & Source Findings (`openebs 4.6.2` / `mayastor v2.12.2`)
- **Verified Upstream Repository Mapping (2026-11-11):** `helm search repo openebs/openebs` confirms umbrella chart version **`4.6.2`** packages subchart `mayastor` **`2.12.2`** (`docker.io/openebs/mayastor-*:v2.12.2`), `etcd:3.6.4-debian-12-r0`, `nats:2.9.17-alpine`, and `provisioner-localpv:4.6.0` (used exclusively for `mayastor-etcd-localpv`).
- **CSI Driver Provisioner & Parameters (`control-plane/csi-driver` at `v2.12.2`):**
  - Provisioner identifier (`utils::csi_plugin_name`): `io.openebs.csi-mayastor`.
  - Validated `StorageClass` parameters include `protocol`, `repl`, `fsType`, `rwxBlock`, `nvmeIoTimeout`, `nvmeCtrlLossTmo`, `nvmeReconnectDelay`, `nvmeNrIoQueues`, `nvmeKeepAliveTmo`, `poolAffinityTopologyLabel`, `poolHasTopologyKey`, `encrypted`, and `snapshotRestorePolicy`.
  - Confirmed **no `thin` parameter exists** in `v2.12.2` CSI `Parameters`; overcommit/thin-provisioning is controlled globally under `agents.core.capacity.thin.*` in `infrastructure/storage/openebs/values.yaml`.
  - Native Mayastor `ReadWriteMany` rejects `Filesystem` PVCs and enforces both `rwxBlock: "true"` and `volumeMode: Block`.
- **DiskPool Schema (`openebs.io/v1beta3`):** Verified exact `DiskPoolSpec` struct (`node`, `disks`, `topology.labelled`, `encryptionConfig.source.secret.name`, `clusterSize`, `maxExpansion`) from `k8s/operators/src/pool/diskpool/crd/v1beta3.rs` into offline strict schema `infrastructure/storage/mayastor/schemas/openebs.io/diskpool_v1beta3.json`.
- **Compatibility Boundary:** Upstream Mayastor `v2.12.2` automated E2E CI testing ends at Kubernetes `v1.35.6`; static Helm rendering passed against Kubernetes `v1.36.6+k3s1`, while live runtime behavior on `1.36.x` remains `INFRASTRUCTURE-DEPENDENT`.
