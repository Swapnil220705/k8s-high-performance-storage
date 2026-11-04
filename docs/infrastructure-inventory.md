# Local Hardware & Host Environment Inventory

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Document Type:** Infrastructure Inventory & Local Feasibility Assessment  
**Assessment Date:** 2026-11-04  
**Classification:** LOCALLY VERIFIED (Development Workstation)  

---

> [!NOTE]
> **Assessment Scope & Privacy Notice:**  
> This inventory reflects the local development machine inspected via read-only Windows Management Instrumentation (WMI / CIM) and PowerShell utilities. Device serial numbers, MAC addresses, and Windows product keys have been redacted to ensure repository security.

---

## 1. Detected Hardware Specifications

| Component Tier | Specification Detected | Verification Query Source | Assessment & Hardware Context |
| :--- | :--- | :--- | :--- |
| **System Model** | HP Victus Gaming Laptop 15-fb1xxx | `Win32_ComputerSystem` | Consumer/gaming x86_64 laptop |
| **Processor (CPU)** | AMD Ryzen 5 7535HS with Radeon Graphics | `Win32_Processor` | 6 Physical Cores / 12 Logical Threads (Base ~3.3 GHz) |
| **CPU Architecture** | x86_64 (Architecture ID: 9) | `Win32_Processor` | 64-bit AMD Zen 3+ microarchitecture |
| **Firmware Virtualization** | Enabled (`VirtualizationFirmwareEnabled: True`) | `Win32_Processor` | AMD-V (SVM) enabled in UEFI/BIOS |
| **Hypervisor Presence** | Active (`HypervisorPresent: True`) | `Win32_ComputerSystem` | Windows Hypervisor Platform / VBS active |
| **Physical Memory (RAM)** | 8,589,934,592 bytes (8.00 GB installed) | `Win32_PhysicalMemory` | Single-channel DDR5 @ 4800 MT/s (1x 8GB module) |
| **Visible System Memory** | 7,558,520 KB (~7.21 GiB) | `Win32_OperatingSystem` | ~512 MB reserved for integrated Radeon GPU |
| **Available Free Memory** | ~730 MB – 760 MB (under normal desktop load) | `Win32_OperatingSystem` / `systeminfo` | Severe memory constraint (< 1 GB unallocated) |
| **Storage Subsystem** | 1x NVMe SSD (512 GB class, GPT partition table) | `Get-Disk` | BusType: NVMe; Single physical disk attached |
| **Primary System Volume (C:)** | 510,860,980,224 bytes (~475.77 GiB NTFS) | `Get-Volume` | Free space: ~18,651,115,520 bytes (~17.37 GiB free) |
| **Graphics Controllers** | 1. AMD Radeon(TM) Graphics (512 MB iGPU)<br/>2. NVIDIA GeForce RTX 2050 (4 GB dGPU) | `Win32_VideoController` | Discrete mobile GPU + integrated graphics |
| **Host Operating System** | Windows 11 Home Single Language (Build 26300) | `Win32_OperatingSystem` | 64-bit Desktop OS with VBS enabled |
| **WSL2 Runtime** | WSL2 Installed (Default distro: Ubuntu, stopped) | `wsl.exe --status` | Ubuntu image available on disk |

---

## 2. Workload Feasibility Analysis on Development Laptop

The detected hardware was systematically evaluated against 5 project workload tiers to determine operational boundaries:

### Workload A: Code Authoring, Manifest Editing, and Documentation
- **Technical Feasibility:** **SUPPORTED & OPTIMAL**
- **Evaluation:** Text editing, Markdown documentation, Git version control, static YAML schema validation, and web research operate comfortably within available CPU and memory resources.
- **Limitation:** None. This remains the designated purpose of the laptop throughout the project lifecycle.

### Workload B: Lightweight Kubernetes via Kind or K3d (Single-Node)
- **Technical Feasibility:** **MARGINAL / HIGH RISK**
- **Evaluation:** A minimal Kind or K3d cluster running standard API server, core DNS, and a few pause pods consumes between 1.5 GiB and 2.5 GiB of memory. With only ~750 MB of free physical RAM currently unallocated, launching Docker Desktop and a Kind container would force heavy Windows paging (commit charge swapping to disk), resulting in severe UI lag and potential OOM kills.
- **Disk Impact:** With ~17.37 GiB of free disk space remaining on C:, container images (Kubernetes, Mayastor, KubeVirt, Ubuntu VM cloud images) would rapidly consume 10–12 GiB, pushing the primary drive below safe operating margins.

