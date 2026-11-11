# Diagram 01 — Overall Four-Node Kubernetes Architecture

**Project:** Deploy High-Performance Storage for Kubernetes (`SWFW_5S_08`)  
**Architecture Distinction:**  
- **Top Topology (`INFRASTRUCTURE-DEPENDENT` Target Cluster):** Four Ubuntu Server `24.04 LTS` nodes (`kubeadm v1.36.6`, `containerd 2.3.x LTS`, `Calico v3.33.0` Pure BGP, OpenEBS `4.6.2` / Mayastor `v2.12.2`, KubeVirt `v1.9.1`, `kube-prometheus-stack v93.2.0`).  
- **Bottom Box (`VALIDATED` Local Dev Cluster):** Single-node K3s `v1.36.6+k3s1` (`containerd v2.3.7-k3s1.36`, Flannel CNI) validated on WSL2 Ubuntu `24.04.4 LTS` (`3515 MiB` RAM, zero HugePages, zero raw NVMe devices).

```mermaid
flowchart TB
    subgraph TargetArch["TARGET 4-NODE ARCHITECTURE (INFRASTRUCTURE-DEPENDENT)"]
        direction TB
        subgraph Node0["Node 0: Dedicated Control Plane (NoSchedule Taint)"]
            K8sCP["kube-apiserver (:6443)<br/>etcd (:2379/:2380)<br/>controller-manager & scheduler"]
            MSCP["Mayastor Control Plane<br/>(agent-core, api-rest, csi-controller, operator-diskpool)"]
            KVCP["KubeVirt & CDI Control Plane<br/>(virt-operator, virt-api :8443, virt-controller, cdi-controller)"]
            MON["Observability Plane (Internal ClusterIP)<br/>Prometheus v3.16.0 (:9090) & Grafana 13.3.1 (:3000)"]
        end

        subgraph Workers["Storage & Compute Workers (Calico v3.33.0 Pure BGP Mesh TCP :179 | Pod CIDR 10.244.0.0/16)"]
            subgraph W1["Worker 1 (openebs.io/engine=mayastor, rack-1)"]
                IO1["io-engine SPDK (2 pinned cores, 2Gi HugePages)"]
                DP1[("DiskPool 1<br/>Raw NVMe/SSD")]
                VH1["virt-handler + /dev/kvm"]
                VM1["virt-launcher Pod<br/>(Source VM)"]
            end
            subgraph W2["Worker 2 (openebs.io/engine=mayastor, rack-2)"]
                IO2["io-engine SPDK (2 pinned cores, 2Gi HugePages)"]
                DP2[("DiskPool 2<br/>Raw NVMe/SSD")]
                VH2["virt-handler + /dev/kvm"]
                VM2["virt-launcher Pod<br/>(Migration Target / NFS)"]
            end
            subgraph W3["Worker 3 (openebs.io/engine=mayastor, rack-3)"]
                IO3["io-engine SPDK (2 pinned cores, 2Gi HugePages)"]
                DP3[("DiskPool 3<br/>Raw NVMe/SSD")]
                VH3["virt-handler + /dev/kvm"]
                NFSGW["mayastor-nfs-server<br/>(NFSv4.1 ClusterIP :2049)"]
            end
        end

        K8sCP <-->|"Control / Kubelet (:6443 / :10250)"| Workers
        MSCP -->|"gRPC (:10124)"| IO1 & IO2 & IO3
        KVCP -->|"Subresources"| VH1 & VH2 & VH3
        IO1 <-->|"NVMe-oF TCP (:8420 / :4421)"| IO2 & IO3
        VM1 <-.->|"Pre-Copy TLS Live Migration (:49152-49215)"| VM2
        IO1 --- DP1
        IO2 --- DP2
        IO3 --- DP3
        MON -.->|"Scrapes :9502, :8443, :9100"| Workers
    end

    subgraph LocalValidated["LOCAL WSL2 DEV CLUSTER (EMPIRICALLY VALIDATED FOR API/LINT/DRY-RUN)"]
        K3S["Single-Node K3s v1.36.6+k3s1 (wsl2-dev-node)<br/>containerd v2.3.7-k3s1.36 | CoreDNS | Flannel CNI<br/>Validates K8s 1.36 API, Pod Scheduling & Strict CRD Schemas ONLY<br/>Does NOT Host Mayastor SPDK, Live KubeVirt VMs, or Multi-Node BGP"]
    end
```

