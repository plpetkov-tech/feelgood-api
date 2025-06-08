# Repository Setup Guide

This guide provides comprehensive instructions for setting up a new repository to work with the SLSA Level 3 Supply Chain Security pipeline implemented in this project.

## Overview

This repository implements a **SLSA Level 3+ Enhanced Supply Chain Security proof of concept** with comprehensive DevSecOps pipeline featuring:
- Multi-platform container builds with vulnerability scanning and patching
- **Multi-layer SBOM generation and attestation**:
  - Build-time SBOMs (application dependencies)
  - Container SBOMs (full image contents)
  - Runtime filtered SBOMs (Kubescape relevancy analysis)
  - Consolidated multi-layer SBOMs (unified transparency)
- Build-time + runtime VEX (Vulnerability Exploitability eXchange) integration
- **Flexible runtime analysis**: Support for both ephemeral Kind clusters and external Kubernetes clusters
- **Enhanced VEX and SBOM extraction**: Advanced detection and handling of Kubescape security documents
- SLSA Level 3+ provenance generation and comprehensive verification
- Container signing with Cosign and multi-layer attestations
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

**Optional Secrets:**
```
KUBECONFIG           # Base64-encoded kubeconfig for external Kubernetes cluster runtime analysis
```

**How to add required secrets:**
1. Click "New repository secret"
2. Name: `COSIGN_PRIVATE_KEY`
3. Value: Copy and paste the entire content of your `cosign.key` file
4. Click "Add secret"
5. Repeat for `COSIGN_PASSWORD` with the password you used

**How to add KUBECONFIG secret (optional):**

The `KUBECONFIG` secret enables runtime VEX analysis using an existing Kubernetes cluster instead of creating ephemeral Kind clusters. This is useful for:
- Production-like environment testing
- Using clusters with pre-installed Kubescape
- Reducing CI/CD resource usage
- Testing with specific cluster configurations

**Setup Instructions:**

1. **Prepare your kubeconfig file:**
   ```bash
   # Ensure your kubeconfig works locally
   kubectl --kubeconfig=/path/to/your/kubeconfig cluster-info
   
   # Verify Kubescape is installed (optional but recommended)
   kubectl --kubeconfig=/path/to/your/kubeconfig get ns kubescape
   ```

2. **Base64 encode the kubeconfig:**
   ```bash
   # Encode the kubeconfig file
   cat /path/to/your/kubeconfig | base64 -w 0
   # Copy the output (long base64 string)
   ```

3. **Add as GitHub secret:**
   - Click "New repository secret"
   - Name: `KUBECONFIG`
   - Value: Paste the base64-encoded kubeconfig content
   - Click "Add secret"

**Runtime Analysis Behavior:**

- **With KUBECONFIG secret**: Uses your external cluster, preserves cluster after analysis
- **Without KUBECONFIG secret**: Creates ephemeral Kind cluster, destroys after analysis

**External Cluster Requirements:**

- **Kubernetes Version**: 1.24+ recommended
- **Network Access**: Outbound internet access for image pulls
- **Resources**: At least 2 CPU cores and 4GB RAM available
- **Kubescape**: Pre-installed operator recommended (will be installed automatically if missing)
- **Permissions**: Kubeconfig should have cluster-admin or sufficient permissions for:
  - Creating deployments and services
  - Installing Helm charts (if Kubescape not pre-installed)
  - Accessing `kubescape` namespace
  - Reading CRDs: `openvulnerabilityexchangecontainers.spdx.softwarecomposition.kubescape.io`

**Security Considerations:**

