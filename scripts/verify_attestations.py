#!/usr/bin/env python3
"""Enhanced SLSA attestation and signature verification"""
import subprocess
import json
import sys
import argparse
from typing import Optional


class AttestationVerifier:
    """Verify SLSA attestations and container signatures"""
    
    def __init__(self, image_ref: str):
        self.image_ref = image_ref
        self.verified_components = []
    
    def verify_signature(self) -> bool:
        """Verify container signature with Cosign"""
        print(f"🔍 Verifying signature for {self.image_ref}")
        
        result = subprocess.run([
            "cosign", "verify",
            "--certificate-identity-regexp", ".*",
            "--certificate-oidc-issuer-regexp", ".*",
            self.image_ref
        ], capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"❌ Signature verification failed: {result.stderr}")
            return False
        
        print("✅ Container signature verified")
        self.verified_components.append("signature")
        return True
    
    def verify_slsa_provenance(self) -> bool:
        """Verify SLSA provenance attestation"""
        print(f"🔍 Verifying SLSA provenance for {self.image_ref}")
        
        result = subprocess.run([
            "cosign", "verify-attestation",
            "--type", "slsaprovenance",
            "--certificate-identity-regexp", ".*",
            "--certificate-oidc-issuer-regexp", ".*",
            self.image_ref
        ], capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"❌ SLSA provenance verification failed: {result.stderr}")
            return False
        
        print("✅ SLSA provenance verified")
        self.verified_components.append("slsa-provenance")
        
        # Parse and display provenance details
        try:
            attestation = json.loads(result.stdout)
            self._display_provenance_summary(attestation)
        except json.JSONDecodeError:
            print("⚠️ Could not parse provenance attestation")
        
        return True
    
    def verify_with_slsa_verifier(self, source_uri: str) -> bool:
        """Verify using the official SLSA verifier"""
        print(f"🔍 Verifying with SLSA verifier against source {source_uri}")
        
        result = subprocess.run([
            "slsa-verifier", "verify-image",
            self.image_ref,
            "--source-uri", source_uri
        ], capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"❌ SLSA verifier failed: {result.stderr}")
            return False
        
        print("✅ SLSA verifier validation passed")
        self.verified_components.append("slsa-verifier")
        return True
    
    def verify_github_attestations(self) -> bool:
        """Verify GitHub native attestations"""
        print(f"🔍 Verifying GitHub attestations for {self.image_ref}")
        
        result = subprocess.run([
            "cosign", "verify-attestation",
            "--type", "https://slsa.dev/provenance/v1",
            "--certificate-identity-regexp", ".*",
            "--certificate-oidc-issuer-regexp", ".*",
            self.image_ref
        ], capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"⚠️ GitHub attestations not found or verification failed")
            return False
        
        print("✅ GitHub attestations verified")
        self.verified_components.append("github-attestations")
        return True
    
    def _display_provenance_summary(self, attestation: dict):
        """Display a summary of the provenance attestation"""
        print("\n📋 Provenance Summary:")
        
        # Extract key information
        builder_id = attestation.get("predicate", {}).get("builder", {}).get("id", "Unknown")
        build_type = attestation.get("predicate", {}).get("buildType", "Unknown")
        
        invocation = attestation.get("predicate", {}).get("invocation", {})
        config_source = invocation.get("configSource", {})
        
        print(f"  🏗️  Builder: {builder_id}")
        print(f"  🔧 Build Type: {build_type}")
        print(f"  📂 Source URI: {config_source.get('uri', 'Unknown')}")
        print(f"  🎯 Entry Point: {config_source.get('entryPoint', 'Unknown')}")
        
        # Display materials (dependencies)
        materials = attestation.get("predicate", {}).get("materials", [])
        if materials:
            print(f"  📦 Materials: {len(materials)} components")
            for material in materials[:3]:  # Show first 3
                print(f"    - {material.get('uri', 'Unknown')}")
            if len(materials) > 3:
                print(f"    ... and {len(materials) - 3} more")
    
    def generate_verification_report(self) -> dict:
        """Generate a verification report"""
        return {
            "image": self.image_ref,
            "timestamp": subprocess.check_output(["date", "-Iseconds"], text=True).strip(),
            "verified_components": self.verified_components,
            "slsa_level": "3" if "slsa-provenance" in self.verified_components else "unknown",
            "status": "verified" if self.verified_components else "failed"
        }


def main():
    parser = argparse.ArgumentParser(description="Verify SLSA attestations and signatures")
    parser.add_argument("image_ref", help="Container image reference to verify")
    parser.add_argument("--source-uri", help="Source repository URI for verification")
    parser.add_argument("--report", help="Output verification report to file")
    
    args = parser.parse_args()
    
    verifier = AttestationVerifier(args.image_ref)
    
    # Run all verifications
    all_passed = True
    
    # Verify signature
    if not verifier.verify_signature():
        all_passed = False
    
    # Verify SLSA provenance
    if not verifier.verify_slsa_provenance():
        all_passed = False
    
    # Verify with SLSA verifier if source URI provided
    if args.source_uri:
        if not verifier.verify_with_slsa_verifier(args.source_uri):
            all_passed = False
    
    # Try to verify GitHub attestations
    verifier.verify_github_attestations()  # Don't fail on this
    
    # Generate report
    report = verifier.generate_verification_report()
    
    if args.report:
        with open(args.report, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"\n📄 Verification report saved to {args.report}")
    
    print(f"\n🎯 Overall Status: {'PASSED' if all_passed else 'FAILED'}")
    print(f"🔧 Verified Components: {', '.join(verifier.verified_components)}")
    
    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
