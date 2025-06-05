# Base Image Update Automation

This document describes the automated base image update system that keeps Docker base images current with the latest security patches and improvements while maintaining supply chain security through SHA digest pinning.

## Overview

The base image update system consists of:

1. **`scripts/update-base-images.sh`** - Script that scans Dockerfiles and updates base images to latest SHA digests
2. **`.github/workflows/base-image-updates.yml`** - GitHub Actions workflow that runs weekly to check for updates and create PRs

## How It Works

### 1. Image Detection
The script automatically finds and analyzes all Dockerfiles in your repository, parsing `FROM` statements to identify:
- Base image names (e.g., `python`, `gcr.io/distroless/python3-debian12`)
- Tags (e.g., `3.11-slim`, `nonroot`)
- Current SHA digests (if already pinned)

### 2. Update Checking
For each base image, the script:
- Pulls the latest version of the specified tag
- Extracts the current SHA digest
- Compares with the pinned digest in your Dockerfile
- Checks image creation dates to avoid unnecessary updates

### 3. Automated Updates
The weekly GitHub Actions workflow:
- Runs the update script to detect available updates
- Creates a new branch with updated Dockerfiles
- Generates a pull request with detailed change information
- Includes security context and testing recommendations

## Script Usage

### Basic Usage

```bash
# Check what updates are available (safe, no changes)
./scripts/update-base-images.sh --dry-run

# Apply updates interactively (prompts for each change)
./scripts/update-base-images.sh

# Apply all updates automatically
./scripts/update-base-images.sh --yes

# Force updates even for recent images
./scripts/update-base-images.sh --force --yes
```

### Options

| Flag | Description |
|------|-------------|
| `-d, --dry-run` | Preview changes without modifying files |
| `-y, --yes` | Apply changes automatically without prompts |
| `-f, --force` | Update even if current images are recent |
| `-t, --token TOKEN` | GitHub token for API access |
| `-h, --help` | Show help message |

### Example Output

```bash
$ ./scripts/update-base-images.sh --dry-run
Docker Base Image Update Script
===============================

🔍 Finding Dockerfiles...
Found 1 Dockerfile(s):
  ./Dockerfile

🔍 DRY RUN MODE - No changes will be made

Processing: ./Dockerfile
  📦 Line 2: Found image python:3.11-slim
  🔍 Checking python:3.11-slim for updates... ✓ Latest digest available
    📅 Newer image available:
      Current: 2025-05-08T22:27:23Z
      Latest:  2025-06-03T23:02:53Z
    📝 Update available:
      Current: python:3.11-slim@sha256:dbf1de478a55d6763afaa39c2f3d7b54b25230614980276de5cacdde79529d0c
      Latest:  python:3.11-slim@sha256:7a3ed1226224bcc1fe5443262363d42f48cf832a540c1836ba8ccbeaadf8637c
    WOULD CHANGE:
      FROM: FROM python:3.11-slim@sha256:dbf1de478a55d6763afaa39c2f3d7b54b25230614980276de5cacdde79529d0c as builder
      TO:   FROM python:3.11-slim@sha256:7a3ed1226224bcc1fe5443262363d42f48cf832a540c1836ba8ccbeaadf8637c as builder
```

## Workflow Configuration

### Schedule
The workflow runs automatically:
- **Weekly**: Every Monday at 2:00 AM UTC
- **Manual**: Can be triggered via GitHub Actions UI with optional force update

### Permissions Required
```yaml
permissions:
  contents: write      # Create branches and commits
  pull-requests: write # Create pull requests
  actions: read       # Access workflow information
```

### Manual Trigger
You can manually trigger the workflow with force update option:
1. Go to **Actions** → **Base Image Updates**
2. Click **Run workflow**
3. Optionally check **Force update** to update even recent images

## Pull Request Process

When updates are available, the workflow creates a PR with:

### PR Title Format
```
🐳 Update Docker base images (YYYY-MM-DD)
```

### PR Content Includes
- **Update Summary**: Number of images updated and files modified
- **Detailed Changes**: Diff showing exact SHA digest changes
- **Security Benefits**: Explanation of security improvements
- **Testing Recommendations**: Checklist for validation
- **Review Checklist**: Steps for maintainers

