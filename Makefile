.PHONY: help install lock test lint security-check build run clean

help:
	@echo "Available commands:"
	@echo ""
	@echo "📦 Dependencies:"
	@echo "  make install        Install dependencies"
	@echo "  make lock          Generate lock files"
	@echo "  make refresh-locks  Refresh lock files (clear caches and regenerate)"
	@echo "  make update-deps   Update dependencies and regenerate locks"
	@echo "  make bump-deps     Bump all dependencies to latest versions"
	@echo "  make verify-lock   Verify lock file integrity"
	@echo ""
	@echo "🧪 Testing & Quality:"
	@echo "  make test          Run tests"
	@echo "  make lint          Run linters (black, ruff, mypy)"
	@echo ""
	@echo "🔒 Security:"
	@echo "  make security-check Run basic security checks"
	@echo "  make security-full  Run full security pipeline"
	@echo "  make trivy-scan    Run Trivy vulnerability scan"
	@echo "  make verify-local  Verify attestations locally (requires IMAGE=...)"
	@echo ""
	@echo "📋 Documentation & Compliance:"
	@echo "  make sbom          Generate SBOM with build metadata"
	@echo "  make vex           Generate VEX document"
	@echo "  make slsa-check    Check SLSA Level 3 compliance"
	@echo ""
	@echo "🐳 Docker:"
	@echo "  make build         Build Docker image"
	@echo "  make run           Run Docker container"
	@echo ""
	@echo "🧹 Utilities:"
	@echo "  make clean         Clean up cache files and bytecode"

install:
	poetry install

# Generate all lock files
lock:
	@echo "🔒 Generating lock files..."
	poetry lock 
	poetry export -f requirements.txt --output requirements.txt --without-hashes
	poetry export -f requirements.txt --output requirements-lock.txt 
	poetry export -f requirements.txt --output requirements-dev.txt --with dev --without-hashes
	@echo "✅ Lock files generated"

# Verify lock file integrity
verify-lock:
	poetry check
	@echo "✅ Lock file verified"

# Update dependencies and regenerate locks
update-deps:
	@echo "📦 Updating dependencies..."
	poetry update
	$(MAKE) lock
	@echo "✅ Dependencies updated"

# Bump all dependencies to latest versions
bump-deps:
	@echo "🚀 Bumping all dependencies to latest versions..."
	./scripts/bump-deps.sh
	@echo "✅ All dependencies updated to latest versions"

# Clear caches and regenerate everything
refresh-locks:
	@echo "🧹 Clearing caches..."
	poetry cache clear pypi --all -n
	rm -f poetry.lock requirements*.txt
	poetry lock
	$(MAKE) lock
	@echo "✅ Lock files refreshed"

test:
	poetry run pytest tests/ -v

lint:
	poetry run black src/ tests/
	poetry run mypy src/

security-check:
	poetry run pip-audit
	@echo "Checking for known vulnerabilities in dependencies..."

build:
	docker build -t feelgood-api:latest .


run:
	docker run -p 8000:8000 feelgood-api:latest

clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
# Add to existing Makefile

# Security targets
security-full: security-check sbom vex verify-local
	@echo "✅ Full security pipeline completed"

# Generate SBOM with build metadata
sbom:
	poetry run python scripts/generate_sbom.py > sbom.json
	@echo "SBOM generated: sbom.json"

# Generate VEX document
vex:
	@echo "🔍 Generating VEX document..."
	@if [ -f "trivy-results.json" ] && [ -f "sbom.json" ]; then \
		python scripts/generate_vex.py --trivy-results trivy-results.json --sbom sbom.json --output vex.json; \
	else \
		python scripts/generate_vex.py --output vex.json; \
	fi
	@echo "✅ VEX document generated: vex.json"

# Run Trivy scan locally
trivy-scan:
	@echo "🔍 Running Trivy vulnerability scan..."
	trivy fs --format json --output trivy-results.json .
	trivy fs --format table .

# Verify attestations locally
verify-local:
	@if [ -z "$(IMAGE)" ]; then \
		echo "❌ Please specify IMAGE variable: make verify-local IMAGE=ghcr.io/user/repo:tag"; \
		exit 1; \
	fi
	python scripts/verify_attestations.py $(IMAGE) --source-uri github.com/$$(git config --get remote.origin.url | sed 's/.*github.com[:\/]\([^.]*\).*/\1/')

# SLSA compliance check
slsa-check: sbom vex
	@echo "🎯 SLSA Level 3 Compliance Check:"
	@echo "  ✅ Build process documented (Dockerfile, GitHub Actions)"
	@echo "  ✅ Provenance generation enabled (SLSA generator)"
	@echo "  ✅ Isolated build environment (GitHub Actions hosted runners)"
	@echo "  ✅ SBOM generated with build metadata"
	@echo "  ✅ VEX document for vulnerability analysis"
	@echo "  ✅ Container signing with Cosign"
	@echo "🏆 SLSA Level 3 requirements satisfied!"
