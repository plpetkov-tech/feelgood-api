# Feel Good Phrases API - Supply Chain Security PoC

A Python FastAPI application demonstrating comprehensive supply chain security practices including immutable builds, SLSA provenance, SBOM generation, and VEX documents.

## Features

### Application
- FastAPI-based REST API serving motivational phrases
- Categories: motivation, gratitude, kindness, growth
- Health checks and security endpoints
- Comprehensive test coverage

### Supply Chain Security
- **Immutable Builds**: Poetry lock files ensure reproducible builds
- **SLSA Level 3 Provenance**: Automated attestation generation
- **SBOM Generation**: CycloneDX format with full dependency tree
- **VEX Documents**: Vulnerability exploitability assessments
- **Container Signing**: Cosign signatures for all images
- **Security Scanning**: Trivy vulnerability scanning

## Quick Start

### Local Development
```bash
# Install dependencies
make install

# Run tests
make test

# Run linters
make lint

# Generate SBOM locally
make sbom

# Build container
make build

# Run container
make run
```

### API Endpoints
- `GET /` - API information
- `GET /health` - Health check with build info
- `GET /phrase` - Get random feel-good phrase
- `GET /phrase?category=motivation` - Get phrase from specific category
- `GET /phrases/categories` - List all categories
- `GET /security` - Security information
- `GET /security/sbom` - Download SBOM
- `GET /security/vex` - Download VEX document
- `GET /security/provenance` - View provenance information

## Supply Chain Security Implementation

### 1. Dependency Management
- Uses Poetry for deterministic dependency resolution
- Lock files (`poetry.lock` and `requirements-lock.txt`) ensure reproducible builds
- Regular dependency updates via Dependabot

### 2. Build Process
- Multi-stage Docker builds for minimal attack surface
- Non-root container execution
- Build-time SBOM generation
- Comprehensive security headers

### 3. SLSA Provenance
- GitHub Actions workflow generates SLSA Level 3 provenance
- Provenance includes:
  - Source repository information
  - Build environment details
  - Build parameters
  - Cryptographic signatures

### 4. SBOM (Software Bill of Materials)
- Generated in CycloneDX format
- Includes all direct and transitive dependencies
- Embedded in container image
- Accessible via API endpoint

### 5. VEX (Vulnerability Exploitability eXchange)
- Documents known vulnerabilities and their exploitability
- Reduces false positives in security scans
- Updated independently of builds
- Machine-readable format

### 6. Container Security
- Signed with Cosign (keyless signing via OIDC)
- Vulnerability scanning with Trivy
- Security findings uploaded to GitHub Security tab
- Minimal base image (python:3.11-slim)

## Verification

### Verify Container Signatures
```bash
# Install cosign
brew install cosign  # or your package manager

# Verify signature
cosign verify --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  ghcr.io/yourusername/feelgood-api:latest

# Verify SLSA provenance
cosign verify-attestation --type slsaprovenance \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  ghcr.io/yourusername/feelgood-api:latest
```

### Verify SBOM
```bash
# Download and verify SBOM
curl http://localhost:8000/security/sbom | jq .

# Scan with Grype
grype sbom:./sbom.json
```

### Verify Build Reproducibility
```bash
# Clone repository
git clone https://github.com/yourusername/feelgood-api.git
cd feelgood-api

# Checkout specific commit
git checkout <commit-sha>

# Install exact dependencies
poetry install --no-dev

# Verify installed packages match lock file
poetry show --tree
```

## CI/CD Pipeline

The GitHub Actions workflow performs:
1. **Test & Scan**: Run tests, linters, and security audits
2. **Build**: Create container image with embedded SBOM
3. **Sign**: Sign container with Cosign
4. **Generate Provenance**: Create SLSA attestations
5. **Scan**: Run Trivy vulnerability scanner
6. **Generate VEX**: Create exploitability assessments

## Security Best Practices Demonstrated

1. **Principle of Least Privilege**: Non-root container user
2. **Defense in Depth**: Multiple security layers
3. **Supply Chain Transparency**: Full visibility into dependencies
4. **Immutable Infrastructure**: Reproducible builds
5. **Continuous Security**: Automated scanning and updates
6. **Cryptographic Verification**: Signed artifacts
7. **Security Headers**: OWASP recommended headers
8. **Minimal Attack Surface**: Slim base images, only required dependencies

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run tests and linters
4. Update SBOM if dependencies change
5. Submit pull request

## License

MIT License - See LICENSE file for details
