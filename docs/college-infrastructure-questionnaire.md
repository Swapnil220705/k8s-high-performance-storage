# College Infrastructure Requirements & Discovery Questionnaire

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Document Status:** FORMAL INQUIRY SPECIFICATION  
**Target Audience:** College Laboratory Administrator, Department Systems Engineer, or Faculty Mentor  

---

> [!IMPORTANT]
> **Context for Laboratory Administrators:**  
> This project implements a high-performance distributed block storage cluster (OpenEBS Mayastor with SPDK and NVMe over Fabrics) integrated with cloud-native virtualization (KubeVirt) on Kubernetes. To execute real-world performance benchmarking and fault-tolerance drills without financial cost, the deployment is designed to run on physical or high-spec hypervisor-hosted Linux laboratory servers.

---

## 1. Technical Infrastructure Requirements Breakdown

### 1.1 Node Topology & Sizing Specifications

To achieve true distributed consensus, synchronous 3-way data replication, and virtual machine live migration, the target cluster requires **1 Control Plane Node** and **3 Dedicated Storage & Virtualization Worker Nodes**:

| Node Role | Minimum Specification (Functional Baseline) | Preferred Specification (Optimal Benchmarking) | Critical Architectural Function |
| :--- | :--- | :--- | :--- |
| **Control Plane (Node 0)** | • 2 Physical CPU Cores (x86_64)<br/>• 4 GB RAM<br/>• 40 GB Storage (OS & etcd)<br/>• 1x 1 Gbps NIC | • 4 Physical CPU Cores (x86_64)<br/>• 8 GB RAM<br/>• 100 GB SSD (High write endurance for etcd)<br/>• 1x 1 Gbps / 10 Gbps NIC | Hosts Kubernetes API Server, etcd database, scheduler, controller-manager, and Mayastor control plane agents. Untainted for workloads in minimal setups. |
| **Worker Node 1 (Storage + VM)** | • 4 Physical CPU Cores (x86_64)<br/>• 16 GB DDR4/DDR5 RAM<br/>• 40 GB OS Disk<br/>• 1x Dedicated 50+ GB SSD/NVMe<br/>• 1x 1 Gbps NIC | • 8+ Physical CPU Cores (x86_64)<br/>• 32 GB DDR4/DDR5 RAM<br/>• 100 GB OS Disk<br/>• 1x Dedicated 120+ GB NVMe SSD<br/>• 1x 10 Gbps NIC (or dual 1 Gbps) | Runs Mayastor `io-engine` (SPDK), DiskPool 1, KubeVirt `virt-handler`, and active source guest virtual machines. |
| **Worker Node 2 (Storage + VM)** | • 4 Physical CPU Cores (x86_64)<br/>• 16 GB DDR4/DDR5 RAM<br/>• 40 GB OS Disk<br/>• 1x Dedicated 50+ GB SSD/NVMe<br/>• 1x 1 Gbps NIC | • 8+ Physical CPU Cores (x86_64)<br/>• 32 GB DDR4/DDR5 RAM<br/>• 100 GB OS Disk<br/>• 1x Dedicated 120+ GB NVMe SSD<br/>• 1x 10 Gbps NIC (or dual 1 Gbps) | Hosts synchronous storage replica, DiskPool 2, and serves as the destination target for VM live migration drills. |
| **Worker Node 3 (Storage + Quorum)** | • 4 Physical CPU Cores (x86_64)<br/>• 16 GB DDR4/DDR5 RAM<br/>• 40 GB OS Disk<br/>• 1x Dedicated 50+ GB SSD/NVMe<br/>• 1x 1 Gbps NIC | • 8+ Physical CPU Cores (x86_64)<br/>• 32 GB DDR4/DDR5 RAM<br/>• 100 GB OS Disk<br/>• 1x Dedicated 120+ GB NVMe SSD<br/>• 1x 10 Gbps NIC (or dual 1 Gbps) | Hosts synchronous storage replica, DiskPool 3, providing the 3rd quorum tie-breaker during node failure simulations. |

---

