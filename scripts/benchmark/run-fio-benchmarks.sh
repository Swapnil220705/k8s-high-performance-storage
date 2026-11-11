#!/usr/bin/env bash
# ==============================================================================
# Script Name: run-fio-benchmarks.sh
# Project: Deploy High-Performance Storage for Kubernetes (Zoho SETU - SWFW_5S_08)
# Purpose: Validates versioned FIO job profiles, enforces target-device and free-space
#          safety checks, collects host/CPU/memory metadata, executes multi-tier FIO
#          matrices, and invokes scripts/benchmark/summarize-results.py.
#
# Modes & Governance:
#   - `--mode dry-run` (DEFAULT): Validates all FIO profiles via `fio --parse-only`,
#     runs Python parser validation, performs ZERO storage writes.
#   - `--mode synthetic-fixture`: Validates the end-to-end FIO parser & reporting
#     pipeline on clearly labeled synthetic JSON fixtures in a temp directory.
#   - `--mode execute`: Runs actual FIO jobs against an explicitly confirmed path.
#     Requires `--target-tier`, `--target-path`, `--confirm-target YES-I-CONFIRMED-TARGET`.
#     Refuses raw NVMe/Mayastor claims inside WSL2; WSL2 pipeline smoke tests require
#     `--allow-wsl2-pipeline-test` and label outputs `WSL2_PIPELINE_ONLY`.
# ==============================================================================

set -euo pipefail

log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

FIO_DIR="${REPO_ROOT}/benchmarks/fio"
RESULTS_ROOT="${REPO_ROOT}/benchmarks/results"
SUMMARIZER="${SCRIPT_DIR}/summarize-results.py"

MODE="dry-run" # dry-run, synthetic-fixture, execute
TARGET_TIER="local-baseline"
TARGET_PATH=""
CONFIRM_TARGET=""
PROFILES="all"
QDS=""
NUMJOBS_LIST="1"
SIZE="2G"
RUNTIME="120"
RAMP_TIME="30"
IOENGINE="libaio"
ENVIRONMENT_CLASS=""
OUTPUT_DIR=""
ALLOW_WSL2_PIPELINE_TEST=false

IS_WSL2=false
if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    IS_WSL2=true
fi

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Runs non-destructive FIO profile validation or explicitly confirmed storage benchmarks.

Options:
      --mode MODE                 Execution mode: dry-run (default), synthetic-fixture, execute
      --target-tier TIER          Storage tier under test:
                                    local-baseline | mayastor-rwo-fs | mayastor-rwo-block |
                                    nfs-rwx | mayastor-rwx-block-exp
      --target-path PATH          Target test file (filesystem) or block device (raw block)
      --confirm-target ACK        Required for --mode execute: YES-I-CONFIRMED-TARGET
      --profiles LIST             Comma-separated profile IDs or 'all' (default: all)
      --qds LIST                  Optional comma-separated iodepth overrides (e.g. 1,16,32)
      --numjobs LIST              Optional comma-separated job count overrides (default: 1)
      --size SIZE                 Test dataset size per job (default: 2G)
      --runtime SEC               Timed runtime in seconds (default: 120)
      --ramp SEC                  Warmup ramp time in seconds (default: 30)
      --ioengine ENGINE           FIO ioengine (libaio or io_uring; default: libaio)
      --env-class CLASS           Explicit environment class label (e.g. bare-metal-4node)
  -o, --output-dir DIR            Directory to write JSON outputs & summary
      --allow-wsl2-pipeline-test  Permit tiny (<= 64M) temp-dir pipeline test inside WSL2
                                  (outputs tagged WSL2_PIPELINE_ONLY, never NVMe evidence)
  -h, --help                      Display this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --mode)
        MODE="${2:-}"
        shift 2
        ;;
    --target-tier)
        TARGET_TIER="${2:-}"
        shift 2
        ;;
    --target-path)
        TARGET_PATH="${2:-}"
        shift 2
        ;;
    --confirm-target)
        CONFIRM_TARGET="${2:-}"
        shift 2
        ;;
    --profiles)
        PROFILES="${2:-}"
        shift 2
        ;;
    --qds)
        QDS="${2:-}"
        shift 2
        ;;
    --numjobs)
        NUMJOBS_LIST="${2:-}"
        shift 2
        ;;
    --size)
        SIZE="${2:-}"
        shift 2
        ;;
    --runtime)
        RUNTIME="${2:-}"
        shift 2
        ;;
    --ramp)
        RAMP_TIME="${2:-}"
        shift 2
        ;;
    --ioengine)
        IOENGINE="${2:-}"
        shift 2
        ;;
    --env-class)
        ENVIRONMENT_CLASS="${2:-}"
        shift 2
        ;;
    -o | --output-dir)
        OUTPUT_DIR="${2:-}"
        shift 2
        ;;
    --allow-wsl2-pipeline-test)
        ALLOW_WSL2_PIPELINE_TEST=true
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        log_error "Unknown option: $1"
        usage >&2
        exit 2
        ;;
    esac
