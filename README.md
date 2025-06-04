# 🛡️ FeelGood API – Supply Chain Security & DevSecOps Showcase

Welcome to the **FeelGood API**! While the API itself is a simple motivational phrase service, this repository is a real-world demonstration of modern, end-to-end supply chain security, SLSA compliance, and DevSecOps automation.

---

## 🚦 What Makes This Project Special?

This repo is not just about code – it’s about **trust**. Every artifact, dependency, and workflow is:
- **Audited**
- **Signed**
- **Attested**
- **Tracked**
- **Verified**

with industry best practices and open standards.

---

## 🔒 SLSA Level 3 Compliance
- **Isolated, reproducible builds** using GitHub Actions and multi-stage Docker builds
- **Provenance generation** with [SLSA](https://slsa.dev/) GitHub generator workflows
- **Container signing** and attestation with [Cosign](https://github.com/sigstore/cosign)
- **Automated verification** of signatures and provenance in CI

**Relevant files:**
- `.github/workflows/build-and-security.yml`
- `.github/workflows/slsa-provenance.yml`
- `scripts/verify_attestations.py`
- `Dockerfile`

---

## 📦 SBOM (Software Bill of Materials)
- **Automated SBOM generation** at build time (CycloneDX format)
- **Enhanced SBOM** includes SLSA metadata, GitHub Actions context, and git commit info
- **SBOM hash verification** for tamper detection
- **Dependency SBOM** for lock file transparency

**Relevant files:**
- `scripts/generate_sbom.py`
- `sbom.json`, `sbom-deps.json`
- `.github/workflows/build-and-security.yml`

---

## 🦺 VEX (Vulnerability Exploitability eXchange)
- **Build-time VEX**: Static vulnerability analysis with Trivy, output as OpenVEX
- **Runtime VEX**: Dynamic analysis using [Kubescape](https://github.com/kubescape/kubescape) in ephemeral Kubernetes clusters
- **VEX consolidation**: All VEX docs are validated, merged, and attached to images as signed attestations
- **Production VEX**: Real-world VEX from production can be added and automatically integrated

**Relevant files:**
- `scripts/generate_vex.py`, `.vex/`, `.vex/README.md`
- `.github/workflows/build-and-security.yml`, `.github/workflows/vex-integration.yml`
- Example: `.vex/production/example.vex.json`

---

## 🔍 Automated Security Scanning & Lock Management
- **Dependency audits** with pip-audit (pre/post lock generation)
- **Container scans** with Trivy
- **Lock file generation** with integrity and hash verification
- **Automated lock refresh, update, and verification**

**Relevant files:**
- `scripts/generate_locks.sh`, `Makefile`
- `.github/workflows/dependency-review.yml`

---

## 🛠️ Makefile Commands

All security, compliance, and build tasks are managed via the Makefile. Here are the available commands:

### 📦 Dependencies
- `make install` – Install dependencies (via Poetry)
- `make lock` – Generate all lock files (`requirements.txt`, `requirements-lock.txt`, `requirements-dev.txt`)
- `make refresh-locks` – Clear caches and regenerate all lock files
- `make update-deps` – Update dependencies and regenerate locks
- `make verify-lock` – Verify lock file integrity

### 🧪 Testing & Quality
- `make test` – Run all tests
- `make lint` – Run code formatters and type checks (black, mypy)

### 🔒 Security
- `make security-check` – Run basic security checks (pip-audit)
- `make security-full` – Run the full security pipeline: audit, SBOM, VEX, attestation verification
- `make trivy-scan` – Run Trivy vulnerability scan (filesystem)
- `make verify-local IMAGE=...` – Verify signatures and attestations locally for a given image

### 📋 Documentation & Compliance
- `make sbom` – Generate a basic SBOM (CycloneDX)
- `make sbom-enhanced` – Generate an enhanced SBOM with build metadata
- `make vex` – Generate a basic VEX document
- `make vex-enhanced` – Generate an enhanced VEX document (uses Trivy scan and SBOM if available)
- `make slsa-check` – Check SLSA Level 3 compliance (runs SBOM/VEX generation and prints compliance status)

### 🐳 Docker
- `make build` – Build the Docker image
- `make run` – Run the Docker container (port 8000)

### 🧹 Utilities
- `make clean` – Clean up cache files and Python bytecode

---

## 🚦 Quick Start
```zsh
# Install dependencies
make install

# Generate and verify lock files
make lock
make verify-lock

# Run all security checks and generate SBOM/VEX
make security-full

# Build and run the container
make build
make run
```

---

## 🗂️ VEX Document Management
- `.vex/production/`: VEX from production runtime
- `.vex/README.md`: Naming conventions, update instructions, OpenVEX format
- VEX docs are validated with `vexctl` before commit

---

## 🏗️ CI/CD Pipeline Overview
- **Test & Scan**: Lint, test, pip-audit, Trivy
- **Build**: Multi-stage Docker build, SBOM generation
- **Attest & Sign**: Cosign signing, SLSA provenance, VEX attestation
- **VEX Analysis**: Build-time and runtime VEX, consolidation, and artifact upload
- **Verification**: Automated signature, provenance, and VEX verification
- **Security Monitoring**: Scheduled scans and dependency reviews

---

## 🌈 Why This Matters
- **Transparency**: Know exactly what’s in your software and how it was built
- **Trust**: Every artifact is signed, attested, and verified
- **Resilience**: Both static and runtime vulnerabilities are tracked and mitigated
- **Modern DevSecOps**: Real-world SLSA, SBOM, and VEX integration

---

## 📚 Learn More
- [SLSA Framework](https://slsa.dev/)
- [OpenVEX](https://openvex.dev/)
- [Sigstore/Cosign](https://docs.sigstore.dev/cosign/overview/)
- [CycloneDX SBOM](https://cyclonedx.org/)
- [Kubescape](https://github.com/kubescape/kubescape)

---

> **FeelGood API** – Where even Hello World is built like a fortress. 🏰
