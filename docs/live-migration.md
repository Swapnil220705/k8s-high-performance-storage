# KubeVirt Live Migration Architecture, Policy & Operations Runbook

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Artifacts:** [`kubevirt/migration/`](../kubevirt/migration/), [`scripts/validate/validate-live-migration.sh`](../scripts/validate/validate-live-migration.sh)

---

## 1. Honest Verification Matrix

| Capability Layer | Status | Scope & Notes |
| :--- | :---: | :--- |
| **Migration Configuration, CRs, Policies & Automation** | **`IMPLEMENTED` & Statically `VALIDATED`** | `kubevirt-cr.yaml`, `MigrationPolicy` (`v1alpha1`), `VirtualMachineInstanceMigration` (`v1`), `vm-ubuntu-rwx-nfs-migration.yaml`, and `validate-live-migration.sh` pass `yamllint`, `kubeconform -strict`, `ShellCheck`, and `--dry-run`. |
| **Cross-Node Live Migration Execution** | **`INFRASTRUCTURE-DEPENDENT`** | **NOT executed on WSL2.** Single-node K3s (`wsl2-dev-node`) cannot perform inter-node migration and lacks >=16/32 GB worker memory and Mayastor pools. Must be executed empirically on >=2 KVM worker nodes before claiming live migration success. |

---

## 2. Migration Policy, Network & Storage Requirements

### 2.1 Global & Policy Controls
- **Global KubeVirt Defaults ([`kubevirt-cr.yaml`](../kubevirt/installation/kubevirt-cr.yaml)):**
  - `disableTLS: false` (encrypts live RAM page stream between `virt-handler` peers).
  - `allowAutoConverge: true` (throttles vCPU writes temporarily if dirty-page rate prevents convergence).
  - `allowPostCopy: false` (prevents VM crashes caused by page-fault stalls if network drops).
  - `bandwidthPerMigration: "64Mi"` (`~537 Mbps` cap protecting co-located NVMe-oF TCP traffic on `1 GbE`/`10 GbE` links).
  - `completionTimeoutPerGiB: 800`, `progressTimeout: 150`.
- **Policy Overrides ([`migration-policy.yaml`](../kubevirt/migration/migration-policy.yaml)):**
  - `default-nfs-rwx-migration-policy` targets `kubevirt.io/migration-tier: default-nfs-rwx` (`64Mi/s`, `completionTimeoutPerGiB: 800`).
  - `experimental-rwx-block-migration-policy` targets opt-in `experimental-rwx-block` VMs (`128Mi/s`, `completionTimeoutPerGiB: 600`).

### 2.2 Network Considerations
- Live migration transfers iterative dirty guest RAM pages directly between source and target QEMU/virt-launcher endpoints over **TCP `49152–49215`** (`ARCHITECTURE.md` Canonical Port #16).
- **Default Routing:** Flows over the cluster pod network (Calico v3.33 unencapsulated BGP mesh on target hardware).
- **Isolated Migration Interface Option:** Setting `spec.configuration.migrations.network` in `kubevirt-cr.yaml` to a Multus `NetworkAttachmentDefinition` isolates memory transfers onto a dedicated NIC/VLAN so RAM streaming does not contend with Mayastor NVMe-oF TCP (:8420).

### 2.3 VM & Memory Sizing Prerequisites
1. **Shared Storage (`ReadWriteMany`):** `evictionStrategy: LiveMigrate` + masquerade pod interface + `nfs-mayastor-rwx` default PVC (or opt-in `mayastor-nvme-r3-block-rwx`). `ReadWriteOnce` VMs are rejected cleanly by `validate-live-migration.sh`.
2. **Multi-Node RAM Headroom (`ARCHITECTURE.md` §2.1):** Because loaded `16 GB` workers suffer a `−0.60 to −5.20 GiB` OOM deficit during concurrent cutover, **32 GB RAM per worker node** is recommended for reliable multi-VM live migration.

---

## 3. Execution, Failure Handling & Post-Migration Verification

### 3.1 Triggering & Monitoring Migration
Run via CLI or declarative `VirtualMachineInstanceMigration` ([`live-migration-job.yaml`](../kubevirt/migration/live-migration-job.yaml)):
```bash
# Option A: Automated validator + executor (recommended)
./scripts/validate/validate-live-migration.sh --execute \
  --vmi vm-ubuntu-migration-nfs \
  --namespace kubevirt-workloads \
  --timeout 300

# Option B: Direct virtctl command
virtctl migrate vm-ubuntu-migration-nfs -n kubevirt-workloads
kubectl get vmim -n kubevirt-workloads -w
```

### 3.2 Failure & Timeout Handling
- **`progressTimeout` (`150s`) / `completionTimeoutPerGiB`:** KubeVirt aborts stuck pre-copy transfers and leaves the guest safely executing on the source worker node.
- **Script Timeout Rollback:** If migration fails to reach `Succeeded` within `--timeout`, `validate-live-migration.sh` deletes the `VirtualMachineInstanceMigration` object (`kubectl delete vmim`), leaving source VM integrity intact (`virtctl migrate-cancel` is equivalent manual rollback).
- **Common Failure Causes:** RWO PVC attached (`NonMigratable` condition), insufficient RAM/CPU on target workers, blocked TCP `49152–49215` firewall rules, or host-specific CPU features preventing cross-node migration without `cpuModel` alignment.

### 3.3 Post-Migration Verification Checklist
1. Confirm `vmi.status.nodeName` changed (`Worker A -> Worker B`) and `vmi.status.phase == Running`.
2. Inspect `vmi.status.migrationState` (`completed: true`, `failed: false`, `startTimestamp` / `endTimestamp`).
3. Verify guest OS uptime/continuity & storage marker without reboot:
   ```bash
   virtctl guestosinfo -n kubevirt-workloads vm-ubuntu-migration-nfs
   virtctl ssh -n kubevirt-workloads ubuntu@vm-ubuntu-migration-nfs \
     --command "cat /var/lib/verify-storage/boot-marker.txt && sudo /usr/local/bin/verify-vm-storage.sh"
   ```
