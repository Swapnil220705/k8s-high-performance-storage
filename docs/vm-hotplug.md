# KubeVirt Runtime Resource Hot-Plugging Guide (CPU, Memory & Disk)

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Artifacts:** [`kubevirt/hotplug/`](../kubevirt/hotplug/), [`scripts/validate/validate-vm-hotplug.sh`](../scripts/validate/validate-vm-hotplug.sh)

---

## 1. Capability Matrix, Guest Agent & Restart Boundaries

Under **KubeVirt `v1.9.1`** (`vmRolloutStrategy: LiveUpdate`, GA since `v1.5.0`), hot-plug behavior differs strictly across scale-up, scale-down, and storage operations:

| Hot-Plug Operation | Live Execution? | Guest OS / Kernel Requirement | `qemu-guest-agent` Required? | Restart / Caveats |
| :--- | :---: | :--- | :---: | :--- |
| **CPU Scale-Up** (`sockets: 2 -> 4`) | **Yes (Live)** | Linux ACPI CPU hot-add (Ubuntu 24.04 kernel 6.8 supports out of the box) | Recommended for topology verification | KubeVirt scales **sockets** only; `cores` and `threads` stay constant; bounded by `domain.cpu.maxSockets`. |
| **CPU Scale-Down** (`4 -> 2`) | **No** | — | — | Shrinking sockets requires a **VM restart** (`Stage`/reboot). |
| **Memory Scale-Up** (`guest: 2Gi -> 4Gi`) | **Yes (Live)** | Linux ACPI memory hot-add (`virtio-mem`/DIMM; Ubuntu 24.04 udev online rules) | Recommended for live guest confirmation | Pod `resources.limits.memory` must cover `maxGuest` + QEMU overhead or cgroup OOMKill occurs. |
| **Memory Scale-Down** (`4Gi -> 2Gi`) | **No** | — | — | Shrinking guest RAM requires a **VM restart**. |
| **Disk Attach** (`virtctl addvolume`) | **Yes (Live)** | `virtio_scsi` kernel driver (built into Ubuntu 24.04) | Optional (helpful for clean sync/mount checks) | Attaches over **`scsi`** bus cleanly via `hotplugVolume` sidecar pod (`/dev/sda`, `/dev/sdb`). |
| **Disk Detach** (`virtctl removevolume`) | **Yes (Live)** | Guest must `umount` filesystems first | — | Unplugging a still-mounted filesystem risks guest I/O errors; unmount inside guest before `removevolume`. |

---

## 2. Manifest Design (`kubevirt/hotplug/`)

1. **[`vm-ubuntu-hotplug-ready.yaml`](../kubevirt/hotplug/vm-ubuntu-hotplug-ready.yaml):**
   - `domain.cpu`: `sockets: 2`, `cores: 1`, `threads: 1`, `maxSockets: 4`.
   - `domain.memory`: `guest: 2Gi`, `maxGuest: 4Gi`.
   - `domain.resources`: `requests: { cpu: "2", memory: "2Gi" }`, `limits: { cpu: "4", memory: "4608Mi" }` (leaves headroom above `4Gi` `maxGuest` for QEMU/libvirt memory so live scale-up avoids container cgroup OOM).
2. **[`hotplug-data-volume.yaml`](../kubevirt/hotplug/hotplug-data-volume.yaml):**
   - Stages a 3-replica Filesystem PVC (`hotplug-extra-disk-01`, `mayastor-nvme-r3-ext4`, `5Gi`) and a blank raw Block DataVolume (`hotplug-extra-block-02`, `mayastor-nvme-r3-block`, `5Gi`) for dynamic SCSI hot-plug attachment.

---

## 3. Execution, Verification & Rollback Commands (Target Cluster)

### 3.1 Pre-flight Check (Safe Anywhere)
```bash
./scripts/validate/validate-vm-hotplug.sh --dry-run
```

### 3.2 Live CPU, Memory & Disk Execution (`INFRASTRUCTURE-DEPENDENT`)
```bash
# Automated all-in-one flow (live CPU 2->3 sockets, RAM 2Gi->3Gi, SCSI attach/detach):
./scripts/validate/validate-vm-hotplug.sh --execute --operation all

# Manual equivalent commands:
# 1. CPU Socket Scale-Up:
kubectl -n kubevirt-workloads patch vm vm-ubuntu-hotplug --type merge \
  -p '{"spec":{"template":{"spec":{"domain":{"cpu":{"sockets":3}}}}}}'

# 2. Guest Memory Scale-Up:
kubectl -n kubevirt-workloads patch vm vm-ubuntu-hotplug --type merge \
  -p '{"spec":{"template":{"spec":{"domain":{"memory":{"guest":"3Gi"}}}}}}'

# 3. Secondary Disk Attach & Verify:
virtctl addvolume vm-ubuntu-hotplug -n kubevirt-workloads \
  --volume-name=hotplug-extra-disk-01 --persist
```

### 3.3 Verification (Kubernetes + Guest OS)
- **Kubernetes API:**
  ```bash
  kubectl -n kubevirt-workloads get vmi vm-ubuntu-hotplug -o jsonpath='{.status.currentCPUTopology}{"\n"}{.status.memory}{"\n"}{.status.volumeStatus}{"\n"}'
  ```
- **Inside Ubuntu Guest (must show zero reboot via `uptime`):**
  ```bash
  uptime && nproc && lscpu | grep -E 'Socket|CPU\(s\)'
  free -m
  lsblk -o NAME,SIZE,TYPE,TRAN,MODEL
  ```

### 3.4 Cleanup & Rollback Procedure
```bash
# 1. Inside guest OS, unmount any mounted hot-plugged partition:
# sudo umount /mnt/hotplug-disk && sync
# 2. Detach SCSI volume live (zero reboot):
virtctl removevolume vm-ubuntu-hotplug -n kubevirt-workloads --volume-name=hotplug-extra-disk-01
# 3. If reverting CPU sockets or memory downward, patch VM back and perform controlled restart:
virtctl restart vm-ubuntu-hotplug -n kubevirt-workloads
```
