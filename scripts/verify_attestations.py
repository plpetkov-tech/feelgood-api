#!/usr/bin/env python3
"""Enhanced SLSA attestation and signature verification"""
import subprocess
import json
import sys
import argparse
import re
import shlex
from typing import Optional
from pathlib import Path


class AttestationVerifier:
    """Verify SLSA attestations and container signatures"""
    
    # Security configuration
    VERIFICATION_CONFIG = {
        "allowed_repos": ["plamen/feelgood-api"],
        "trusted_issuers": ["https://token.actions.githubusercontent.com"],
        "slsa_generator_pattern": r"^https://github\.com/slsa-framework/slsa-github-generator/\.github/workflows/generator_container_slsa3\.yml@refs/tags/v\d+\.\d+\.\d+$",
        "max_command_timeout": 120
    }
    
    def __init__(self, image_ref: str, repository: str = "plamen/feelgood-api"):
        self.image_ref = self._validate_image_ref(image_ref)
        self.repository = self._validate_repository(repository)
        self.verified_components = []
    
    def _validate_image_ref(self, image_ref: str) -> str:
        """Validate and sanitize OCI image reference"""
        if not image_ref or not isinstance(image_ref, str):
            raise ValueError("Image reference must be a non-empty string")
        
        # Validate OCI image reference format
        # Supports: registry/namespace/name:tag or registry/namespace/name@sha256:digest
        pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?(/[a-zA-Z0-9]([a-zA-Z0-9\-\._]*[a-zA-Z0-9])?)*(@sha256:[a-f0-9]{64}|:[a-zA-Z0-9]([a-zA-Z0-9\-\._]*[a-zA-Z0-9])?)$'
        
        if not re.match(pattern, image_ref):
            raise ValueError(f"Invalid OCI image reference format: {image_ref}")
        
        # Additional length check to prevent buffer overflow attacks
        if len(image_ref) > 512:
            raise ValueError("Image reference too long")
        
        return image_ref
    
    def _validate_repository(self, repository: str) -> str:
        """Validate GitHub repository format"""
        if not repository or not isinstance(repository, str):
            raise ValueError("Repository must be a non-empty string")
        
        # Validate GitHub repo format: owner/repo
        pattern = r'^[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9]/[a-zA-Z0-9][a-zA-Z0-9\-\._]*[a-zA-Z0-9]$'
        
        if not re.match(pattern, repository):
            raise ValueError(f"Invalid GitHub repository format: {repository}")
        
        if repository not in self.VERIFICATION_CONFIG["allowed_repos"]:
            raise ValueError(f"Repository {repository} not in allowed list")
        
        return repository
    
    def _get_certificate_identity_pattern(self) -> str:
        """Get repository-specific certificate identity pattern"""
        escaped_repo = re.escape(self.repository)
        return f"^https://github\.com/{escaped_repo}/\.github/workflows/.*@refs/.*"
    
    def _safe_subprocess_run(self, cmd: list[str], timeout: int = None) -> subprocess.CompletedProcess:
        """Safely execute subprocess with proper validation and timeouts"""
        if not cmd or not isinstance(cmd, list):
            raise ValueError("Command must be a non-empty list")
        
        # Validate command arguments
        for arg in cmd:
            if not isinstance(arg, str):
                raise ValueError("All command arguments must be strings")
            if len(arg) > 1024:  # Reasonable limit
                raise ValueError("Command argument too long")
        
        timeout = timeout or self.VERIFICATION_CONFIG["max_command_timeout"]
        
        try:
            return subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False  # We handle return codes manually
            )
        except subprocess.TimeoutExpired:
            raise RuntimeError(f"Command timed out after {timeout} seconds")
        except Exception as e:
            raise RuntimeError(f"Subprocess execution failed: {e}")
    
    def verify_signature(self) -> bool:
        """Verify container signature with Cosign"""
        print(f"🔍 Verifying signature for {self.image_ref}")
        
        cert_pattern = self._get_certificate_identity_pattern()
        issuer_pattern = self.VERIFICATION_CONFIG["trusted_issuers"][0]
        
        cmd = [
            "cosign", "verify",
            "--certificate-identity-regexp", cert_pattern,
            "--certificate-oidc-issuer-regexp", f"^{re.escape(issuer_pattern)}$",
            self.image_ref
        ]
        
        try:
            result = self._safe_subprocess_run(cmd)
        except (ValueError, RuntimeError) as e:
            print(f"❌ Signature verification failed: {e}")
            return False
        
        if result.returncode != 0:
            print(f"❌ Signature verification failed: {result.stderr}")
            return False
        
        print("✅ Container signature verified")
        self.verified_components.append("signature")
        return True
    
    def verify_slsa_provenance(self) -> bool:
        """Verify SLSA provenance attestation"""
        print(f"🔍 Verifying SLSA provenance for {self.image_ref}")
        
        slsa_pattern = self.VERIFICATION_CONFIG["slsa_generator_pattern"]
        issuer_pattern = self.VERIFICATION_CONFIG["trusted_issuers"][0]
        
        cmd = [
            "cosign", "verify-attestation",
            "--type", "slsaprovenance",
            "--certificate-identity-regexp", slsa_pattern,
            "--certificate-oidc-issuer-regexp", f"^{re.escape(issuer_pattern)}$",
            self.image_ref
        ]
        
        try:
            result = self._safe_subprocess_run(cmd)
        except (ValueError, RuntimeError) as e:
            print(f"❌ SLSA provenance verification failed: {e}")
            return False
        
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
        
        # Validate source URI format
        if not source_uri or not isinstance(source_uri, str):
            print("❌ Invalid source URI")
            return False
        
        # Basic GitHub URI validation
        github_pattern = r'^github\.com/[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9]/[a-zA-Z0-9][a-zA-Z0-9\-\._]*[a-zA-Z0-9]$'
        if not re.match(github_pattern, source_uri):
            print(f"❌ Invalid GitHub source URI format: {source_uri}")
            return False
        
        cmd = [
            "slsa-verifier", "verify-image",
            self.image_ref,
            "--source-uri", source_uri
        ]
        
        try:
            result = self._safe_subprocess_run(cmd)
        except (ValueError, RuntimeError) as e:
            print(f"❌ SLSA verifier failed: {e}")
            return False
        
        if result.returncode != 0:
            print(f"❌ SLSA verifier failed: {result.stderr}")
            return False
        
        print("✅ SLSA verifier validation passed")
        self.verified_components.append("slsa-verifier")
        return True
    
    def verify_github_attestations(self) -> bool:
        """Verify GitHub native attestations"""
        print(f"🔍 Verifying GitHub attestations for {self.image_ref}")
        
        cert_pattern = self._get_certificate_identity_pattern()
        issuer_pattern = self.VERIFICATION_CONFIG["trusted_issuers"][0]
        
        cmd = [
            "cosign", "verify-attestation",
            "--type", "https://slsa.dev/provenance/v1",
            "--certificate-identity-regexp", cert_pattern,
            "--certificate-oidc-issuer-regexp", f"^{re.escape(issuer_pattern)}$",
            self.image_ref
        ]
        
        try:
            result = self._safe_subprocess_run(cmd)
        except (ValueError, RuntimeError) as e:
            print(f"⚠️ GitHub attestations verification failed: {e}")
            return False
        
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
            
            cert_pattern = self._get_certificate_identity_pattern()
            issuer_pattern = self.VERIFICATION_CONFIG["trusted_issuers"][0]
            
            cmd = [
                "cosign", "verify-attestation",
                "--type", "cyclonedx",
                "--certificate-identity-regexp", cert_pattern,
                "--certificate-oidc-issuer-regexp", f"^{re.escape(issuer_pattern)}$",
                self.image_ref
            ]
            
            try:
                result = self._safe_subprocess_run(cmd)
            except (ValueError, RuntimeError) as e:
                print(f"    ❌ {description}: Verification failed - {e}")
                continue
            
            if result.returncode == 0:
                try:
                    # Validate JSON size before parsing
                    if len(result.stdout) > 10 * 1024 * 1024:  # 10MB limit
                        print(f"    ❌ {description}: Response too large")
                        continue
                    
                    attestations = json.loads(result.stdout)
                    if not isinstance(attestations, list):
                        print(f"    ❌ {description}: Invalid attestation format")
                        continue
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
                        
                except (json.JSONDecodeError, ValueError) as e:
                    print(f"    ❌ {description}: Invalid JSON in attestation - {e}")
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
        
        cert_pattern = self._get_certificate_identity_pattern()
        issuer_pattern = self.VERIFICATION_CONFIG["trusted_issuers"][0]
        
        cmd = [
            "cosign", "verify-attestation",
            "--type", "openvex",
            "--certificate-identity-regexp", cert_pattern,
            "--certificate-oidc-issuer-regexp", f"^{re.escape(issuer_pattern)}$",
            self.image_ref
        ]
        
        try:
            result = self._safe_subprocess_run(cmd)
        except (ValueError, RuntimeError) as e:
            print(f"⚠️ VEX attestations verification failed: {e}")
            return False
        
        if result.returncode != 0:
            print(f"⚠️ VEX attestations not found or verification failed")
            return False
        
        try:
            # Validate JSON size before parsing
            if len(result.stdout) > 5 * 1024 * 1024:  # 5MB limit for VEX
                print("❌ VEX attestation response too large")
                return False
            
            attestations = json.loads(result.stdout)
            if not isinstance(attestations, list):
                print("❌ Invalid VEX attestation format")
                return False
            
            total_statements = 0
            
            for attestation in attestations:
                if not isinstance(attestation, dict):
                    continue
                predicate = attestation.get("predicate", {})
                statements = predicate.get("statements", [])
                if isinstance(statements, list):
                    total_statements += len(statements)
            
            print(f"✅ VEX attestations verified: {total_statements} statements across {len(attestations)} documents")
            self.verified_components.append("vex-attestations")
            return True
            
        except (json.JSONDecodeError, ValueError) as e:
            print(f"❌ Invalid VEX attestation JSON: {e}")
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
        
        # Safe timestamp generation
        try:
            timestamp_result = self._safe_subprocess_run(["date", "-Iseconds"], timeout=10)
            timestamp = timestamp_result.stdout.strip() if timestamp_result.returncode == 0 else "unknown"
        except (ValueError, RuntimeError):
            timestamp = "unknown"
        
        return {
            "image": self.image_ref,
            "repository": self.repository,
            "timestamp": timestamp,
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
    parser.add_argument("--repository", default="plamen/feelgood-api", help="GitHub repository (owner/repo)")
    parser.add_argument("--report", help="Output verification report to file")
    
    args = parser.parse_args()
    
    try:
        verifier = AttestationVerifier(args.image_ref, args.repository)
    except ValueError as e:
        print(f"❌ Invalid input: {e}")
        sys.exit(1)
    
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
        try:
            # Validate report file path
            report_path = Path(args.report).resolve()
            if not report_path.parent.exists():
                print(f"❌ Report directory does not exist: {report_path.parent}")
                sys.exit(1)
            
            with open(report_path, 'w') as f:
                json.dump(report, f, indent=2)
            print(f"\n📄 Verification report saved to {report_path}")
        except (OSError, ValueError) as e:
            print(f"❌ Failed to save report: {e}")
            sys.exit(1)
    
    print(f"\n🎯 Overall Status: {'PASSED' if all_passed else 'FAILED'}")
    print(f"🔧 Verified Components: {', '.join(verifier.verified_components) if verifier.verified_components else 'None'}")
    print(f"🏷️ Repository: {verifier.repository}")
    print(f"📊 SLSA Level: {report['slsa_level']}")
    
    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
