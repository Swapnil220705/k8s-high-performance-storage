# Software Version Compatibility Matrix & Lifecycle Reassessment

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Audit Date:** 2026-11-05 (Chunk 1.9 Final Lifecycle & Compatibility Audit)  
**Document Status:** AUDITED TECHNICAL COMPATIBILITY SPECIFICATION  
**Governance Standard:** Zero EOL Software as Approved Baseline — Evidence-Based Upstream Audit  

---

> [!CRITICAL]
> **Chunk 1.9 Mandatory Lifecycle Corrections:**  
> 1. **Kubernetes 1.34 EOL Removal:** Kubernetes v1.34 reached upstream End-of-Life on **October 27, 2026**. It is formally **removed** as an approved fallback.
> 2. **Kubernetes 1.35 Time-Limited Status:** Kubernetes v1.35 is currently in active support, but reaches upstream EOL on **February 28, 2027**. It is designated as a time-limited primary candidate.
> 3. **containerd 1.7 EOL Removal:** containerd 1.7 reached upstream End-of-Life on **September 30, 2026**. It is formally **removed**. **containerd 2.3 LTS** is adopted as the preferred runtime candidate (supported through April 30, 2028), with containerd 2.4 evaluated as an interim alternative.
> 4. **Calico Upgrade:** Calico 3.28/3.29 is superseded by **Calico v3.33**, which officially tests and supports Kubernetes `>=1.35` to `<1.38`.

---

## 1. Upstream Kubernetes Release Lifecycles (Audited November 5, 2026)

Upstream Kubernetes maintains an active support window of approximately 14 months per minor release under a rolling $N-2$ maintenance policy:

| Kubernetes Minor Release | Upstream Release Date | Upstream End-of-Life (EOL) Date | Current Status (Nov 2026) | Compatibility Assessment & Project Stance |
| :--- | :--- | :--- | :--- | :--- |
| **v1.28** | August 2023 | October 22, 2024 | **EOL** | **REJECTED:** Deprecated; unmaintained upstream. |
| **v1.29** | December 2023 | February 2025 | **EOL** | **REJECTED:** Deprecated; unmaintained upstream. |
| **v1.30** | April 2024 | July 15, 2025 | **EOL** | **REJECTED:** Out of community support. |
| **v1.31** | August 2024 | November 11, 2025 | **EOL** | **REJECTED:** Out of community support. |
| **v1.32** | December 2024 | February 28, 2026 | **EOL** | **REJECTED:** Out of community support. |
| **v1.33** | April 2025 | June 28, 2026 | **EOL** | **REJECTED:** Out of community support. |
| **v1.34** | August 2025 | **October 27, 2026** | **EOL** | **REJECTED / REMOVED:** Crossed official upstream EOL boundary. Cannot serve as an approved fallback. |
| **v1.35** | December 2025 | **February 28, 2027** | **ACTIVE (SUPPORTED)** | **PRIMARY CANDIDATE (TIME-LIMITED):** In active community maintenance for ~3 months. Aligns with KubeVirt v1.8 and OpenEBS v4.6+. |
| **v1.36** | April 2026 | June 2027 | **ACTIVE (SUPPORTED)** | **EXPERIMENTAL TARGET:** Within active support, but Mayastor CSI release qualification lag requires empirical testing in Chunk 2. |
| **v1.37** | August 2026 | October 2027 | **ACTIVE (LATEST)** | **UNVALIDATED:** Bleeding-edge release. Neither KubeVirt v1.8 nor OpenEBS 4.6 officially guarantees compatibility. |

