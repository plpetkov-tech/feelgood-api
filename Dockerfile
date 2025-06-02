# Multi-stage build for supply chain security
FROM python:3.11-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy dependency files
COPY pyproject.toml poetry.lock requirements.txt requirements-lock.txt ./

# Install poetry and dependencies
RUN pip install --no-cache-dir poetry==1.7.1 && \
    poetry config virtualenvs.create false && \
    poetry install --no-interaction --no-ansi --no-root

# Generate pip freeze for hash verification
RUN pip freeze > /build/pip-freeze.txt

# Copy source code
COPY src/ ./src/
COPY scripts/ ./scripts/

# Generate SBOM during build
RUN pip install cyclonedx-bom && \
    cyclonedx-py poetry -o /build/sbom.json --of json

# Final stage
FROM python:3.11-slim

# Security: Run as non-root user
RUN useradd -m -u 1000 apiuser

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy dependencies from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application
COPY --from=builder /build/src ./src
COPY --from=builder /build/sbom.json ./sbom.json
COPY --from=builder /build/pip-freeze.txt ./pip-freeze.txt

# Copy lock files for transparency
COPY requirements-lock.txt ./
COPY poetry.lock ./

# Set ownership
RUN chown -R apiuser:apiuser /app

# Switch to non-root user
USER apiuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Labels for provenance
LABEL org.opencontainers.image.source="https://github.com/plpetkov-tech/feelgood-api"
LABEL org.opencontainers.image.description="Feel Good Phrases API with SLSA provenance"
LABEL org.opencontainers.image.licenses="MIT"

# Run the application
CMD ["uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "8000"]