### 1.2 Storage Subsystem Requirements (OpenEBS Mayastor Prerequisites)
Mayastor executes a user-space I/O pipeline using the Storage Performance Development Kit (SPDK). The following prerequisites must be supported by the worker nodes:
1. **CPU Instruction Set:** x86_64 processor supporting `SSE4.2` (and optionally `AVX2`).
2. **Dedicated Raw Block Device:** Each worker node requires at least one dedicated physical block device (e.g., `/dev/sdb`, `/dev/nvme1n1`) that is:
   - Completely unpartitioned and unformatted (no existing filesystem or LVM metadata).
   - Dedicated exclusively to the Mayastor `DiskPool`.
3. **HugePages Allocation:** Host Linux kernel must allow reserving **1024 pages of 2 MiB HugePages** (total 2048 MiB = 2 GiB) per worker node at boot time:
   ```bash
   echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
   ```
4. **Kernel Modules:** The host operating system kernel must support and allow loading:
   - `nvme-tcp` (NVMe over Fabrics TCP initiator module).
   - `uio` or `vfio_pci` (User-space I/O drivers for SPDK).

---

### 1.3 Virtualization Subsystem Requirements (KubeVirt Prerequisites)
KubeVirt schedules virtual machines inside Kubernetes pods using Linux KVM:
1. **Hardware Virtualization Flag:** Processors on worker nodes must have virtualization extensions enabled in the BIOS/UEFI:
   - Intel: `VT-x` (`vmx` flag in `/proc/cpuinfo`).
   - AMD: `AMD-V` (`svm` flag in `/proc/cpuinfo`).
2. **KVM Character Device:** `/dev/kvm` must be accessible with read/write permissions for container virtualization (`chmod 666 /dev/kvm`).
3. **Nested Virtualization (If running inside college hypervisors e.g., Proxmox/ESXi):**
   - If the servers provided are virtual machines rather than bare-metal hosts, the hypervisor must have **nested virtualization enabled** (`kvm_intel.nested=1` or `kvm_amd.nested=1`), and CPU type must be passed through as `host-passthrough`.

---

### 1.4 Network & Interconnect Specifications
1. **Network Fabric:** Low-latency switched Ethernet interconnecting all 4 nodes on the same Layer-2 subnet.
2. **Bandwidth:** Minimum 1 Gbps full-duplex; 10 Gbps preferred for high-throughput FIO benchmarking.
3. **MTU:** Standard MTU 1500 supported; capability to enable MTU 9000 (Jumbo Frames) on the storage/migration VLAN is highly desirable.
4. **IP Addressing:** Static IPv4 addresses assigned to all nodes on the lab network (or static DHCP leases) to prevent Kubernetes cluster certificate invalidation across reboots.
5. **Firewall Access:** Ability to open internal cluster ports (Kubernetes API 6443, etcd 2379–2380, Kubelet 10250, Mayastor gRPC 10124, Mayastor NVMe-oF 8420, KubeVirt migration 49152–49215).

---

## 2. Infrastructure Discovery Questionnaire

*Please complete the following technical inquiry to assist in configuring the deployment environment.*

### Section A: Hardware Availability & Allocation
1. **Are physical bare-metal Linux servers available for this project, or will virtual machines provisioned on a campus hypervisor (e.g., VMware vSphere, Proxmox VE, OpenStack) be provided?**  
   `[ ] Physical Bare-Metal Servers`  
   `[ ] Hypervisor-Hosted Virtual Machines`  
   `[ ] Combination / Other:` _________________________

2. **How many independent machines can be allocated exclusively for the duration of this project?**  
   `[ ] 4 Nodes (1 Control Plane + 3 Workers) [RECOMMENDED]`  
   `[ ] 3 Nodes (1 Combined Control/Worker + 2 Workers)`  
   `[ ] Less than 3 Nodes (Specify count):` _______

3. **What are the CPU and RAM specifications per machine?**  
   - Control Plane Node: ______ CPU Cores | ______ GB RAM  
   - Worker Node 1: ______ CPU Cores | ______ GB RAM  
   - Worker Node 2: ______ CPU Cores | ______ GB RAM  
   - Worker Node 3: ______ CPU Cores | ______ GB RAM  

