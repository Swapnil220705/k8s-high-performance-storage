# AI Agent Operating Directives & Governance Manual

**Project Name:** Deploy High-Performance Storage for Kubernetes  
**Project ID:** SWFW_5S_08  
**Scope:** AI-Assisted Development via Antigravity  
**Enforcement Level:** MANDATORY — ZERO DEVIATION PERMITTED  

---

## 1. Project Identity & Objective

This project, developed under the **Zoho SETU — College Student Project Program**, aims to design, deploy, validate, and benchmark a high-performance cloud-native storage architecture on a multi-node Kubernetes cluster. It integrates **OpenEBS Mayastor** (leveraging SPDK and NVMe-oF) with **KubeVirt** to deliver resilient, high-throughput, low-latency block storage for containerized virtual machines.

---

## 2. Mandatory Behavioral Directives

All AI agents assisting this project MUST adhere strictly to the following core tenets:

1. **Chunk Boundaries:** Work ONLY on the currently authorized chunk. Never jump ahead to future chunks, create manifests, or execute operations outside the active chunk's explicit scope.
2. **Explicit User Approval:** After completing an authorized chunk, the agent MUST STOP and await explicit user review and approval before proceeding.
3. **No Fabricated Evidence:** Never invent, simulate, or synthesize test results, benchmarks, deployment outcomes, or hardware metrics. If a test has not been executed on live hardware, record it as **NOT VERIFIED**.
4. **No Premature Feature Completion:** Never claim an infrastructure feature is complete or functional solely because a Kubernetes YAML manifest or shell script has been written. A manifest is merely an artifact until deployed and verified.
5. **No Destructive Operations:** Never execute destructive system commands (`rm -rf`, disk formatting, partition deletion, host reboots, BIOS alterations, network interface resets) without explicit, unambiguous user confirmation.
6. **No Paid Infrastructure:** Never invoke, configure, or provision paid cloud infrastructure. The deployment strategy is strictly limited to college laboratory servers and free local resources.
7. **Secrets & Security:** Never hardcode or commit API tokens, passwords, SSH private keys, TLS private keys, or kubeconfigs.
8. **Git Discipline:** Follow Conventional Commits. Stage only intentional files. Never force-push or rewrite repository history.
9. **Documentation Synchronization:** Keep `PROJECT_STATE.md`, `ARCHITECTURE.md`, `RESEARCH.md`, `LEARNING_NOTES.md`, and `DECISIONS.md` synchronized after every meaningful milestone.

---

## 3. Technology Stack Boundaries

All architecture and code produced must conform to the following technology components and constraints:
- **Operating System:** Linux Ubuntu Server 22.04 / 24.04 LTS (x86_64).
- **Cluster Deployment:** `kubeadm` + `containerd` (systemd cgroup driver).
- **Storage Subsystem:** OpenEBS Mayastor utilizing SPDK user-space I/O engine, NVMe-oF (TCP), and HugePages.
- **Virtualization Subsystem:** KubeVirt with hardware KVM pass-through (`/dev/kvm`).
- **Benchmarking Tool:** Flexible I/O Tester (`fio`).
- **Observability:** Prometheus + Grafana.

---

## 4. Repository Structure & File Management

All code, manifests, and documentation must reside strictly within the designated repository hierarchy:

```text
k8s-high-performance-storage/
├── AGENTS.md               # Governance rules and agent guardrails
├── README.md               # Project landing page and high-level summary
├── PROJECT_STATE.md        # Single source of truth for implementation state
├── ARCHITECTURE.md         # Target system design and component topology
├── RESEARCH.md             # Theoretical investigations and API references
├── LEARNING_NOTES.md       # Student engineering reference and viva prep
├── DECISIONS.md            # Architectural Decision Records (ADRs)
├── .gitignore              # Repository exclusion rules
├── LICENSE                 # Project open-source license
├── infrastructure/         # Cluster manifests (k8s, networking, storage classes)
├── kubevirt/               # KubeVirt CRDs, VM manifests, hot-plug specs
├── storage/                # Mayastor configs, NFS gateway manifests
├── monitoring/             # Prometheus and Grafana dashboards
├── benchmarks/             # FIO profiles, test scripts, and empirical results
├── scripts/                # Operational bash scripts (setup, validation, test)
├── tests/                  # Verification test plans and test logs
├── docs/                   # Detailed technical runbooks and submission reports
└── reports/                # Verified graphs, screenshots, and final paper
```

