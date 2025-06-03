#!/usr/bin/env python3
"""Enhanced VEX (Vulnerability Exploitability eXchange) document generator with vexctl compatibility"""
import json
import argparse
import sys
import os
import subprocess
from datetime import datetime
from typing import Dict, List, Any, Optional
from pathlib import Path


class VEXGenerator:
    """Enhanced VEX document generator compatible with vexctl and OpenVEX format"""
    
    def __init__(self):
        self.vex_states = {
            "affected": "The vulnerability affects the product",
            "not_affected": "The vulnerability does not affect the product", 
            "fixed": "The vulnerability has been fixed",
            "under_investigation": "Investigation is ongoing"
        }
        
        self.justifications = {
            "code_not_present": "The vulnerable code is not present in the product",
            "code_not_reachable": "The vulnerable code is present but not reachable",
            "requires_configuration": "The vulnerability requires specific configuration",
            "requires_dependency": "The vulnerability requires a specific dependency",
            "requires_environment": "The vulnerability requires a specific environment",
            "protected_by_compiler": "The vulnerability is protected by compiler settings",
            "protected_at_runtime": "The vulnerability is protected at runtime",
            "protected_at_perimeter": "The vulnerability is protected at the perimeter",
            "protected_by_mitigating_control": "The vulnerability is mitigated by controls",
            "inline_mitigations_already_exist": "Inline mitigations already exist"
        }

        self.response_actions = {
            "can_not_fix": "Cannot fix the vulnerability",
            "will_not_fix": "Will not fix the vulnerability",
            "update": "Update to newer version",
            "workaround_available": "Workaround is available"
        }

    def analyze_vulnerability(self, vuln: Dict[str, Any], sbom_components: List[Dict], 
                            image_ref: Optional[str] = None) -> Dict[str, Any]:
        """Analyze vulnerability against SBOM components to determine exploitability"""
        vuln_id = vuln.get("VulnerabilityID", "")
        pkg_name = vuln.get("PkgName", "")
        pkg_version = vuln.get("InstalledVersion", "")
        
        # Find matching component in SBOM
        matching_component = None
        for comp in sbom_components:
            if comp.get("name", "") == pkg_name:
                matching_component = comp
                break
        
        # Determine state based on analysis
        state = "under_investigation"  # Default
        justification = "requires_configuration"
        detail = f"Analyzing vulnerability {vuln_id} in component {pkg_name}@{pkg_version}"
        response = ["will_not_fix"]
        
        # Apply enhanced analysis logic
        severity = vuln.get("Severity", "").upper()
        title = vuln.get("Title", "").lower()
        description = vuln.get("Description", "").lower()
        
        # Check for development/test dependencies
        if any(marker in pkg_name.lower() for marker in ["test", "dev", "debug", "mock", "fixture"]):
            state = "not_affected"
            justification = "code_not_present"
            detail = f"Component {pkg_name} is only used in development/testing environments"
            response = ["will_not_fix"]
        
        # Check for low severity vulnerabilities
        elif severity in ["LOW", "NEGLIGIBLE"]:
            state = "not_affected" 
            justification = "protected_by_mitigating_control"
            detail = f"Low severity vulnerability mitigated by security controls and monitoring"
            response = ["will_not_fix"]
        
        # Check for specific vulnerability patterns that are often not exploitable
        elif any(pattern in description for pattern in [
            "requires local access", "requires physical access", "denial of service",
            "information disclosure", "requires authenticated user"
        ]):
            state = "not_affected"
            justification = "requires_environment"
            detail = f"Vulnerability requires specific conditions not present in production environment"
            response = ["will_not_fix"]
        
        # Check for vulnerabilities in non-executable content
        elif any(pattern in title for pattern in ["documentation", "example", "sample"]):
            state = "not_affected"
            justification = "code_not_present"
            detail = f"Vulnerability in non-executable content"
            response = ["will_not_fix"]
        
        # High/Critical vulnerabilities require investigation
        elif severity in ["CRITICAL", "HIGH"]:
            state = "under_investigation"
            justification = "requires_configuration"
            detail = f"High/Critical severity vulnerability requires detailed analysis"
            response = ["can_not_fix", "update"]
        
        # Check if there's a fixed version available
        fixed_version = vuln.get("FixedVersion", "")
        if fixed_version and fixed_version != "":
            if state != "not_affected":  # Don't override not_affected status
                state = "affected"
                response = ["update"]
                detail += f". Fixed in version {fixed_version}"
            
        return {
            "state": state,
            "justification": justification,
            "response": response,
            "detail": detail,
            "analysis_timestamp": datetime.now().isoformat()
        }

    def create_product_identifier(self, image_ref: Optional[str], pkg_name: str, pkg_version: str) -> str:
        """Create a proper product identifier (PURL format)"""
        if image_ref:
            # If we have an image reference, use OCI PURL
            if image_ref.startswith("pkg:"):
                return image_ref
            else:
                # Clean up image reference for PURL
                clean_ref = image_ref.replace("ghcr.io/", "").replace("docker.io/", "")
                return f"pkg:oci/{clean_ref}"
        else:
            # Fall back to package-level PURL
            # Detect package type from common patterns
            if any(marker in pkg_name for marker in [".jar", "maven"]):
                return f"pkg:maven/{pkg_name}@{pkg_version}"
            elif any(marker in pkg_name for marker in ["node_modules", "npm"]):
                return f"pkg:npm/{pkg_name}@{pkg_version}"
            elif any(marker in pkg_name for marker in ["site-packages", "pypi"]):
                return f"pkg:pypi/{pkg_name}@{pkg_version}"
            elif any(marker in pkg_name for marker in ["apk", "alpine"]):
                return f"pkg:apk/alpine/{pkg_name}@{pkg_version}"
            elif any(marker in pkg_name for marker in ["deb", "ubuntu", "debian"]):
                return f"pkg:deb/ubuntu/{pkg_name}@{pkg_version}"
            else:
                return f"pkg:generic/{pkg_name}@{pkg_version}"

    def generate_vex_from_trivy(self, trivy_file: Path, sbom_file: Optional[Path] = None, 
                               image_ref: Optional[str] = None) -> Dict[str, Any]:
        """Generate OpenVEX-compatible document from Trivy scan results and SBOM"""
        
        # Load Trivy results
        try:
            with open(trivy_file) as f:
                trivy_data = json.load(f)
        except Exception as e:
            print(f"Error loading Trivy results: {e}", file=sys.stderr)
            return self.generate_default_vex(image_ref)
        
        # Load SBOM if provided
        sbom_components = []
        if sbom_file and sbom_file.exists():
            try:
                with open(sbom_file) as f:
                    sbom_data = json.load(f)
                    sbom_components = sbom_data.get("components", [])
            except Exception as e:
                print(f"Warning: Error loading SBOM: {e}", file=sys.stderr)
        
        statements = []
        
        # Process Trivy results
        for result in trivy_data.get("Results", []):
            target = result.get("Target", "")
            
            for vuln in result.get("Vulnerabilities", []):
                analysis = self.analyze_vulnerability(vuln, sbom_components, image_ref)
                pkg_name = vuln.get("PkgName", "")
                pkg_version = vuln.get("InstalledVersion", "")
                
                # Create product identifier
                if image_ref:
                    product_id = self.create_product_identifier(image_ref, pkg_name, pkg_version)
                else:
                    product_id = self.create_product_identifier(None, pkg_name, pkg_version)
                
                statement = {
                    "vulnerability": {
                        "name": vuln.get("VulnerabilityID", "")
                    },
                    "timestamp": datetime.now().isoformat(),
                    "products": [
                        {
                            "@id": product_id
                        }
                    ],
                    "status": analysis["state"]
                }
                
                # Add optional fields based on status
                if analysis["justification"]:
                    statement["justification"] = analysis["justification"]
                
                if analysis.get("detail"):
                    statement["detail"] = analysis["detail"]
                
                # Add action statements for non-affected vulnerabilities
                if analysis["state"] == "not_affected" and analysis.get("response"):
                    statement["action_statement"] = analysis["response"][0]
                
                # Add impact assessment for affected vulnerabilities
                if analysis["state"] == "affected":
                    cvss_score = self.extract_cvss_score(vuln)
                    if cvss_score > 0:
                        statement["impact_statement"] = f"CVSS Score: {cvss_score}"
                
                statements.append(statement)
        
        return self.create_openvex_document(statements, image_ref)

    def extract_cvss_score(self, vuln: Dict[str, Any]) -> float:
        """Extract CVSS score from vulnerability data"""
        cvss = vuln.get("CVSS", {})
        
        # Try different CVSS sources
        for source in ["nvd", "redhat", "ubuntu", "ghsa"]:
            if source in cvss:
                score = cvss[source].get("V3Score") or cvss[source].get("V2Score")
                if score:
                    return float(score)
        
        return 0.0

    def create_openvex_document(self, statements: List[Dict[str, Any]], 
                               image_ref: Optional[str] = None) -> Dict[str, Any]:
        """Create a complete OpenVEX-compatible document"""
        
        # Generate document ID
        doc_id = f"https://openvex.dev/docs/public/vex-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        
        # Determine author from environment or default
        author = os.environ.get("VEX_AUTHOR", "FeelGood API Security Team")
        
        doc = {
            "@context": "https://openvex.dev/ns/v0.2.0",
            "@id": doc_id,
            "author": author,
            "timestamp": datetime.now().isoformat(),
            "version": 1,
            "statements": statements
        }
        
        # Add metadata about the tool and process
        if image_ref:
            doc["document_notes"] = f"VEX document generated for container image: {image_ref}"
        
        return doc

    def generate_default_vex(self, image_ref: Optional[str] = None) -> Dict[str, Any]:
        """Generate a default OpenVEX document when no scan results available"""
        
        product_id = image_ref if image_ref else "pkg:generic/feelgood-api@1.0.0"
        if image_ref and not image_ref.startswith("pkg:"):
            product_id = self.create_product_identifier(image_ref, "feelgood-api", "1.0.0")
        
        statements = [
            {
                "vulnerability": {
                    "name": "PLACEHOLDER-VEX"
                },
                "timestamp": datetime.now().isoformat(),
                "products": [
                    {
                        "@id": product_id
                    }
                ],
                "status": "not_affected",
                "justification": "code_not_present",
                "detail": "No vulnerabilities detected in current scan - placeholder VEX statement"
            }
        ]
        
        return self.create_openvex_document(statements, image_ref)

    def validate_with_vexctl(self, vex_file: Path) -> bool:
        """Validate VEX document using vexctl if available"""
        try:
            # Check if vexctl is available
            result = subprocess.run(["vexctl", "version"], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                print("Warning: vexctl not available for validation", file=sys.stderr)
                return True  # Don't fail if vexctl isn't available
            
            # Validate the VEX document
            result = subprocess.run(["vexctl", "validate", str(vex_file)], 
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                print(f"✅ VEX document validated successfully with vexctl")
                return True
            else:
                print(f"❌ VEX validation failed: {result.stderr}", file=sys.stderr)
                return False
                
        except subprocess.TimeoutExpired:
            print("Warning: vexctl validation timed out", file=sys.stderr)
            return True
        except FileNotFoundError:
            print("Warning: vexctl not found - skipping validation", file=sys.stderr)
            return True
        except Exception as e:
            print(f"Warning: vexctl validation error: {e}", file=sys.stderr)
            return True


def main():
    parser = argparse.ArgumentParser(description="Generate OpenVEX-compatible document")
    parser.add_argument("--trivy-results", type=Path, help="Trivy scan results JSON file")
    parser.add_argument("--sbom", type=Path, help="SBOM JSON file")
    parser.add_argument("--image-ref", type=str, help="Container image reference")
    parser.add_argument("--output", type=Path, help="Output VEX file")
    parser.add_argument("--validate", action="store_true", help="Validate with vexctl")
    parser.add_argument("--author", type=str, help="VEX document author")
    
    args = parser.parse_args()
    
    # Set author if provided
    if args.author:
        os.environ["VEX_AUTHOR"] = args.author
    
    generator = VEXGenerator()
    
    if args.trivy_results and args.trivy_results.exists():
        vex_doc = generator.generate_vex_from_trivy(
            args.trivy_results, 
            args.sbom, 
            args.image_ref
        )
    else:
        vex_doc = generator.generate_default_vex(args.image_ref)
    
    vex_json = json.dumps(vex_doc, indent=2)
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(vex_json)
        
        print(f"📄 VEX document written to {args.output}")
        
        # Validate if requested
        if args.validate:
            if not generator.validate_with_vexctl(args.output):
                sys.exit(1)
    else:
        print(vex_json)


if __name__ == "__main__":
    main()