*Official Reference:* [Kubernetes Releases Schedule](https://kubernetes.io/releases/) | [Kubernetes End of Life Data](https://endoflife.date/kubernetes) (Audited 2026-11-05).

---

## 2. Container Runtime Lifecycle Audit (`containerd`)

`containerd` serves as the core Container Runtime Interface (CRI) implementation:

| containerd Version | Upstream Release Date | End-of-Life (EOL) Date | Current Status (Nov 2026) | Compatibility Assessment & Decision |
| :--- | :--- | :--- | :--- | :--- |
| **v1.7.x (LTS)** | March 10, 2023 | **September 30, 2026** | **EOL** | **REJECTED / REMOVED:** Crossed extended support boundary. Insecure for new cluster deployments. |
| **v2.0.x (LTS)** | November 5, 2024 | March 1, 2027 | **ACTIVE** | Viable, but superseded by newer v2.x LTS branches. |
| **v2.3.x (LTS)** | April 30, 2026 | **April 30, 2028** | **ACTIVE LTS (RECOMMENDED)** | **PREFERRED PRIMARY CANDIDATE:** Modern enterprise LTS release. Fully supports CRI v1, systemd cgroup v2, and Linux 6.8 kernel. |
| **v2.4.x** | September 16, 2026 | May 15, 2027 | **ACTIVE (REGULAR)** | **ALTERNATIVE CANDIDATE:** Short-lived interim release. Less suitable than 2.3 LTS for educational/production stability. |

*Official Reference:* [containerd Releases & Support Horizon](https://containerd.io/releases/) | [containerd End of Life Tracker](https://endoflife.date/containerd) (Audited 2026-11-05).

---

## 3. Calico CNI Compatibility Audit

Networking fabric selection requires strict alignment with target Kubernetes API versions:

| Calico Minor Version | Tested Kubernetes Versions | Networking Mode Proposed | Upstream Validation Status |
| :--- | :--- | :--- | :--- |
| **Calico v3.28 / v3.29** | Kubernetes 1.28 – 1.33 | BGP / VXLAN | **OUTDATED:** Deprecated for Kubernetes 1.35+. Risks admission webhook and CRD schema errors. |
| **Calico v3.30 – v3.32** | Kubernetes 1.31 – 1.36 | BGP / VXLAN | **INTERIM:** Compatible with k8s 1.35, but superseded by v3.33. |
| **Calico v3.33** | **Kubernetes $\ge$1.35 to $<$1.38** | **Native Routed BGP (No VXLAN)** | **OFFICIALLY TESTED & ADOPTED:** Explicitly validated for Kubernetes 1.35, 1.36, and 1.37. Eliminates 50-byte encapsulation overhead, maximizing NVMe-oF data plane wire speed. |

*Official Reference:* [Calico System Requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) (Audited 2026-11-05).

---

## 4. Comprehensive Audited Component Matrix

| Component | Target Baseline Version | Status Label | Compatibility Evidence & Technical Invariants | Source Reference |
| :--- | :--- | :--- | :--- | :--- |
| **Host Linux OS** | Ubuntu Server 24.04 LTS | **DOCUMENTED** | Native Linux 6.8 kernel, systemd cgroup v2, glibc 2.39, in-tree `nvme-tcp` and `/dev/kvm`. | [Ubuntu 24.04 Release Notes](https://ubuntu.com/about/release-cycle) |
| **Linux Kernel** | 6.8.0 LTS | **DOCUMENTED** | Supports SPDK user-space polling, VFIO/UIO, NVMe-oF multipath (`nvme_core.multipath=Y`). | [Mayastor Node Prerequisites](https://openebs.io/docs/user-guides/mayastor/prerequisites) |
| **Kubernetes Core** | **v1.35.x (Time-Limited)** | **PROPOSED** | In active support through Feb 28, 2027. Time-limited window documented. Candidate for Chunk 2. | [Kubernetes Releases](https://kubernetes.io/releases/) |
| **Cluster Bootstrapper**| `kubeadm` v1.35.x | **DOCUMENTED** | Standard upstream cluster provisioning tool matched 1:1 with target Kubernetes release. | [kubeadm Reference](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) |
| **Container Runtime** | `containerd` v2.3.x LTS | **PROPOSED** | Enterprise LTS branch supported through April 2028. CRI v1 compliant; systemd cgroup driver. | [containerd Lifecycle](https://containerd.io/releases/) |
| **Cluster CNI Plugin** | Calico v3.33 | **DOCUMENTED** | Tested for Kubernetes 1.35–1.37. Configured for native routed BGP mesh. | [Calico Requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) |
| **Storage Engine** | OpenEBS v4.6.x (Mayastor v2.11+) | **DOCUMENTED / PROPOSED** | SPDK-based replicated block storage. Introduces native experimental RWX block volumes. | [OpenEBS Documentation](https://openebs.io/docs) \| [Mayastor Releases](https://github.com/openebs/mayastor/releases) |
| **Virtualization Operator**| KubeVirt v1.8.x | **DOCUMENTED** | Officially validated for Kubernetes `>=1.33` to `<1.36` (covers k8s 1.35). | [KubeVirt K8s Compatibility](https://github.com/kubevirt/kubevirt/blob/main/docs/kubernetes-compatibility.md) |
| **Data Importer** | CDI v1.61.x | **DOCUMENTED** | Aligned with KubeVirt v1.8 release family for raw disk image ingestion. | [CDI Releases](https://github.com/kubevirt/containerized-data-importer/releases) |
| **Secondary Network** | Multus CNI v4.1.2 | **DOCUMENTED** | In-process CNI meta-plugin invoked via local domain socket; no TCP/UDP network ports. | [Multus CNI Repository](https://github.com/k8snetworkplumbingwg/multus-cni) |
| **Shared Storage Fallback**| `csi-driver-nfs` v4.9.0 | **DOCUMENTED** | Standard NFS CSI driver providing shared filesystem fallback for live migration. | [Kubernetes CSI NFS Driver](https://github.com/kubernetes-csi/csi-driver-nfs) |
| **Observability Suite**| `kube-prometheus-stack` v62.x | **DOCUMENTED** | Packages Prometheus v2.54+ and Grafana v11.x; fully supports k8s 1.35 metrics APIs. | [Prometheus Helm Charts](https://github.com/prometheus-community/helm-charts) |

---

## 5. Storage Operator Qualification Gap Analysis

1. **The Upstream Lag Reality:**  
   Kubernetes v1.35 is supported upstream until February 2027. Kubernetes v1.36 and v1.37 are available, but OpenEBS Mayastor maintainers primarily qualify against Kubernetes minor releases with a 1-to-2 cycle offset due to low-level SPDK and CSI driver dependencies.
2. **KubeVirt Qualification Boundary:**  
   KubeVirt v1.8 officially certifies Kubernetes versions up to `<1.36`. Running KubeVirt v1.8 on Kubernetes 1.36 or 1.37 represents an **unverified combination** that risks admission webhook rejections and CRD schema mismatches.
3. **containerd 2.x Qualification Gap:**  
   While `containerd` v2.3 LTS is the only supported LTS branch in late 2026, Mayastor's historical documentation references containerd 1.6/1.7. containerd 2.0+ deprecates legacy CRI configuration flags. During Chunk 2 pre-flight testing, the containerd 2.3 `config.toml` must explicitly ensure `systemd_cgroup = true` under `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]` to avoid Kubelet startup failures.
4. **Resolution Strategy:**  
   Target **Kubernetes v1.35.x + containerd v2.3 LTS + Calico v3.33 + OpenEBS v4.6.x + KubeVirt v1.8.x**. If unexpected CSI sidecar incompatibilities emerge during live testing on 1.35, the team will document the exact failure log and evaluate experimental patches rather than silently retreating to EOL releases.
