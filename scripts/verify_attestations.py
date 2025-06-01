#!/usr/bin/env python3
"""Verify SLSA attestations and signatures"""
import subprocess
import json
import sys


def verify_image_attestation(image_ref: str):
    """Verify SLSA provenance for a container image"""
    print(f"Verifying attestations for {image_ref}")
    
    # Verify signature
    result = subprocess.run(
        ["cosign", "verify", "--certificate-identity-regexp", ".*", 
         "--certificate-oidc-issuer-regexp", ".*", image_ref],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"Signature verification failed: {result.stderr}")
        return False
    
    print("✓ Signature verified")
    
    # Verify SLSA provenance
    result = subprocess.run(
        ["cosign", "verify-attestation", "--type", "slsaprovenance",
         "--certificate-identity-regexp", ".*",
         "--certificate-oidc-issuer-regexp", ".*", image_ref],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"Provenance verification failed: {result.stderr}")
        return False
    
    print("✓ SLSA provenance verified")
    
    # Parse and display provenance
    try:
        attestation = json.loads(result.stdout)
        print("\nProvenance summary:")
        print(f"  Builder: {attestation.get('builder', {}).get('id', 'Unknown')}")
        print(f"  Build type: {attestation.get('buildType', 'Unknown')}")
    except:
        pass
    
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: verify_attestations.py <image-ref>")
        sys.exit(1)
    
    success = verify_image_attestation(sys.argv[1])
    sys.exit(0 if success else 1)
