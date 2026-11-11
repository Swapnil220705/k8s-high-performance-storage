# Kubernetes Cluster Deployment & Operations Guide

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Document Status:** M2 DELIVERED (Local Deployment VALIDATED; 4-Node Target Procedures Documented for Future Execution)  
**Last Updated:** 2026-11-11 (Milestone M2)

---

## Guide Scope & Environment Separation

This guide maintains a strict boundary between:
1. **Part A — Local WSL2 Single-Node Development Deployment (EXECUTED & VALIDATED):** Lightweight `k3s v1.36.6+k3s1` cluster inside WSL2 Ubuntu 24.04 for API testing and manifest validation.
2. **Part B — Intended Four-Node Target Deployment (IMPLEMENTED / NOT YET EXECUTED):** Production/benchmark bootstrap automation for four physical/VM Ubuntu Server 24.04 LTS nodes (`Node 0` + `Nodes 1–3`).

---

## Part A: Local WSL2 Single-Node Development Cluster

### A.1 Selection Justification (`k3s` vs. `kind`)
After empirically measuring host resources on the development laptop (Host `C:` 17.32 GiB free prior to M2, Windows physical RAM ~623 MB free, WSL2 2,879 MiB available RAM, host Docker holding 13.3 GB across 23 images with two active containers `rakshakgis-backend` and `rakshakgis-db`):
- **`k3s v1.36.6+k3s1` was selected** over `kind v0.33.0` because:
  1. It requires only a 75 MB verified binary and ~550 MB total runtime state/images vs. `kindest/node:v1.36.4` (>1.1 GB base image + nested systemd/containerd overhead inside Docker).
  2. It consumes only **~341 MiB RAM** when running (`kubectl`, API, etcd/sqlite, Flannel, CoreDNS, metrics-server) and **0 MiB RAM** when stopped.
  3. It isolates Kubernetes on `containerd v2.3.7-k3s1.36` (`/run/k3s/containerd/containerd.sock`), preserving the pre-installed host `docker.io 29.1.3` and `containerd 2.2.1` runtimes without risking active user containers.
  4. It exposes the exact upstream **Kubernetes v1.36.6** API with matching `10.244.0.0/16` Pod CIDR and `10.96.0.0/12` Service CIDR.

### A.2 Resource Safeguards
[`scripts/setup/dev-cluster-local.sh`](../scripts/setup/dev-cluster-local.sh) enforces pre-flight checks before installation or startup:
- Refuses startup if WSL2 `MemAvailable < 1500 MiB`.
- Refuses startup if root filesystem free space `< 2 GiB`.
- Configures `--disable=traefik,servicelb` and `--kubelet-arg=fail-swap-on=false` (so host WSL2 swap configuration is left unmodified).

### A.3 Local Deployment & Lifecycle Commands
```bash
# 1. Install, verify SHA-256 checksum, start systemd service, wait for Ready + CoreDNS, configure ~/.kube/config
sudo scripts/setup/dev-cluster-local.sh install

# 2. Inspect service health, RAM usage, nodes, and system pods
scripts/setup/dev-cluster-local.sh status

# 3. Validate API, node health, CoreDNS, Pod scheduling, and Pod-to-Pod networking
scripts/validate/validate-kubernetes-cluster.sh

# 4. Read-only validation (no test pods scheduled)
scripts/validate/validate-kubernetes-cluster.sh --report-only

# 5. Pause local cluster to reclaim ~341 MiB RAM without losing cluster data
sudo scripts/setup/dev-cluster-local.sh stop

# 6. Resume local cluster cleanly
sudo scripts/setup/dev-cluster-local.sh start
```

### A.4 Observed Verification Output (2026-11-11)
- **Cluster Startup (`kubectl get nodes,pods -A`):**
  ```text
  NAME                 STATUS   ROLES           AGE     VERSION
  node/wsl2-dev-node   Ready    control-plane   6m30s   v1.36.6+k3s1

  kube-system   pod/coredns-7cfb7bc9c7-g76kk                  1/1     Running
  kube-system   pod/local-path-provisioner-5598c9cb4c-qx677   1/1     Running
  kube-system   pod/metrics-server-6dc596dfb8-wjxv5           1/1     Running
  ```
- **Validation Suite (`validate-kubernetes-cluster.sh`):**
  `PASS: 12 | WARNING: 1 | FAIL: 0 | NOT TESTABLE: 1` (Report archived in [`reports/kubernetes/k8s-cluster-validation-2026-11-11_10-45-42.txt`](../reports/kubernetes/k8s-cluster-validation-2026-11-11_10-45-42.txt)).

---

## Part B: Intended Four-Node Target Cluster Deployment (NOT YET EXECUTED)

> [!WARNING]
> **Execution Status: NOT VERIFIED ON LIVE MULTI-NODE HARDWARE**  
> All procedures in Part B target dedicated Ubuntu Server 24.04 LTS physical/VM nodes. The scripts `03-bootstrap-control-plane.sh` and `04-join-worker-node.sh` explicitly refuse execution inside WSL2.

### B.1 Target Node Package Installation (`containerd 2.3.x LTS` + `kubeadm v1.36.6`)

Ubuntu 24.04 default repositories currently ship `containerd 2.2.1` (upstream EOL on November 6, 2026). On target Ubuntu 24.04 nodes, install **`containerd 2.3.x LTS`** via one of two official upstream channels before running bootstrap scripts:

#### Method 1: Official Docker APT Repository (Recommended — Pinned `containerd.io 2.3.6`)
```bash
# Configure official Docker APT keyring and noble stable repository
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

# Install and pin containerd 2.3.x LTS (verified package: 2.3.6-1~ubuntu.24.04~noble)
sudo apt-get update
sudo apt-get install -y containerd.io=2.3.6-1~ubuntu.24.04~noble
sudo apt-mark hold containerd.io

# Generate schema v3 config and enable SystemdCgroup = true (matching infrastructure/k8s/containerd-config-v3.toml)
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable --now containerd
```

#### Method 2: Upstream Containerd Release Tarball (`v2.3.7` LTS)
Alternatively, download `containerd-2.3.7-linux-amd64.tar.gz` alongside `containerd-2.3.7-linux-amd64.tar.gz.sha256sum` from `https://github.com/containerd/containerd/releases/tag/v2.3.7`, verify the SHA-256 digest, extract to `/usr/local`, install `runc` and CNI plugins, and configure `containerd.service`.

#### Installing Kubernetes v1.36 (`kubeadm`, `kubelet`, `kubectl`) on Target Nodes
```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

sudo apt-get update
sudo apt-get install -y kubelet=1.36.6-1.1 kubeadm=1.36.6-1.1 kubectl=1.36.6-1.1
sudo apt-mark hold kubelet kubeadm kubectl
```

### B.2 Bootstrapping the Control Plane (Node 0)
Ensure `scripts/setup/02-node-prerequisites.sh` passes (`overlay`, `br_netfilter`, swap disabled, `net.ipv4.ip_forward=1`, firewall ports open):
```bash
# 1. Dry-run schema check and preflight verification (replace <CP_NODE_IP> with confirmed lab IP)
sudo scripts/setup/03-bootstrap-control-plane.sh \
  --advertise-ip <CP_NODE_IP> \
  --node-name k8s-cp-0 \
  --dry-run

# 2. Execute live initialization and deploy Calico v3.33.0 (prompts for 'BOOTSTRAP')
sudo scripts/setup/03-bootstrap-control-plane.sh \
  --advertise-ip <CP_NODE_IP> \
  --node-name k8s-cp-0
```

### B.3 Joining Worker Nodes (Nodes 1–3)
On Node 0, generate a short-lived bootstrap token (valid 2h) and retrieve the CA hash:
```bash
kubeadm token create --ttl 2h
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* /sha256:/'
```
On each Worker Node (store the token temporarily in `/root/k8s-join.token` with `chmod 0600` outside any Git folder):
```bash
sudo scripts/setup/04-join-worker-node.sh \
  --endpoint <CP_NODE_IP>:6443 \
  --node-ip <WORKER_NODE_IP> \
  --node-name k8s-worker-1 \
  --ca-cert-hash sha256:<CA_HASH> \
  --token-file /root/k8s-join.token

# Immediately remove temporary token file after join completes
sudo rm -f /root/k8s-join.token
```

---

## Part C: Infrastructure-Dependent Steps & Known Limitations

1. **Infrastructure-Dependent Verification:**
   - Four-node quorum initialization and worker node joins (`03-bootstrap-control-plane.sh`, `04-join-worker-node.sh`).
   - Inter-node Calico BGP peering mesh (TCP 179) and multi-node cross-host Pod routing.
   - OpenEBS Mayastor v2.12.2 qualification against Kubernetes v1.36.6 (scheduled in Milestone M3/M10).
2. **Known WSL2 Limitations:**
   - Swap remains enabled (`1024 MiB`) inside WSL2, requiring `--kubelet-arg=fail-swap-on=false` locally.
   - Local `k3s` relies on single-node Flannel networking rather than Calico BGP.
   - Windows WSL2 VM idle timeout (`vmIdleTimeout`) automatically shuts down idle WSL2 instances when no background handles remain open; upon wake, `k3s.service` restarts via `systemd` and `metrics-server` requires ~15–20 seconds after pod startup for its initial scrape readiness check.
   - Physical NVMe devices and 2 GiB HugePages are unavailable locally.

---

## Part D: Rollback & Troubleshooting Procedures

| Issue / Symptom | Diagnostic Command | Corrective Action / Rollback |
| :--- | :--- | :--- |
| Local K3s fails pre-install memory guard | `free -m` / `systemctl status k3s` | Close unneeded apps or `docker stop` inactive projects to free $\ge 1500\text{ MiB}$ RAM; run `sudo scripts/setup/dev-cluster-local.sh start`. |
| Reclaim RAM locally without losing dev cluster state | `sudo scripts/setup/dev-cluster-local.sh stop` | Stops `k3s.service` (~341 MiB freed) while retaining cluster state in `/var/lib/rancher/k3s` and leaving Docker untouched. |
| Completely remove local dev cluster | `sudo scripts/setup/dev-cluster-local.sh uninstall` | Interactive confirmation removes `/usr/local/bin/k3s`, unit file, and `/var/lib/rancher/k3s` without touching `/var/lib/docker`. |
| Target node `kubeadm` preflight fails on Swap | `swapon --show` | Disable swap (`sudo swapoff -a`) and comment out swap entries in `/etc/fstab`. |
| Target `kubelet` cgroup driver mismatch | `containerd config dump \| grep SystemdCgroup` | Verify `/etc/containerd/config.toml` sets `SystemdCgroup = true` and restart `containerd`. |
| Reset failed target `kubeadm` bootstrap attempt | `sudo kubeadm reset -f` | Removes `/etc/kubernetes/` and `/var/lib/etcd` on target server before re-running `03-bootstrap-control-plane.sh`. |

