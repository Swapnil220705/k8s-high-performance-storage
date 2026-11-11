#!/usr/bin/env python3
"""Parse, validate, and summarize FIO benchmark JSON outputs safely.

Project: Deploy High-Performance Storage for Kubernetes (SWFW_5S_08)
Governance:
  - Enforces explicit evidence-level labeling (EMPIRICAL_HARDWARE, SYNTHETIC_FIXTURE,
    WSL2_PIPELINE_ONLY, DRY_RUN) so synthetic or WSL2 results are never misrepresented
    as bare-metal Mayastor/NVMe hardware benchmarks.
  - Prevents direct performance comparisons across heterogeneous environment_class
    values unless --allow-mixed-env is explicitly requested with warning banners.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


VALID_EVIDENCE_LEVELS = {
    "EMPIRICAL_HARDWARE",
    "SYNTHETIC_FIXTURE",
    "WSL2_PIPELINE_ONLY",
    "DRY_RUN",
    "UNKNOWN",
}


@dataclass
class BenchmarkRecord:
    """Normalized benchmark metric row extracted from a single FIO job run."""

    source_file: str
    job_name: str
    pattern: str
    block_size: str
    queue_depth: str
    numjobs: str
    target_tier: str
    environment_class: str
    evidence_level: str
    read_iops: float
    write_iops: float
    read_bw_mib_s: float
    write_bw_mib_s: float
    read_lat_mean_us: float
    write_lat_mean_us: float
    read_p50_us: float
    read_p95_us: float
    read_p99_us: float
    read_p999_us: float
    write_p50_us: float
    write_p95_us: float
    write_p99_us: float
    write_p999_us: float
    usr_cpu_pct: float
    sys_cpu_pct: float

    @property
    def total_iops(self) -> float:
        return self.read_iops + self.write_iops

    @property
    def total_bw_mib_s(self) -> float:
        return self.read_bw_mib_s + self.write_bw_mib_s

    def to_dict(self) -> dict[str, Any]:
        return {
            "source_file": self.source_file,
            "job_name": self.job_name,
            "pattern": self.pattern,
            "block_size": self.block_size,
            "queue_depth": self.queue_depth,
            "numjobs": self.numjobs,
            "target_tier": self.target_tier,
            "environment_class": self.environment_class,
            "evidence_level": self.evidence_level,
            "read_iops": round(self.read_iops, 2),
            "write_iops": round(self.write_iops, 2),
            "total_iops": round(self.total_iops, 2),
            "read_bw_mib_s": round(self.read_bw_mib_s, 2),
            "write_bw_mib_s": round(self.write_bw_mib_s, 2),
            "total_bw_mib_s": round(self.total_bw_mib_s, 2),
            "read_lat_mean_us": round(self.read_lat_mean_us, 2),
            "write_lat_mean_us": round(self.write_lat_mean_us, 2),
            "read_p50_us": round(self.read_p50_us, 2),
            "read_p95_us": round(self.read_p95_us, 2),
            "read_p99_us": round(self.read_p99_us, 2),
            "read_p999_us": round(self.read_p999_us, 2),
            "write_p50_us": round(self.write_p50_us, 2),
            "write_p95_us": round(self.write_p95_us, 2),
            "write_p99_us": round(self.write_p99_us, 2),
            "write_p999_us": round(self.write_p999_us, 2),
            "usr_cpu_pct": round(self.usr_cpu_pct, 2),
            "sys_cpu_pct": round(self.sys_cpu_pct, 2),
        }


def _ns_to_us(value_ns: Any) -> float:
    """Convert nanoseconds to microseconds safely."""
    try:
        return float(value_ns) / 1000.0
    except (TypeError, ValueError):
        return 0.0


def _extract_percentile_us(section: dict[str, Any], target_pct: str) -> float:
    """Extract completion latency percentile (ns -> us) from FIO JSON output."""
    clat = section.get("clat_ns", {})
    percentiles = clat.get("percentile", {})
    if not isinstance(percentiles, dict):
        return 0.0
    # FIO formats keys as e.g. '50.000000', '95.000000', '99.000000', '99.900000'
    for key in (target_pct, f"{float(target_pct):.6f}", f"{float(target_pct):.2f}"):
        if key in percentiles:
            return _ns_to_us(percentiles[key])
    target_val = float(target_pct)
    for k, v in percentiles.items():
        try:
            if abs(float(k) - target_val) < 1e-4:
                return _ns_to_us(v)
        except ValueError:
            continue
    return 0.0


def _extract_bw_mib_s(section: dict[str, Any]) -> float:
    """Extract bandwidth in MiB/s (preferring bw_bytes over legacy KiB/s bw)."""
    if "bw_bytes" in section and section["bw_bytes"]:
        return float(section["bw_bytes"]) / (1024.0 * 1024.0)
    if "bw" in section and section["bw"]:
        return float(section["bw"]) / 1024.0
    return 0.0


def _load_sibling_metadata(json_path: Path) -> dict[str, Any]:
    """Load sibling benchmark-metadata.json when present alongside FIO JSON files."""
    meta_path = json_path.parent / "benchmark-metadata.json"
    if meta_path.is_file():
        try:
            with meta_path.open("r", encoding="utf-8") as fh:
                data = json.load(fh)
            if isinstance(data, dict):
                return data
        except (OSError, json.JSONDecodeError):
            pass
    return {}


def parse_fio_json_file(json_path: Path) -> list[BenchmarkRecord]:
    """Parse one FIO JSON output file into normalized BenchmarkRecord items."""
    with json_path.open("r", encoding="utf-8") as fh:
        payload = json.load(fh)

    if not isinstance(payload, dict) or "jobs" not in payload:
        raise ValueError(f"{json_path} does not contain FIO 'jobs' array")

    file_meta = payload.get("metadata", {})
    if not isinstance(file_meta, dict) or not file_meta:
        file_meta = _load_sibling_metadata(json_path)

    global_opts = payload.get("global options", {})
    if not isinstance(global_opts, dict):
        global_opts = {}

    env_class = str(file_meta.get("environment_class", "unknown"))
    target_tier = str(file_meta.get("target_tier", "unknown"))
    evidence = str(file_meta.get("evidence_level", "UNKNOWN"))
    if evidence not in VALID_EVIDENCE_LEVELS:
        evidence = "UNKNOWN"

    records: list[BenchmarkRecord] = []
    for job in payload.get("jobs", []):
        job_opts = job.get("job options", {})
        if not isinstance(job_opts, dict):
            job_opts = {}

        pattern = str(job_opts.get("rw") or global_opts.get("rw") or "unknown")
        block_size = str(job_opts.get("bs") or global_opts.get("bs") or "unknown")
        queue_depth = str(job_opts.get("iodepth") or global_opts.get("iodepth") or "1")
        numjobs = str(job_opts.get("numjobs") or global_opts.get("numjobs") or "1")

        read_sec = job.get("read", {}) or {}
        write_sec = job.get("write", {}) or {}

        read_mean_ns = (read_sec.get("clat_ns") or {}).get("mean") or (read_sec.get("lat_ns") or {}).get("mean") or 0.0
        write_mean_ns = (write_sec.get("clat_ns") or {}).get("mean") or (write_sec.get("lat_ns") or {}).get("mean") or 0.0

        records.append(
            BenchmarkRecord(
                source_file=str(json_path),
                job_name=str(job.get("jobname", "unnamed")),
                pattern=pattern,
                block_size=block_size,
                queue_depth=queue_depth,
                numjobs=numjobs,
                target_tier=target_tier,
                environment_class=env_class,
                evidence_level=evidence,
                read_iops=float(read_sec.get("iops", 0.0) or 0.0),
                write_iops=float(write_sec.get("iops", 0.0) or 0.0),
                read_bw_mib_s=_extract_bw_mib_s(read_sec),
                write_bw_mib_s=_extract_bw_mib_s(write_sec),
                read_lat_mean_us=_ns_to_us(read_mean_ns),
                write_lat_mean_us=_ns_to_us(write_mean_ns),
                read_p50_us=_extract_percentile_us(read_sec, "50.000000"),
                read_p95_us=_extract_percentile_us(read_sec, "95.000000"),
                read_p99_us=_extract_percentile_us(read_sec, "99.000000"),
                read_p999_us=_extract_percentile_us(read_sec, "99.900000"),
                write_p50_us=_extract_percentile_us(write_sec, "50.000000"),
                write_p95_us=_extract_percentile_us(write_sec, "95.000000"),
                write_p99_us=_extract_percentile_us(write_sec, "99.000000"),
                write_p999_us=_extract_percentile_us(write_sec, "99.900000"),
                usr_cpu_pct=float(job.get("usr_cpu", 0.0) or 0.0),
                sys_cpu_pct=float(job.get("sys_cpu", 0.0) or 0.0),
            )
        )
    return records


def collect_fio_files(inputs: list[Path]) -> list[Path]:
    """Collect FIO JSON files cleanly, skipping metadata manifests."""
    files: list[Path] = []
    for path in inputs:
        if path.is_file():
            if path.name != "benchmark-metadata.json":
                files.append(path)
        elif path.is_dir():
            for candidate in sorted(path.rglob("*.json")):
                if candidate.name in {"benchmark-metadata.json", "summary.json"}:
                    continue
                files.append(candidate)
    return files


def check_comparability(records: list[BenchmarkRecord], allow_mixed_env: bool) -> tuple[bool, list[str]]:
    """Verify whether all records originate from comparable hardware environments."""
    env_classes = sorted({r.environment_class for r in records})
    evidences = sorted({r.evidence_level for r in records})
    warnings: list[str] = []

    if len(env_classes) > 1:
        msg = f"Mixed environment classes detected ({', '.join(env_classes)}); results are NOT directly comparable."
        warnings.append(msg)
        if not allow_mixed_env:
            return False, warnings

    if "WSL2_PIPELINE_ONLY" in evidences:
        warnings.append("Includes WSL2 virtual disk pipeline test(s) — NOT representative of physical NVMe hardware.")
    if "SYNTHETIC_FIXTURE" in evidences:
        warnings.append("Includes SYNTHETIC_FIXTURE test data — intended for parser validation ONLY, never empirical claims.")
    if "DRY_RUN" in evidences:
        warnings.append("Includes DRY_RUN entries — zero actual storage I/O executed.")

    return True, warnings


def render_markdown(records: list[BenchmarkRecord], warnings: list[str]) -> str:
    """Render structured Markdown summary table and comparison insights."""
    lines: list[str] = [
        "# FIO Storage Benchmark Summary Report",
        "",
    ]

    if warnings:
        lines.append("## Comparability & Evidence Notices")
        for w in warnings:
            lines.append(f"- **[NOTICE]** {w}")
        lines.append("")

    if not records:
        lines.append("*No FIO benchmark records found.*")
        return "\n".join(lines)

    lines.extend([
        "## Workload Metrics Matrix",
        "",
        "| Evidence | Environment | Tier | Job (`bs`/`qd`/`jobs`) | Read IOPS | Write IOPS | Read BW (MiB/s) | Write BW (MiB/s) | Read p95 / p99 (us) | Write p95 / p99 (us) |",
        "| :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])

    for r in records:
        job_desc = f"`{r.job_name}` (`{r.block_size}`/`qd{r.queue_depth}`/`j{r.numjobs}`)"
        r_lat = f"{r.read_p95_us:.1f} / {r.read_p99_us:.1f}"
        w_lat = f"{r.write_p95_us:.1f} / {r.write_p99_us:.1f}"
        lines.append(
            f"| `{r.evidence_level}` | `{r.environment_class}` | `{r.target_tier}` | {job_desc} | "
            f"{r.read_iops:.1f} | {r.write_iops:.1f} | {r.read_bw_mib_s:.2f} | {r.write_bw_mib_s:.2f} | {r_lat} | {w_lat} |"
        )

    return "\n".join(lines) + "\n"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Summarize FIO benchmark JSON files with comparability checks.")
    parser.add_argument("-i", "--input", action="append", required=True, help="FIO JSON file or directory (repeatable)")
    parser.add_argument("--output-markdown", help="Optional path to write Markdown summary report")
    parser.add_argument("--output-json", help="Optional path to write consolidated normalized JSON")
    parser.add_argument(
        "--compare",
        action="store_true",
        help="Strict comparability check across inputs (fails exit 2 on mismatched environment_class unless --allow-mixed-env)",
    )
    parser.add_argument(
        "--allow-mixed-env",
        action="store_true",
        help="Allow outputting heterogeneous environments together with explicit warning banners",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    input_paths = [Path(p) for p in args.input]
    files = collect_fio_files(input_paths)
    if not files:
        print("Error: No FIO JSON result files found under specified inputs.", file=sys.stderr)
        return 1

    records: list[BenchmarkRecord] = []
    for jf in files:
        try:
            records.extend(parse_fio_json_file(jf))
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            print(f"Error parsing {jf}: {exc}", file=sys.stderr)
            return 1

    is_comparable, warnings = check_comparability(records, allow_mixed_env=(args.allow_mixed_env or not args.compare))
    if not is_comparable:
        for w in warnings:
            print(f"[COMPARABILITY ERROR] {w}", file=sys.stderr)
        return 2

    md = render_markdown(records, warnings)
    print(md)

    if args.output_markdown:
        out_md = Path(args.output_markdown)
        out_md.parent.mkdir(parents=True, exist_ok=True)
        out_md.write_text(md, encoding="utf-8")

    if args.output_json:
        out_json = Path(args.output_json)
        out_json.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "schema_version": "1.0",
            "warnings": warnings,
            "record_count": len(records),
            "records": [r.to_dict() for r in records],
        }
        out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

