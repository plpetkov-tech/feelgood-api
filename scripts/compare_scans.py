#!/usr/bin/env python3
"""Compare Trivy scan results to identify new and resolved vulnerabilities"""
import json
import argparse
import sys
from pathlib import Path
from typing import Dict, List, Set, Any
from datetime import datetime


class ScanComparator:
    """Compare two Trivy scan results and identify changes"""
    
    def __init__(self):
        self.severity_order = {
            "CRITICAL": 5,
            "HIGH": 4,
            "MEDIUM": 3,
            "LOW": 2,
            "NEGLIGIBLE": 1,
            "UNKNOWN": 0
        }
    
    def extract_vulnerabilities(self, scan_data: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
        """Extract vulnerabilities from Trivy scan results"""
        vulnerabilities = {}
        
        for result in scan_data.get("Results", []):
            target = result.get("Target", "unknown")
            
            for vuln in result.get("Vulnerabilities", []):
                vuln_id = vuln.get("VulnerabilityID", "")
                pkg_name = vuln.get("PkgName", "")
                installed_version = vuln.get("InstalledVersion", "")
                
                # Create unique key for vulnerability
                key = f"{vuln_id}:{pkg_name}:{installed_version}:{target}"
                
                vulnerabilities[key] = {
                    "id": vuln_id,
                    "package": pkg_name,
                    "installed_version": installed_version,
                    "fixed_version": vuln.get("FixedVersion", ""),
                    "severity": vuln.get("Severity", "UNKNOWN"),
                    "title": vuln.get("Title", ""),
                    "description": vuln.get("Description", ""),
                    "target": target,
                    "cvss_score": self.get_cvss_score(vuln),
                    "primary_url": vuln.get("PrimaryURL", ""),
                    "published_date": vuln.get("PublishedDate", ""),
                    "last_modified_date": vuln.get("LastModifiedDate", "")
                }
        
        return vulnerabilities
    
    def get_cvss_score(self, vuln: Dict[str, Any]) -> float:
        """Extract CVSS score from vulnerability data"""
        cvss = vuln.get("CVSS", {})
        
        # Try different CVSS sources
        for source in ["nvd", "redhat", "ubuntu"]:
            if source in cvss:
                score = cvss[source].get("V3Score") or cvss[source].get("V2Score")
                if score:
                    return float(score)
        
        return 0.0
    
    def compare_scans(self, previous_file: Path, current_file: Path) -> Dict[str, Any]:
        """Compare two scan files and return differences"""
        
        # Load previous scan
        try:
            with open(previous_file) as f:
                previous_data = json.load(f)
            previous_vulns = self.extract_vulnerabilities(previous_data)
        except Exception as e:
            print(f"Error loading previous scan: {e}", file=sys.stderr)
            previous_vulns = {}
        
        # Load current scan
        try:
            with open(current_file) as f:
                current_data = json.load(f)
            current_vulns = self.extract_vulnerabilities(current_data)
        except Exception as e:
            print(f"Error loading current scan: {e}", file=sys.stderr)
            current_vulns = {}
        
        # Find differences
        previous_keys = set(previous_vulns.keys())
        current_keys = set(current_vulns.keys())
        
        new_vuln_keys = current_keys - previous_keys
        resolved_vuln_keys = previous_keys - current_keys
        unchanged_vuln_keys = previous_keys & current_keys
        
        # Build detailed comparison
        comparison = {
            "comparison_metadata": {
                "timestamp": datetime.now().isoformat(),
                "previous_scan_vulns": len(previous_vulns),
                "current_scan_vulns": len(current_vulns),
                "new_vulnerabilities_count": len(new_vuln_keys),
                "resolved_vulnerabilities_count": len(resolved_vuln_keys),
                "unchanged_vulnerabilities_count": len(unchanged_vuln_keys)
            },
            "new_vulnerabilities": [current_vulns[key] for key in new_vuln_keys],
            "resolved_vulnerabilities": [previous_vulns[key] for key in resolved_vuln_keys],
            "unchanged_vulnerabilities": [current_vulns[key] for key in unchanged_vuln_keys],
            "summary": self.generate_summary(new_vuln_keys, resolved_vuln_keys, current_vulns, previous_vulns)
        }
        
        # Add severity breakdown for new vulnerabilities
        if new_vuln_keys:
            comparison["new_vulnerabilities_by_severity"] = self.categorize_by_severity(
                [current_vulns[key] for key in new_vuln_keys]
            )
        
        # Add high-priority new vulnerabilities (CRITICAL/HIGH)
        high_priority_new = [
            current_vulns[key] for key in new_vuln_keys 
            if current_vulns[key]["severity"] in ["CRITICAL", "HIGH"]
        ]
        comparison["high_priority_new_vulnerabilities"] = high_priority_new
        
        return comparison
    
    def categorize_by_severity(self, vulnerabilities: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
        """Categorize vulnerabilities by severity"""
        by_severity = {}
        
        for vuln in vulnerabilities:
            severity = vuln["severity"]
            if severity not in by_severity:
                by_severity[severity] = []
            by_severity[severity].append(vuln)
        
        return by_severity
    
    def generate_summary(self, new_keys: Set[str], resolved_keys: Set[str], 
                        current_vulns: Dict[str, Any], previous_vulns: Dict[str, Any]) -> Dict[str, Any]:
        """Generate a human-readable summary of changes"""
        
        summary = {
            "has_new_vulnerabilities": len(new_keys) > 0,
            "has_resolved_vulnerabilities": len(resolved_keys) > 0,
            "net_change": len(new_keys) - len(resolved_keys)
        }
        
        if new_keys:
            new_vulns = [current_vulns[key] for key in new_keys]
            summary["new_vulnerabilities_summary"] = {
                "critical": len([v for v in new_vulns if v["severity"] == "CRITICAL"]),
                "high": len([v for v in new_vulns if v["severity"] == "HIGH"]),
                "medium": len([v for v in new_vulns if v["severity"] == "MEDIUM"]),
                "low": len([v for v in new_vulns if v["severity"] == "LOW"]),
                "negligible": len([v for v in new_vulns if v["severity"] == "NEGLIGIBLE"])
            }
            
            # Find highest severity new vulnerability
            highest_severity_vuln = max(new_vulns, key=lambda v: self.severity_order.get(v["severity"], 0))
            summary["highest_severity_new"] = {
                "id": highest_severity_vuln["id"],
                "severity": highest_severity_vuln["severity"],
                "package": highest_severity_vuln["package"],
                "cvss_score": highest_severity_vuln["cvss_score"]
            }
        
        if resolved_keys:
            resolved_vulns = [previous_vulns[key] for key in resolved_keys]
            summary["resolved_vulnerabilities_summary"] = {
                "critical": len([v for v in resolved_vulns if v["severity"] == "CRITICAL"]),
                "high": len([v for v in resolved_vulns if v["severity"] == "HIGH"]),
                "medium": len([v for v in resolved_vulns if v["severity"] == "MEDIUM"]),
                "low": len([v for v in resolved_vulns if v["severity"] == "LOW"]),
                "negligible": len([v for v in resolved_vulns if v["severity"] == "NEGLIGIBLE"])
            }
        
        # Risk assessment
        critical_new = len([v for v in [current_vulns[key] for key in new_keys] if v["severity"] == "CRITICAL"])
        high_new = len([v for v in [current_vulns[key] for key in new_keys] if v["severity"] == "HIGH"])
        
        if critical_new > 0:
            summary["risk_level"] = "CRITICAL"
            summary["recommended_action"] = "Immediate attention required - critical vulnerabilities detected"
        elif high_new > 0:
            summary["risk_level"] = "HIGH"
            summary["recommended_action"] = "High priority vulnerabilities require prompt remediation"
        elif len(new_keys) > 0:
            summary["risk_level"] = "MEDIUM"
            summary["recommended_action"] = "New vulnerabilities detected - review and plan remediation"
        else:
            summary["risk_level"] = "LOW"
            summary["recommended_action"] = "No new vulnerabilities detected"
        
        return summary


def main():
    parser = argparse.ArgumentParser(description="Compare Trivy scan results")
    parser.add_argument("--previous", type=Path, required=True, 
                       help="Previous scan results JSON file")
    parser.add_argument("--current", type=Path, required=True,
                       help="Current scan results JSON file")
    parser.add_argument("--output", type=Path, required=True,
                       help="Output comparison JSON file")
    parser.add_argument("--verbose", action="store_true",
                       help="Enable verbose output")
    
    args = parser.parse_args()
    
    if not args.previous.exists():
        print(f"Error: Previous scan file not found: {args.previous}", file=sys.stderr)
        sys.exit(1)
    
    if not args.current.exists():
        print(f"Error: Current scan file not found: {args.current}", file=sys.stderr)
        sys.exit(1)
    
    comparator = ScanComparator()
    comparison_result = comparator.compare_scans(args.previous, args.current)
    
    # Write results
    with open(args.output, 'w') as f:
        json.dump(comparison_result, f, indent=2)
    
    if args.verbose:
        metadata = comparison_result["comparison_metadata"]
        summary = comparison_result["summary"]
        
        print(f"Comparison completed:")
        print(f"  Previous scan: {metadata['previous_scan_vulns']} vulnerabilities")
        print(f"  Current scan: {metadata['current_scan_vulns']} vulnerabilities")
        print(f"  New vulnerabilities: {metadata['new_vulnerabilities_count']}")
        print(f"  Resolved vulnerabilities: {metadata['resolved_vulnerabilities_count']}")
        print(f"  Risk level: {summary['risk_level']}")
        print(f"  Recommendation: {summary['recommended_action']}")
        
        if comparison_result["new_vulnerabilities"]:
            print(f"\nHigh-priority new vulnerabilities: {len(comparison_result['high_priority_new_vulnerabilities'])}")


if __name__ == "__main__":
    main()
