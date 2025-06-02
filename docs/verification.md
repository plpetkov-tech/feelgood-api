# Verifying FeelGood API Supply Chain Security

## Prerequisites

Install verification tools:
```bash
# Install Cosign
brew install cosign  # macOS
# or
curl -O -L "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64"

# Install SLSA Verifier
go install github.com/slsa-framework/slsa-verifier/v2/cli/slsa-verifier@latest

# Install Grype for SBOM verification
brew install grype
```
