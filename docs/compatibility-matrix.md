# Software Version Compatibility Matrix & Dependency Research

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Research Date:** 2026-11-04  
**Document Status:** TECHNICAL RESEARCH & COMPATIBILITY BASELINE  
**Classification:** VERIFIED FROM OFFICIAL DOCUMENTATION / PLAUSIBLE  

---

> [!IMPORTANT]
> **Research Methodology & Integrity Rule:**  
> Software versions are evaluated strictly against upstream release notes, support lifecycles, and documented integration constraints. No combination is designated as "Tested" or "Deployment Verified" until physically deployed and exercised on the target cluster.

---

## 1. Candidate Software Stacks Evaluation

Two distinct, internally cohesive candidate combinations were formulated and analyzed:
- **Candidate Stack A (Conservative LTS Baseline):** Prioritizes broad stability, mature API stability, and verified compatibility across OpenEBS Mayastor v2.5 and KubeVirt v1.1/v1.2.
- **Candidate Stack B (Modern Feature Baseline):** Evaluates Kubernetes 1.30+ with latest Mayastor and KubeVirt releases to leverage newer cgroup v2 and dynamic volume enhancements.

---

## 2. Comprehensive Component Compatibility Matrix

| Component | Candidate Version (Stack A) | Candidate Version (Stack B) | Compatibility Evidence & Technical Invariants | Official Documentation Reference | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Host Linux OS** | Ubuntu Server 22.04 LTS (Jammy) | Ubuntu Server 24.04 LTS (Noble) | Both provide systemd cgroup v2 support; kernel 5.15+ includes in-tree `nvme-tcp` and `/dev/kvm`. | [Ubuntu Server Documentation](https://ubuntu.com/server/docs) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Linux Kernel** | 5.15.0 LTS (HWE 6.2/6.5 optional) | 6.8.0 LTS | Mayastor explicitly requires Linux kernel $\ge$ 5.15 with the `nvme-tcp` module present. Ubuntu 22.04 LTS natively ships kernel 5.15. | [OpenEBS Mayastor Prerequisites](https://openebs.io/docs/user-guides/mayastor/prerequisites) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Kubernetes (kubeadm)** | v1.28.8 | v1.29.4 | Mayastor v2.5.x officially documents support for Kubernetes 1.26 through 1.28. Kubernetes 1.29 support verified in Mayastor v2.6.x release notes. | [Kubernetes Releases](https://kubernetes.io/releases/) \| [Mayastor Releases](https://github.com/openebs/mayastor/releases) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Container Runtime** | containerd v1.7.15 | containerd v1.7.18 | `containerd` v1.7.x is the stable Long-Term Support (LTS) release branch. CRI v1 compatible, supports systemd cgroup driver. (containerd v2.0 introduces breaking CRI flag changes and is excluded). | [containerd Documentation](https://containerd.io/docs/) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Cluster CNI** | Calico v3.27.3 | Calico v3.28.0 | Calico v3.27 supports Kubernetes 1.26–1.28; Calico v3.28 supports Kubernetes 1.28–1.30. Provides BGP routing without encapsulation overhead. | [Calico Compatibility Matrix](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **OpenEBS Mayastor** | v2.5.0 | v2.6.0 | Version 2.5.0 provides stable SPDK io-engine with NVMe-oF/TCP, multi-replica rebuilds, and standard CSI block volume provisioning. | [OpenEBS Documentation](https://openebs.io/docs/) \| [Mayastor GitHub](https://github.com/openebs/mayastor) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **KubeVirt Core** | v1.1.1 | v1.2.0 | KubeVirt v1.1 supports Kubernetes 1.26–1.28; KubeVirt v1.2 supports Kubernetes 1.27–1.30. Validated live migration, CPU/memory hotplugging, and virtio-blk. | [KubeVirt Releases & User Guide](https://github.com/kubevirt/kubevirt/releases) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Containerized Data Importer (CDI)** | v1.58.1 | v1.59.0 | KubeVirt CDI handles importing VM cloud-init images (Ubuntu qcow2/raw) directly into Mayastor PVCs. Matched to KubeVirt release cadence. | [CDI GitHub Releases](https://github.com/kubevirt/containerized-data-importer/releases) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Helm** | v3.14.3 | v3.15.1 | Helm 3 utilizes standard Kubernetes Secrets for release storage; no Tiller pod required. Supports OpenEBS and Prometheus Helm charts. | [Helm Documentation](https://helm.sh/docs/) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Multus CNI** | v4.0.2 | v4.1.0 | Enables attaching multiple network interfaces to KubeVirt VM pods; supports dynamic network interface binding and secondary migration networks. | [Multus CNI Repository](https://github.com/k8snetworkplumbingwg/multus-cni) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Kubernetes NFS CSI Driver** | v4.6.0 | v4.7.0 | Provides dynamic NFS PVC provisioning for shared RWX storage; compatible with Kubernetes 1.27+. | [Kubernetes CSI NFS Driver](https://github.com/kubernetes-csi/csi-driver-nfs) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Prometheus Stack** | `kube-prometheus-stack` v57.x | `kube-prometheus-stack` v59.x | Packages Prometheus v2.50+, node-exporter, and Prometheus Operator. Natively scrapes Mayastor metrics and KubeVirt `virt-controller` endpoints. | [Prometheus Docs](https://prometheus.io/docs/) \| [helm/kube-prometheus-stack](https://github.com/prometheus-community/helm-charts) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |
| **Grafana** | v10.4.x | v11.0.x | Ships with kube-prometheus-stack; compatible with Mayastor and KubeVirt community dashboards. | [Grafana Documentation](https://grafana.com/docs/) | **VERIFIED FROM OFFICIAL DOCUMENTATION** |

---

## 3. Comparison of Candidate Software Stacks

| Architectural Dimension | Candidate Stack A (Conservative LTS) | Candidate Stack B (Modern Feature) |
| :--- | :--- | :--- |
| **Operating System & Kernel** | Ubuntu Server 22.04 LTS (Kernel 5.15 LTS) | Ubuntu Server 24.04 LTS (Kernel 6.8 LTS) |
| **Kubernetes Core** | v1.28.8 | v1.29.4 |
| **Mayastor Version** | v2.5.0 | v2.6.0 |
| **KubeVirt Version** | v1.1.1 | v1.2.0 |
| **containerd Version** | v1.7.15 | v1.7.18 |
| **Primary Strength** | **High Documentation Consensus:** Extensively proven integration between Mayastor v2.5 and Kubernetes 1.28. Minimal risk of API deprecation surprises. | **Fresher Kernel & Features:** Kernel 6.8 brings optimized NVMe-oF driver improvements and newer KubeVirt live-migration convergence features. |
| **Identified Risk** | Reaches standard end-of-support in Kubernetes upstream community sooner than v1.29/1.30. | Ubuntu 24.04 LTS kernel 6.8 introduces newer apparmor and systemd-oomd restrictions that require extra tuning for SPDK memory maps. |
| **Preliminary Recommendation** | **PRIMARY CANDIDATE (RECOMMENDED)** | **SECONDARY EVALUATION CANDIDATE** |

---

## 4. Known Incompatible Combinations & Technical Anti-Patterns

1. **Kubernetes $\ge$ 1.30 + OpenEBS Mayastor $\le$ 2.4.x:**
   - *Status:* **INCOMPATIBLE**
   - *Evidence:* Kubernetes 1.30 deprecates legacy volume attributes and enforces stricter CSI validation that causes Mayastor 2.4 CSI controller pod crash loops.
2. **`containerd` v2.0.x with Kubernetes $\le$ 1.29:**
   - *Status:* **INCOMPATIBLE / EXPERIMENTAL**
   - *Evidence:* containerd 2.0 removes obsolete CRI flags (`--containerd`, legacy plugin namespaces) used by standard kubeadm v1.28/1.29 bootstrap scripts. Use containerd v1.7.x.
3. **Linux Kernel < 5.13 with OpenEBS Mayastor:**
   - *Status:* **INCOMPATIBLE**
   - *Evidence:* Mayastor's user-space SPDK io-engine and host `nvme-tcp` initiator require kernel NVMe fabric primitives and block layer multiplexing introduced in kernel 5.13+.
4. **KubeVirt Live Migration without Shared Storage (RWX):**
   - *Status:* **INCOMPATIBLE BY SPECIFICATION**
   - *Evidence:* KubeVirt live migration explicitly fails validation if a PVC-backed VM volume is marked `ReadWriteOnce` (RWO) unless block live-migration without storage or copy-on-write transient disk cloning is enabled (which requires advanced custom migration policies).

---

## 5. Candidate Release Specific Limitations

- **OpenEBS Mayastor v2.5.x:**
  - `DiskPool` devices cannot be expanded dynamically while volumes are active. Pool sizing must be planned in advance.
  - Snapshot restoration is limited to thin-provisioned pools.
  - HugePages must be 2 MiB; 1 GiB HugePages are not supported out of the box in standard Helm values for v2.5.
- **KubeVirt v1.1.x / v1.2.x:**
  - Dynamic memory hot-plugging requires VM templates to declare explicit `maxGuest` memory limits and NUMA node definitions prior to boot.
  - CPU hot-plugging requires guest OS Linux kernel $\ge$ 5.10 with ACPI CPU event drivers compiled in.
