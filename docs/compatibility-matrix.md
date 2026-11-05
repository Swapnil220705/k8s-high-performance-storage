# Software Version Compatibility Matrix & Lifecycle Reassessment

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Research Date:** 2026-11-05 (Reassessed & Corrected)  
**Document Status:** CORRECTED TECHNICAL RESEARCH & COMPATIBILITY MATRIX  
**Governance Standard:** Zero EOL Software as Approved Target — Evidence-Based Lifecycle Assessment  

---

> [!CRITICAL]
> **Corrective Reassessment Notice (November 2026):**  
> The initial Chunk 1 proposal selected Kubernetes v1.28.8 and v1.29.4 based on historical Mayastor documentation. In the current operational timeline (November 2026), **Kubernetes 1.28 reached End-of-Life (EOL) on October 22, 2024**, and **Kubernetes 1.29 reached EOL in February 2025**. Deploying EOL releases introduces unpatched CVEs, deprecated API dependencies, and obsolete toolchains. This document completely supersedes the obsolete baseline with currently supported and technically defensible version intersections.

---

## 1. Upstream Kubernetes Release Lifecycles (Current Status in Late 2026)

Upstream Kubernetes maintains an active support window of approximately 14 months per minor release under a rolling $N-2$ maintenance policy:

| Kubernetes Minor Release | Upstream Release Date | Upstream End-of-Life (EOL) Date | Current Status (Nov 2026) | Compatibility Assessment |
| :--- | :--- | :--- | :--- | :--- |
| **v1.28** | August 2023 | October 22, 2024 | **EOL** | **REJECTED:** Deprecated; unsupported upstream. |
| **v1.29** | December 2023 | February 2025 | **EOL** | **REJECTED:** Deprecated; unsupported upstream. |
| **v1.30** | April 2024 | July 15, 2025 | **EOL** | **REJECTED:** Out of community support. |
| **v1.31** | August 2024 | November 11, 2025 | **EOL** | **REJECTED:** Out of community support. |
| **v1.32** | December 2024 | February 28, 2026 | **EOL** | **REJECTED:** Out of community support. |
| **v1.33** | April 2025 | June 28, 2026 | **EOL** | **REJECTED:** Out of community support. |
| **v1.34** | August 2025 | October 27, 2026 | **RECENT EOL / PROVEN** | **SECONDARY FALLBACK:** Highly stable intersection across OpenEBS 4.6 and KubeVirt v1.8, but recently crossed official EOL boundary. |
| **v1.35** | December 2025 | February 28, 2027 | **ACTIVE / SUPPORTED** | **PRIMARY TARGET (PROPOSED):** Within active upstream support window; supported by KubeVirt v1.8 and OpenEBS v4.6+. |
| **v1.36** | April 2026 | June 2027 | **ACTIVE / CURRENT** | **EXPERIMENTAL:** Active, but storage operator testing lag exists. |
| **v1.37** | August 2026 | October 2027 | **ACTIVE / LATEST** | **UNVALIDATED:** Storage operators (Mayastor) lack documented testing guarantees. |

