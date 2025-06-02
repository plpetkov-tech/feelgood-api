#!/usr/bin/env python3
"""Enhanced SBOM generation with SLSA metadata"""
import subprocess
import json
import sys
import os
from datetime import datetime
from pathlib import Path


def get_git_info():
    """Get Git repository information"""
    try:
        commit_sha = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], 
            text=True
        ).strip()
        
        repo_url = subprocess.check_output(
            ["git", "config", "--get", "remote.origin.url"], 
            text=True
        ).strip()
        
        return {
            "commit_sha": commit_sha,
            "repository_url": repo_url
        }
    except subprocess.CalledProcessError:
        return {
            "commit_sha": "unknown",
            "repository_url": "unknown"
        }


def generate_enhanced_sbom():
    """Generate SBOM with enhanced metadata and SLSA properties"""
    
    # Run cyclonedx-bom to generate base SBOM
    result = subprocess.run(
        ["poetry", "run", "cyclonedx-py", "poetry", "-o", "-", "--of", "json"],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"Error generating SBOM: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    
    # Parse base SBOM
    sbom = json.loads(result.stdout)
    
    # Get environment information
    git_info = get_git_info()
    build_timestamp = datetime.now().isoformat()
    
    # Enhance metadata
    if "metadata" not in sbom:
        sbom["metadata"] = {}
    
    sbom["metadata"]["timestamp"] = build_timestamp
    
    # Add SLSA-related properties
    if "properties" not in sbom["metadata"]:
        sbom["metadata"]["properties"] = []
    
    slsa_properties = [
        {
            "name": "build.timestamp",
            "value": build_timestamp
        },
        {
            "name": "build.tool",
            "value": "github-actions"
        },
        {
            "name": "build.platform",
            "value": "GitHub Actions"
        },
        {
            "name": "slsa.buildLevel",
            "value": "3"
        },
        {
            "name": "source.commit.sha",
            "value": git_info["commit_sha"]
        },
        {
            "name": "source.repository.url", 
            "value": git_info["repository_url"]
        }
    ]
    
    # Add GitHub Actions specific metadata if available
    if "GITHUB_ACTIONS" in os.environ:
        github_properties = [
            {
                "name": "github.workflow",
                "value": os.environ.get("GITHUB_WORKFLOW", "")
            },
            {
                "name": "github.run.id",
                "value": os.environ.get("GITHUB_RUN_ID", "")
            },
            {
                "name": "github.run.number",
                "value": os.environ.get("GITHUB_RUN_NUMBER", "")
            },
            {
                "name": "github.actor",
                "value": os.environ.get("GITHUB_ACTOR", "")
            }
        ]
        slsa_properties.extend(github_properties)
    
    sbom["metadata"]["properties"].extend(slsa_properties)
    
    # Add component metadata
    if "component" in sbom["metadata"]:
        sbom["metadata"]["component"]["supplier"] = {
            "name": "FeelGood API Team",
            "url": ["https://github.com/yourusername/feelgood-api"]
        }
        
        # Add external references
        if "externalReferences" not in sbom["metadata"]["component"]:
            sbom["metadata"]["component"]["externalReferences"] = []
        
        sbom["metadata"]["component"]["externalReferences"].extend([
            {
                "type": "vcs",
                "url": git_info["repository_url"]
            },
            {
                "type": "website",
                "url": "https://github.com/yourusername/feelgood-api"
            }
        ])
    
    return json.dumps(sbom, indent=2)


if __name__ == "__main__":
    print(generate_enhanced_sbom())
