# Diagram 04 — Monitoring & Observability Architecture

**Project:** Deploy High-Performance Storage for Kubernetes (`SWFW_5S_08`)  
**Scope Notice:** `promtool v3.16.0` config/rules validation, `monitoring.coreos.com/v1` CRD schemas, and 3 Grafana dashboard JSONs are `VALIDATED`; live cluster scraping and UI rendering remain **`INFRASTRUCTURE-DEPENDENT`**.

```mermaid
flowchart TB
    subgraph Targets["Cluster Scrape & Telemetry Sources (Verified Exporter Endpoints)"]
        MS_EXP["Mayastor metrics-exporter-io-engine (:9502 /metrics)<br/>diskpool_status, diskpool_*_size_bytes, diskpool_io_*,<br/>volume_*, replica_*, mayastor_node_*"]
        MS_REST["Mayastor API REST (:8081 /v0/volumes)<br/>Gap Mitigation: Per-Volume Online/Degraded<br/>& Rebuild Progress via observe-rebuild-events.sh"]
        KV_EXP["KubeVirt virt-controller & virt-handler (HTTPS :8443)<br/>Selector: prometheus.kubevirt.io=true<br/>kubevirt_vmi_info, kubevirt_vmi_non_evictable,<br/>kubevirt_vmi_migration_*, kubevirt_vmi_storage_*"]
        HOST_EXP["prometheus-node-exporter (:9100) + kube-state-metrics<br/>node_cpu_seconds_total, node_memory_HugePages_*,<br/>node_disk_*, container_cpu_usage_seconds_total"]
        FIO_JSON["FIO Empirical JSON Outputs<br/>Gap Mitigation: p50 / p95 / p99 / p99.9 Latency Tails"]
    end

    subgraph MonNS["Namespace: monitoring (kube-prometheus-stack v93.2.0 | Internal ClusterIP ONLY)"]
        SM["ServiceMonitors<br/>mayastor-io-engine-metrics<br/>kubevirt-metrics"]
        PROM["Prometheus v3.16.0 (:9090 ClusterIP)<br/>15d Target Retention / 2d Lightweight Overlay"]
        RULES["PrometheusRule (10 promtool-Verified Alerts)<br/>DiskPoolDegraded, Faulted, IOStalled, Cap>85%,<br/>MayastorNodeOffline, VMINonEvictable, MigrationFailed"]
        GRAF["Grafana 13.3.1 (:3000 ClusterIP)<br/>1. Mayastor Storage Performance<br/>2. KubeVirt VM Telemetry<br/>3. Cluster Node Resources & SPDK"]
        ACCESS["Operator Access via kubectl port-forward<br/>(Zero NodePort / Ingress Exposure)"]
    end

    SM --> PROM
    PROM -->|Scrapes| MS_EXP & KV_EXP & HOST_EXP
    PROM --> RULES
    GRAF -->|PromQL| PROM
    ACCESS -.-> PROM & GRAF
```