4. **Can dedicated secondary block devices (SATA SSD, SAS SSD, or NVMe) be provided on each worker node for raw storage pool allocation?**  
   `[ ] Yes — Dedicated raw SSD/NVMe available per worker (Capacity: _______ GB per disk)`  
   `[ ] No — Only single OS drive available (Unpartitioned space can be carved out)`  
   `[ ] Unsure / Need assistance inspecting hardware`

---

### Section B: Operating System & Administrative Permissions
5. **Can Ubuntu Server 22.04 LTS or 24.04 LTS be installed on these machines?**  
   `[ ] Yes — Fresh Ubuntu Server can be installed`  
   `[ ] No — Existing Linux distribution installed (Specify distro & version):` _________________

6. **Will root privileges or passwordless `sudo` access be granted to the student project team on all nodes?**  
   *(Note: Root/sudo access is mandatory for loading kernel modules, installing containerd, configuring HugePages, and bootstrapping Kubernetes via kubeadm).*  
   `[ ] Yes — Full sudo/root access is available`  
   `[ ] Restricted sudo access (Specify restrictions):` _________________________  
   `[ ] No sudo access available`

7. **Is hardware virtualization (Intel VT-x / AMD-V) enabled in the BIOS/UEFI on all worker machines? (If VMs, is CPU passed through as `host` with nested virtualization enabled?)**  
   `[ ] Yes — Hardware virtualization / /dev/kvm is available`  
   `[ ] Can be enabled upon request`  
   `[ ] No / Not permitted by lab policy`

---

### Section C: Networking, Access & Operational Logistics
8. **Are all candidate nodes connected via a dedicated local switch, and can static local IP addresses be assigned?**  
   `[ ] Yes — Static private IPv4 addresses available on the same subnet`  
   `[ ] Dynamic DHCP only (with long lease time)`  
   `[ ] Nodes are on different subnets / routing restrictions apply`

9. **Can internal node-to-node ports be opened without institutional firewall filtering?**  
   `[ ] Yes — Unrestricted communication permitted between designated cluster IPs`  
   `[ ] Internal firewall rules apply (Port opening requests must be submitted)`

10. **What is the remote access policy for these machines?**  
    `[ ] SSH access available from campus Wi-Fi / VPN`  
    `[ ] Physical in-lab access only during lab operating hours`  
    `[ ] Remote SSH via jump-host / port-forwarding available`

11. **What is the available reservation window for this hardware?**  
    `Reservation Start Date:` _______________  
    `Reservation End Date:` _______________  
    `Department Coordinator / Lab In-Charge Name:` _________________________

---

## 3. Alternative Fallback Matrix (If Preferred Hardware Is Unavailable)

If the college laboratory cannot provide the full 4-node bare-metal environment, the following degraded operational tiers are proposed:

| Fallback Tier | Hardware Topology | Compromised Features | Project Feasibility Assessment |
| :--- | :--- | :--- | :--- |
| **Tier 1: Degraded 3-Node Topology** | 1 Combined Control Plane/Worker + 2 Dedicated Storage Workers | No dedicated control plane isolation; control plane untainted. | **FEASIBLE:** Supports 2-way replication ($N=2$) and live migration between Node 1 and Node 2. Tolerates 0 worker node failures during migration. |
| **Tier 2: Proxmox / ESXi Nested VMs** | 4 VMs created on a single large lab server (e.g., 64 GB RAM Xeon workstation) | Virtualized storage and network latency; nested virtualization overhead. | **FEASIBLE FOR FUNCTIONALITY:** Allows testing all CRDs, live migration, and hot-plugging; benchmark IOPS will reflect hypervisor overhead rather than bare-metal NVMe speed. |
| **Tier 3: 2-Node Cluster** | 1 Control Plane + 1 Storage Worker | No multi-node quorum; no cross-node live migration possible. | **UNACCEPTABLE FOR FINAL SUBMISSION:** Live migration and distributed replication cannot be demonstrated. |
