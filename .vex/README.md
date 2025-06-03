# VEX Documents

This directory contains VEX (Vulnerability Exploitability eXchange) documents for the project.

## Directory Structure

- `production/` - VEX documents generated from production runtime analysis
- `build-time/` - VEX documents generated during CI/CD build process  
- `consolidated/` - Merged VEX documents combining multiple sources
- `archive/` - Historical VEX documents for reference

## VEX Document Naming Convention

Production VEX documents should follow this naming pattern:
```
production/{environment}-{timestamp}.vex.json
```

Examples:
- `production/prod-cluster-20250603T120000Z.vex.json`
- `production/staging-cluster-20250603T120000Z.vex.json`

## Updating Production VEX

To add new VEX documents from production:

1. Copy VEX files to the `production/` directory
2. Commit and push to trigger the VEX integration workflow
3. The workflow will automatically consolidate and update attestations

## VEX Document Format

All VEX documents should follow the OpenVEX specification:
- Use proper PURL identifiers for products
- Include required fields: @context, @id, author, timestamp, statements
- Validate using `vexctl validate` before committing