- **Cluster Access**: Ensure the kubeconfig has minimal required permissions
- **Network Security**: Consider network policies if using production clusters
- **Resource Isolation**: Use dedicated namespaces or clusters for CI/CD testing
- **Temporary Deployments**: The pipeline only deploys test applications temporarily (cleaned up automatically)

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
├── build-and-test.yml             # Phase 1: Build, vulnerability scanning & multi-layer SBOM generation
├── vex-analysis.yml               # Phase 2: VEX generation, runtime analysis & filtered SBOM extraction
├── attestation-and-verify.yml     # Phase 3: Multi-layer SBOM processing, signing & comprehensive verification
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
├── vex-processor/               # VEX document processing and consolidation
├── sbom-processor/              # Multi-layer SBOM processing and consolidation
└── runtime-analyzer/            # Runtime security analysis with external cluster support
```

**SBOM Processor Action Details:**

The `sbom-processor` action implements the multi-layer SBOM strategy for enhanced SLSA Level 3+ compliance:

- **Multi-layer Processing**: Consolidates build-time, runtime-filtered, and container SBOMs
- **SLSA Metadata Integration**: Adds provenance and layer information to all SBOMs
- **Automated Container SBOM Generation**: Uses Syft to scan container images
- **CycloneDX Format Compliance**: Industry-standard SBOM format with enhanced metadata
- **Consolidated View Creation**: Generates unified multi-layer SBOM for complete transparency

**Input Parameters:**
- `build-sbom-artifact`: Build-time SBOM artifact name (from build phase)
- `runtime-filtered-sbom-artifact`: Runtime filtered SBOM artifact name (from VEX analysis)
- `container-image`: Container image reference for container SBOM generation
- `output-prefix`: Prefix for output SBOM files (default: "consolidated")

**Outputs:**
- Build-time SBOM (processed)
- Runtime filtered SBOM (from Kubescape relevancy analysis)
- Container SBOM (comprehensive image contents)
- Consolidated multi-layer SBOM (unified view with SLSA metadata)

**Runtime Analyzer Action Details:**

The `runtime-analyzer` action supports multiple operational modes:

- **setup-cluster**: Initializes Kubernetes environment
  - Checks for `KUBECONFIG` secret and uses external cluster if available
  - Falls back to creating ephemeral Kind cluster if no external cluster
  - Installs Kubescape operator with VEX generation and filtered SBOM capabilities
  - Configures nodeAgent with proper learning periods for relevancy analysis

- **deploy-and-analyze**: Deploys application for runtime analysis
  - Creates security-hardened deployment with non-root user
  - Generates runtime load for comprehensive VEX and relevancy analysis
  - Supports background testing during VEX generation period
  - Triggers Kubescape relevancy analysis for filtered SBOM generation

- **cleanup**: Cleans up analysis environment
  - Preserves external clusters (only removes test deployments)
  - Destroys ephemeral Kind clusters completely
  - Handles cleanup gracefully for both scenarios

**Input Parameters:**
- `action`: Operation to perform (setup-cluster, deploy-and-analyze, cleanup)
- `cluster-name`: Kubernetes cluster name (default: security-analysis-cluster)
- `image-ref`: Container image reference for analysis
- `app-name`: Application name for deployment
- `timeout`: Operation timeout in seconds (default: 600)
- `vex-analysis-time`: VEX analysis duration (default: 2m) - configures learningPeriod, applicationActivityTime, and filtered SBOM generation timing
- `kubeconfig-content`: Base64-encoded kubeconfig for external clusters (optional)

## Required Scripts

Copy the following scripts from this repository to your `scripts/` directory:

```
scripts/
├── generate_sbom.py              # Enhanced SBOM generation with SLSA metadata
├── generate_vex.py               # VEX document generation with exploitability analysis
├── compare_scans.py              # Vulnerability comparison and analysis
├── verify_attestations.py       # Multi-layer SBOM and VEX attestation verification
├── sbom_diff.py                 # SBOM comparison and difference analysis
├── fix_vex_timestamps.sh        # VEX timestamp correction
└── pin-and-upgrader-gh-actions.sh # GitHub Actions pinning and upgrading
```

### GitHub Actions Pinning Script

The `pin-and-upgrader-gh-actions.sh` script is crucial for maintaining supply chain security by pinning GitHub Actions to their SHA commits instead of using mutable tag references.

**What it does:**
- **Pins Actions**: Converts `uses: actions/checkout@v4` to `uses: actions/checkout@8ade135a41bc03ea155e62e844d188df1ea18608`
- **Upgrades Actions**: Checks for newer versions and updates pinned actions to latest SHA digests
- **Bulk Processing**: Handles all `.github/**/*.yml` and `.github/**/*.yaml` files automatically

**Usage Examples:**

```bash
# Make the script executable
chmod +x scripts/pin-and-upgrader-gh-actions.sh

# Preview what would be changed (safe)
./scripts/pin-and-upgrader-gh-actions.sh --dry-run

# Pin all GitHub Actions to their current SHA digests
./scripts/pin-and-upgrader-gh-actions.sh --yes

# Check for upgrades and preview changes
./scripts/pin-and-upgrader-gh-actions.sh --upgrade --dry-run

# Auto-upgrade all actions to latest versions
./scripts/pin-and-upgrader-gh-actions.sh --upgrade --yes

