# FIO Storage Performance Benchmarking Guide

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Program:** Zoho SETU — College Student Project Program  
**Toolchain Pinned:** Flexible I/O Tester `fio` `>= 3.30` (locally validated with `fio-3.36`), Python `3.12+` parser  
**Three-State Classification:** `IMPLEMENTED` + `VALIDATED` (FIO profiles, `--parse-only`, safety checks, Python parser unit suite, synthetic pipeline) | `INFRASTRUCTURE-DEPENDENT` (Bare-metal & multi-node NVMe/Mayastor/KubeVirt IOPS & tail-latency measurements)

---

## 1. Standardized Job Profiles ([`benchmarks/fio/`](../benchmarks/fio/))

All profiles enforce `direct=1`, `ioengine=libaio` (overridable to `io_uring`), `time_based=1`, warmup `ramp_time`, `group_reporting=1`, and completion-latency percentiles `50:95:99:99.9` (`clat_percentiles=1`). Profiles intentionally **omit** hardcoded `filename=` paths so operators must pass verified targets explicitly.

| Profile File | Workload Pattern | Block Size | Default `iodepth` | Default `numjobs` | Measurement Objective |
| :--- | :--- | :---: | :---: | :---: | :--- |
| [`4k-randread.fio`](../benchmarks/fio/4k-randread.fio) | `randread` | `4k` | `32` | `1` | Peak random read IOPS & tail latency |
| [`4k-randwrite.fio`](../benchmarks/fio/4k-randwrite.fio) | `randwrite` | `4k` | `32` | `1` | Synchronous 3-way write replication latency penalty |
| [`4k-randrw-70-30.fio`](../benchmarks/fio/4k-randrw-70-30.fio) | `randrw` (70/30) | `4k` | `16` | `2` | Mixed transactional OLTP simulation |
| [`64k-seqread.fio`](../benchmarks/fio/64k-seqread.fio) | `read` | `64k` | `16` | `1` | Streaming read bandwidth & IOPS |
| [`64k-seqwrite.fio`](../benchmarks/fio/64k-seqwrite.fio) | `write` | `64k` | `16` | `1` | Streaming write replication pipeline |
| [`1m-bandwidth.fio`](../benchmarks/fio/1m-bandwidth.fio) | Sequential `read` + `write` | `1m` | `8` | `2` | NIC / NVMe-oF TCP saturation ceiling (`MiB/s`) |

Queue-depth sweeps (`1, 16, 32, 64`) and job scaling (`1, 4`) are parameterized via [`benchmarks/fio/matrix-config.yaml`](../benchmarks/fio/matrix-config.yaml) and `--qds` / `--numjobs` in [`run-fio-benchmarks.sh`](../scripts/benchmark/run-fio-benchmarks.sh).

---

## 2. Target Storage Tiers & Evidence Separation Protocol

1. **`local-baseline`:** Physical host NVMe filesystem control (zero network/SPDK/VM overhead).
2. **`mayastor-rwo-fs`:** 3-replica NVMe-oF TCP ext4 PVC (`mayastor-nvme-r3-ext4`).
3. **`mayastor-rwo-block`:** 3-replica NVMe-oF TCP raw Block (`mayastor-nvme-r3-block` / KubeVirt `/dev/vdb`).
4. **`nfs-rwx`:** NFSv4.1 shared filesystem (`nfs-mayastor-rwx`) quantifying NFS RPC translation overhead.
5. **`mayastor-rwx-block-exp`** *(Opt-In)*: Experimental native Mayastor RWX Block (`mayastor-nvme-r3-block-rwx`).

> [!CAUTION]
> **Anti-Fabrication & Comparability Rules:**
> - **Never present WSL2 virtual disks as NVMe hardware benchmarks.**
> - Every run records an explicit `evidence_level` (`EMPIRICAL_HARDWARE`, `WSL2_PIPELINE_ONLY`, `SYNTHETIC_FIXTURE`, or `DRY_RUN`) in `benchmark-metadata.json`.
> - [`scripts/benchmark/summarize-results.py`](../scripts/benchmark/summarize-results.py) rejects cross-environment comparisons (`--compare`) with exit code `2` unless `--allow-mixed-env` is specified alongside mandatory warning banners.

---

## 3. Execution, Safety & Summary Commands

```bash
# 1. Non-destructive validation of all FIO profiles & Python parser (safe anywhere)
./scripts/benchmark/run-fio-benchmarks.sh --mode dry-run

# 2. Verify JSON parser pipeline on clearly labeled SYNTHETIC_FIXTURE data
./scripts/benchmark/run-fio-benchmarks.sh --mode synthetic-fixture

# 3. Execute live matrix on confirmed bare-metal / VM target (example: raw block /dev/vdb inside KubeVirt VM)
./scripts/benchmark/run-fio-benchmarks.sh \
  --mode execute \
  --target-tier mayastor-rwo-block \
  --target-path /dev/vdb \
  --size 2G --runtime 120 --ramp 30 \
  --qds 1,16,32 --numjobs 1,4 \
  --confirm-target YES-I-CONFIRMED-TARGET

# 4. Aggregate & compare same-environment results safely
python3 scripts/benchmark/summarize-results.py \
  --input benchmarks/results/baremetal-run-1 \
  --input benchmarks/results/baremetal-run-2 \
  --compare \
  --output-markdown benchmarks/results/comparison-summary.md \
  --output-json benchmarks/results/comparison-summary.json
```

### Target-Path Safety Protections Built into `run-fio-benchmarks.sh`
- Blocks system paths (`/`, `/boot`, `/etc`, `/usr`, `/var`, `/proc`, `/sys`).
- Resolves root device via `findmnt -n -o SOURCE /` and refuses writes overlapping the OS disk.
- Verifies raw block tiers point to unmounted block devices (`lsblk -no MOUNTPOINT` must be empty).
- Enforces `free_space >= requested_size + 1 GiB` on filesystem targets and refuses non-`local-baseline` execution on WSL2.

