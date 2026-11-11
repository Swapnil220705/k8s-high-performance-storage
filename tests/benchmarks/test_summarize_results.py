#!/usr/bin/env python3
"""Unit tests for scripts/benchmark/summarize-results.py."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts" / "benchmark" / "summarize-results.py"

SPEC = importlib.util.spec_from_file_location("summarize_results", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
SUMMARIZER = importlib.util.module_from_spec(SPEC)
sys.modules["summarize_results"] = SUMMARIZER
SPEC.loader.exec_module(SUMMARIZER)


def _sample_fio_payload(
    *,
    jobname: str = "randread-4k",
    rw: str = "randread",
    bs: str = "4k",
    iodepth: str = "32",
    numjobs: str = "1",
    read_iops: float = 100000.0,
    write_iops: float = 0.0,
    env_class: str = "bare-metal-4node",
    target_tier: str = "mayastor-rwo-block",
    evidence_level: str = "SYNTHETIC_FIXTURE",
) -> dict:
    return {
        "fio version": "fio-3.36",
        "metadata": {
            "environment_class": env_class,
            "target_tier": target_tier,
            "evidence_level": evidence_level,
        },
        "global options": {
            "ioengine": "libaio",
            "direct": "1",
            "bs": bs,
            "iodepth": iodepth,
            "numjobs": numjobs,
        },
        "jobs": [
            {
                "jobname": jobname,
                "job options": {
                    "rw": rw,
                    "bs": bs,
                    "iodepth": iodepth,
                    "numjobs": numjobs,
                },
                "usr_cpu": 3.5,
                "sys_cpu": 8.5,
                "read": {
                    "iops": read_iops,
                    "bw_bytes": int(read_iops * 4096),
                    "clat_ns": {
                        "mean": 250000.0,
                        "percentile": {
                            "50.000000": 200000,
                            "95.000000": 420000,
                            "99.000000": 750000,
                            "99.900000": 1200000,
                        },
                    },
                },
                "write": {
                    "iops": write_iops,
                    "bw_bytes": int(write_iops * 4096),
                    "clat_ns": {
                        "mean": 310000.0 if write_iops > 0 else 0.0,
                        "percentile": (
                            {
                                "50.000000": 260000,
                                "95.000000": 510000,
                                "99.000000": 880000,
                                "99.900000": 1500000,
                            }
                            if write_iops > 0
                            else {}
                        ),
                    },
                },
            }
        ],
    }


class SummarizeResultsTests(unittest.TestCase):
    """Tests FIO JSON parsing, percentile conversion, and environment comparability guards."""

    def test_parse_single_fio_json_and_percentiles(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            json_path = Path(tmpdir) / "randread.json"
            json_path.write_text(json.dumps(_sample_fio_payload()), encoding="utf-8")

            records = SUMMARIZER.parse_fio_json_file(json_path)
            self.assertEqual(len(records), 1)
            rec = records[0]
            self.assertEqual(rec.job_name, "randread-4k")
            self.assertAlmostEqual(rec.read_iops, 100000.0)
            self.assertAlmostEqual(rec.read_lat_mean_us, 250.0)
            self.assertAlmostEqual(rec.read_p50_us, 200.0)
            self.assertAlmostEqual(rec.read_p95_us, 420.0)
            self.assertAlmostEqual(rec.read_p99_us, 750.0)
            self.assertAlmostEqual(rec.read_p999_us, 1200.0)
            self.assertEqual(rec.evidence_level, "SYNTHETIC_FIXTURE")

    def test_sibling_metadata_loading(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            meta = Path(tmpdir) / "benchmark-metadata.json"
            meta.write_text(
                json.dumps(
                    {
                        "environment_class": "wsl2-virtual",
                        "target_tier": "local-baseline",
                        "evidence_level": "WSL2_PIPELINE_ONLY",
                    }
                ),
                encoding="utf-8",
            )
            payload = _sample_fio_payload()
            del payload["metadata"]
            json_path = Path(tmpdir) / "job.json"
            json_path.write_text(json.dumps(payload), encoding="utf-8")

            records = SUMMARIZER.parse_fio_json_file(json_path)
            self.assertEqual(records[0].environment_class, "wsl2-virtual")
            self.assertEqual(records[0].evidence_level, "WSL2_PIPELINE_ONLY")

    def test_compare_rejects_mixed_environments_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            p1 = Path(tmpdir) / "hw.json"
            p2 = Path(tmpdir) / "wsl.json"
            p1.write_text(
                json.dumps(_sample_fio_payload(env_class="bare-metal-4node")),
                encoding="utf-8",
            )
            p2.write_text(
                json.dumps(_sample_fio_payload(env_class="wsl2-virtual", evidence_level="WSL2_PIPELINE_ONLY")),
                encoding="utf-8",
            )

            rc_strict = SUMMARIZER.main(["--input", str(p1), "--input", str(p2), "--compare"])
            self.assertEqual(rc_strict, 2)

            out_md = Path(tmpdir) / "summary.md"
            out_json = Path(tmpdir) / "summary.json"
            rc_override = SUMMARIZER.main(
                [
                    "--input",
                    str(p1),
                    "--input",
                    str(p2),
                    "--compare",
                    "--allow-mixed-env",
                    "--output-markdown",
                    str(out_md),
                    "--output-json",
                    str(out_json),
                ]
            )
            self.assertEqual(rc_override, 0)
            self.assertIn("NOT directly comparable", out_md.read_text(encoding="utf-8"))
            parsed = json.loads(out_json.read_text(encoding="utf-8"))
            self.assertEqual(parsed["record_count"], 2)


if __name__ == "__main__":
    unittest.main()