### Workload C: One or Two Lightweight Linux Virtual Machines (Hyper-V / VirtualBox / WSL2)
- **Technical Feasibility:** **HIGHLY CONSTRAINED / UNRECOMMENDED**
- **Evaluation:** Allocating 2 GiB to a Linux virtual machine leaves the host Windows OS starved (< 500 MB RAM). Two VMs (e.g., 2 GiB each) would consume 4 GiB, exceeding available free memory by over 400% and causing instantaneous memory thrashing.

### Workload D: Complete Three-Worker OpenEBS Mayastor Cluster
- **Technical Feasibility:** **IMPOSSIBLE ON THIS HARDWARE**
- **Technical Reasons:**
  1. **Memory Deficit:** OpenEBS Mayastor's SPDK `io-engine` requires pre-allocated HugePages (minimum 2 GiB of 2 MiB HugePages per storage node). A 3-worker cluster requires at least 6 GiB of dedicated HugePages exclusively for SPDK memory pools, before allocating any RAM for the Linux kernel, Kubelet, containerd, etcd, or the Kubernetes API server. The laptop has only 8 GB total system RAM (with only ~7.21 GiB visible to the OS).
  2. **Dedicated Block Devices:** Mayastor `DiskPool` primitives require dedicated, unformatted block devices (e.g., `/dev/sdb`, `/dev/nvme1n1`) per worker. The laptop has only one physical NVMe disk (`Disk 0`), which hosts the active Windows OS partition. Loopback devices over sparse files on NTFS introduce catastrophic write amplification and SPDK I/O errors.
  3. **SPDK Core Dedication:** The `io-engine` pins dedicated CPU cores for its user-space polling loops (100% core saturation by design). Running three SPDK instances locally would monopolize 3–6 logical threads, starving the host operating system.

### Workload E: KubeVirt and Hardware KVM Virtualization
- **Technical Feasibility:** **IMPOSSIBLE FOR BENCHMARKING**
- **Technical Reasons:**
  1. While AMD-V (`svm`) is enabled in the laptop's UEFI firmware, running KubeVirt inside nested VMs or WSL2 requires nested virtualization support (`/dev/kvm`). While WSL2 supports `/dev/kvm`, running both Mayastor SPDK and KubeVirt VM pods concurrently inside WSL2 would exceed the 8 GB physical RAM ceiling instantly.
  2. Running KubeVirt VMs with 2–4 GiB RAM allocations inside a host with < 1 GiB free RAM is mathematically unfeasible.

---

## 3. Detected Facts vs. Inferred Conclusions

| Item | Detected Fact (Direct Measurement) | Inferred Engineering Conclusion |
| :--- | :--- | :--- |
| **Physical Memory** | Single 8 GB DDR5 module installed; ~750 MB free RAM currently available. | The laptop cannot host multi-node storage engines or virtualization test clusters without extreme memory starvation. |
| **Disk Hardware** | Exactly 1 physical NVMe drive (512 GB) with ~17.37 GB free space on C:. | The laptop lacks secondary raw block devices required for physical Mayastor DiskPools; free space is insufficient for multiple VM base images. |
| **CPU Virtualization** | `VirtualizationFirmwareEnabled: True` on AMD Ryzen 5 7535HS (6C/12T). | The processor possesses the hardware capability for virtualization (AMD-V), but memory and storage topology prevent local cluster deployment. |
| **WSL2 Runtime** | WSL2 with Ubuntu is installed on the system. | WSL2 can be utilized for Linux-based CLI tools, manifest linting, and scripting, but not as a full multi-node storage hypervisor. |

---

## 4. Architectural Recommendations

1. **Maintain Hybrid Model (ADR-001):** The laptop must remain dedicated to development, documentation, manifest authoring, and repository management.
2. **Do Not Attempt Local Cluster Deployment:** Do not install Minikube, Kind, or multi-node VMs locally. Doing so risks Windows system instability and unrecoverable disk saturation.
3. **Target Remote Laboratory Servers:** The 4-node Kubernetes cluster, OpenEBS Mayastor storage pools, and KubeVirt VMs must be deployed on external, dedicated Linux hardware (College Laboratory Servers).
