# College Infrastructure Discovery & Allocation Questionnaire

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Document Status:** FORMAL INQUIRY & ALLOCATION REQUEST  
**Target Recipient:** Department Laboratory Administrator / Systems Engineer / Faculty Project Coordinator  

---

## 1. Project Context & Purpose

This academic project investigates the deployment and performance benchmarking of a high-performance, cloud-native distributed storage architecture on Kubernetes. It integrates **OpenEBS Mayastor** (using SPDK user-space polling and NVMe over Fabrics) with **KubeVirt** to run virtual machines on containerized infrastructure.

To ensure realistic, publishable engineering results without incurring commercial cloud costs, the project is designed to run entirely on **college laboratory infrastructure**.

We request the allocation of **four (4) networked systems** (physical bare-metal servers or high-specification hypervisor virtual machines) for the project duration. Below are the technical specifications and a structured inquiry form.

---

## 2. Infrastructure Requirements Summary

| Component | Minimum Functional Requirement | Preferred Benchmarking Specification | Purpose & Technical Justification |
| :--- | :--- | :--- | :--- |
| **Node Count** | **4 Nodes** (1 Control Plane + 3 Workers) | **4 Nodes** (Dedicated physical servers) | 3-way synchronous replication ($N=3$), quorum tie-breaking, and cross-node VM live migration. |
| **Control Plane Node** | • 2–4 CPU Cores (x86_64)<br/>• 4–8 GB RAM<br/>• 40–100 GB OS Disk<br/>• 1x 1 Gbps NIC | • 4 Physical CPU Cores<br/>• 8 GB RAM<br/>• 100 GB SSD (High write endurance)<br/>• 1x 1 Gbps / 10 Gbps NIC | Hosts Kubernetes API Server, etcd database, scheduler, controller-manager, and storage control plane agents. |
| **Storage Worker Nodes<br/>(3 Nodes Required)** | • 6 Physical CPU Cores (x86_64)<br/>• 16 GB RAM (Constrained baseline)<br/>• 40 GB OS Disk<br/>• **1x Dedicated 50+ GB raw SSD/NVMe**<br/>• 1x 1 Gbps NIC | • 8–16 Physical CPU Cores (x86_64)<br/>• 32 GB RAM (Recommended)<br/>• 100 GB OS Disk<br/>• **1x Dedicated 120+ GB raw NVMe SSD**<br/>• 1x 10 Gbps NIC (or dedicated storage NIC) | Each worker dedicates 2 CPU cores to SPDK busy-polling, 2 GiB HugePages, a dedicated raw block device for storage pools, and hosts KubeVirt VMs. |
| **Virtualization** | Intel VT-x or AMD-V enabled in BIOS | Hardware `/dev/kvm` accessible directly | Mandatory for hardware-accelerated KVM virtual machines in KubeVirt. |
| **Operating System** | Fresh Ubuntu Server 24.04 LTS (or 22.04 LTS) | Clean install with Linux 6.8 LTS kernel | Upstream Kubernetes and Mayastor driver compatibility (`nvme-tcp`). |
| **Administrative Access** | Full `sudo` / root permissions | Sudo access with SSH key authentication | Needed for kernel module loading, HugePage reservation, and disk formatting. |
| **Networking** | Common Layer-2 subnet, Static IPs | 1 Gbps or 10 Gbps switched LAN | Prevents cluster certificate expiration and ensures low-latency NVMe-oF transport. |

---

## 3. Infrastructure Discovery Questionnaire

*Please complete or check the relevant fields below to help us align the deployment strategy with available laboratory resources.*

### Part A: General Information
- **Department / Laboratory:** __________________________________________________
- **Lab In-Charge / System Administrator Name:** _________________________________
- **Contact Email / Extension:** _________________________________________________
- **Date of Inquiry:** __________________________________________________________

---

### Part B: Machine Allocation & Hardware Topology
1. **What type of hardware can be allocated for this project?**
   - [ ] Dedicated physical bare-metal servers
   - [ ] Virtual machines provisioned on a campus hypervisor (e.g., Proxmox VE, VMware ESXi, OpenStack)
   - [ ] Existing lab desktop workstations with virtualization support
   - [ ] Other: ______________________________________________________________

2. **How many machines can be allocated exclusively for the project duration?**
   - [ ] 4 Nodes (1 Control Plane + 3 Workers) — *Standard architecture*
   - [ ] 3 Nodes (1 Combined Control/Worker + 2 Workers) — *Degraded fallback*
   - [ ] Other count: ________

3. **Hardware Specifications of Candidate Machines:**

| Machine Role / Identifier | CPU Model & Cores | Total RAM (GB) | Primary OS Disk Size | Dedicated Raw SSD/NVMe Size | NIC Count & Speed |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Machine 1 (Control Plane)** | | | | *(N/A)* | |
| **Machine 2 (Worker 1)** | | | | | |
| **Machine 3 (Worker 2)** | | | | | |
| **Machine 4 (Worker 3)** | | | | | |

