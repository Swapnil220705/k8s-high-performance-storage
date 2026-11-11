# Kubernetes Cluster Architecture Specification

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Document Status:** M2 DELIVERED (Manifests & Schemas VALIDATED; 4-Node Multi-Node Execution INFRASTRUCTURE-DEPENDENT)  
**Last Updated:** 2026-11-11 (Milestone M2)

---

## 1. Architectural Overview & Dual-Environment Separation

Milestone M2 establishes two clearly delineated Kubernetes environments serving distinct engineering objectives without compromising the permanent project scope ([**ADR-011**](../DECISIONS.md#adr-011)):

1. **Target Four-Node Production/Benchmark Architecture (`kubeadm`):** A multi-node bare-metal/VM cluster (`Node 0` Control Plane + `Nodes 1–3` Workers) running **Kubernetes v1.36.6**, **containerd 2.3.x LTS**, and **Calico v3.33.0** pure routed BGP networking, sized for OpenEBS Mayastor SPDK and KubeVirt hardware virtualization.
2. **Local Single-Node Development Cluster (`k3s`):** A lightweight, resource-bounded single-node cluster running **K3s v1.36.6+k3s1** (`containerd v2.3.7`) inside WSL2 Ubuntu 24.04 for rapid Kubernetes API testing, manifest validation, Pod scheduling, and CoreDNS verification.

> [!IMPORTANT]
> **Architectural Honesty Invariant:**  
> The local single-node K3s cluster validates Kubernetes v1.36 API interactions, local Pod scheduling, and ClusterIP DNS resolution. It does **NOT** validate four-node etcd scheduling topology, Calico multi-node BGP peering, SPDK NVMe-oF data replication, or KubeVirt live migration. Those capabilities remain strictly **`INFRASTRUCTURE-DEPENDENT`** until target hardware allocation.

---

## 2. Target Four-Node Cluster Topology

```mermaid
flowchart TB
    subgraph TargetCluster["Target 4-Node Kubernetes Cluster (v1.36.6 + containerd 2.3.x LTS)"]
        subgraph CP["Node 0: Dedicated Control Plane"]
            APISrv["kube-apiserver (TCP 6443)"]
            ETCD["etcd Raft Store (TCP 2379-2380)"]
            CM["kube-controller-manager & kube-scheduler"]
            Kubelet0["kubelet + containerd 2.3.x + calico-node"]
        end

        subgraph Workers["Worker & Storage Fleet (Nodes 1, 2, 3)"]
            W1["Node 1 (Worker)<br/>kubelet + containerd 2.3.x<br/>calico-node (BGP TCP 179)<br/>Target: 2 GiB HugePages + Raw NVMe"]
            W2["Node 2 (Worker)<br/>kubelet + containerd 2.3.x<br/>calico-node (BGP TCP 179)<br/>Target: 2 GiB HugePages + Raw NVMe"]
            W3["Node 3 (Worker)<br/>kubelet + containerd 2.3.x<br/>calico-node (BGP TCP 179)<br/>Target: 2 GiB HugePages + Raw NVMe"]
        end
    end

    CP <-->|API / Kubelet (TCP 6443, 10250)| Workers
    W1 <-->|BGP Mesh (TCP 179) / Pod CIDR 10.244.0.0/16| W2
    W2 <-->|BGP Mesh (TCP 179) / Pod CIDR 10.244.0.0/16| W3
    W1 <-->|BGP Mesh (TCP 179) / Pod CIDR 10.244.0.0/16| W3
```

### 2.1 Node Role Allocation
- **Node 0 (`control-plane`):** Runs Kubernetes control plane static pods (`kube-apiserver`, `etcd`, `kube-controller-manager`, `kube-scheduler`) and CoreDNS. Retains the standard `node-role.kubernetes.io/control-plane:NoSchedule` taint so CPU-intensive storage engines (`io-engine`) and VMs do not contend with API quorum components.
- **Nodes 1–3 (`worker`):** Dedicated compute and storage nodes hosting workload pods, Calico BGP routing, and future Mayastor SPDK/KubeVirt components (M3/M4).

---

## 3. Target Software Stack & Qualification Status (Candidate B)

| Component | Target Specification | Upstream Status / Lifecycle | Qualification & Evidence Status |
| :--- | :--- | :--- | :--- |
| **Operating System** | Ubuntu Server 24.04 LTS (`x86_64`, Linux 6.8) | Active LTS (2029) | Audited locally in WSL2 (`Ubuntu 24.04.4 LTS`); target bare-metal kernel pending hardware. |
| **Kubernetes** | **v1.36.6** (`pkgs.k8s.io/core:/stable:/v1.36/deb`) | Active through late June 2027 | `kubeadm` v1.36.6 config schema **`VALIDATED`** (`kubeadm.k8s.io/v1beta4`); local API **`VALIDATED`** via K3s `v1.36.6+k3s1`. |
| **Container Runtime** | **containerd 2.3.x LTS** (Docker APT `2.3.6` or upstream `2.3.7`) | Active LTS through April 30, 2028 | Officially recommended pairing for K8s 1.36+; schema v3 (`SystemdCgroup = true`) configured in [`containerd-config-v3.toml`](../infrastructure/k8s/containerd-config-v3.toml). |
| **Cluster Provisioner** | **`kubeadm` (v1.36.6)** | Upstream Standard | Config template [`kubeadm-init-config.yaml`](../infrastructure/k8s/kubeadm-init-config.yaml) validated; bootstrap scripts implemented; live 4-node run **`INFRASTRUCTURE-DEPENDENT`**. |
| **CNI Plugin** | **Calico v3.33.0** (`tigera-operator:v1.44.0`) | Qualified for K8s 1.35–1.37 | Operator & CRD manifests strictly validated via `kubeconform`; multi-node BGP mesh **`INFRASTRUCTURE-DEPENDENT`**. |
| **Mayastor Compatibility** | OpenEBS v4.6.x (`mayastor v2.12.2`) | E2E tested up to K8s 1.35.6 | **Qualification Gap Documented (ADR-010):** K8s 1.36 qualification will be empirically evaluated in M3. |

---

## 4. Container Runtime Compatibility & Host Isolation

During M2 environment inspection on the WSL2 development laptop:
- The host Ubuntu 24.04 APT environment runs **`containerd 2.2.1-0ubuntu1~24.04.3`** alongside **`docker.io 29.1.3`** with active user containers (`rakshakgis-backend`, `rakshakgis-db`) and no `/etc/containerd/config.toml` (defaulting to `SystemdCgroup = false`).
- **Two Critical Decisions:**
  1. `containerd 2.2.x` reached upstream EOL on **November 6, 2026**, and is **NOT** acceptable as the target production cluster runtime. Target Ubuntu 24.04 nodes must deploy **`containerd 2.3.x LTS`** (`containerd.io=2.3.6-1~ubuntu.24.04~noble` from Docker's official Noble APT repo or upstream `v2.3.7` release tarball) with schema **`version = 3`** and **`SystemdCgroup = true`**.
  2. Reconfiguring or upgrading the laptop's `/usr/bin/containerd` daemon would disrupt Docker Desktop / running user containers on the developer machine. Instead, the local K3s dev cluster operates its own **isolated `containerd v2.3.7-k3s1.36`** via `/run/k3s/containerd/containerd.sock`, matching the target Candidate B runtime minor branch while preserving existing host Docker workloads completely untouched.

### 4.1 CRI Socket Standard for Target `kubeadm` Nodes
All target `kubeadm` configs and node bootstrap scripts explicitly target:
- **CRI Socket:** `unix:///run/containerd/containerd.sock`
- **Cgroup Driver:** `systemd` (configured in both `containerd` `version = 3` TOML and `KubeletConfiguration`)

---

## 5. Parameterized Hardware, Network & Storage Requirements

Because target college hardware IPs, hostnames, NIC names, and raw storage devices are unconfirmed:
- **Zero Hardcoded Infrastructure Secrets or Addresses:** Neither [`kubeadm-init-config.yaml`](../infrastructure/k8s/kubeadm-init-config.yaml) nor bootstrap scripts invent static production IPs. All node IPs, endpoints, and hostnames are passed dynamically at runtime via CLI parameters (`--advertise-ip`, `--node-ip`, `--endpoint`).
- **Expected Resource Sizing (Target 4-Node Cluster):**
  - **Control Plane (Node 0):** $\ge 4$ CPU cores ($\ge 2$ minimum), $\ge 4\text{ GiB}$ RAM ($\ge 2\text{ GiB}$ minimum), swap disabled, Ubuntu 24.04 LTS.
  - **Worker / Storage Nodes (Nodes 1–3):** $\ge 6$ physical CPU cores (8–16 preferred; 2 reserved for SPDK PMD), **32 GB RAM preferred** (16 GB absolute minimum constrained to single-VM idle-destination tests per `MemTotal` migration math), 2 GiB 2048 kB HugePages, dedicated raw unpartitioned secondary block device (`>= 100 GB`), `/dev/kvm`.
  - **Networking CIDRs:** Pod CIDR `10.244.0.0/16` (chosen to avoid overlap with common `192.168.0.0/16` campus LANs) and Service CIDR `10.96.0.0/12`.
  - **Firewall Ports (M2 Kubernetes + Calico Core):** Control plane TCP `6443`, `2379–2380`; Worker/All nodes TCP `10250`, BGP TCP `179` (or UDP `4789` if VXLAN fallback is activated).

---

## 6. Local Development Cluster vs. Target Architecture Comparison

| Dimension | Local WSL2 Dev Cluster (`k3s`) | Target 4-Node Cluster (`kubeadm`) |
| :--- | :--- | :--- |
| **Distribution** | K3s `v1.36.6+k3s1` (single binary) | Upstream `kubeadm` / `kubelet` / `kubectl` v1.36.6 |
| **Node Count** | 1 node (`wsl2-dev-node`, `control-plane`) | 4 nodes (1 `control-plane` + 3 `worker` nodes) |
| **CRI Runtime** | Embedded `containerd v2.3.7-k3s1.36` (`/run/k3s/containerd/containerd.sock`) | System `containerd 2.3.x LTS` (`/run/containerd/containerd.sock`) |
| **CNI Plugin** | Integrated Flannel VXLAN (`PodCIDR: 10.244.0.0/24`) | Calico `v3.33.0` Pure Routed BGP (`PodCIDR: 10.244.0.0/16`) |
| **Ingress / LoadBalancer** | Disabled (`--disable=traefik,servicelb`) to conserve RAM | Configured only as needed during target deployment |
| **Swap Policy** | Permitted locally (`fail-swap-on=false`) to avoid altering WSL2 swap | Strictly disabled (`failSwapOn: true`, `swapoff -a`) |
| **Resource Overhead** | Observed **~341 MiB RAM**, **~626 MB disk** (k3s bin + data dir) | Full production sizing ($\ge 16\text{–}32\text{ GB}$ RAM per worker) |
| **Validation Status** | **`VALIDATED`** (API, Ready node, CoreDNS, Pod scheduling, DNS/HTTP probe) | **`IMPLEMENTED` / `INFRASTRUCTURE-DEPENDENT`** |