# Interactive mode (prompts for each change)
./scripts/pin-and-upgrader-gh-actions.sh --upgrade
```

**Why Pin GitHub Actions?**
- **Supply Chain Security**: Prevents malicious updates to third-party actions
- **SLSA Level 3 Compliance**: Required for build integrity verification
- **Reproducible Builds**: Ensures consistent CI/CD behavior
- **Audit Trail**: Clear record of exactly which code versions were used

**Setting up GitHub Token (Optional but Recommended):**
```bash
# Set GitHub token to avoid rate limiting
export GITHUB_TOKEN="your_github_token_here"

# Or pass it directly
./scripts/pin-and-upgrader-gh-actions.sh --token your_github_token_here --upgrade
```

**Recommended Workflow:**
1. **Initial Setup**: Pin all actions when setting up the repository
2. **Monthly Maintenance**: Check for upgrades and review changes
3. **Security Updates**: Run immediately when security advisories are published

```bash
# Monthly maintenance routine
./scripts/pin-and-upgrader-gh-actions.sh --upgrade --dry-run
# Review the proposed changes
./scripts/pin-and-upgrader-gh-actions.sh --upgrade --yes
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

### 1. Dockerfile with Pinned Base Images

Your application must have a `Dockerfile` for containerization. **CRITICAL**: For SLSA Level 3 compliance and supply chain security, you MUST pin base images to their SHA256 digests, not just tags.

**Example Dockerfile with pinned images:**

```dockerfile
# Multi-stage build for security and minimal size
FROM python:3.11-slim@sha256:dbf1de478a55d6763afaa39c2f3d7b54b25230614980276de5cacdde79529d0c as builder

# Install only essential build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

WORKDIR /build

# Copy dependency files first for better caching
COPY requirements-lock.txt ./
RUN pip install --no-cache-dir --user -r requirements-lock.txt

# Copy and prepare source code
COPY src/ ./src/

# Final stage - use Google's distroless image for minimal attack surface
FROM gcr.io/distroless/python3-debian12:nonroot@sha256:4f8b42850389c3d3fc274df755d956448b81d4996d5328551893070e16616f1c

# Copy Python packages from builder
COPY --from=builder /root/.local /home/nonroot/.local

# Copy application code
COPY --from=builder /build/src /app/src

WORKDIR /app

# Set Python path for user-installed packages
ENV PATH=/home/nonroot/.local/bin:$PATH
ENV PYTHONPATH=/app

# Use distroless non-root user (UID 65532)
USER nonroot

# Expose port
EXPOSE 8000

# Add security labels
LABEL org.opencontainers.image.source="https://github.com/your-username/your-repo"
LABEL org.opencontainers.image.description="Your App - Ultra-Minimal Secure Build"
LABEL org.opencontainers.image.licenses="MIT"

# Run application
ENTRYPOINT ["python", "-m", "uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "8000"]
```

**How to Pin Base Images to SHA Digests:**

1. **Find the current digest for your base image:**
   ```bash
   # Pull the image you want to use
   docker pull python:3.11-slim
   
   # Get the digest
   docker inspect python:3.11-slim --format='{{index .RepoDigests 0}}'
   # Output: python@sha256:dbf1de478a55d6763afaa39c2f3d7b54b25230614980276de5cacdde79529d0c
   ```

2. **Update your Dockerfile:**
   ```dockerfile
   # Instead of:
   FROM python:3.11-slim
   
   # Use:
   FROM python:3.11-slim@sha256:dbf1de478a55d6763afaa39c2f3d7b54b25230614980276de5cacdde79529d0c
   ```

3. **For distroless images:**
   ```bash
   # Pull and inspect distroless images
   docker pull gcr.io/distroless/python3-debian12:nonroot
   docker inspect gcr.io/distroless/python3-debian12:nonroot --format='{{index .RepoDigests 0}}'
   ```

**Why Pin Base Images?**
- **Supply Chain Security**: Prevents malicious updates to base images
- **SLSA Level 3 Compliance**: Required for provenance verification
- **Reproducible Builds**: Ensures consistent builds across environments
- **Vulnerability Management**: VEX documents can accurately track base image CVEs

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

### 5. Multi-layer SBOM and Attestation Verification

