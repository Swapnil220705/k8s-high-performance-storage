# OpenEBS Mayastor Testing & Validation Plan

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Milestone:** M3 — OpenEBS Mayastor Storage Engine & Volume Provisioning  
**Governance Alignment:** Strict Evidence Integrity (`AGENTS.md` §6, `ADR-011`)

---

## 1. Two-Tier Verification Architecture

To uphold complete engineering honesty across both local development hardware (Windows 11 + WSL2 Ubuntu 24.04) and target bare-metal 4-node lab hardware, verification is partitioned into two non-overlapping tiers:

1. **Tier 1 — Static Analysis, Schema Validation & Local Non-Destructive Safety Checks (Executable on WSL2)**
2. **Tier 2 — Live Cluster Deployment, NVMe DiskPool & Volume Integrity Verification (`INFRASTRUCTURE-DEPENDENT`)**

A manifest or automation script passing Tier 1 is classified strictly as `IMPLEMENTED` and statically `VALIDATED`, **never** claimed as empirical storage validation.

---

## 2. Tier 1: Local Verification Suite (Executed on WSL2)

| Check ID | Tool / Script | Scope Verified | Expected Result on WSL2 |
| :--- | :--- | :--- | :--- |
| **T1-01** | `scripts/validate/run-validation.sh` | Executable bits, `ShellCheck`, `shfmt -i 4`, `yamllint`, `kubeconform -strict` (with `diskpool_v1beta3.json` & Calico schemas), `yq` check on Helm values, `jq` JSON checks | **PASS** (0 warnings, 0 errors across all steps) |
| **T1-02** | `helm lint` & `helm template` | OpenEBS chart `4.6.2` (`values.yaml`), zero `:latest` tags, pinned `v2.12.2` images, `io-engine` 2-core / `2Gi` HugePages config, disabled LVM/ZFS/rawfile/Loki/Alloy | **PASS** (`0 chart(s) failed`) |
| **T1-03** | `scripts/setup/05-deploy-mayastor.sh --dry-run` | Automated artifact check, repo sync, `helm lint`, template audit, non-mutating prerequisite preview | **PASS** (exit `0`, zero cluster/host edits) |
| **T1-04** | `scripts/setup/05-deploy-mayastor.sh` (live mode) | WSL2 & failed-prerequisite hard safety refusal | **PASS Refusal Gate** (exits `1` immediately, zero edits) |
| **T1-05** | `scripts/validate/validate-mayastor-prerequisites.sh` | Non-destructive CPU (`x86_64`, `sse4_2`), RAM/HugePages (`2Mi`), kernel (`nvme_tcp`, `ext4`, `xfs`), read-only `lsblk` block inspection, TCP ports (`10124/8420/4421`), K8s API/nodes | **Expected Exit `1`** on WSL2 (accurately reports `FAIL` on 0 HugePages, 0 raw NVMe disks, `<3` K8s workers, and `NOT_TESTABLE` on cross-node NVMe-oF) |
| **T1-06** | `scripts/validate/validate-mayastor-deployment.sh` | Honest deployment status check when Mayastor is absent locally (`--report-only`, default, and `--require-deployed`) | **PASS Honest Detection** (`WARNING` + `NOT_TESTABLE` cleanly archived to `reports/storage/`; `--require-deployed` exits `1`) |

---

## 3. Tier 2: Target 4-Node Empirical Verification Sequence

Execute strictly in sequence **only after** college/multi-node Ubuntu 24.04 hardware (`1` control plane + `3` worker nodes with blank institutionally cleared NVMe drives) is provisioned via M2 scripts (`02`, `03`, `04`):