done

case "${MODE}" in
dry-run | synthetic-fixture | execute) ;;
*)
    log_error "Invalid --mode '${MODE}'. Must be dry-run, synthetic-fixture, or execute."
    exit 2
    ;;
esac

case "${TARGET_TIER}" in
local-baseline | mayastor-rwo-fs | mayastor-rwo-block | nfs-rwx | mayastor-rwx-block-exp) ;;
*)
    log_error "Invalid --target-tier '${TARGET_TIER}'."
    exit 2
    ;;
esac

for bin in fio python3 jq; do
    if ! command -v "${bin}" >/dev/null 2>&1; then
        log_error "Required binary '${bin}' not found in PATH."
        exit 2
    fi
done

parse_size_mib() {
    local spec="$1"
    local num unit
    if [[ "${spec}" =~ ^([0-9]+)([KkMmGg]?)[Bb]?$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        case "${unit^^}" in
        "") echo $((num / 1024 / 1024)) ;;
        K) echo $((num / 1024)) ;;
        M) echo "${num}" ;;
        G) echo $((num * 1024)) ;;
        *) echo "0" ;;
        esac
    else
        echo "0"
    fi
}

resolve_profiles() {
    local -a list=()
    if [[ "${PROFILES}" == "all" ]]; then
        for f in \
            "${FIO_DIR}/4k-randread.fio" \
            "${FIO_DIR}/4k-randwrite.fio" \
            "${FIO_DIR}/4k-randrw-70-30.fio" \
            "${FIO_DIR}/64k-seqread.fio" \
            "${FIO_DIR}/64k-seqwrite.fio" \
            "${FIO_DIR}/1m-bandwidth.fio"; do
            list+=("${f}")
        done
    else
        IFS=',' read -ra ids <<<"${PROFILES}"
        for id in "${ids[@]}"; do
            local candidate="${FIO_DIR}/${id%.fio}.fio"
            if [[ ! -f "${candidate}" ]]; then
                log_error "Requested FIO profile not found: ${candidate}"
                exit 2
            fi
            list+=("${candidate}")
        done
    fi
    printf '%s\n' "${list[@]}"
}

validate_fio_profiles() {
    local -a files
    mapfile -t files < <(resolve_profiles)
    log_info "Validating ${#files[@]} FIO profile(s) with $(fio --version) (--parse-only)..."
    for f in "${files[@]}"; do
        fio --parse-only --ioengine="${IOENGINE}" "${f}" >/dev/null
        echo "    [OK] $(basename "${f}")"
    done
    python3 -m py_compile "${SUMMARIZER}"
    echo "    [OK] $(basename "${SUMMARIZER}") syntax check"
}

