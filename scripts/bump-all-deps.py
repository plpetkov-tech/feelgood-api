#!/usr/bin/env python3
"""
Dependency Update Script - Bumps all dependencies to their latest versions

This script updates all dependencies in pyproject.toml to their latest versions
and regenerates the lock files. It supports both production and development dependencies.

Usage:
    python scripts/bump-all-deps.py [--dry-run] [--dev-only] [--prod-only] [--exclude PACKAGE]

Options:
    --dry-run       Show what would be updated without making changes
    --dev-only      Only update development dependencies
    --prod-only     Only update production dependencies  
    --exclude       Exclude specific packages (can be used multiple times)
    --help          Show this help message
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple

import requests
import toml


class DependencyUpdater:
    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.pyproject_path = project_root / "pyproject.toml"
        self.excluded_packages: Set[str] = set()
        
    def get_latest_version(self, package_name: str) -> str:
        """Get the latest version of a package from PyPI."""
        try:
            response = requests.get(f"https://pypi.org/pypi/{package_name}/json", timeout=10)
            response.raise_for_status()
            data = response.json()
            return data["info"]["version"]
        except Exception as e:
            print(f"⚠️  Failed to get latest version for {package_name}: {e}")
            return None

    def parse_version_constraint(self, constraint: str) -> Tuple[str, str]:
        """Parse version constraint and extract the operator and version."""
        # Handle complex constraints like {extras = ["standard"], version = "^0.34.3"}
        if isinstance(constraint, dict):
            return "^", constraint.get("version", "").lstrip("^~>=<!")
        
        # Handle simple string constraints like "^2.5.0"
        constraint = constraint.strip()
        if constraint.startswith("^"):
            return "^", constraint[1:]
        elif constraint.startswith("~"):
            return "~", constraint[1:]
        elif constraint.startswith(">="):
            return ">=", constraint[2:]
        elif constraint.startswith("=="):
            return "==", constraint[2:]
        elif constraint.startswith(">"):
            return ">", constraint[1:]
        elif constraint.startswith("<="):
            return "<=", constraint[2:]
        elif constraint.startswith("<"):
            return "<", constraint[1:]
        else:
            return "^", constraint  # Default to caret

    def format_constraint(self, operator: str, version: str, original_constraint) -> str:
        """Format the constraint back to the original format."""
        if isinstance(original_constraint, dict):
            # Preserve the dict structure
            new_constraint = original_constraint.copy()
            new_constraint["version"] = f"{operator}{version}"
            return new_constraint
        else:
            return f"{operator}{version}"

    def update_dependencies(self, section: str, dry_run: bool = False) -> Dict[str, Tuple[str, str]]:
        """Update dependencies in a specific section."""
        updates = {}
        
        with open(self.pyproject_path, 'r') as f:
            pyproject_data = toml.load(f)
        
        # Handle nested sections like "group.dev.dependencies"
        if "." in section:
            parts = section.split(".")
            dependencies = pyproject_data.get("tool", {}).get("poetry", {})
            for part in parts:
                dependencies = dependencies.get(part, {})
        else:
            dependencies = pyproject_data.get("tool", {}).get("poetry", {}).get(section, {})
        
        if not dependencies:
            print(f"📦 No dependencies found in [{section}] section")
            return updates
        
        print(f"\n🔍 Checking {section} dependencies...")
        
        for package_name, constraint in dependencies.items():
            if package_name == "python" or package_name in self.excluded_packages:
                print(f"⏭️  Skipping {package_name} (excluded)")
                continue
                
            print(f"🔎 Checking {package_name}...")
            
            # Parse current constraint
            operator, current_version = self.parse_version_constraint(constraint)
            
            # Get latest version
            latest_version = self.get_latest_version(package_name)
            
            if not latest_version:
                continue
                
            if current_version != latest_version:
                updates[package_name] = (current_version, latest_version)
                print(f"📈 {package_name}: {current_version} → {latest_version}")
                
                if not dry_run:
                    # Update the dependency
                    dependencies[package_name] = self.format_constraint(
                        operator, latest_version, constraint
                    )
            else:
                print(f"✅ {package_name}: already at latest version ({current_version})")
        
        if not dry_run and updates:
            # Write back the updated pyproject.toml
            with open(self.pyproject_path, 'w') as f:
                toml.dump(pyproject_data, f)
        
        return updates

    def run_poetry_lock(self) -> bool:
        """Run poetry lock to update the lock file."""
        print("\n🔒 Updating poetry.lock...")
        try:
            result = subprocess.run(
                ["poetry", "lock"], 
                cwd=self.project_root, 
                capture_output=True, 
                text=True,
                timeout=300
            )
            if result.returncode != 0:
                print(f"❌ Poetry lock failed: {result.stderr}")
                return False
            print("✅ poetry.lock updated successfully")
            return True
        except subprocess.TimeoutExpired:
            print("❌ Poetry lock timed out")
            return False
        except Exception as e:
            print(f"❌ Poetry lock failed: {e}")
            return False

    def regenerate_requirements(self) -> bool:
        """Regenerate requirements files using make lock."""
        print("\n📝 Regenerating requirements files...")
        try:
            result = subprocess.run(
                ["make", "lock"], 
                cwd=self.project_root, 
                capture_output=True, 
                text=True,
                timeout=300
            )
            if result.returncode != 0:
                print(f"❌ Requirements generation failed: {result.stderr}")
                return False
            print("✅ Requirements files regenerated successfully")
            return True
        except subprocess.TimeoutExpired:
            print("❌ Requirements generation timed out")
            return False
        except Exception as e:
            print(f"❌ Requirements generation failed: {e}")
            return False

    def run_tests(self) -> bool:
        """Run tests to ensure updates don't break anything."""
        print("\n🧪 Running tests...")
        try:
            result = subprocess.run(
                ["make", "test"], 
                cwd=self.project_root, 
                capture_output=True, 
                text=True,
                timeout=600
            )
            if result.returncode != 0:
                print(f"❌ Tests failed: {result.stderr}")
                return False
            print("✅ All tests passed")
            return True
        except subprocess.TimeoutExpired:
            print("❌ Tests timed out")
            return False
        except Exception as e:
            print(f"❌ Tests failed: {e}")
            return False

    def update_all(self, dry_run: bool = False, dev_only: bool = False, 
                   prod_only: bool = False, run_tests: bool = True) -> bool:
        """Update all dependencies."""
        print("🚀 Starting dependency update process...")
        
        all_updates = {}
        
        if not prod_only:
            dev_updates = self.update_dependencies("group.dev.dependencies", dry_run)
            all_updates.update({f"{k} (dev)": v for k, v in dev_updates.items()})
        
        if not dev_only:
            prod_updates = self.update_dependencies("dependencies", dry_run)
            all_updates.update({f"{k} (prod)": v for k, v in prod_updates.items()})
        
        if not all_updates:
            print("\n✨ All dependencies are already up to date!")
            return True
        
        print(f"\n📊 Summary: {len(all_updates)} packages to update")
        for package, (old, new) in all_updates.items():
            print(f"  • {package}: {old} → {new}")
        
        if dry_run:
            print("\n🔍 Dry run completed. Use --no-dry-run to apply changes.")
            return True
        
        # Update lock files
        if not self.run_poetry_lock():
            return False
        
        # Regenerate requirements files
        if not self.regenerate_requirements():
            return False
        
        # Run tests if requested
        if run_tests and not self.run_tests():
            print("\n⚠️  Tests failed after update. Consider reverting changes.")
            return False
        
        print("\n🎉 All dependencies updated successfully!")
        print("\nNext steps:")
        print("  1. Review the changes: git diff")
        print("  2. Run additional tests if needed")
        print("  3. Commit the changes: git add . && git commit -m 'deps: bump all dependencies to latest'")
        
        return True


def main():
    parser = argparse.ArgumentParser(
        description="Update all dependencies to their latest versions",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        "--dry-run", 
        action="store_true", 
        help="Show what would be updated without making changes"
    )
    parser.add_argument(
        "--dev-only", 
        action="store_true", 
        help="Only update development dependencies"
    )
    parser.add_argument(
        "--prod-only", 
        action="store_true", 
        help="Only update production dependencies"
    )
    parser.add_argument(
        "--exclude", 
        action="append", 
        default=[], 
        help="Exclude specific packages (can be used multiple times)"
    )
    parser.add_argument(
        "--no-tests", 
        action="store_true", 
        help="Skip running tests after updates"
    )
    
    args = parser.parse_args()
    
    if args.dev_only and args.prod_only:
        print("❌ Cannot specify both --dev-only and --prod-only")
        sys.exit(1)
    
    project_root = Path(__file__).parent.parent
    updater = DependencyUpdater(project_root)
    updater.excluded_packages.update(args.exclude)
    
    try:
        success = updater.update_all(
            dry_run=args.dry_run,
            dev_only=args.dev_only,
            prod_only=args.prod_only,
            run_tests=not args.no_tests
        )
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n⏸️  Update cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n💥 Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
