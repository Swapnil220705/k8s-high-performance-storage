# Development Toolchain & Environment Verification Specification

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Document Status:** VALIDATED (Milestone M1 Empirical Delivery)  
**Last Updated:** 2026-11-09 (Milestone M1 Development Environment Preparation)

---

## 1. Executive Summary & Purpose

Milestone **M1 (Development Environment Preparation & Automated Tooling)** establishes the automated toolchain, static analysis linters, preflight inspection utilities, and node prerequisite validation frameworks required to develop, lint, verify, and document the Kubernetes high-performance storage architecture inside a local **WSL2 Ubuntu 24.04 LTS** environment.

In accordance with [**ADR-011**](../DECISIONS.md#adr-011) and [**AGENTS.md**](../AGENTS.md), the entire project scope is preserved without downscaling to laptop hardware. College infrastructure is decoupled from development gating, and all features are classified under the three-state completion framework: `IMPLEMENTED`, `VALIDATED`, or `INFRASTRUCTURE-DEPENDENT`.

---

## 2. Complete Inventory of Installed Tools & Verification

All client-side CLI tools, linters, benchmark utilities, and runtime dependencies have been installed, cryptographically verified, and empirically validated inside the WSL2 environment:

| Tool Name | Binary Path | Version | Delivery Channel | Upstream Source / SHA-256 Digest | Primary Operational Purpose | Verification Command |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`kubectl`** | `/usr/local/bin/kubectl` | **v1.36.0** | Official Binary | `https://dl.k8s.io/release/v1.36.0/bin/linux/amd64/kubectl`<br>`123d8c8844f46b1244c547fffb3c17180c0c26dac9890589fe7e67763298748e` | Kubernetes cluster CLI & API communication | `kubectl version --client` |
| **`helm`** | `/usr/local/bin/helm` | **v3.17.1** | Official Binary | `https://get.helm.sh/helm-v3.17.1-linux-amd64.tar.gz`<br>`3b66f3cd28409f29832b1b35b43d9922959a32d795003149707fea84cbcd4469` | Kubernetes package manager (OpenEBS & Prometheus charts) | `helm version --short` |
| **`kubeconform`** | `/usr/local/bin/kubeconform` | **v0.8.0** | Official Binary | `https://github.com/yannh/kubeconform/releases/download/v0.8.0`<br>`9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883` | Fast, offline Kubernetes manifest schema validation | `kubeconform -v` |
| **`yamllint`** | `/usr/bin/yamllint` | **1.33.0** | Ubuntu APT | `archive.ubuntu.com/ubuntu noble/universe` | Strict YAML style, indentation, and syntax analysis | `yamllint --version` |
| **`shellcheck`** | `/usr/bin/shellcheck` | **0.9.0** | Ubuntu APT | `archive.ubuntu.com/ubuntu noble/universe` | Bash static analysis, POSIX portability, and bug detection | `shellcheck --version` |
| **`shfmt`** | `/usr/bin/shfmt` | **3.8.0** | Ubuntu APT | `archive.ubuntu.com/ubuntu noble/universe` | Automated shell script formatting and indentation enforcer | `shfmt --version` |
| **`jq`** | `/usr/bin/jq` | **1.7.1** | Ubuntu APT | `archive.ubuntu.com/ubuntu noble-updates/main` | Command-line JSON processor and report validator | `jq --version` |
| **`yq`** | `/usr/local/bin/yq` | **v4.54.3** | Official Binary | `https://github.com/mikefarah/yq/releases/download/v4.54.3`<br>`129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973` | Portable command-line YAML processor for manifests | `yq --version` |
| **`git`** | `/usr/bin/git` | **2.43.0** | Ubuntu APT | `archive.ubuntu.com/ubuntu noble-updates/main` | Git version control and conventional commit management | `git --version` |
| **`curl`** | `/usr/bin/curl` | **8.5.0** | Ubuntu APT | `archive.ubuntu.com/ubuntu noble-updates/main` | HTTP client for downloading approved resources | `curl --version` |
| **`fio`** | `/usr/bin/fio` | **3.36** | Ubuntu APT | `archive.ubuntu.com/ubuntu noble-updates/universe` | Flexible I/O Tester for storage benchmarking and latency profiles | `fio --version` |
| **`virtctl`** | `/usr/local/bin/virtctl` | **v1.9.0** | Official Binary | `https://github.com/kubevirt/kubevirt/releases/download/v1.9.0`<br>`40ede2ee37c98a1aeed71c9c219616a05247ce2be109e1edddf0477572e8b978` | KubeVirt virtual machine management and migration CLI | `virtctl version --client` |
| **`containerd`** | `/usr/bin/containerd` | **2.2.1** | Pre-installed | Ubuntu 24.04 (retained, untouched per runtime directive) | Host container runtime daemon | `containerd --version` |
| **`docker`** | `/usr/bin/docker` | **29.1.3** | Pre-installed | Ubuntu 24.04 (retained, untouched per runtime directive) | Container management CLI | `docker --version` |

---

## 3. Environment Reproduction Runbook

The development environment can be reproduced idempotently from scratch using the automated scripts committed in this repository:

### 3.1 Prerequisites
- Windows 11 with WSL2 enabled (`wsl --status`).
- Ubuntu 24.04 LTS installed in WSL2.
- Outbound internet access for APT repositories and GitHub releases.

### 3.2 Automated Toolchain Installation
Run the automated installation script inside WSL2:
```bash
sudo scripts/setup/install-dev-tools.sh
```
*Operation:* Updates APT, installs native packages, downloads official binaries, validates their SHA-256 cryptographic digests, installs them into `/usr/local/bin`, and prints a verification summary.

### 3.3 Running Non-Destructive Host Preflight
Audit the host hardware and virtualization capabilities without altering host configuration:
```bash
scripts/setup/01-host-preflight.sh
```
*Outputs:* Formatted console output, timestamped text report (`reports/environment/host-preflight-*.txt`), and JSON report (`reports/environment/host-preflight-*.json`).

### 3.4 Running Node Prerequisite Detection
Audit prospective node readiness for Kubernetes, Mayastor, and KubeVirt:
```bash
scripts/setup/02-node-prerequisites.sh --report
```
*Outputs:* Formatted console audit, timestamped text report (`reports/environment/node-prerequisites-*.txt`), and JSON report (`reports/environment/node-prerequisites-*.json`).

### 3.5 Running Unified Validation Suite
Execute all linting, formatting, permissions, and parsing checks in a single command:
```bash
scripts/validate/run-validation.sh
```
*Verification Steps:*
1. Toolchain availability check (all 12 tools).
2. Script executable permissions (`chmod +x`).
3. ShellCheck static analysis across all scripts in `scripts/`.
4. `shfmt` style check with 4-space indentation.
5. `yamllint` configuration validation (`.yamllint.yaml`).
6. `kubeconform` manifest schema validation.
7. `jq` parsing integrity on all generated environment reports.
8. Preflight automation execution test.

---

## 4. Empirical Preflight & Node Audit Findings

### 4.1 Host Preflight Summary (`01-host-preflight.sh`)
```text
==============================================================================
Host Preflight Audit Completed:
  PASS:         27
  WARNING:      8
  FAIL:         0
  NOT TESTABLE: 1
==============================================================================
```
- **CPU:** AMD Ryzen 5 7535HS (Zen 3+, 6C/12T), SSE4.2 supported, AMD-V `svm` flag present in `/proc/cpuinfo`.
- **Memory:** Total: 3,515 MiB, Available: 2,811 MiB. Swap enabled (1,024 MiB). HugePages size: 2,048 kB, Total: 0.
- **Virtualization:** `/dev/kvm` character device present (`crw-rw---- root kvm 10, 232`).
- **Storage:** 939 GiB available on `/`, 6 block devices enumerated. Zero `/dev/nvme*` physical devices visible in WSL2.
- **Network:** Interface `eth0` active, DNS functional, `net.ipv4.ip_forward = 1`.
- **Toolchain:** All 12 CLI tools verified operational.

### 4.2 Node Prerequisites Summary (`02-node-prerequisites.sh`)
```text
==============================================================================
Node Prerequisites Audit Completed:
  MET:   10
  WARN:  5
  UNMET: 0
==============================================================================
```
- **Met Prerequisites (10):** OS (Ubuntu 24.04.4 LTS), Kernel (6.6.87.2 >= 5.15), Architecture (x86_64), Cores (12 available), SSE4.2 (supported), br_netfilter (loaded), `net.ipv4.ip_forward` (1), `bridge-nf-call-iptables` (1), Raw Block Candidates (2 virtual disks), containerd (2.2.1).
- **Warnings (5):** Total RAM (3.5 GiB vs. 8.0 GiB target), HugePages (0 allocated vs. 1024 pages), `overlay` (compiled but not pre-loaded), `nvme_tcp` (compiled but not pre-loaded), `/dev/kvm` permissions (unprivileged user requires `kvm` group membership).
- **Unmet Prerequisites (0):** Zero fatal missing dependencies.

---

## 5. WSL2 Specific Constraints & Mitigations

| Subsystem | WSL2 Characteristic | Bare-Metal Target Requirement | Mitigation / Impact on Project Pipeline |
| :--- | :--- | :--- | :--- |
| **Kernel** | Microsoft customized kernel (`6.6.87.2-microsoft-standard-WSL2`) | Standard Ubuntu distribution kernel (`6.8.x-generic`) | Sufficient for local container runtimes, `kubeadm` manifest testing, and KVM micro-VMs. Bare-metal target will run generic Ubuntu server kernel. |
| **Hardware KVM** | `/dev/kvm` is passed through by WSL2 Hyper-V backend | Physical AMD-V / Intel VT-x with bare-metal KVM module | Hardware acceleration is functional in WSL2 (`/dev/kvm` exists). KubeVirt can run micro-VMs (Alpine/CirrOS) locally without emulation fallback. |
| **System Memory** | 3,515 MiB RAM assigned to WSL2; host has 8.0 GB physical RAM | 8.0 GB RAM per node (with 2 GiB HugePages reservation) | Local single-node cluster must budget < 2.0 GiB RAM. Full 6 GiB HugePages for Mayastor multi-replica cluster remains infrastructure-dependent. |
| **Dedicated NVMe** | Virtual dynamic VHDX block devices (`/dev/sda`, `/dev/sdb`) | Dedicated physical NVMe SSDs (`/dev/nvme0n1`, `/dev/nvme1n1`) | Mayastor manifests and CRDs are authored locally using block devices; wire-speed NVMe-oF benchmarks require dedicated college servers. |
| **Networking** | Hyper-V NAT vEthernet (192.168.x.x / 172.x.x.x) | Static IPv4 addressing on dedicated physical LAN switch | Local testing uses NAT interface; multi-node BGP mesh with Calico remains infrastructure-dependent. |

---

## 6. Three-State Feature Completion Ledger for M1

| Capability / Deliverable | Status | Verification Evidence |
| :--- | :---: | :--- |
| **Client-side CLI Toolchain** (`kubectl`, `helm`, `virtctl`, `fio`, etc.) | **`VALIDATED`** | All 12 tools installed in `/usr/local/bin` and `/usr/bin`; SHA-256 verified; `--version` commands pass. |
| **Linting & Analysis Framework** (`shellcheck`, `shfmt`, `yamllint`, `kubeconform`) | **`VALIDATED`** | `scripts/validate/run-validation.sh` executed cleanly with 8/8 passed checks; zero linter errors. |
| **Automated Host Preflight Script** (`scripts/setup/01-host-preflight.sh`) | **`VALIDATED`** | Executed against local WSL2; detected 27 PASS, 8 WARN, 0 FAIL; generated text and JSON reports. |
| **Node Prerequisite Detection Script** (`scripts/setup/02-node-prerequisites.sh`) | **`VALIDATED`** | Executed in report-only mode; detected 10 MET, 5 WARN, 0 UNMET; generated text and JSON reports. |
| **KVM Hardware Acceleration Device** (`/dev/kvm`) | **`VALIDATED`** | Character device node verified present (`10, 232`); KVM device permissions audited. |
| **Local 2 GiB HugePages sysctl Allocation** | **`INFRASTRUCTURE-DEPENDENT`** | Feasibility audited: WSL2 has 3.4 GiB RAM; reserving 2 GiB leaves < 1.0 GiB for OS, making it constrained. |
| **Physical Secondary NVMe Block Device Pool** | **`INFRASTRUCTURE-DEPENDENT`** | Requires bare-metal server with dedicated secondary NVMe SSD for Mayastor SPDK `DiskPool`. |
| **Physical Multi-Node BGP Network Fabric** | **`INFRASTRUCTURE-DEPENDENT`** | Requires physical multi-node cluster connected to dedicated lab network switch. |

