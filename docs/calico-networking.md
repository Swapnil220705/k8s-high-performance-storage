# Calico CNI Networking & BGP Architecture Specification

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Pinned Version:** Calico `v3.33.0` (`quay.io/tigera/operator:v1.44.0`)  
**Document Status:** MANIFESTS & SCHEMAS VALIDATED (`kubeconform -strict`); MULTI-NODE BGP INFRASTRUCTURE-DEPENDENT  
**Last Updated:** 2026-11-11 (Milestone M2)

---

## 1. Design Rationale & Protocol Selection

For high-performance distributed NVMe-oF storage and KubeVirt VM live migration, Pod and VM network throughput directly impacts storage and migration latency.

- **Selected CNI:** **Project Calico `v3.33.0`** deployed via Tigera Operator ([`infrastructure/k8s/calico/installation.yaml`](../infrastructure/k8s/calico/installation.yaml)).
- **Kubernetes Version Qualification:** Calico `v3.33` is officially tested for Kubernetes `v1.35–v1.37`, matching Candidate B (`v1.36.6`).
- **Routing Mode:** **Pure Routed BGP Mesh (`encapsulation: None`, `bgp: Enabled`)** paired with explicit [`bgp-configuration.yaml`](../infrastructure/k8s/calico/bgp-configuration.yaml).
  - *Why Pure BGP (`encapsulation: None`)?* VXLAN (+50 byte header) and IPIP (+20 byte header) encapsulation incur per-packet CPU encapsulate/decapsulate penalties and reduce effective guest MTU. Native BGP routes Pod CIDRs directly across the Layer-2 college laboratory switch at wire speed with full physical MTU preserved.
  - *Conditional Fallback (`VXLANCrossSubnet`):* If allocated college lab nodes reside across separate Layer-3 routed VLANs where native BGP across subnets is blocked by campus routers, change `encapsulation: None` to `encapsulation: VXLANCrossSubnet` in `installation.yaml` and permit UDP `4789` in host firewalls.

---

## 2. Addressing & CIDR Consistency

Every CIDR across the cluster configuration must remain strictly aligned and avoid overlapping typical campus LAN subnets (`192.168.0.0/16` or `172.16.0.0/12`):

| Network Plane | Configured CIDR | Reference File(s) | Design Justification |
| :--- | :--- | :--- | :--- |
| **Pod Network (`podSubnet`)** | **`10.244.0.0/16`** (`blockSize: 26`) | `kubeadm-init-config.yaml`, `installation.yaml`, `dev-cluster-local.sh` | Supports 65,534 Pod IPs (`/26` = 64 IPs per block) without conflicting with common `192.168.x.x` physical lab NICs. |
| **Service ClusterIP (`serviceSubnet`)** | **`10.96.0.0/12`** | `kubeadm-init-config.yaml`, `bgp-configuration.yaml`, `dev-cluster-local.sh` | Explicitly matches `BGPConfiguration.spec.serviceClusterIPs` without overlapping Pod CIDR. |

---

## 3. IP Autodetection Strategy

Hardcoding physical interface names (`eth0`, `ens18`, `enp3s0`) breaks portability across heterogeneous college hardware.

- **Configured Method:**
  ```yaml
  nodeAddressAutodetectionV4:
    kubernetes: NodeInternalIP
  ```
- **How It Works:** Both `03-bootstrap-control-plane.sh` and `04-join-worker-node.sh` configure `/etc/default/kubelet` with `--node-ip=<ALLOCATED_HOST_IP>`, guaranteeing Kubernetes records the exact intended Layer-2 management/storage IP as each node's `InternalIP`. Calico binds its BGP daemon and host routes strictly to `InternalIP`.
- **Alternative Override (Multi-NIC Future Expansion):** If a dedicated physical storage network interface is later allocated in the laboratory, `nodeAddressAutodetectionV4` can be switched cleanly to `canReach: <CONTROL_PLANE_IP>` or `cidrs: [<LAB_SUBNET_CIDR>]` without altering core bootstrap scripts. No dedicated physical storage NIC is assumed in the base M2 topology.

---

## 4. Explicit BGP & Security Configuration

[`infrastructure/k8s/calico/bgp-configuration.yaml`](../infrastructure/k8s/calico/bgp-configuration.yaml) pins:
- `asNumber: 64512` (private RFC 6996 2-byte AS).
- `nodeToNodeMeshEnabled: true` (full BGP mesh across 4 nodes — ideal scale for $\le 50$ nodes with zero external ToR BGP router requirement).
- `listenPort: 179` and `bindMode: NodeIP`.
- `serviceClusterIPs: [10.96.0.0/12]` — restricts advertisement strictly to internal ClusterIPs. External LoadBalancer / ExternalIP ranges are **omitted** so cluster-internal services remain isolated and unexposed.

---

## 5. Required Node-to-Node Communication

Per the canonical 20-port matrix ([`docs/network-and-virtualization-requirements.md`](network-and-virtualization-requirements.md)):
- **Mandatory (BGP Mode):** Bidirectional **TCP `179`** between all cluster nodes (`Node 0` and `Nodes 1–3`).
- **Conditional (VXLAN Fallback Only):** Bidirectional **UDP `4789`** between all nodes only if `VXLANCrossSubnet` or `VXLAN` is enabled.
- **Unnecessary Exposures Avoided:** Typha metrics, Goldmane/Whisker UIs, and Calico API server services remain ClusterIP-scoped (`APIServer` default resource only, zero LoadBalancer/NodePort bindings).

---

## 6. Validation Scope & Local vs. Target Boundaries

1. **Manifest Syntax & Schema Validation (`VALIDATED`):**
   - `yamllint` verified zero syntax/indentation errors on `installation.yaml` and `bgp-configuration.yaml`.
   - `kubeconform -strict` validated all 7 objects in upstream Calico `v3.33.0` `tigera-operator.yaml` AND all 3 custom resources (`Installation`, `APIServer`, `BGPConfiguration`) against extracted official Calico `v3.33.0` OpenAPIV3Schemas stored in `infrastructure/k8s/calico/schemas/`.
2. **Runtime Execution (`INFRASTRUCTURE-DEPENDENT`):**
   - The local single-node WSL2 K3s cluster utilizes lightweight built-in Flannel CNI (`10.244.0.0/24`) to save RAM and disk (~500 MB saved).
   - **Single-node WSL2 does NOT validate Calico v3.33.0 multi-node BGP peering.** Inter-node BGP session establishment (`calicoctl node status`), full-mesh route propagation, and wire-speed unencapsulated I/O performance remain strictly `INFRASTRUCTURE-DEPENDENT` until deployment on Nodes 0–3.

