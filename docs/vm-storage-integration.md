# KubeVirt VM & Persistent Storage Integration Guide

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Manifests:** [`kubevirt/virtualmachines/`](../kubevirt/virtualmachines/), [`storage/nfs/`](../storage/nfs/)

---

## 1. Storage Integration Architecture & Access-Mode Boundaries

Virtual machine disks impose strict single-writer and access-mode constraints that differ significantly from stateless container mounts:

| Workload Tier | Manifest | StorageClass & Provisioner | `accessModes` / `volumeMode` | Live Migratable? | Purpose & Trade-offs |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **Standard RWO Filesystem** | [`vm-ubuntu-rwo-filesystem.yaml`](../kubevirt/virtualmachines/vm-ubuntu-rwo-filesystem.yaml) | `mayastor-nvme-r3-ext4` (`io.openebs.csi-mayastor`) | `ReadWriteOnce` / `Filesystem` | **No** (`evictionStrategy: None`) | General Linux VM OS/data disks (`disk.img` inside ext4); adds host ext4 layer; fails multi-attach across nodes. |
| **Raw Block RWO Direct** | [`vm-ubuntu-mayastor-rwo-block.yaml`](../kubevirt/virtualmachines/vm-ubuntu-mayastor-rwo-block.yaml) | `mayastor-nvme-r3-block` (`io.openebs.csi-mayastor`) | `ReadWriteOnce` / `Block` | **No** (`evictionStrategy: None`) | **Maximum I/O control tier:** QEMU writes raw `/dev/nvmeXnY` NVMe-oF device with zero host VFS/filesystem double-journaling. |
| **Default Migration RWX (NFS)** | [`vm-ubuntu-rwx-nfs-migration.yaml`](../kubevirt/virtualmachines/vm-ubuntu-rwx-nfs-migration.yaml) | `nfs-mayastor-rwx` (`nfs.csi.k8s.io`) | `ReadWriteMany` / `Filesystem` | **Yes** (`evictionStrategy: LiveMigrate`) | **Default safe live-migration storage:** Backed by Mayastor RWO (`mayastor-nfs-server`), POSIX locking, lower IOPS due to NFSv4.1 RPCs. |
| **Experimental RWX Block** | [`vm-ubuntu-rwx-block-experimental.yaml`](../kubevirt/virtualmachines/vm-ubuntu-rwx-block-experimental.yaml) | `mayastor-nvme-r3-block-rwx` (`rwxBlock: "true"`) | `ReadWriteMany` / `Block` | **Yes** (Opt-In `Manual`) | **EXPERIMENTAL research only:** Requires strict QEMU pre-copy single-writer fencing; NO DLM; NEVER default migration path. |
| **Constrained Micro-VM** | [`vm-cirros-dev-minimal.yaml`](../kubevirt/virtualmachines/vm-cirros-dev-minimal.yaml) | Ephemeral `containerDisk` (`cirros`) | Ephemeral | **No** | `256Mi` minimal KVM/console sanity check for constrained hardware clusters (`runStrategy: Manual`). |

### Critical Access-Mode & Filesystem Rules
1. **Never Configure Experimental RWX Block as Default:** `vm-ubuntu-rwx-block-exp` uses `runStrategy: Manual` and requires explicit `--include-experimental-rwx` in `07-deploy-vm-examples.sh`. Default live migration uses `nfs-mayastor-rwx` ([`storage/nfs/`](../storage/nfs/)).
2. **RWX Filesystem Rejection in Mayastor:** `io.openebs.csi-mayastor` (`v2.12.2`) rejects `ReadWriteMany` + `volumeMode: Filesystem` PVCs because ext4/xfs lack cluster-wide metadata locking and would corrupt immediately under dual mount.
3. **NFSv4.1 Gateway Architecture ([`nfs-server-mayastor.yaml`](../storage/nfs/nfs-server-mayastor.yaml)):** A single `mayastor-nfs-server` Deployment (`docker.io/itsthenetwork/nfs-server-alpine:12`) mounts `mayastor-nvme-r3-ext4` RWO (`30Gi`) once and re-exports it over ClusterIP TCP `2049` (`nfsvers=4.1,hard,timeo=600,retrans=2`) so multiple worker nodes mount safely as `ReadWriteMany`. Note single-server SPOF trade-off on gateway pod restart.

---

## 2. Cloud-Init Initialization & Security Discipline

Reproducible Ubuntu `24.04` provisioning is defined in [`kubevirt/virtualmachines/cloud-init-secret.yaml`](../kubevirt/virtualmachines/cloud-init-secret.yaml) and uses image `docker://quay.io/containerdisks/ubuntu:24.04-2610180208` via CDI `DataVolumeTemplate`:
- Installs `qemu-guest-agent`, `fio`, `nvme-cli`, and `lsscsi`.
- Enables passwordless SSH key authentication ONLY (`lock_passwd: true`); private keys and password hashes are **never** stored in Git.
- Operators pass their public key dynamically via:
  ```bash
  ./scripts/setup/07-deploy-vm-examples.sh --tier standard --ssh-key-file ~/.ssh/id_ed25519.pub
  ```
- Embeds `/usr/local/bin/verify-vm-storage.sh` and creates `/var/lib/verify-storage/boot-marker.txt` for deterministic boot and storage checks.

---

## 3. Connectivity & Storage Verification Procedure

After deploying on a target cluster with `07-deploy-vm-examples.sh`:
1. Run static + live storage validation:
   ```bash
   ./scripts/validate/validate-vm-storage.sh --require-deployed
   ```
2. Verify CDI image import and PVC binding:
   ```bash
   kubectl get dv,pvc,vmi -n kubevirt-workloads -o wide
   ```
3. Verify guest OS connectivity and disk layout via `qemu-guest-agent` and `virtctl`:
   ```bash
   virtctl guestosinfo -n kubevirt-workloads vm-ubuntu-rwo-fs
   virtctl ssh -n kubevirt-workloads ubuntu@vm-ubuntu-rwo-fs --command "sudo /usr/local/bin/verify-vm-storage.sh"
   ```
4. For raw block (`vm-ubuntu-rwo-block`), confirm QEMU presents the unformatted secondary `10Gi` `raw-bench-disk` (`/dev/vdb`) cleanly for direct `fio` or `mkfs` testing without host PVC filesystem overhead.