### Example PR Body
```markdown
## 🐳 Automated Base Image Updates

This automated pull request updates Docker base images to their latest SHA digests to ensure we're using the most recent versions with security patches and improvements.

### 📊 Update Summary
- **Updated Images**: 1
- **Files Modified**: Dockerfile
- **Update Date**: 2025-06-05 02:00:00 UTC
- **Trigger**: schedule

### 🔍 What Changed
```diff
-FROM python:3.11-slim@sha256:dbf1de478a55d6763afaa39c2f3d7b54b25230614980276de5cacdde79529d0c as builder
+FROM python:3.11-slim@sha256:7a3ed1226224bcc1fe5443262363d42f48cf832a540c1836ba8ccbeaadf8637c as builder
```

### 🛡️ Security Benefits
- **Latest Security Patches**: Updated base images include the latest security fixes
- **Supply Chain Security**: All images pinned to specific SHA digests
- **SLSA Level 3 Compliance**: Maintains build reproducibility and integrity
- **Vulnerability Management**: VEX documents will accurately track any new CVEs
```

## Integration with Security Pipeline

### Automatic Validation
When a base image update PR is created:
1. **Security Pipeline** runs automatically to validate changes
2. **Container Builds** test with new base images
3. **Vulnerability Scans** check for new security issues
4. **VEX Documents** are updated if new vulnerabilities are found

### SLSA Level 3 Compliance
Base image updates maintain SLSA Level 3 compliance by:
- Pinning all images to specific SHA digests
- Providing complete build provenance
- Ensuring reproducible builds
- Maintaining audit trail of all changes

## Best Practices

### Review Process
1. **Automatic Checks**: Wait for security pipeline to complete
2. **Manual Review**: Check the specific image changes
3. **Vulnerability Assessment**: Review any new security findings
4. **Testing**: Validate application functionality if significant changes
5. **Merge**: Approve once all checks pass

### Maintenance Schedule
- **Weekly**: Automated updates via workflow
- **As Needed**: Manual updates for critical security patches
- **Monthly**: Review update patterns and adjust configuration

### Emergency Updates
For critical security vulnerabilities:
```bash
# Force immediate update
./scripts/update-base-images.sh --force --yes

# Or trigger workflow manually with force option
gh workflow run base-image-updates.yml -f force_update=true
```

## Troubleshooting

### Common Issues

**1. Script Fails to Pull Images**
```bash
# Check Docker daemon is running
docker version

# Check network connectivity
docker pull hello-world

# Check image name/tag exists
docker pull python:3.11-slim
```

**2. No Updates Detected**
- Current images may already be latest
- Use `--force` flag to update regardless of age
- Check if image repositories are accessible

**3. Workflow Permission Errors**
- Verify repository settings allow Actions to create PRs
- Check workflow permissions in `.github/workflows/base-image-updates.yml`

**4. Large Number of Updates**
- Review changes carefully before merging
- Consider updating in smaller batches
- Test application functionality thoroughly

### Debug Commands

```bash
# Check current image details
docker inspect python:3.11-slim --format='{{.Created}} {{index .RepoDigests 0}}'

# Manually pull latest version
docker pull python:3.11-slim

# Compare digests
docker images --digests python
```

## Configuration

### Customizing Update Frequency
Edit `.github/workflows/base-image-updates.yml`:
```yaml
on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly on Monday at 2 AM UTC
    # - cron: '0 2 * * *'  # Daily at 2 AM UTC
    # - cron: '0 2 1 * *'  # Monthly on 1st at 2 AM UTC
```

### Excluding Specific Images
The script automatically skips:
- `scratch` images
- Local images (starting with `./`)

To exclude specific images, modify the script's `process_dockerfile()` function.

### Custom Branch Naming
The workflow creates branches with format:
```
base-images/update-YYYYMMDD-HHMMSS
```

## Security Considerations

### Supply Chain Security
- All updates maintain SHA digest pinning
- No mutable tag references are introduced
- Complete audit trail via Git history

### Vulnerability Management
- Updated images include latest security patches
- VEX documents track any new vulnerabilities
- Security pipeline validates all changes

### Access Control
- Workflow uses standard GitHub tokens
- No external credentials required
- Branch protection rules apply to update PRs

## Monitoring and Alerting

### GitHub Notifications
- PR creation notifications
- Workflow failure alerts
- Security pipeline status updates

### Workflow Summary
Each run creates a detailed summary showing:
- Number of images updated
- Files modified
- Pull request status
- Next scheduled run

### Integration with Security Monitoring
Base image updates integrate with the existing security monitoring workflow to provide comprehensive vulnerability tracking across the entire container supply chain.