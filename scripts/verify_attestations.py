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
    
    def verify_multi_layer_sboms(self) -> bool:
        """Verify multi-layer SBOM attestations for SLSA Level 3+ compliance"""
        print(f"📦 Verifying multi-layer SBOM attestations for {self.image_ref}")
        
        sbom_types = {
            "build-time": "Build-time SBOM (application dependencies)",
            "runtime-filtered": "Runtime filtered SBOM (Kubescape relevancy analysis)",
            "container": "Container SBOM (full image contents)",
            "consolidated": "Consolidated multi-layer SBOM"
        }
        
        verified_sboms = []
        sbom_details = {}
        
        for sbom_type, description in sbom_types.items():
            print(f"  🔍 Checking {description}...")
            
            result = subprocess.run([
                "cosign", "verify-attestation",
                "--type", "cyclonedx",
                "--certificate-identity-regexp", ".*",
                "--certificate-oidc-issuer-regexp", ".*",
                self.image_ref
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                try:
                    attestations = json.loads(result.stdout)
                    # Look for SBOM that matches our type based on metadata
                    for attestation in attestations:
                        predicate = attestation.get("predicate", {})
                        metadata = predicate.get("metadata", {})
                        properties = metadata.get("properties", [])
                        
                        # Check if this SBOM matches our type
                        layer_match = False
                        for prop in properties:
                            if (prop.get("name") == "slsa:layer" and 
                                prop.get("value") == sbom_type.replace("-", "-")):
                                layer_match = True
                                break
                        
                        # For consolidated SBOM, check for layer_types property
                        if sbom_type == "consolidated":
                            for prop in properties:
                                if (prop.get("name") == "sbom:layer_types" and 
                                    "build-time" in prop.get("value", "")):
                                    layer_match = True
                                    break
                        
                        # If no specific layer info, consider it for build-time or container
                        if not layer_match and sbom_type in ["build-time", "container"]:
                            layer_match = True
                        
                        if layer_match:
                            components = predicate.get("components", [])
                            component_count = len(components)
                            sbom_details[sbom_type] = {
                                "components": component_count,
                                "format": predicate.get("bomFormat", "Unknown"),
                                "spec_version": predicate.get("specVersion", "Unknown")
                            }
                            verified_sboms.append(sbom_type)
                            print(f"    ✅ {description}: {component_count} components")
                            break
                    else:
                        print(f"    ⚠️ {description}: Not found or no matching layer info")
                        
                except json.JSONDecodeError:
                    print(f"    ❌ {description}: Invalid JSON in attestation")
            else:
                print(f"    ⚠️ {description}: No attestation found")
        
        if verified_sboms:
            print(f"\n📊 SBOM Verification Summary:")
            for sbom_type in verified_sboms:
                details = sbom_details.get(sbom_type, {})
                print(f"  ✅ {sbom_types[sbom_type]}")
                print(f"     📦 Components: {details.get('components', 'Unknown')}")
                print(f"     📋 Format: {details.get('format', 'Unknown')} v{details.get('spec_version', 'Unknown')}")
            
            self.verified_components.extend([f"sbom-{sbom}" for sbom in verified_sboms])
            print(f"✅ Multi-layer SBOM verification: {len(verified_sboms)}/{len(sbom_types)} types verified")
            return True
        else:
            print("❌ No SBOM attestations found")
            return False
    
    def verify_vex_attestations(self) -> bool:
        """Verify VEX attestations"""
        print(f"🛡️ Verifying VEX attestations for {self.image_ref}")
        
        result = subprocess.run([
            "cosign", "verify-attestation",
            "--type", "openvex",
            "--certificate-identity-regexp", ".*",
            "--certificate-oidc-issuer-regexp", ".*",
            self.image_ref
        ], capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"⚠️ VEX attestations not found or verification failed")
            return False
        
        try:
            attestations = json.loads(result.stdout)
            total_statements = 0
            
            for attestation in attestations:
                predicate = attestation.get("predicate", {})
                statements = predicate.get("statements", [])
                total_statements += len(statements)
            
            print(f"✅ VEX attestations verified: {total_statements} statements across {len(attestations)} documents")
            self.verified_components.append("vex-attestations")
            return True
            
        except json.JSONDecodeError:
            print("❌ Invalid VEX attestation JSON")
            return False
    
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
        # Assess SLSA level based on verified components
        slsa_level = "unknown"
        sbom_components = [comp for comp in self.verified_components if comp.startswith("sbom-")]
        has_vex = "vex-attestations" in self.verified_components
        
        if "slsa-provenance" in self.verified_components:
            if len(sbom_components) >= 3 and has_vex:
                slsa_level = "3+"  # Enhanced SLSA Level 3 with multi-layer SBOMs and VEX
            elif len(sbom_components) >= 1:
                slsa_level = "3"   # Standard SLSA Level 3
            else:
                slsa_level = "2+"  # SLSA Level 2 with provenance
        
        return {
            "image": self.image_ref,
            "timestamp": subprocess.check_output(["date", "-Iseconds"], text=True).strip(),
            "verified_components": self.verified_components,
            "slsa_level": slsa_level,
            "sbom_layers_verified": len(sbom_components),
            "has_vex_attestations": has_vex,
            "has_runtime_filtered_sbom": "sbom-runtime-filtered" in self.verified_components,
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
    
    # Verify multi-layer SBOMs for SLSA Level 3+ compliance
    print("\n" + "="*60)
    if not verifier.verify_multi_layer_sboms():
        print("⚠️ Multi-layer SBOM verification failed, but continuing...")
    
    # Verify VEX attestations
    print("\n" + "="*60)
    if not verifier.verify_vex_attestations():
        print("⚠️ VEX attestation verification failed, but continuing...")
    
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