**Verify Multi-layer SBOM Attestations:**
```bash
# Verify all SBOM types attached to your image
python scripts/verify_attestations.py ghcr.io/your-username/your-repo:latest \
  --source-uri github.com/your-username/your-repo \
  --report verification-report.json

# The enhanced verification script will check:
# - Build-time SBOM attestation (application dependencies)
# - Runtime filtered SBOM attestation (Kubescape relevancy analysis)
# - Container SBOM attestation (full image contents)
# - Consolidated multi-layer SBOM attestation (unified view)
# - VEX attestations (vulnerability analysis)
# - SLSA provenance attestations
```

**Manual SBOM Attestation Verification:**
```bash
# Verify specific SBOM types
cosign verify-attestation --type=cyclonedx \
  --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer-regexp ".*" \
  ghcr.io/your-username/your-repo:latest

# Extract and view SBOM contents
cosign verify-attestation --type=cyclonedx \
  --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer-regexp ".*" \
  ghcr.io/your-username/your-repo:latest | \
  jq '.payload | @base64d | fromjson | .predicate'
```

**SLSA Level Assessment:**
The verification script will assess your SLSA compliance level:
- **SLSA Level 3**: Standard provenance + at least one SBOM type
- **SLSA Level 3+**: Enhanced compliance with multiple SBOM layers + VEX attestations
- **Runtime-aware**: Additional points for Kubescape filtered SBOM indicating runtime relevancy

