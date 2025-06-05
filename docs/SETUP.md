# Repository Setup Guide

This guide provides comprehensive instructions for setting up a new repository to work with the SLSA Level 3 Supply Chain Security pipeline implemented in this project.

## Overview

This repository implements a **SLSA Level 3 Supply Chain Security proof of concept** with comprehensive DevSecOps pipeline featuring:
- Multi-platform container builds with vulnerability scanning and patching
- Build-time + runtime VEX (Vulnerability Exploitability eXchange) integration
- SLSA Level 3 provenance generation and verification
- Container signing with Cosign
- Automated security monitoring and reporting

## Prerequisites

### 1. Repository Structure Requirements

Your repository must have the following minimum structure:
```
your-repo/
├── .github/workflows/           # Copy all workflow files from this repo
├── src/                        # Your application source code
├── Dockerfile                  # Container build configuration
├── pyproject.toml             # Python project configuration (if using Python)
├── cosign.pub                 # Cosign public key (generate as described below)
└── CLAUDE.md                  # Optional: Claude Code instructions
```

### 2. Generate Cosign Key Pair

**Step 1: Install Cosign**
```bash
# Install cosign (choose your platform)
# Linux/macOS via Homebrew:
brew install cosign

# Or download from GitHub releases:
curl -O -L "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64"
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
```

**Step 2: Generate Key Pair**
```bash
# Generate key pair (you'll be prompted for a password)
cosign generate-key-pair

# This creates:
# - cosign.key (private key - NEVER commit this!)
# - cosign.pub (public key - commit this to your repo)
```

**Step 3: Add Keys to Repository**
```bash
# Add public key to your repository
cp cosign.pub /path/to/your/repo/

# The private key and password will be added as GitHub secrets (see below)
```

## GitHub Repository Configuration

### 1. Repository Settings

**General Settings:**
- Enable "GitHub Container Registry" under Packages
- Enable "Security" tab for SARIF uploads
- Enable "Actions" for GitHub Actions workflows

**Actions Settings** (Repository Settings → Actions → General):
- **Actions permissions**: "Allow all actions and reusable workflows"
- **Workflow permissions**: 
  - Select "Read and write permissions"
  - ✅ Check "Allow GitHub Actions to create and approve pull requests"
- **Artifact and log retention**: Set to at least 90 days (recommended)

**Security Settings** (Repository Settings → Security):
- ✅ Enable "Dependency graph"
- ✅ Enable "Dependabot alerts"
- ✅ Enable "Dependabot security updates"
- ✅ Enable "Code scanning" (will be populated by workflows)

### 2. Required GitHub Secrets

Navigate to **Repository Settings → Secrets and variables → Actions**

**Required Secrets:**
```
COSIGN_PRIVATE_KEY    # Content of your cosign.key file
COSIGN_PASSWORD       # Password you used when generating the key pair
```

**How to add secrets:**
1. Click "New repository secret"
2. Name: `COSIGN_PRIVATE_KEY`
3. Value: Copy and paste the entire content of your `cosign.key` file
4. Click "Add secret"
5. Repeat for `COSIGN_PASSWORD` with the password you used

### 3. Repository Variables (Optional)

Navigate to **Repository Settings → Secrets and variables → Actions → Variables tab**

**Optional Variables:**
```
REGISTRY              # Override default registry (default: ghcr.io)
VULNERABILITY_THRESHOLD # Override vulnerability threshold (default: MEDIUM)
```

### 4. Branch Protection Rules (Recommended)

Navigate to **Repository Settings → Branches**

**Recommended Protection for `main` branch:**
- ✅ Require a pull request before merging
- ✅ Require status checks to pass before merging
  - Add required status checks:
    - `build-and-test`
    - `vex-analysis` 
    - `attestation-and-verify`
- ✅ Require signed commits (optional, enhances SLSA Level 3 compliance)
- ✅ Include administrators (recommended)

## Required Workflow Files

Copy the following workflow files from this repository to your `.github/workflows/` directory:

### Core Security Pipeline:
```
.github/workflows/
├── security-pipeline.yml          # Main orchestrator
├── build-and-test.yml             # Phase 1: Build & vulnerability scanning
├── vex-analysis.yml               # Phase 2: VEX generation
├── attestation-and-verify.yml     # Phase 3: Signing & verification
├── security-monitoring.yml        # Daily security monitoring
└── slsa-provenance.yml            # SLSA Level 3 provenance generation
```

### Supporting Workflows:
```
├── vex-integration.yml            # VEX document management
└── runtime-vex.yml               # Runtime vulnerability analysis
```

### Custom GitHub Actions:
```
.github/actions/
├── security-reporter/            # Unified security reporting
├── vex-processor/               # VEX document processing
└── runtime-analyzer/            # Runtime security analysis
```

## Required Scripts

Copy the following scripts from this repository to your `scripts/` directory:

```
scripts/
├── generate_sbom.py              # Enhanced SBOM generation
├── generate_vex.py               # VEX document generation
├── compare_scans.py              # Vulnerability comparison
├── verify_attestations.py       # Local verification
├── sbom_diff.py                 # SBOM comparison
└── fix_vex_timestamps.sh        # VEX timestamp correction
```

