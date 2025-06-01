#!/usr/bin/env python3
"""Enhanced SBOM generation with additional metadata"""
import subprocess
import json
import sys
from datetime import datetime


def generate_enhanced_sbom():
    """Generate SBOM with additional metadata"""
    # Run cyclonedx-bom
    result = subprocess.run(
        ["cyclonedx-py", "-p", "-o", "-", "--format", "json"],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"Error generating SBOM: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    
    # Parse and enhance SBOM
    sbom = json.loads(result.stdout)
    
    # Add metadata
    sbom["metadata"]["timestamp"] = datetime.now().isoformat()
    sbom["metadata"]["properties"] = [
        {
            "name": "build.timestamp",
            "value": datetime.now().isoformat()
        },
        {
            "name": "build.tool",
            "value": "github-actions"
        },
        {
            "name": "slsa.buildLevel",
            "value": "3"
        }
    ]
    
    return json.dumps(sbom, indent=2)


if __name__ == "__main__":
    print(generate_enhanced_sbom())