4. **Dedicated Raw Storage Availability:**  
   *Mayastor requires at least one dedicated physical block device per worker that can be completely wiped and formatted for storage pools.*
   - [ ] Yes — A separate secondary SSD or NVMe drive is available on each worker.
   - [ ] Yes — A dedicated unformatted partition can be carved out on a single drive.
   - [ ] Unsure — Needs inspection by the project team.
   - [ ] No — Only single OS drive available with full disk utilization.

---

### Part C: BIOS, Kernel & Virtualization Capabilities
5. **Hardware Virtualization Support:**
   - [ ] Intel VT-x or AMD-V is enabled in BIOS/UEFI on all candidate machines.
   - [ ] Virtualization is currently disabled, but can be enabled in BIOS/UEFI upon request.
   - [ ] (If Virtual Machines) CPU pass-through (`host` model) with nested virtualization (`/dev/kvm`) is enabled.
   - [ ] Virtualization extensions are restricted or unavailable.

6. **Operating System & Kernel Prerequisites:**
   - [ ] Ubuntu Server 24.04 LTS (or 22.04 LTS) can be cleanly installed on the machines.
   - [ ] Existing Linux installation must be retained: Distro: __________________ Kernel: ________
   - [ ] The Linux kernel allows loading the `nvme-tcp` initiator module.
   - [ ] Host configuration permits reserving 2 GiB of 2 MiB HugePages per worker at boot.

---

### Part D: Network Connectivity & Security
7. **IP Addressing & Subnet Topology:**
   - [ ] Static private IPv4 addresses can be assigned to all 4 nodes on the same subnet.
   - [ ] DHCP is used, but static MAC-IP reservations can be configured on the router/switch.
   - [ ] Dynamic DHCP only (IP addresses may change upon reboot).
   - [ ] Machines reside on different subnets or VLANs.

8. **Inter-Node Communication & Firewalls:**
   - [ ] Unrestricted inter-node communication is permitted across the designated cluster IP range.
   - [ ] Institutional/host firewall rules apply. (A list of 10 inter-node ports will be submitted for whitelisting).
   - [ ] Is an isolated storage switch or secondary network interface available for NVMe traffic? `[ ] Yes  [ ] No`

---

### Part E: Administrative Access & Operational Logistics
9. **Administrative Permissions:**
   - [ ] Full root access or passwordless `sudo` privileges will be provided to the project team.
   - [ ] Limited `sudo` privileges can be granted for specific administrative commands.
   - [ ] No root/sudo access permitted. (Note: Root access is mandatory for cluster bootstrap and storage setup).

10. **Remote Access & Operating Hours:**
    - [ ] SSH access is available from campus Wi-Fi or VPN.
    - [ ] Physical laboratory access only during official college working hours.
    - [ ] Remote SSH access via jump host / port forwarding is available.
    - Lab operating hours / physical access schedule: ______________________________

11. **Reservation Duration & Stability:**
    - Anticipated project testing window: **From:** _______________ **To:** _______________
    - Can the machines remain continuously powered on and reserved without interruption during benchmark runs? `[ ] Yes  [ ] No`
    - Are scheduled lab maintenance reboots performed on specific days/times? ___________________

---

## 4. Fallback Architecture Matrix (If Ideal Hardware Is Unavailable)

If laboratory constraints prevent allocating 4 dedicated physical servers, we can accommodate the following structured fallbacks:

| Priority | Operational Tier | Proposed Hardware Topology | Feasibility & Limitations |
| :---: | :--- | :--- | :--- |
| **1** | **Degraded 3-Node Cluster** | 1 Combined Control Plane/Worker + 2 Storage Workers | **Feasible for Functionality:** Supports 2-way replication ($N=2$) and VM live migration. Zero tolerance for worker node loss during active migration. |
| **2** | **College Lab Desktops** | 4 physical lab workstations running Ubuntu Server | **Feasible for Benchmarking:** Suitable if workstations possess $\ge 6$ CPU cores, $\ge 16$ GB RAM, and secondary SSDs. |
| **3** | **Nested VMs on Single High-Spec Server** | 4 Linux VMs hosted on a single large lab server ($\ge 64$ GB RAM, 16+ cores) | **Feasible for Protocol Validation:** Allows full validation of Kubernetes, KubeVirt, live migration, and hot-plugging. Performance benchmarks will reflect hypervisor virtualization tax. |
| **4** | **2-Node Minimal Cluster** | 1 Control Plane + 1 Worker | **Unacceptable for Final Delivery:** Cannot demonstrate 3-way replication or cross-node live migration. |

---

## 5. Submission & Next Steps

Once this questionnaire is completed, the student engineering team will:
1. Conduct non-destructive pre-flight verification on the allocated machines (checking `/dev/kvm`, HugePages, and `nvme-tcp`).
2. Submit specific firewall port whitelisting requests based on the verified cluster IPs.
3. Schedule cluster provisioning without disrupting general laboratory operations.

**Student Project Team Lead:** Swapnil Sharma (Project ID: SWFW_5S_08)  
**Program:** Zoho SETU — College Student Project Program  
**Repository:** `https://github.com/Swapnil220705/k8s-high-performance-storage`
