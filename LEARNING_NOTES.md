# Systems Engineering & Distributed Storage: Comprehensive Student Study Guide

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Audience:** Undergraduate Systems Engineer / Student Technical Evaluation Preparation  

---

> [!NOTE]
> **Purpose of This Guide:**  
> This study guide provides deep theoretical foundations, architectural context, viva preparation questions, and diagnostic references across all 21 technical domains involved in this project. It is structured to help the student achieve mastery over the complete stack from bare-metal Linux to distributed cloud-native virtualization.

---

## Table of Contents
1. [Linux Fundamentals](#1-linux-fundamentals)
2. [Containers & OCI Architecture](#2-containers--oci-architecture)
3. [Kubernetes Fundamentals](#3-kubernetes-fundamentals)
4. [Kubernetes Networking & CNI](#4-kubernetes-networking--cni)
5. [Distributed Systems Fundamentals](#5-distributed-systems-fundamentals)
6. [Block Storage Architecture](#6-block-storage-architecture)
7. [Storage Replication & Consensus](#7-storage-replication--consensus)
8. [Storage Performance Development Kit (SPDK)](#8-storage-performance-development-kit-spdk)
9. [NVMe over Fabrics (NVMe-oF)](#9-nvme-over-fabrics-nvme-of)
10. [OpenEBS Mayastor Architecture](#10-openebs-mayastor-architecture)
11. [Virtualization Principles](#11-virtualization-principles)
12. [QEMU and Linux KVM Hypervisor](#12-qemu-and-linux-kvm-hypervisor)
13. [KubeVirt Architecture & Operators](#13-kubevirt-architecture--operators)
14. [Virtual Machine Live Migration](#14-virtual-machine-live-migration)
15. [CPU Hot-Plugging](#15-cpu-hot-plugging)
16. [Memory Hot-Plugging](#16-memory-hot-plugging)
17. [Storage Volume Hot-Plugging](#17-storage-volume-hot-plugging)
18. [Network Interface Hot-Plugging](#18-network-interface-hot-plugging)
19. [Storage Performance Benchmarking (FIO)](#19-storage-performance-benchmarking-fio)
20. [Failure Modes & Recovery Drills](#20-failure-modes--recovery-drills)
21. [Monitoring, Telemetry & Observability](#21-monitoring-telemetry--observability)

---

## 1. Linux Fundamentals
- **Concept:** Kernel space vs. user space, virtual memory subsystems, HugePages, cgroups v2, and systemd process management.
- **Explanation:** The Linux operating system enforces hardware privilege boundaries through CPU ring levels (Ring 0 for the kernel, Ring 3 for user applications). Memory is managed in 4 KiB pages via virtual memory translation tables (MMU). HugePages (e.g., 2 MiB or 1 GiB) reduce page table entries and Translation Lookaside Buffer (TLB) misses, providing deterministic low-latency access for database and storage memory pools. Control Groups (cgroups v2) enforce resource limits on CPU, memory, and I/O.
- **Why It Matters:** High-performance storage engines require direct hardware control, minimal kernel intervention, and dedicated memory structures to avoid latency spikes caused by paging and page table walks.
- **Where It Appears in Our Project:** Host node preparation in Chunk 1; reserving 2 MiB HugePages (`/dev/hugepages`) for SPDK; configuring `systemd` cgroup drivers for `containerd`.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  cat /proc/meminfo | grep -i hugepages
  ls -la /sys/fs/cgroup/
  uname -r
  dmesg -T | grep -i kvm
  ```
- **Common Misconceptions:** Assuming HugePages dynamically allocate on demand; SPDK requires HugePages to be pre-allocated at boot or module load time to guarantee contiguous physical address space.
- **Viva / Evaluation Questions:**
  1. *What is a Translation Lookaside Buffer (TLB) miss, and how do 2 MiB HugePages alleviate memory access latency in SPDK?*
  2. *Why must Kubernetes and containerd share the `systemd` cgroup driver rather than `cgroupfs` on modern Linux distributions?*

---

## 2. Containers & OCI Architecture
- **Concept:** Linux namespaces (`pid`, `net`, `mnt`, `ipc`, `uts`, `user`), root filesystems (overlayfs), and the Open Container Initiative (OCI) runtime boundary.
- **Explanation:** Containers are not lightweight virtual machines; they are ordinary Linux processes isolated by kernel namespaces and restricted by cgroups. Container runtimes (e.g., `containerd` via `runc`) configure these namespaces and construct an overlay filesystem layer before invoking the `execve` system call.
- **Why It Matters:** Understanding that container processes share the underlying host kernel explains how storage drivers and character devices (`/dev/kvm`, `/dev/nvme-fabrics`) can be passed into containerized daemons without virtualization overhead.
- **Where It Appears in Our Project:** Running the `containerd` runtime on all nodes; running the Mayastor `io-engine` and KubeVirt `virt-launcher` pods.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  crictl ps
  crictl info
  lsns
  ps aux | grep containerd
  ```
- **Common Misconceptions:** Believing containers emulate hardware or run independent kernels; they execute machine code directly on the host CPU.
- **Viva / Evaluation Questions:**
  1. *Which Linux kernel namespaces provide network isolation vs. process isolation in a container?*
  2. *How does the `privileged: true` security context in a pod manifest alter container isolation?*

---

## 3. Kubernetes Fundamentals
- **Concept:** Declarative state reconciliation, controllers, Custom Resource Definitions (CRDs), and the Kubelet node lifecycle.
- **Explanation:** Kubernetes operates as a distributed state reconciliation engine. Desired state is declared via YAML manifests and stored in `etcd`. Autonomous controllers continuously execute reconciliation loops: `Reconcile() { CurrentState = Observe(); if CurrentState != DesiredState { ActuateChanges(); } }`. The Kubelet acts as the primary node agent communicating with the container runtime via the Container Runtime Interface (CRI).
- **Why It Matters:** Both OpenEBS Mayastor and KubeVirt extend Kubernetes using CRDs (`DiskPool`, `VirtualMachine`, `VirtualMachineInstanceMigration`) and custom operators rather than modifying core Kubernetes binaries.
- **Where It Appears in Our Project:** Cluster initialization with `kubeadm` (Chunk 2); deploying Mayastor and KubeVirt operators.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  kubectl get nodes -o wide
  kubectl get pods -A
  kubectl api-resources
  kubectl describe node <worker-node>
  ```
- **Common Misconceptions:** Believing the Kubelet schedules pods; the `kube-scheduler` assigns pods to nodes, and the Kubelet is responsible only for executing assigned pods on its local node.
- **Viva / Evaluation Questions:**
  1. *What is a CRD, and how does a custom controller observe state changes to custom resources?*
  2. *Explain the role of etcd in Kubernetes and what happens to running workloads if the etcd cluster loses quorum.*

---

## 4. Kubernetes Networking & CNI
- **Concept:** Flat IP-per-pod network model, Container Network Interface (CNI) plugins, encapsulation (VXLAN) vs. routed networking (BGP), and MTU sizing.
- **Explanation:** Kubernetes requires that all pods communicate with all other pods across nodes without NAT. CNI plugins (e.g., Calico, Flannel) implement this requirement. Encapsulated networks (VXLAN) prepend an outer UDP/IP header (typically 50 bytes), reducing the effective payload MTU from 1500 to 1450.
- **Why It Matters:** High-throughput storage protocols (NVMe-oF) and live migration memory streams can saturate network links; packet fragmentation due to incorrect MTU destroys storage throughput and inflates tail latency.
- **Where It Appears in Our Project:** CNI installation in Chunk 2; network interface configuration for storage mesh and migration in Chunks 3 and 6.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  ip link show
  ip route show
  tracepath -n <target-node-ip>
  kubectl get pods -n kube-system -l k8s-app=calico-node
  ```
- **Common Misconceptions:** Assuming pod traffic always passes through Linux `iptables` or `nftables`; modern eBPF and native routed CNI configurations bypass standard netfilter tables entirely.
- **Viva / Evaluation Questions:**
  1. *Why does VXLAN encapsulation introduce CPU and throughput overhead compared to native BGP routing?*
  2. *What is Jumbo Frames (MTU 9000), and why is it advantageous for NVMe-oF storage traffic?*

---

## 5. Distributed Systems Fundamentals
- **Concept:** Failure domains, synchronous vs. asynchronous replication, CAP theorem, split-brain conditions, and quorum consensus.
- **Explanation:** In distributed systems, node crashes and network partitions are inevitable. The CAP theorem proves that under a network partition ($P$), a system must choose between Consistency ($C$) and Availability ($A$). Storage engines protecting block devices must enforce strong consistency ($CP$) to prevent silent data corruption or divergent state across replicas. Quorum requires $Q = \lfloor N/2 \rfloor + 1$ affirmative votes to execute mutations safely.
- **Why It Matters:** Mayastor's synchronous replication requires strict consensus before confirming I/O writes; split-brain prevention is paramount when worker nodes lose connectivity.
- **Where It Appears in Our Project:** 3-node worker architecture (ADR-002); replica rebuilding and failure drills in Chunk 9.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  # Check node latency distribution
  ping -c 100 -i 0.01 <remote-worker-ip>
  ```
- **Common Misconceptions:** Assuming 2-node clusters can achieve high-availability quorum safely; 2-node systems cannot resolve split-brain without an external third-party tie-breaker or witness.
- **Viva / Evaluation Questions:**
  1. *Why does a 3-node storage cluster tolerate the complete loss of 1 node while maintaining quorum, whereas a 2-node cluster cannot?*
  2. *What is the difference between RPO (Recovery Point Objective) and RTO (Recovery Time Objective) in distributed storage?*

---

## 6. Block Storage Architecture
- **Concept:** Block devices, sectors, logical block addressing (LBA), POSIX file systems, and the Linux I/O stack (VFS $\rightarrow$ Block Layer $\rightarrow$ Device Driver).
- **Explanation:** A block device exposes storage as a flat array of fixed-size sectors (e.g., 512 bytes or 4096 bytes) addressable by LBA. Filesystems (ext4, XFS) organize hierarchical directories and files on top of block devices. In traditional Linux, I/O traverses the Virtual File System (VFS), page cache, block layer scheduler (mq-deadline, none), and device driver, triggering CPU hardware interrupts on completion.
- **Why It Matters:** Virtual machines demand raw block devices for virtual disks. Understanding where latency accumulates in the kernel block layer motivates the adoption of user-space bypass engines like SPDK.
- **Where It Appears in Our Project:** Raw disk preparation for Mayastor DiskPools in Chunk 1 and Chunk 4; attaching PVC block devices to KubeVirt VMs in Chunk 5.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT
  fdisk -l /dev/sdb
  blockdev --getss --getpbsz /dev/sdb
  iostat -xz 1
  ```
- **Common Misconceptions:** Believing block storage is slower than file storage; block storage is the primitive foundational layer upon which all file and object storage systems are constructed.
- **Viva / Evaluation Questions:**
  1. *Explain the path of a `write()` system call from a user process down to a physical NVMe disk in a traditional Linux kernel.*
  2. *Why do databases and virtual machine hypervisors often prefer raw block devices (`direct=1` / O_DIRECT) over filesystem-mounted files?*

---

## 7. Storage Replication & Consensus
- **Concept:** Dual-write pipelines, primary-replica topologies, synchronous replication, degraded states, and differential rebuilds.
- **Explanation:** In synchronous storage replication, when a client issues a write command, the primary controller (Nexus in Mayastor) dispatches the write to the local storage engine and simultaneously transmits it across the network to all active remote replicas. The write is only acknowledged to the client once all replicas report successful write completion to non-volatile media.
- **Why It Matters:** Synchronous replication guarantees zero data loss (RPO = 0) upon abrupt node death, but incurs a write-latency penalty equal to the slowest replica acknowledgment.
- **Where It Appears in Our Project:** 2-way and 3-way volume replication in Chunk 4; failure injection and rebuild testing in Chunk 9.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  kubectl get msreplicas -A
  kubectl get msnexus -A
  ```
- **Common Misconceptions:** Assuming asynchronous replication is acceptable for transactional VM root disks; asynchronous replication risks unrecoverable filesystem corruption upon host power loss.
- **Viva / Evaluation Questions:**
  1. *How does network round-trip time (RTT) directly dictate the maximum possible write IOPS in a synchronously replicated block storage volume?*
  2. *What is a dirty-block bitmap and how does it accelerate volume rebuilding after a transient node disconnection?*

---

## 8. Storage Performance Development Kit (SPDK)
- **Concept:** User-space device drivers, Polled-Mode Drivers (PMD), zero-copy DMA, and lockless ring buffers.
- **Explanation:** SPDK is a set of libraries and drivers for building fast, user-mode, polled-mode storage applications. By moving NVMe drivers into user space (using UIO or VFIO kernel frameworks), applications communicate directly with NVMe controllers via PCI BAR registers, eliminating system call context switches. Instead of CPU interrupts, dedicated CPU cores run infinite polling loops checking completion queues.
- **Why It Matters:** SPDK reduces per-I/O software overhead from microseconds to nanoseconds, allowing modern NVMe drives to reach millions of IOPS.
- **Where It Appears in Our Project:** Mayastor `io-engine` daemonset deployment and core pinning in Chunk 3.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  # Check hugepage allocation used by SPDK
  grep -i huge /proc/meminfo
  # Check if VFIO / UIO modules are loaded
  lsmod | grep -E "vfio|uio|nvme"
  ```
- **Common Misconceptions:** Believing SPDK uses 100% CPU because the system is overloaded; an SPDK polling thread continuously polls the NVMe completion queue, appearing as 100% CPU utilization in `top` even when idle.
- **Viva / Evaluation Questions:**
  1. *Why does interrupt-driven I/O fail to scale efficiently on modern PCIe Gen 4/5 NVMe SSDs capable of > 1,000,000 IOPS?*
  2. *What are the architectural trade-offs of dedicating physical CPU cores to SPDK polling threads in a shared Kubernetes worker node?*

---

## 9. NVMe over Fabrics (NVMe-oF)
- **Concept:** NVMe protocol encapsulation across network fabrics (RDMA, TCP, Fibre Channel), submission/completion queues, and NVMe-oF targets/initiators.
- **Explanation:** NVMe over Fabrics extends the low-latency NVMe command set over network transports. In NVMe-oF over TCP, standard 64-byte NVMe submission and 16-byte completion capsules are encapsulated inside TCP/IP packets. The Linux kernel includes an in-tree NVMe-oF initiator module (`nvme-tcp`), allowing a remote node to attach an NVMe target over standard Ethernet and expose it as a local `/dev/nvmeXnY` device.
- **Why It Matters:** Mayastor uses NVMe-oF/TCP as its primary data plane transport, delivering block I/O between the Nexus controller and storage replicas across Kubernetes nodes.
- **Where It Appears in Our Project:** Loading `nvme-tcp` kernel modules on all worker nodes in Chunk 1; dynamic volume export and attachment in Chunks 3–5.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  lsmod | grep nvme_tcp
  nvme list
  nvme discover -t tcp -a <target-ip> -s 8420
  ```
- **Common Misconceptions:** Believing NVMe-oF strictly requires specialized InfiniBand or RoCE RDMA network cards; NVMe-oF over standard TCP works across standard commodity Ethernet switches.
- **Viva / Evaluation Questions:**
  1. *Compare NVMe-oF over TCP with traditional iSCSI in terms of queue architecture and protocol overhead.*
  2. *How does the Linux kernel `nvme-tcp` module map remote NVMe namespaces to local `/dev/nvme*` block devices?*

---

## 10. OpenEBS Mayastor Architecture
- **Concept:** Mayastor Control Plane (Core Agent, REST, CSI), Data Plane (`io-engine`), `DiskPool` CRD, `Nexus`, and block devices (`bdev`).
- **Explanation:** Mayastor is a containerized, declarative distributed block storage orchestrator. Its control plane registers CRDs in Kubernetes and coordinates volume lifecycle. Its data plane runs as a DaemonSet (`io-engine`) containing an embedded SPDK instance on each storage node. A `DiskPool` carves SPDK logical volumes (`lvol`). When a volume is mounted, Mayastor instantiates a `Nexus`—an SPDK virtual controller that mirrors I/O across replicas over NVMe-oF.
- **Why It Matters:** Serves as the central high-performance storage engine underpinning the entire project.
- **Where It Appears in Our Project:** Deployment in Chunk 3; pool configuration in Chunk 4; benchmarking in Chunk 8; recovery in Chunk 9.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  kubectl get diskpools -n mayastor
  kubectl get msnexus -n mayastor
  kubectl get msreplicas -n mayastor
  ```
- **Common Misconceptions:** Assuming Mayastor is a clustered filesystem like CephFS or GlusterFS; Mayastor strictly provisions raw block devices (RWO).
- **Viva / Evaluation Questions:**
  1. *What is the exact function of a Mayastor Nexus, and where is it scheduled relative to the workload pod?*
  2. *What steps does Mayastor take when one of the replicas in a 2-way replicated volume fails during active write I/O?*

---

## 11. Virtualization Principles
- **Concept:** Full virtualization, hardware-assisted virtualization (Intel VT-x / AMD-V), trap-and-emulate, extended page tables (EPT/NPT), and virtio paravirtualization.
- **Explanation:** Virtualization abstracts physical hardware to run multiple guest operating systems concurrently. Hardware virtualization provides root and non-root execution modes (VMX root/non-root). Sensitive CPU instructions execute directly in non-root mode without software binary translation; when an instruction requires hypervisor intervention, a "VM-exit" occurs. Virtio paravirtualization bypasses hardware device emulation by providing standardized hypervisor-aware drivers (virtio-blk, virtio-net, virtio-scsi) with shared ring buffers.
- **Why It Matters:** KubeVirt VMs must run with hardware KVM acceleration and virtio storage drivers to approach bare-metal throughput.
- **Where It Appears in Our Project:** Verifying hardware CPU virtualization flags (`grep -E 'vmx|svm' /proc/cpuinfo`) in Chunk 1; VM specification authoring in Chunk 5.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  egrep -c '(vmx|svm)' /proc/cpuinfo
  kvm-ok
  ls -l /dev/kvm
  ```
- **Common Misconceptions:** Confusing QEMU emulation with KVM virtualization; QEMU performs machine emulation and device modeling, while KVM is the Linux kernel module executing guest code directly on the physical CPU.
- **Viva / Evaluation Questions:**
  1. *What is a VM-exit, and why do frequent VM-exits degrade guest I/O performance?*
  2. *Explain the virtio split-ring buffer mechanism and how it achieves high-throughput data transfer between guest and host.*

---

## 12. QEMU and Linux KVM Hypervisor
- **Concept:** Kernel-based Virtual Machine (`/dev/kvm`), QEMU process model, vhost-user, and hypervisor memory mapping.
- **Explanation:** In the Linux KVM model, every virtual machine is a standard Linux process managed by QEMU. Each virtual CPU (vCPU) is a standard POSIX thread scheduled by the Linux CFS scheduler. Guest physical RAM is simply mmap'd anonymous memory in QEMU's virtual address space. The `/dev/kvm` character device provides `ioctl()` system calls to initialize vCPUs and enter guest execution mode (`KVM_RUN`).
- **Why It Matters:** Inside KubeVirt, each VM is executed by a QEMU process contained inside a Kubernetes pod wrapper (`virt-launcher`).
- **Where It Appears in Our Project:** Host pre-requisite configuration in Chunk 1; debugging guest VM execution in Chunk 5.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  ps -ef | grep qemu-system-x86_64
  virsh list --all
  ```
- **Common Misconceptions:** Assuming KubeVirt replaces QEMU/KVM; KubeVirt manages, schedules, and automates QEMU/KVM inside Kubernetes containers.
- **Viva / Evaluation Questions:**
  1. *How does the Linux kernel treat a QEMU vCPU thread compared to a standard user-space thread?*
  2. *What role does the `virt-launcher` pod play in isolating the QEMU process within Kubernetes cgroups?*

---

## 13. KubeVirt Architecture & Operators
- **Concept:** KubeVirt CRDs (`VirtualMachine`, `VirtualMachineInstance`), `virt-operator`, `virt-api`, `virt-controller`, and `virt-handler`.
- **Explanation:** KubeVirt orchestrates VMs using an operator pattern. A `VirtualMachine` resource defines desired declarative configuration (offline state). When started, `virt-controller` instantiates a `VirtualMachineInstance` (VMI) representing the running instance and generates a corresponding `virt-launcher` Pod. The `virt-handler` DaemonSet on the target node talks to libvirtd/QEMU inside the launcher pod to transition the VM to running state.
- **Why It Matters:** Provides the cloud-native management plane for our virtualized workloads.
- **Where It Appears in Our Project:** Installation in Chunk 5; live migration in Chunk 6; resource hot-plugging in Chunk 7.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  kubectl get vms -A
  kubectl get vmis -A
  virtctl version
  virtctl console <vm-name>
  ```
- **Common Misconceptions:** Believing a VM disk must be an image file on a filesystem; KubeVirt natively supports binding raw block volume PVCs directly to the VM as virtual disks.
- **Viva / Evaluation Questions:**
  1. *What is the difference between a `VirtualMachine` (VM) CR and a `VirtualMachineInstance` (VMI) CR in KubeVirt?*
  2. *How does `virt-handler` communicate with the QEMU process running inside an isolated pod network namespace?*

---

## 14. Virtual Machine Live Migration
- **Concept:** Pre-copy memory iteration, dirty page tracking, migration convergence, pause-and-copy handover, and storage dependency.
- **Explanation:** Live migration transfers a running VM across nodes without disconnecting client TCP sessions. The pre-copy algorithm works in rounds: Round 1 copies all RAM. Subsequent rounds copy only pages dirtied during the previous round. When the dirty rate drops below network transfer capacity (or max downtime threshold is reached), QEMU briefly pauses the source VM, copies final CPU registers and remaining dirty pages, and resumes the target VM.
- **Why It Matters:** Demonstrates enterprise high-availability and workload rebalancing across Kubernetes nodes.
- **Where It Appears in Our Project:** Live migration implementation and validation in Chunk 6; shared storage design in ADR-004.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  virtctl migrate <vm-name>
  kubectl get vmim -A
  kubectl describe vmim <migration-job-name>
  ```
- **Common Misconceptions:** Assuming live migration has zero downtime; guest execution pauses for a few milliseconds during final state handover (typically 50–150 ms).
- **Viva / Evaluation Questions:**
  1. *What causes live migration "non-convergence," and how do hypervisors resolve it (e.g., auto-converge CPU throttling, post-copy)?*
  2. *Why does KubeVirt require shared storage (RWX) to execute standard live migration without disk replication?*

---

## 15. CPU Hot-Plugging
- **Concept:** ACPI CPU hot-plug events, guest kernel vCPU onlining, KubeVirt dynamic core scaling.
- **Explanation:** Dynamic CPU scaling allows modifying a VM's assigned CPU core count while the guest OS is running. KubeVirt triggers a QEMU device addition command (`device_add`), which emits an ACPI hardware addition interrupt to the guest kernel. The guest kernel initializes the new vCPU and transitions its state to `/sys/devices/system/cpu/cpuX/online = 1`.
- **Why It Matters:** Enables reactive autoscaling for computational workloads inside virtual machines without application downtime.
- **Where It Appears in Our Project:** Hot-plugging evaluation in Chunk 7.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  # Inside guest VM:
  lscpu
  cat /sys/devices/system/cpu/online
  # Host modification:
  kubectl patch vm <vm-name> --type merge -p '{"spec":{"template":{"spec":{"domain":{"cpu":{"cores":4}}}}}}'
  ```
- **Common Misconceptions:** Believing CPU hot-unplug is as universally supported as hot-plug; removing CPUs dynamically often fails in older Linux kernels due to interrupt affinity pinning.
- **Viva / Evaluation Questions:**
  1. *How does an ACPI interrupt notify the guest Linux kernel of newly available vCPUs?*
  2. *What must be pre-configured in the VM template domain spec (`maxSockets`) to allow CPU hot-plugging?*

---

## 16. Memory Hot-Plugging
- **Concept:** ACPI memory hot-add, virtio-balloon driver, memory block onlining.
- **Explanation:** Expanding guest RAM at runtime occurs either via ACPI memory hot-add (adding physical memory blocks in increments such as 128 MiB) or via a dynamic memory ballooning driver (inflating/deflating reserved guest pages back to the hypervisor).
- **Why It Matters:** Allows expanding memory allocations for database caches and memory-intensive applications on demand.
- **Where It Appears in Our Project:** Hot-plugging evaluation in Chunk 7.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  # Inside guest VM:
  free -h
  cat /proc/meminfo
  grep -r . /sys/devices/system/memory/
  ```
- **Common Misconceptions:** Assuming hot-plugged memory is immediately freed back to the host when guest memory pressure drops; memory balloon deflation requires guest cooperation and explicit driver triggering.
- **Viva / Evaluation Questions:**
  1. *Explain the architectural difference between Virtio-balloon memory management and ACPI memory hot-add.*
  2. *Why must hot-plugged memory blocks adhere to specific boundary alignments in the Linux kernel?*

---

## 17. Storage Volume Hot-Plugging
- **Concept:** Dynamic PCI/virtio-scsi device attachment, `virtctl addvolume`, guest kernel LUN discovery.
- **Explanation:** Hot-plugging persistent storage attaches an additional block volume to an already running VM instance. In KubeVirt, `virtctl addvolume` issues an API call that instructs `virt-handler` to mount the secondary PVC on the host and issue a hot-plug attachment command to the running QEMU monitor. The guest kernel's SCSI/virtio subsystem detects the new device and registers `/dev/vdX` or `/dev/sdX`.
- **Why It Matters:** Allows provisioning independent high-performance storage volumes for database partitions or log drives without stopping active services.
- **Where It Appears in Our Project:** Hot-plugging evaluation in Chunk 7.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  virtctl addvolume <vm-name> --volume-name=<pvc-name>
  virtctl removevolume <vm-name> --volume-name=<pvc-name>
  # Inside guest VM:
  dmesg | tail -n 20
  lsblk
  ```
- **Common Misconceptions:** Assuming hot-plugging a volume automatically formats and mounts it inside the guest; the guest OS registers the raw block device, but filesystem creation and mounting must be handled inside the guest.
- **Viva / Evaluation Questions:**
  1. *What underlying QEMU monitor command is triggered when `virtctl addvolume` is executed?*
  2. *How does KubeVirt maintain volume attachment across pod restarts if a hot-plugged volume is marked persistent?*

---

## 18. Network Interface Hot-Plugging
- **Concept:** Multus CNI, dynamic network attachment definitions (NAD), virtio-net hot-plug.
- **Explanation:** In enterprise clusters, VMs often require secondary dedicated network interfaces (e.g., for storage networks, management backplanes, or customer VLANs). Network hot-plugging connects a secondary network interface to a running VM instance by plugging a virtual NIC into the running QEMU PCI bus.
- **Why It Matters:** Enables dynamic network reconfiguration, such as connecting a VM to an isolated Mayastor storage network dynamically.
- **Where It Appears in Our Project:** Hot-plugging evaluation in Chunk 7.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  # Inside guest VM:
  ip link show
  ip addr show
  ```
- **Common Misconceptions:** Assuming standard Kubernetes single-interface CNI supports multiple network interfaces per pod; secondary dynamic interfaces require Multus CNI.
- **Viva / Evaluation Questions:**
  1. *What role does Multus CNI play in enabling multiple network attachments on a single Kubernetes pod or VM launcher?*
  2. *What guest driver is required for dynamic virtio-net interface attachment?*

---

## 19. Storage Performance Benchmarking (FIO)
- **Concept:** IOPS, throughput (MB/s), average latency, tail latency percentiles ($p_{95}, p_{99}, p_{99.9}$), queue depth, direct I/O, and asynchronous I/O engines (`io_uring`, `libaio`).
- **Explanation:** Storage performance cannot be characterized by a single number. Synthetic benchmarking using Flexible I/O Tester (`fio`) evaluates system behavior across a matrix of access patterns (random 4k reads/writes for IOPS and latency; sequential 1M reads/writes for maximum bandwidth). Direct I/O (`direct=1`) ensures the operating system page cache is bypassed, measuring true media and storage engine performance.
- **Why It Matters:** Empirical benchmarking provides the quantitative data required to evaluate Mayastor against standard baseline storage.
- **Where It Appears in Our Project:** Automated benchmark runner suite and result analysis in Chunk 8.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  fio --name=randwrite_test --ioengine=libaio --direct=1 --rw=randwrite --bs=4k --size=1G --numjobs=1 --iodepth=32 --runtime=60 --time_based --group_reporting
  ```
- **Common Misconceptions:** Quoting only average latency; average latency masks catastrophic tail latency spikes ($p_{99.9}$) that cause distributed database timeouts.
- **Viva / Evaluation Questions:**
  1. *Why does increasing queue depth (`iodepth`) increase IOPS up to a saturation point while simultaneously increasing latency?*
  2. *Explain the architectural difference between `libaio` and `io_uring` in the Linux kernel.*

---

## 20. Failure Modes & Recovery Drills
- **Concept:** Chaos engineering, fault injection, degraded pool states, replica reconciliation, and self-healing storage.
- **Explanation:** High-performance storage is useless if it cannot survive hardware failure. Testing involves injecting discrete failure scenarios: (1) dropping network connectivity to a storage node, (2) simulating physical disk detachment, and (3) killing the Mayastor `io-engine` process during active write operations. The control plane must detect the fault, mark the affected replica as degraded, maintain continuous read/write I/O on remaining replicas, and initiate automatic rebuild when a healthy node/disk becomes available.
- **Why It Matters:** Verifies production reliability and fault tolerance under adverse conditions.
- **Where It Appears in Our Project:** Fault injection scripts and recovery analysis in Chunk 9.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  kubectl get msreplicas -A -o wide
  # Check rebuild status in Mayastor
  kubectl get msnode -A
  ```
- **Common Misconceptions:** Believing that data is lost the instant a disk drops offline; in an $N=2$ or $N=3$ replicated volume, client I/O continues uninterrupted on healthy replicas.
- **Viva / Evaluation Questions:**
  1. *What happens to pending in-flight I/O operations when the active Mayastor Nexus node suddenly loses power?*
  2. *What is the difference between a partial (bitmap-based) rebuild and a full rebuild in distributed storage systems?*

---

## 21. Monitoring, Telemetry & Observability
- **Concept:** Time-series telemetry, pull-based metrics scraping, PromQL, Grafana visualization, and latency histograms.
- **Explanation:** Observability provides empirical visibility into distributed systems. Prometheus scrapes metric endpoints (exposed in OpenMetrics format) over HTTP at defined intervals. Mayastor exports low-level SPDK counters and volume latency histograms, while KubeVirt exposes hypervisor and guest telemetry. Grafana visualizes these time series into real-time operational dashboards.
- **Why It Matters:** Provides empirical, visual validation of storage performance and fault recovery during project demonstrations.
- **Where It Appears in Our Project:** Prometheus and Grafana deployment and dashboard templates in Chunk 10.
- **Practical Commands & Diagnostic Checks:**
  ```bash
  curl -s http://<mayastor-metrics-ip>:9502/metrics | grep mayastor
  curl -s http://<node-exporter-ip>:9100/metrics | grep node_disk
  ```
- **Common Misconceptions:** Assuming metrics monitoring is sufficient for debugging all bugs; metrics capture quantitative system state over time, but distributed traces and structured logs are required to debug discrete request failure sequences.
- **Viva / Evaluation Questions:**
  1. *Why are latency histograms preferable to simple counter averages when monitoring storage I/O performance?*
  2. *What is the performance overhead of Prometheus scraping on storage-critical worker nodes, and how can it be minimized?*

---

## 22. Milestone M3 Field Engineering Notes (OpenEBS 4.6.2 / Mayastor v2.12.2)
- **Why Internal `etcd` Needs `localpv-provisioner` Even When LVM/ZFS Are Disabled:** Mayastor stores pool, replica, and nexus topology metadata in its own dedicated 3-replica `openebs-etcd` StatefulSet decoupled from Kubernetes' cluster etcd. By default (`storageClass: mayastor-etcd-localpv`, `openebs.io/local`), those etcd PVCs bind via `provisioner-localpv`. Keeping `engines.local.hostpath.enabled=true` with `localpv-provisioner.hostpathClass.enabled=false` satisfies internal etcd persistence without exposing a generic `hostpath` user StorageClass.
- **Why Static CR Validation Uses Local JSON Schemas:** Because `mayastor-operator-diskpool` installs/reconciles the `diskpools.openebs.io` CRD dynamically, offline `kubeconform -strict` needs [`diskpool_v1beta3.json`](infrastructure/storage/mayastor/schemas/openebs.io/diskpool_v1beta3.json) (compiled from `v1beta3.rs`) to catch `DiskPool` typos before cluster deployment.
- **Why `validate-mayastor-prerequisites.sh` Uses Read-Only `lsblk`:** Never rely on `/dev/nvme0n1` naming guesses or blind `wipefs`. Even unmounted disks can hold existing WSL virtual filesystems or partition tables (`fstype`/`pttype`), so inspect `lsblk -J` fields non-destructively and require persistent `/dev/disk/by-id/` identifiers plus institutional confirmation before `DiskPool` creation.
- **Viva Questions (M3):**
  1. *Why must `hugepages1Gi` remain omitted rather than empty string `""` in upstream `openebs 4.6.2` `values.yaml`?* (`""` fails Kubernetes resource `Quantity` parsing on API validation, whereas omitted renders YAML null tolerated by kube-apiserver.)
  2. *What two conditions must both hold for Mayastor v2.12.2 CSI to allow a `ReadWriteMany` PVC?* (`StorageClass` parameter `rwxBlock: "true"` AND `PersistentVolumeClaim` `spec.volumeMode: Block`; general `RWX` `Filesystem` uses M4/M5 Ganesha NFS gateway.)