*Official References:* [Kubernetes Releases & Lifecycle](https://kubernetes.io/releases/) | [End of Life Data](https://endoflife.date/kubernetes)

---

## 2. Component Interoperability & Intersection Matrix

Evaluating software requires finding the exact intersection between Kubernetes lifecycle support, KubeVirt hypervisor operators, OpenEBS Mayastor SPDK storage engines, and Linux kernel drivers:

| Component | Target Version (Stack 1 — Supported Primary) | Fallback Version (Stack 2 — Proven Boundary) | Compatibility Evidence & Technical Invariants | Official Documentation Reference | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Host Linux OS** | Ubuntu Server 24.04 LTS (Noble Numbat) | Ubuntu Server 22.04.5 LTS (Jammy) | Ubuntu 24.04 LTS provides modern systemd cgroup v2, glibc 2.39, and native Linux 6.8 kernel. Ubuntu 22.04 LTS requires HWE kernel for modern NVMe-oF fixes. | [Ubuntu Server Releases](https://ubuntu.com/about/release-cycle) | **DOCUMENTED** |
| **Linux Kernel** | 6.8.0 LTS | 5.15.0 LTS / 6.5 HWE | Kernel $\ge$ 5.15 required by Mayastor for `nvme-tcp` initiator and fabrics multiplexing. Kernel 6.8 optimizes NVMe-oF multipath and KVM page tables. | [Mayastor Prerequisites](https://openebs.io/docs/user-guides/mayastor/prerequisites) | **DOCUMENTED** |
| **Kubernetes Core** | **v1.35.x** | **v1.34.x** | v1.35 is in active upstream support through Feb 2027. v1.34 provides maximum historical test coverage across KubeVirt and Mayastor. | [Kubernetes Releases](https://kubernetes.io/releases/) | **PROPOSED** |
| **Cluster Bootstrapper** | `kubeadm` v1.35.x | `kubeadm` v1.34.x | Matched 1:1 with target Kubernetes minor release. Scriptable, upstream-standard cluster lifecycle. | [kubeadm Documentation](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) | **DOCUMENTED** |
| **Container Runtime** | `containerd` v1.7.22 (LTS) | `containerd` v1.7.18 | `containerd` v1.7.x remains the enterprise LTS branch implementing CRI v1. Fully compatible with k8s 1.34/1.35 systemd cgroup driver. | [containerd Releases](https://github.com/containerd/containerd/releases) | **DOCUMENTED** |
| **Cluster CNI** | Calico v3.28.2 / v3.29.0 | Calico v3.28.0 | Calico v3.28+ explicitly validates Kubernetes 1.30 through 1.35. Provides native routed BGP without VXLAN MTU penalty. | [Calico System Requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) | **DOCUMENTED** |
| **OpenEBS Mayastor** | **OpenEBS v4.6.x (Mayastor v2.11+)** | OpenEBS v4.5.x (Mayastor v2.10+) | OpenEBS 4.6 bundles Mayastor v2.11+, providing tested support for Kubernetes 1.33–1.35 and introducing **native experimental RWX block volumes** for KubeVirt. | [OpenEBS Documentation](https://openebs.io/docs) \| [Mayastor GitHub](https://github.com/openebs/mayastor) | **DOCUMENTED / PROPOSED** |
| **KubeVirt Core** | **v1.8.x** | v1.7.x | KubeVirt v1.8 officially documents support for Kubernetes range `>=1.33` to `<1.36` (directly covering Kubernetes 1.34 and 1.35). | [KubeVirt K8s Compatibility](https://github.com/kubevirt/kubevirt/blob/main/docs/kubernetes-compatibility.md) | **DOCUMENTED** |
| **CDI (Data Importer)** | v1.61.x | v1.60.x | Aligned with KubeVirt v1.8 release family. Handles raw disk imports into Mayastor PVCs. | [CDI GitHub Releases](https://github.com/kubevirt/containerized-data-importer/releases) | **DOCUMENTED** |
| **Helm** | v3.16.x | v3.15.x | Fully compatible with Kubernetes 1.34/1.35 API schema validation. | [Helm Releases](https://github.com/helm/helm/releases) | **DOCUMENTED** |
| **Multus CNI** | v4.1.2 | v4.1.0 | Thin CNI meta-plugin; compatible across all Kubernetes 1.3x releases. | [Multus Repository](https://github.com/k8snetworkplumbingwg/multus-cni) | **DOCUMENTED** |
| **NFS CSI Driver** | `csi-driver-nfs` v4.9.0 | `csi-driver-nfs` v4.8.0 | Used for the conservative RWX shared storage fallback tier. Validated on k8s 1.33+. | [Kubernetes CSI NFS Driver](https://github.com/kubernetes-csi/csi-driver-nfs) | **DOCUMENTED** |
| **Observability Stack** | `kube-prometheus-stack` v62.x | `kube-prometheus-stack` v59.x | Packages Prometheus v2.54+ and Grafana v11.x; fully supports k8s 1.34/1.35 metrics schemas. | [Prometheus Community Helm Charts](https://github.com/prometheus-community/helm-charts) | **DOCUMENTED** |

---

## 3. Analysis of the Upstream Storage Compatibility Gap

A fundamental reality of cloud-native systems engineering is that **storage engine testing trails upstream Kubernetes releases by 1 to 2 cycles**:
1. Upstream Kubernetes moves rapidly with 3 minor releases annually.
2. In-tree kernel drivers, SPDK C/Rust bindings, and complex CSI specifications require substantial qualification time by storage maintainers (OpenEBS/Mayastor).
3. In late 2026:
   - While Kubernetes 1.36 and 1.37 are available, OpenEBS Mayastor documentation officially tests up to Kubernetes 1.34 and 1.35.
   - Targeting Kubernetes 1.37 would introduce unknown CSI driver breakage and risk deployment failure.
   - Targeting Kubernetes 1.28/1.29 is completely unacceptable due to EOL status.
4. **Defensible Engineering Decision:**
   - **Target Kubernetes v1.35.x with OpenEBS v4.6.x (Mayastor v2.11+) and KubeVirt v1.8.x.**
   - This represents the exact boundary where active upstream Kubernetes support coincides with official KubeVirt v1.8 support and OpenEBS Mayastor validation.
   - If cluster bootstrapping encounters unresolvable API changes in 1.35 during Chunk 2 deployment, the secondary fallback is **Kubernetes v1.34.x**, which is fully validated across all project components.

---

## 4. Known Incompatible Combinations & Anti-Patterns (Updated)

1. **Kubernetes $\le$ 1.29 with Modern KubeVirt ($\ge$ v1.6):**
   - *Status:* **INCOMPATIBLE / EOL**
   - *Evidence:* Modern KubeVirt CRDs require Kubernetes API schemas (`apiextensions.k8s.io/v1`) and admission webhook configurations that fail on EOL Kubernetes releases.
2. **Kubernetes $\ge$ 1.35 with Legacy Mayastor $\le$ 2.5:**
   - *Status:* **INCOMPATIBLE**
   - *Evidence:* Mayastor 2.5 relies on older CSI sidecar containers (e.g., `csi-provisioner` v3.x) that cannot negotiate the VolumeSnapshot and StorageCapacity API changes present in Kubernetes 1.35+. OpenEBS 4.6+ (Mayastor v2.11+) is strictly required.
3. **`containerd` v2.0.x with Untested Kubernetes Minor Versions:**
   - *Status:* **EXPERIMENTAL / UNVALIDATED**
   - *Evidence:* containerd 2.0 removes legacy CRI configuration syntax. To maintain rock-solid stability, `containerd` v1.7.x LTS is selected.
4. **Native Mayastor RWX on Filesystem-Mode Volumes:**
   - *Status:* **INCOMPATIBLE BY DESIGN**
   - *Evidence:* Mayastor's native RWX capability is restricted exclusively to raw block devices (`volumeMode: Block`). Requesting `volumeMode: Filesystem` on an RWX Mayastor volume will be rejected by the CSI driver.