**File Rules:**
- Empty directories must contain `.gitkeep`.
- Do not create unrequested scratch files, dummy manifests, or placeholder shell scripts.
- Never modify files unrelated to the active chunk.

---

## 5. Development Standards

### 5.1 Kubernetes Manifest Standards
- **API Versions:** Use stable, current API versions (no deprecated beta APIs).
- **Labels & Selectors:** Adhere to Kubernetes recommended standard labels (`app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/part-of`).
- **Resource Constraints:** Always specify `requests` and `limits` for CPU and memory on production pods.
- **Security Contexts:** Enforce least-privilege security contexts (`runAsNonRoot: true`, `readOnlyRootFilesystem: true`, drop unnecessary Linux capabilities) except where system daemons (Mayastor `io-engine`, KubeVirt `virt-handler`) strictly require host device access (`privileged: true`, `/dev/kvm`, `/dev/hugepages`).
- **Validation:** Every manifest must be syntactically valid YAML and parseable by standard linters.

### 5.2 Shell Scripting Standards
- **Interpreter & Flags:** All scripts must begin with `#!/usr/bin/env bash` and enforce strict error handling:
  ```bash
  set -euo pipefail
  ```
- **Idempotency:** Scripts must be safe to run multiple times without duplicating entries, corrupting configurations, or failing ungracefully.
- **Logging & Output:** Provide clear, timestamped log messages with standardized levels (`[INFO]`, `[WARN]`, `[ERROR]`).
- **Safety Checks:** Check for pre-requisite binaries, root/sudo permissions, and environment variables before executing destructive or mutating commands.

---

## 6. Testing, Verification, and Evidence Protocol

To maintain complete scientific and engineering integrity, all claims must be categorized under one of four unambiguous levels:

1. **DOCUMENTED CAPABILITY:** A feature explicitly documented by upstream project maintainers (e.g., KubeVirt docs state live migration is supported).
2. **PROPOSED / STATIC MANIFEST:** A configuration authored in the repository but not yet executed on running hardware.
3. **SIMULATED / SYNTHETIC TEST:** A test executed in a virtual or mocked environment (e.g., local WSL2 or single-node minikube), with documented deviations from bare-metal behavior.
4. **VERIFIED EMPIRICAL DEPLOYMENT:** A capability deployed on the physical multi-node cluster, experimentally exercised, and backed by recorded logs, terminal outputs, or metrics data stored in `benchmarks/results/` or `reports/`.

---

## 7. Git & Commit Conventions

Commit messages must strictly follow the **Conventional Commits** specification:
- `feat:` Introduces a new feature, manifest, or automation script.
- `fix:` Patches a bug, configuration error, or broken reference.
- `docs:` Modifies documentation, architecture specs, or learning notes.
- `chore:` Maintenance tasks, repository structure, dependency updates, `.gitignore`.
- `test:` Introduces or updates test cases, FIO profiles, or verification scripts.
- `perf:` Optimizations in storage, networking, or execution efficiency.
- `refactor:` Code restructuring without functional changes.

**Commit Protocol:**
1. Run `git status` and `git diff` before staging.
2. Stage only files pertinent to the specific atomic change.
3. Review `git diff --cached` to ensure zero unintended files or sensitive tokens are included.
4. Record the commit hash and commit message in project state documentation.
5. **NEVER automatically push to remote repositories without explicit user instruction.**

---

## 8. State Maintenance & Progress Governance

`PROJECT_STATE.md` is the authoritative single source of truth for this project. After every completed chunk or major milestone:
1. Update chunk status (e.g., `NOT STARTED` $\rightarrow$ `IN PROGRESS` $\rightarrow$ `COMPLETED`).
2. Record concrete artifacts produced.
3. Log blockers, risks, and open architectural decisions.
4. Update the "Next Authorized Action" field to reflect the next approved step.
5. Stop and present the completion report to the user.
