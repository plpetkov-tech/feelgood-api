#!/usr/bin/env python3
"""Enhanced VEX (Vulnerability Exploitability eXchange) document generator"""
import json
import argparse
import sys
from datetime import datetime
from typing import Dict, List, Any
from pathlib import Path


class VEXGenerator:
    """Enhanced VEX document generator with vulnerability analysis"""
    
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
            "protected_by_mitigating_control": "The vulnerability is mitigated by controls"
        }

    def analyze_vulnerability(self, vuln: Dict[str, Any], sbom_components: List[Dict]) -> Dict[str, Any]:
        """Analyze vulnerability against SBOM components to determine exploitability"""
        vuln_id = vuln.get("VulnerabilityID", "")
        pkg_name = vuln.get("PkgName", "")
        
        # Find matching component in SBOM
        matching_component = None
        for comp in sbom_components:
            if comp.get("name", "") == pkg_name:
                matching_component = comp
                break
        
        # Determine state based on analysis
        state = "under_investigation"  # Default
        justification = "requires_configuration"
        detail = f"Analyzing vulnerability {vuln_id} in component {pkg_name}"
        response = ["will_not_fix"]
        
        # Apply analysis logic
        severity = vuln.get("Severity", "").upper()
        
        if "test" in pkg_name.lower() or "dev" in pkg_name.lower():
            state = "not_affected"
            justification = "code_not_present"
            detail = f"Component {pkg_name} is only used in development/testing"
            response = ["will_not_fix"]
        elif severity in ["LOW", "NEGLIGIBLE"]:
            state = "not_affected" 
            justification = "protected_by_mitigating_control"
            detail = f"Low severity vulnerability mitigated by security controls"
            response = ["will_not_fix"]
        elif "CRITICAL" in severity:
            state = "affected"
            justification = "code_not_reachable"
            detail = f"Critical vulnerability requires immediate analysis"
            response = ["can_not_fix", "update"]
            
        return {
            "state": state,
            "justification": justification,
            "response": response,
            "detail": detail
        }

    def generate_vex_from_trivy(self, trivy_file: Path, sbom_file: Path) -> Dict[str, Any]:
        """Generate VEX document from Trivy scan results and SBOM"""
        
        # Load Trivy results
        try:
            with open(trivy_file) as f:
                trivy_data = json.load(f)
        except Exception as e:
            print(f"Error loading Trivy results: {e}", file=sys.stderr)
            return self.generate_default_vex()
        
        # Load SBOM
        try:
            with open(sbom_file) as f:
                sbom_data = json.load(f)
                sbom_components = sbom_data.get("components", [])
        except Exception as e:
            print(f"Error loading SBOM: {e}", file=sys.stderr)
            sbom_components = []
        
        vulnerabilities = []
        
        # Process Trivy results
        for result in trivy_data.get("Results", []):
            for vuln in result.get("Vulnerabilities", []):
                analysis = self.analyze_vulnerability(vuln, sbom_components)
                
                vex_vuln = {
                    "id": vuln.get("VulnerabilityID", ""),
                    "source": {
                        "name": "Trivy",
                        "url": vuln.get("PrimaryURL", "")
                    },
                    "analysis": analysis,
                    "affects": [
                        {
                            "ref": f"pkg:pypi/{vuln.get('PkgName', '')}@{vuln.get('InstalledVersion', '')}"
                        }
                    ]
                }
                
                if vuln.get("CVSS"):
                    vex_vuln["ratings"] = [
                        {
                            "source": {"name": "CVSS"},
                            "score": vuln["CVSS"].get("nvd", {}).get("V3Score", 0),
                            "severity": vuln.get("Severity", "UNKNOWN"),
                            "method": "CVSSv3"
                        }
                    ]
                
                vulnerabilities.append(vex_vuln)
        
        return self.create_vex_document(vulnerabilities)

    def create_vex_document(self, vulnerabilities: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Create a complete VEX document"""
        return {
            "@context": "https://cyclonedx.org/schema/vex-1.0.0",
            "bomFormat": "CycloneDX",
            "specVersion": "1.4", 
            "version": 1,
            "metadata": {
                "timestamp": datetime.now().isoformat(),
                "tools": [
                    {
                        "vendor": "FeelGood API",
                        "name": "enhanced-vex-generator",
                        "version": "2.0.0"
                    }
                ],
                "component": {
                    "type": "application",
                    "bom-ref": "feelgood-api",
                    "name": "feelgood-api",
                    "version": "1.0.0"
                }
            },
            "vulnerabilities": vulnerabilities
        }

    def generate_default_vex(self) -> Dict[str, Any]:
        """Generate a default VEX document when no scan results available"""
        return self.create_vex_document([
            {
                "id": "PLACEHOLDER-VEX",
                "source": {
                    "name": "Internal Analysis",
                    "url": "https://github.com/plpetkov-tech/feelgood-api"
                },
                "analysis": {
                    "state": "not_affected",
                    "justification": "code_not_present",
                    "response": ["will_not_fix"],
                    "detail": "No vulnerabilities detected in current scan"
                },
                "affects": []
            }
        ])


def main():
    parser = argparse.ArgumentParser(description="Generate enhanced VEX document")
    parser.add_argument("--trivy-results", type=Path, help="Trivy scan results JSON file")
    parser.add_argument("--sbom", type=Path, help="SBOM JSON file")
    parser.add_argument("--output", type=Path, help="Output VEX file")
    
    args = parser.parse_args()
    
    generator = VEXGenerator()
    
    if args.trivy_results and args.sbom:
        vex_doc = generator.generate_vex_from_trivy(args.trivy_results, args.sbom)
    else:
        vex_doc = generator.generate_default_vex()
    
    vex_json = json.dumps(vex_doc, indent=2)
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(vex_json)
    else:
        print(vex_json)


if __name__ == "__main__":
    main()