### Stage A: Host Preparation & Node Labeling
1. Verify HugePages (`vm.nr_hugepages = 1024` for `2048 MiB` `2MiB` pages) and kernel module `nvme_tcp` (`modprobe nvme_tcp` persisted in `/etc/modules-load.d/`) on each worker node using `scripts/setup/02-node-prerequisites.sh --apply`.
2. Label the 3 dedicated storage worker nodes cleanly (never the control plane):
   ```bash
   kubectl label node <WORKER_NODE_1> openebs.io/engine=mayastor topology.kubernetes.io/zone=rack-1 --overwrite
   kubectl label node <WORKER_NODE_2> openebs.io/engine=mayastor topology.kubernetes.io/zone=rack-2 --overwrite
   kubectl label node <WORKER_NODE_3> openebs.io/engine=mayastor topology.kubernetes.io/zone=rack-3 --overwrite
   ```
3. Run `./scripts/validate/validate-mayastor-prerequisites.sh` across nodes/control plane and confirm **exit code `0`** (`COUNT_FAIL == 0`, 3 labeled workers with `hugepages-2Mi` allocatable).

### Stage B: Chart & StorageClass Deployment
1. Verify dry-run against the live 4-node context: `./scripts/setup/05-deploy-mayastor.sh --dry-run`.
2. Execute live installation with interactive `DEPLOY-MAYASTOR` confirmation:
   ```bash
   ./scripts/setup/05-deploy-mayastor.sh
   ```
3. Verify all pods in `openebs` reach `Ready=True`, including `openebs-io-engine` (3/3 DaemonSet pods), `openebs-csi-node` (all worker nodes), `openebs-agent-core`, `openebs-api-rest`, `openebs-csi-controller`, `openebs-operator-diskpool`, `openebs-etcd` (3/3 StatefulSet), and `openebs-nats`.

### Stage C: Verified DiskPool Creation
1. On each worker node, inspect `lsblk -f` and `ls -l /dev/disk/by-id/` to identify the dedicated empty NVMe drive (`FSTYPE == ""`, zero partitions, zero mountpoints, confirmed institutional wipe permission).
2. Populate concrete node names and `/dev/disk/by-id/...` identifiers in a non-committed working copy (or verified branch config) of [`infrastructure/storage/mayastor/diskpools.yaml`](../infrastructure/storage/mayastor/diskpools.yaml), apply it, and wait for all 3 `DiskPool` objects (`openebs.io/v1beta3`) to report `cr_state=Created` and `status=Online`.

### Stage D: Replicated Provisioning, NVMe-oF Attach & Data Persistence Probe
1. Execute full active validation:
   ```bash
   ./scripts/validate/validate-mayastor-deployment.sh --require-deployed
   ```
   Confirm `0 FAIL` and `0 NOT_TESTABLE` across CRDs, Control Plane, `io-engine`, `csi-node`, 3/3 Online `DiskPools`, StorageClasses, NVMe-oF attach, and the `mayastor-integrity-verifier` write/fsync/SHA-256 readback test.
2. Verify multi-attach persistence manually across pod lifecycle (rescheduling NVMe-oF initiator):
   ```bash
   kubectl apply -f infrastructure/storage/examples/pvc-replicated-r3.yaml
   kubectl apply -f infrastructure/storage/examples/pod-verify-integrity.yaml
   kubectl wait -n mayastor-verification --for=jsonpath='{.status.phase}'=Succeeded pod/mayastor-integrity-verifier --timeout=120s
   kubectl logs -n mayastor-verification pod/mayastor-integrity-verifier
   kubectl delete -n mayastor-verification pod/mayastor-integrity-verifier
   kubectl apply -f infrastructure/storage/examples/pod-verify-integrity.yaml
   kubectl wait -n mayastor-verification --for=jsonpath='{.status.phase}'=Succeeded pod/mayastor-integrity-verifier --timeout=120s
   kubectl logs -n mayastor-verification pod/mayastor-integrity-verifier
   ```
3. Archive `kubectl get diskpools -n openebs -o wide`, `kubectl get sc,pv,pvc -A`, and `reports/storage/*.txt`/`.json` outputs as empirical evidence prior to proceeding to M4 (KubeVirt).