write_environment_metadata() {
    local out_dir="$1"
    local evidence_level="$2"
    local env_class="$3"
    local cpu_stat_before="${4:-}"
    local cpu_stat_after="${5:-}"
    local mem_total mem_avail huge_total huge_free kernel cpu_model cpu_cores fio_ver

    mem_total="$(awk '/^MemTotal:/ {print $2 " " $3}' /proc/meminfo 2>/dev/null || echo 'unknown')"
    mem_avail="$(awk '/^MemAvailable:/ {print $2 " " $3}' /proc/meminfo 2>/dev/null || echo 'unknown')"
    huge_total="$(awk '/^HugePages_Total:/ {print $2}' /proc/meminfo 2>/dev/null || echo '0')"
    huge_free="$(awk '/^HugePages_Free:/ {print $2}' /proc/meminfo 2>/dev/null || echo '0')"
    kernel="$(uname -r)"
    cpu_model="$(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo 'unknown')"
    cpu_cores="$(nproc 2>/dev/null || echo '1')"
    fio_ver="$(fio --version 2>/dev/null || echo 'unknown')"

    jq -n \
        --arg schema "1.0" \
        --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg host "$(hostname)" \
        --arg kernel "${kernel}" \
        --arg cpu_model "${cpu_model}" \
        --arg cpu_cores "${cpu_cores}" \
        --arg mem_total "${mem_total}" \
        --arg mem_avail "${mem_avail}" \
        --arg huge_total "${huge_total}" \
        --arg huge_free "${huge_free}" \
        --arg fio_version "${fio_ver}" \
        --arg target_tier "${TARGET_TIER}" \
        --arg target_path "${TARGET_PATH}" \
        --arg env_class "${env_class}" \
        --arg evidence_level "${evidence_level}" \
        --arg wsl2 "${IS_WSL2}" \
        --arg cpu_stat_before "${cpu_stat_before}" \
        --arg cpu_stat_after "${cpu_stat_after}" \
        '{
            schema_version: $schema,
            timestamp_utc: $ts,
            hostname: $host,
            kernel: $kernel,
            wsl2_detected: ($wsl2 == "true"),
            environment_class: $env_class,
            evidence_level: $evidence_level,
            target_tier: $target_tier,
            target_path: $target_path,
            fio_version: $fio_version,
            host_resources: {
                cpu_model: $cpu_model,
                cpu_cores: ($cpu_cores | tonumber? // $cpu_cores),
                mem_total: $mem_total,
                mem_available: $mem_avail,
                hugepages_total: ($huge_total | tonumber? // 0),
                hugepages_free: ($huge_free | tonumber? // 0),
                proc_stat_cpu_before: $cpu_stat_before,
                proc_stat_cpu_after: $cpu_stat_after
            }
        }' >"${out_dir}/benchmark-metadata.json"
}

assert_safe_target() {
    if [[ -z "${TARGET_PATH}" ]]; then
        log_error "--target-path is required in execute mode."
        exit 2
    fi
    if [[ "${CONFIRM_TARGET}" != "YES-I-CONFIRMED-TARGET" ]]; then
        log_error "Refusing execute mode without explicit '--confirm-target YES-I-CONFIRMED-TARGET'."
        exit 1
    fi

    # Protect critical system directories & root filesystems
    local norm_target
    norm_target="$(readlink -f "${TARGET_PATH}" 2>/dev/null || echo "${TARGET_PATH}")"
    case "${TARGET_PATH}" in
    / | /boot* | /etc* | /usr* | /var* | /bin* | /sbin* | /lib* | /proc* | /sys*)
        log_error "Refusing unsafe target path inside system directory: ${TARGET_PATH}"
        exit 1
        ;;
    esac

    local root_src
    root_src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
    if [[ -n "${root_src}" ]] && [[ "${norm_target}" == "${root_src}" || "${root_src}" == "${norm_target}"* ]]; then
        log_error "Refusing write against host root block device (${root_src}): ${norm_target}"
        exit 1
    fi

    if [[ "${IS_WSL2}" == true ]]; then
        if [[ "${ALLOW_WSL2_PIPELINE_TEST}" != true ]]; then
            log_error "WSL2 detected: Physical NVMe / Mayastor / NFS benchmarks are NOT valid on WSL2 virtual disks."
            log_error "Use '--mode dry-run' or '--mode synthetic-fixture', or pass '--allow-wsl2-pipeline-test' with <= 64M temp file."
            exit 1
        fi
        if [[ "${TARGET_TIER}" != "local-baseline" ]]; then
            log_error "On WSL2, only '--target-tier local-baseline' may be used for pipeline smoke tests (not '${TARGET_TIER}')."
            exit 1
        fi
        local req_mib
        req_mib="$(parse_size_mib "${SIZE}")"
        if [[ "${req_mib}" -gt 64 ]] || [[ "${req_mib}" -le 0 ]]; then
            log_error "WSL2 pipeline smoke test limits --size to <= 64M (requested '${SIZE}' -> ${req_mib} MiB)."
            exit 1
        fi
        if [[ "${TARGET_PATH}" == /dev/* ]]; then
            log_error "WSL2 pipeline smoke test strictly refuses raw /dev/* targets."
            exit 1
        fi
    fi

    if [[ "${TARGET_TIER}" == "mayastor-rwo-block" || "${TARGET_TIER}" == "mayastor-rwx-block-exp" ]]; then
        if [[ ! -b "${norm_target}" ]]; then
            log_error "Raw block tier '${TARGET_TIER}' requires an existing block device (--target-path '${TARGET_PATH}')."
            exit 1
        fi
        local mp
        mp="$(lsblk -no MOUNTPOINT "${norm_target}" 2>/dev/null | head -n 1 || true)"
        if [[ -n "${mp}" ]]; then
            log_error "Refusing raw block write on mounted device '${norm_target}' (mountpoint: '${mp}')."
            exit 1
        fi
    else
        local parent_dir
        parent_dir="$(dirname "${TARGET_PATH}")"
        if [[ ! -d "${parent_dir}" ]]; then
            log_error "Target parent directory does not exist: ${parent_dir}"
            exit 1
        fi
        local avail_kb req_mib margin_kb
        avail_kb="$(df -Pk "${parent_dir}" | awk 'NR==2 {print $4}')"
        req_mib="$(parse_size_mib "${SIZE}")"
        margin_kb=$(((req_mib + 1024) * 1024))
        if [[ "${req_mib}" -gt 64 ]] && [[ "${avail_kb}" -lt "${margin_kb}" ]]; then
            log_error "Insufficient disk space in ${parent_dir}: ${avail_kb} KiB available, need >= ${margin_kb} KiB (${SIZE} + 1GiB safety margin)."
            exit 1
        fi
    fi
}

run_synthetic_fixture_mode() {
    local out_dir="${OUTPUT_DIR:-$(mktemp -d /tmp/fio-synthetic-XXXXXX)}"
    mkdir -p "${out_dir}"
    write_environment_metadata "${out_dir}" "SYNTHETIC_FIXTURE" "synthetic-fixture"

    cat >"${out_dir}/sample-4k-randread-synthetic.json" <<'EOF'
{
  "fio version": "fio-3.36",
  "global options": {
    "ioengine": "libaio",
    "direct": "1",
    "bs": "4k",
    "iodepth": "32",
    "numjobs": "1"
  },
  "jobs": [
    {
      "jobname": "randread-4k",
      "job options": {"rw": "randread", "bs": "4k", "iodepth": "32", "numjobs": "1"},
      "usr_cpu": 4.2,
      "sys_cpu": 9.8,
      "read": {
        "iops": 125000.0,
        "bw_bytes": 512000000,
        "clat_ns": {
          "mean": 255000.0,
          "percentile": {
            "50.000000": 210000,
            "95.000000": 410000,
            "99.000000": 690000,
            "99.900000": 1150000
          }
        }
      },
      "write": {"iops": 0.0, "bw_bytes": 0, "clat_ns": {"mean": 0.0, "percentile": {}}}
    }
  ]
}
EOF
    log_warn "Generated SYNTHETIC_FIXTURE JSON in ${out_dir} for parser verification ONLY (not measured storage performance)."
    python3 "${SUMMARIZER}" --input "${out_dir}" --output-markdown "${out_dir}/summary.md" --output-json "${out_dir}/summary.json"
    if [[ -z "${OUTPUT_DIR}" ]]; then
        rm -rf "${out_dir}"
    fi
}

run_execute_mode() {
    assert_safe_target
    local evidence_level="EMPIRICAL_HARDWARE"
    local env_class="${ENVIRONMENT_CLASS:-bare-metal-4node}"
    if [[ "${IS_WSL2}" == true ]]; then
        evidence_level="WSL2_PIPELINE_ONLY"
        env_class="wsl2-virtual"
        log_warn "Executing tiny WSL2 pipeline verification ONLY (${evidence_level}). Do NOT cite as physical NVMe performance."
    fi

    local ts
    ts="$(date '+%Y-%m-%d_%H-%M-%S')"
    local out_dir="${OUTPUT_DIR:-${RESULTS_ROOT}/${TARGET_TIER}_${ts}}"
    mkdir -p "${out_dir}"

    local -a files
    mapfile -t files < <(resolve_profiles)
    local -a qd_list=()
    if [[ -n "${QDS}" ]]; then
        IFS=',' read -ra qd_list <<<"${QDS}"
    fi
    IFS=',' read -ra nj_list <<<"${NUMJOBS_LIST}"

    local cpu_before cpu_after
    cpu_before="$(awk '/^cpu / {print $0; exit}' /proc/stat 2>/dev/null || true)"

    for f in "${files[@]}"; do
        local pid_base
        pid_base="$(basename "${f}" .fio)"
        if [[ "${#qd_list[@]}" -gt 0 ]]; then
            for qd in "${qd_list[@]}"; do
                for nj in "${nj_list[@]}"; do
                    local out_json="${out_dir}/${pid_base}_qd${qd}_j${nj}.json"
                    log_info "Running ${pid_base} (qd=${qd}, jobs=${nj}, size=${SIZE}, runtime=${RUNTIME}s) -> ${TARGET_PATH}"
                    fio "${f}" \
                        --ioengine="${IOENGINE}" \
                        --filename="${TARGET_PATH}" \
                        --size="${SIZE}" \
                        --runtime="${RUNTIME}" \
                        --ramp_time="${RAMP_TIME}" \
                        --iodepth="${qd}" \
                        --numjobs="${nj}" \
                        --output-format=json \
                        --output="${out_json}"
                done
            done
        else
            for nj in "${nj_list[@]}"; do
                local out_json="${out_dir}/${pid_base}_j${nj}.json"
                log_info "Running ${pid_base} (jobs=${nj}, size=${SIZE}, runtime=${RUNTIME}s) -> ${TARGET_PATH}"
                fio "${f}" \
                    --ioengine="${IOENGINE}" \
                    --filename="${TARGET_PATH}" \
                    --size="${SIZE}" \
                    --runtime="${RUNTIME}" \
                    --ramp_time="${RAMP_TIME}" \
                    --numjobs="${nj}" \
                    --output-format=json \
                    --output="${out_json}"
            done
        fi
    done

    cpu_after="$(awk '/^cpu / {print $0; exit}' /proc/stat 2>/dev/null || true)"
    write_environment_metadata "${out_dir}" "${evidence_level}" "${env_class}" "${cpu_before}" "${cpu_after}"
    python3 "${SUMMARIZER}" --input "${out_dir}" --output-markdown "${out_dir}/summary.md" --output-json "${out_dir}/summary.json"
    log_info "Benchmark artifacts archived under: ${out_dir}"
}

validate_fio_profiles

case "${MODE}" in
dry-run)
    if [[ -n "${OUTPUT_DIR}" ]]; then
        mkdir -p "${OUTPUT_DIR}"
        write_environment_metadata "${OUTPUT_DIR}" "DRY_RUN" "${ENVIRONMENT_CLASS:-dry-run-validation}"
    fi
    log_info "[DRY-RUN] All FIO profiles and parser checks passed with zero disk I/O."
    ;;
synthetic-fixture)
    run_synthetic_fixture_mode
    ;;
execute)
    run_execute_mode
    ;;
esac

exit 0