**Verification Report Output:**
```json
{
  "image": "ghcr.io/your-username/your-repo:latest",
  "slsa_level": "3+",
  "sbom_layers_verified": 4,
  "has_vex_attestations": true,
  "has_runtime_filtered_sbom": true,
  "verified_components": [
    "signature", "slsa-provenance", "github-attestations",
    "sbom-build-time", "sbom-runtime-filtered", 
    "sbom-container", "sbom-consolidated", "vex-attestations"
  ],
  "status": "verified"
}
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
- Run `./scripts/pin-and-upgrader-gh-actions.sh --dry-run` to verify all actions can be resolved

**5. Base Image Issues:**
- Verify base image digests are current and accessible
- Check that pinned digests match expected images:
  ```bash
  # Verify a pinned digest
  docker pull python:3.11-slim@sha256:dbf1de478a55d6763afaa39c2f3d7b54b25230614980276de5cacdde79529d0c
  docker inspect python:3.11-slim@sha256:dbf1de478a55d6763afaa39c2f3d7b54b25230614980276de5cacdde79529d0c
  ```

**6. Action Pinning Issues:**
- If actions fail to resolve, check GitHub API rate limits
- Use GitHub token: `export GITHUB_TOKEN="your_token"`
- Verify action repository exists and is accessible

**7. External Cluster Issues:**
- **Kubeconfig Validation**: Verify base64 encoding is correct:
  ```bash
  # Test decoding
  echo "YOUR_BASE64_STRING" | base64 -d > test-kubeconfig
  kubectl --kubeconfig=test-kubeconfig cluster-info
  ```
- **Network Connectivity**: Ensure cluster is accessible from GitHub Actions runners
- **Kubescape Installation**: Check if Kubescape operator is running:
  ```bash
  kubectl get pods -n kubescape
  kubectl get crd | grep kubescape
  ```
- **VEX Document Generation**: Monitor for VEX resource creation:
  ```bash
  # Check for VEX documents
  kubectl get openvulnerabilityexchangecontainers.spdx.softwarecomposition.kubescape.io -n kubescape
  # Fallback check
  kubectl get openvulnerabilityexchangecontainer -n kubescape
  ```
- **Resource Cleanup**: Verify application deployments are cleaned up:
  ```bash
  kubectl get deployments,services --all-namespaces | grep feelgood
  ```

**8. VEX Extraction Issues:**
- **CRD Availability**: Verify Kubescape CRDs are installed:
  ```bash
  kubectl get crd openvulnerabilityexchangecontainers.spdx.softwarecomposition.kubescape.io
  ```
- **Document Naming**: VEX documents follow naming pattern: `registry-org-image-tag-hash`
- **Timing Issues**: VEX generation may take time; check VEX analysis duration settings
- **Empty Results**: If no VEX documents found, check Kubescape logs:
  ```bash
  kubectl logs -n kubescape -l app.kubernetes.io/name=kubescape --tail=50
  ```

**9. Multi-layer SBOM Issues:**
- **Filtered SBOM Generation**: Check if Kubescape filtered SBOM storage is enabled:
  ```bash
  # Verify filtered SBOM CRDs are available
  kubectl get crd sbomsyftfiltereds.spdx.softwarecomposition.kubescape.io -n kubescape
  
  # Check for filtered SBOM documents
  kubectl get sbomsyftfiltereds -n kubescape
  ```
- **SBOM Processing Failures**: Check if all required SBOMs are available:
  ```bash
  # Check workflow artifacts for missing SBOMs
  gh run list --workflow=security-pipeline.yml
  gh run view <run-id> --log
  ```
- **Attestation Verification Failures**: Verify SBOM attestations are properly attached:
  ```bash
  # Check all attestation types
  cosign verify-attestation --type=cyclonedx \
    --certificate-identity-regexp ".*" \
    --certificate-oidc-issuer-regexp ".*" \
    your-image:latest
  
  # Check VEX attestations
  cosign verify-attestation --type=openvex \
    --certificate-identity-regexp ".*" \
    --certificate-oidc-issuer-regexp ".*" \
    your-image:latest
  ```
- **SLSA Level Assessment Issues**: Run enhanced verification for detailed analysis:
  ```bash
  python scripts/verify_attestations.py your-image:latest \
    --source-uri github.com/your-username/your-repo \
    --report detailed-report.json
  
  # Check the detailed report
  cat detailed-report.json | jq '.'
  ```
- **Kubescape Learning Period Issues**: Verify nodeAgent configuration:
  ```bash
  # Check nodeAgent configuration
  kubectl get kubescape -n kubescape -o yaml | grep -A 10 "nodeAgent"
  
  # Check if learning period matches VEX analysis time
  kubectl logs -n kubescape -l app.kubernetes.io/name=node-agent --tail=20
  ```

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
- **SBOM Monitoring**: Regularly verify all four SBOM layers are being generated and properly attested
- **Runtime Relevancy**: Monitor Kubescape filtered SBOM generation for accurate runtime component tracking

## Support and Maintenance

### Regular Tasks

**Weekly Tasks:**
- Review security monitoring reports
- Check for new vulnerability alerts in GitHub Security tab
- Monitor multi-layer SBOM attestation coverage in container registry
- Verify filtered SBOM generation is working properly

**Monthly Tasks:**
- Update dependencies and base images with new SHA digests
- Run GitHub Actions upgrade script: `./scripts/pin-and-upgrader-gh-actions.sh --upgrade`
- Run comprehensive attestation verification: `python scripts/verify_attestations.py your-image:latest --report monthly-report.json`
- Review multi-layer SBOM completeness and accuracy
- Review and update base image pins in Dockerfile:
  ```bash
  # Check for new base image versions
  docker pull python:3.11-slim
  docker inspect python:3.11-slim --format='{{index .RepoDigests 0}}'
  # Update Dockerfile with new digest if needed
  ```

**Quarterly Tasks:**
- Rotate cosign keys and review access permissions
- Full security audit of pinned dependencies and actions
- Update workflow files when new security tools are available

**As Needed:**
- Run GitHub Actions pinning script after security advisories: `./scripts/pin-and-upgrader-gh-actions.sh --upgrade --yes`
- Update base image digests when critical CVEs are patched

### Updates
- Monitor this repository for updates to workflow files
- Subscribe to security advisories for used tools
- Keep external action versions updated
- **Multi-layer SBOM Updates**: Stay current with CycloneDX specification updates and Kubescape feature releases
- **SLSA Framework Updates**: Monitor SLSA specification evolution for enhanced compliance requirements

## Enhanced SLSA Level 3+ Features Summary

This implementation provides **SLSA Level 3+ Enhanced Compliance** through:

### 🎯 **Multi-layer SBOM Strategy**
- **Build-time SBOMs**: Application dependencies as declared by package managers
- **Container SBOMs**: Complete inventory of deployable container contents  
- **Runtime Filtered SBOMs**: Kubescape relevancy analysis identifying active components
- **Consolidated SBOMs**: Unified view with comprehensive SLSA metadata

### 🛡️ **Comprehensive Attestation Coverage**
- Cryptographic signing of all SBOM layers
- VEX attestations with build-time + runtime analysis
- SLSA provenance with enhanced metadata
- Complete verification and validation capabilities

### 🔍 **Runtime Security Intelligence**
- Dynamic component relevancy analysis
- Runtime behavior correlation with vulnerability data
- Supply chain transparency beyond traditional static analysis

For additional support or questions about this enhanced security pipeline, refer to the project documentation or create an issue in the source repository.