## Required Dependencies

### Python Dependencies (if using Python):

**pyproject.toml** requirements:
```toml
[tool.poetry.dependencies]
python = "^3.11"
fastapi = "^0.104.1"
uvicorn = "^0.24.0"

[tool.poetry.group.dev.dependencies]
pytest = "^7.4.3"
black = "^23.11.0"
mypy = "^1.7.1"
cyclonedx-py = "^4.2.3"
pip-audit = "^2.6.1"
```

### System Dependencies:

The workflows automatically install these tools:
- **Trivy** - Vulnerability scanner
- **Cosign** - Container signing
- **Copa** - Vulnerability patching
- **vexctl** - VEX manipulation
- **SLSA Verifier** - Provenance verification
- **Kubescape** - Runtime analysis

## Application Requirements

### 1. Dockerfile

Your application must have a `Dockerfile` for containerization. Example:

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
EXPOSE 8000

CMD ["uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 2. Application Structure

For Python applications, ensure you have:
- `src/` directory with your application code
- `tests/` directory with test files
- Proper `pyproject.toml` or `requirements.txt`

### 3. Health Endpoints (Recommended)

For proper security scanning, include health endpoints:
```python
@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.get("/security/info")
async def security_info():
    return {"security": "enabled", "slsa_level": "3"}
```

## Verification Steps

### 1. Test Workflow Execution

**Trigger Security Pipeline:**
```bash
# Push to main branch or create PR
git push origin main

# Or manually trigger
gh workflow run security-pipeline.yml
```

**Check Workflow Status:**
```bash
# List workflow runs
gh run list --workflow=security-pipeline.yml

# View specific run
gh run view <run-id>
```

### 2. Verify Container Registry

Check that containers are being pushed to GitHub Container Registry:
```bash
# List packages
gh api /user/packages?package_type=container

# Or visit: https://github.com/users/YOUR_USERNAME/packages
```

### 3. Verify Signatures and Attestations

**Verify Container Signature:**
```bash
# Replace with your actual image
cosign verify --key cosign.pub ghcr.io/your-username/your-repo:latest
```

**Verify SLSA Provenance:**
```bash
# Install slsa-verifier
go install github.com/slsa-framework/slsa-verifier/v2/cli/slsa-verifier@latest

# Verify provenance
slsa-verifier verify-image ghcr.io/your-username/your-repo:latest \
  --source-uri github.com/your-username/your-repo
```

### 4. Local Testing

**Run Security Checks Locally:**
```bash
# If you copied the Makefile
make security-full

# Or run individual components
make lint
make test
make security-check
```

**Test Application:**
```bash
# Build and run locally
docker build -t your-app .
docker run -p 8000:8000 your-app

# Test endpoints
curl http://localhost:8000/health
curl http://localhost:8000/security/info
```

## Troubleshooting

### Common Issues

**1. Cosign Key Issues:**
```bash
# Regenerate if needed
cosign generate-key-pair --force

# Verify key format
cat cosign.key | head -1  # Should be: -----BEGIN ENCRYPTED PRIVATE KEY-----
cat cosign.pub | head -1  # Should be: -----BEGIN PUBLIC KEY-----
```

**2. Container Registry Permissions:**
- Ensure GitHub Container Registry is enabled
- Check that `GITHUB_TOKEN` has `packages: write` permission
- Verify repository visibility (public repos work best for GHCR)

**3. Workflow Permissions:**
- Verify all required permissions are set in workflow files
- Check repository Actions settings allow required permissions

**4. Missing Dependencies:**
- Ensure all required scripts are copied to your repository
- Verify Python dependencies are properly specified
- Check that external actions are accessible

### Debug Commands

**Check Workflow Logs:**
```bash
# Get recent run ID
gh run list --limit 1 --json databaseId --jq '.[0].databaseId'

# Download logs
gh run download <run-id>
```

**Verify Local Environment:**
```bash
# Check cosign installation
cosign version

# Verify Docker setup
docker --version
docker buildx version

# Test GitHub CLI
gh auth status
```

## Security Considerations

### 1. Secret Management
- **NEVER** commit `cosign.key` or passwords to your repository
- Rotate cosign keys periodically (recommended: every 6 months)
- Use repository secrets, not environment variables in workflows

### 2. Network Security
- All external tool downloads use pinned versions and checksums
- Container builds use official base images
- Vulnerability databases are accessed through trusted APIs

### 3. Access Control
- Limit repository access to necessary team members
- Use branch protection rules to prevent direct pushes to main
- Enable required status checks for all security workflows

### 4. Monitoring
- Review security monitoring workflow results daily
- Set up GitHub notifications for security alerts
- Monitor container registry for unauthorized images

## Support and Maintenance

### Regular Tasks
- **Weekly**: Review security monitoring reports
- **Monthly**: Update dependencies and base images
- **Quarterly**: Rotate cosign keys and review access permissions
- **As needed**: Update workflow files when new security tools are available

### Updates
- Monitor this repository for updates to workflow files
- Subscribe to security advisories for used tools
- Keep external action versions updated

For additional support or questions about this security pipeline, refer to the project documentation or create an issue in the source repository.