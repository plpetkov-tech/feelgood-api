#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
AUTO_YES=false
CHECK_UPGRADES=false
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Pin GitHub Actions to their SHA commits in .github/**/*.yml and .github/**/*.yaml files

OPTIONS:
    -d, --dry-run       Show what would be changed without making changes
    -y, --yes           Automatically confirm changes (skip prompts)
    -u, --upgrade       Check for newer versions of pinned actions
    -t, --token TOKEN   GitHub token for API access (or set GITHUB_TOKEN env var)
    -h, --help          Show this help message

EXAMPLES:
    $0 --dry-run                    # Preview changes (safe, no modifications)
    $0 --yes                        # Apply changes automatically (no prompts)
    $0                              # Interactive mode (prompts for each change)
    $0 --upgrade --dry-run          # Check for upgrades (safe preview)
    $0 --upgrade --yes              # Auto-upgrade to latest versions
    $0 --upgrade                    # Interactive upgrade (prompts for each)

IMPORTANT:
    - Without --dry-run: Script can modify files
    - Without --yes: Script will prompt for confirmation before each change
    - With --yes: Script applies all changes automatically
    - With --dry-run: Script only shows what would change (safest option)
    
NOTES:
    - Requires curl and jq to be installed
    - GitHub token is optional but recommended to avoid rate limiting
    - Script is idempotent - can be run multiple times safely
EOF
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}" >&2
        echo "Please install them and try again." >&2
        exit 1
    fi
}

# Function to extract repository name from action (handles all sub-paths)
extract_repo_name() {
    local action="$1"
    
    # Extract just owner/repo from any path like:
    # - github/codeql-action/upload-sarif
    # - slsa-framework/slsa-verifier/actions/installer  
    # - slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml
    # - actions/upload-artifact (no sub-path)
    
    if [[ "$action" =~ ^([^/]+/[^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        # Fallback: return the action as-is if it doesn't match expected pattern
        echo "$action"
    fi
}

# Function to fetch SHA for a given action and ref
fetch_action_sha() {
    local action="$1"
    local ref="$2"
    local repo
    repo=$(extract_repo_name "$action")
    local url="https://api.github.com/repos/${repo}/commits/${ref}"
    local headers=()
    
    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers+=("-H" "Authorization: token $GITHUB_TOKEN")
    fi
    
    headers+=("-H" "Accept: application/vnd.github.v3+json")
    
    local response
    response=$(curl -s "${headers[@]}" "$url" 2>/dev/null || echo "")
    
    if [[ -z "$response" ]]; then
        echo ""
        return 1
    fi
    
    local sha
    sha=$(echo "$response" | jq -r '.sha // empty' 2>/dev/null || echo "")
    
    if [[ -z "$sha" || "$sha" == "null" ]]; then
        # Try getting the ref info (for tags/branches)
        url="https://api.github.com/repos/${repo}/git/refs/heads/${ref}"
        response=$(curl -s "${headers[@]}" "$url" 2>/dev/null || echo "")
        
        if [[ -z "$response" ]]; then
            # Try tags
            url="https://api.github.com/repos/${repo}/git/refs/tags/${ref}"
            response=$(curl -s "${headers[@]}" "$url" 2>/dev/null || echo "")
        fi
        
        if [[ -n "$response" ]]; then
            sha=$(echo "$response" | jq -r '.object.sha // empty' 2>/dev/null || echo "")
        fi
    fi
    
    echo "$sha"
}

# Function to get the latest release tag for an action
get_latest_release() {
    local action="$1"
    local repo
    repo=$(extract_repo_name "$action")
    local url="https://api.github.com/repos/${repo}/releases/latest"
    local headers=()
    
    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers+=("-H" "Authorization: token $GITHUB_TOKEN")
    fi
    
    headers+=("-H" "Accept: application/vnd.github.v3+json")
    
    local response
    response=$(curl -s "${headers[@]}" "$url" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        local tag_name
        tag_name=$(echo "$response" | jq -r '.tag_name // empty' 2>/dev/null || echo "")
        echo "$tag_name"
    fi
}

# Function to get all tags for an action (fallback if no releases)
get_latest_tag() {
    local action="$1"
    local repo
    repo=$(extract_repo_name "$action")
    local url="https://api.github.com/repos/${repo}/tags?per_page=1"
    local headers=()
    
    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers+=("-H" "Authorization: token $GITHUB_TOKEN")
    fi
    
    headers+=("-H" "Accept: application/vnd.github.v3+json")
    
    local response
    response=$(curl -s "${headers[@]}" "$url" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        local tag_name
        tag_name=$(echo "$response" | jq -r '.[0].name // empty' 2>/dev/null || echo "")
        echo "$tag_name"
    fi
}

# Function to find what tag/version a SHA corresponds to
find_tag_for_sha() {
    local action="$1"
    local sha="$2"
    local repo
    repo=$(extract_repo_name "$action")
    local url="https://api.github.com/repos/${repo}/tags?per_page=100"
    local headers=()
    
    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers+=("-H" "Authorization: token $GITHUB_TOKEN")
    fi
    
    headers+=("-H" "Accept: application/vnd.github.v3+json")
    
    local response
    response=$(curl -s "${headers[@]}" "$url" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        local tag_name
        tag_name=$(echo "$response" | jq -r --arg sha "$sha" '.[] | select(.commit.sha == $sha) | .name' 2>/dev/null | head -1 || echo "")
        echo "$tag_name"
    fi
}

# Function to compare version strings (basic semver comparison)
version_gt() {
    local ver1="$1"
    local ver2="$2"
    
    # Remove 'v' prefix if present
    ver1="${ver1#v}"
    ver2="${ver2#v}"
    
    # Use sort -V for version comparison
    if printf '%s\n%s\n' "$ver1" "$ver2" | sort -V -C; then
        [[ "$ver1" != "$ver2" ]]
    else
        return 0
    fi
}

# Function to process a single YAML file
process_file() {
    local file="$1"
    local changes_made=false
    local temp_file
    temp_file=$(mktemp)
    
    echo -e "${BLUE}Processing: $file${NC}"
    
    # Read file line by line and process uses: statements
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*uses:[[:space:]]*([^@]+)@([^[:space:]#]+) ]]; then
            local action="${BASH_REMATCH[1]}"
            local ref="${BASH_REMATCH[2]}"
            local full_action="$action@$ref"
            
            # Skip local actions (starting with ./)
            if [[ "$action" =~ ^\.\/ ]]; then
                echo "  ➤ Skipping local action: $full_action"
                echo "$line" >> "$temp_file"
                continue
            fi
            
            if [[ "$CHECK_UPGRADES" == true ]]; then
                # Upgrade checking mode
                echo -n "  🔍 Checking $full_action... "
                
                local current_version="$ref"
                local current_tag=""
                
                # If it's a SHA, try to find what tag it corresponds to
                if [[ "$ref" =~ ^[a-f0-9]{40}$ ]]; then
                    current_tag=$(find_tag_for_sha "$action" "$ref")
                    if [[ -n "$current_tag" ]]; then
                        current_version="$current_tag (SHA: ${ref:0:7}...)"
                    else
                        current_version="SHA: ${ref:0:7}..."
                    fi
                else
                    current_tag="$ref"
                fi
                
                # Get latest version
                local latest_version
                latest_version=$(get_latest_release "$action")
                if [[ -z "$latest_version" ]]; then
                    latest_version=$(get_latest_tag "$action")
                fi
                
                if [[ -n "$latest_version" ]]; then
                    # Compare versions
                    local needs_upgrade=false
                    if [[ -n "$current_tag" && "$current_tag" != "$latest_version" ]]; then
                        if version_gt "$latest_version" "$current_tag"; then
                            needs_upgrade=true
                        fi
                    elif [[ "$ref" =~ ^[a-f0-9]{40}$ && -z "$current_tag" ]]; then
                        # SHA without known tag - suggest checking manually
                        needs_upgrade="unknown"
                    fi
                    
                    if [[ "$needs_upgrade" == true ]]; then
                        echo -e "${YELLOW}⬆️  UPDATE AVAILABLE${NC}"
                        echo "    Current: $current_version"
                        echo "    Latest:  $latest_version"
                        
                        if [[ "$DRY_RUN" == false ]]; then
                            echo -n "    Update to $latest_version? [y/N]: "
                            if [[ "$AUTO_YES" == true ]]; then
                                echo "y (auto-yes)"
                                local response="y"
                            else
                                read -r response
                            fi
                            
                            if [[ "$response" =~ ^[Yy]$ ]]; then
                                local new_sha
                                new_sha=$(fetch_action_sha "$action" "$latest_version")
                                if [[ -n "$new_sha" ]]; then
                                    local new_line
                                    new_line=$(echo "$line" | sed "s|$action@$ref|$action@$new_sha|")
                                    echo "    ✓ Updated to $latest_version@$new_sha"
                                    echo "$new_line" >> "$temp_file"
                                    changes_made=true
                                else
                                    echo "    ✗ Failed to get SHA for $latest_version"
                                    echo "$line" >> "$temp_file"
                                fi
                            else
                                echo "$line" >> "$temp_file"
                            fi
                        else
                            echo "    ${YELLOW}WOULD UPDATE TO:${NC} $latest_version"
                            echo "$line" >> "$temp_file"
                        fi
                    elif [[ "$needs_upgrade" == "unknown" ]]; then
                        echo -e "${YELLOW}❓ UNKNOWN${NC}"
                        echo "    Current: $current_version"
                        echo "    Latest:  $latest_version"
                        echo "    (Manual check recommended - SHA without known tag)"
                        echo "$line" >> "$temp_file"
                    else
                        echo -e "${GREEN}✓ UP TO DATE${NC}"
                        echo "    Current: $current_version"
                        echo "$line" >> "$temp_file"
                    fi
                else
                    echo -e "${RED}✗ Cannot determine latest version${NC}"
                    echo "$line" >> "$temp_file"
                fi
            else
                # Normal pinning mode
                # Skip if already pinned to SHA (40 character hex string)
                if [[ "$ref" =~ ^[a-f0-9]{40}$ ]]; then
                    echo "  ✓ Already pinned: $full_action"
                    echo "$line" >> "$temp_file"
                    continue
                fi
                
                echo -n "  🔍 Resolving $full_action... "
                
                local sha
                sha=$(fetch_action_sha "$action" "$ref")
                
                if [[ -n "$sha" ]]; then
                    local new_line
                    new_line=$(echo "$line" | sed "s|$action@$ref|$action@$sha|")
                    
                    echo -e "${GREEN}✓${NC}"
                    echo "    $ref → $sha"
                    
                    if [[ "$DRY_RUN" == true ]]; then
                        echo -e "    ${YELLOW}WOULD CHANGE:${NC} $line"
                        echo -e "    ${YELLOW}TO:${NC}          $new_line"
                        echo "$line" >> "$temp_file"  # Keep original in dry-run
                    else
                        echo "$new_line" >> "$temp_file"
                        changes_made=true
                    fi
                else
                    echo -e "${RED}✗ Failed to resolve${NC}"
                    echo "$line" >> "$temp_file"
                fi
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$file"
    
    # Replace original file if changes were made (and not dry-run)
    if [[ "$DRY_RUN" == false && "$changes_made" == true ]]; then
        mv "$temp_file" "$file"
        echo -e "  ${GREEN}✓ Updated $file${NC}"
    else
        rm "$temp_file"
        if [[ "$changes_made" == false && "$DRY_RUN" == false ]]; then
            echo "  ➤ No changes needed"
        fi
    fi
    
    echo ""
}

# Function to find all YAML files in .github directories
find_github_yaml_files() {
    find . -path "*/.github/**" \( -name "*.yml" -o -name "*.yaml" \) -type f 2>/dev/null | sort
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -u|--upgrade)
            CHECK_UPGRADES=true
            shift
            ;;
        -t|--token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo -e "${BLUE}GitHub Actions SHA Pinning Script${NC}"
    echo "=================================="
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Find all YAML files
    echo "🔍 Finding GitHub workflow files..."
    local files
    mapfile -t files < <(find_github_yaml_files)
    
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No GitHub workflow files found in .github directories.${NC}"
        exit 0
    fi
    
    echo "Found ${#files[@]} file(s):"
    printf '  %s\n' "${files[@]}"
    echo ""
    
    # Check for GitHub token
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo -e "${YELLOW}Warning: No GitHub token provided. API rate limiting may apply.${NC}"
        echo "Set GITHUB_TOKEN environment variable or use --token flag for better performance."
        echo ""
    fi
    
    # Confirm execution (unless auto-yes or dry-run)
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$CHECK_UPGRADES" == true ]]; then
            echo -e "${YELLOW}🔍 DRY RUN MODE - Checking for upgrades without making changes${NC}"
        else
            echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
        fi
    elif [[ "$CHECK_UPGRADES" == true ]]; then
        if [[ "$AUTO_YES" == false ]]; then
            echo -n "Proceed with checking and upgrading GitHub Actions? [y/N]: "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo "Aborted."
                exit 0
            fi
        fi
    elif [[ "$AUTO_YES" == false ]]; then
        echo -n "Proceed with pinning GitHub Actions? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
    
    echo ""
    
    # Process each file
    for file in "${files[@]}"; do
        process_file "$file"
    done
    
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$CHECK_UPGRADES" == true ]]; then
            echo -e "${YELLOW}🔍 Upgrade check completed. Use without --dry-run to apply updates.${NC}"
        else
            echo -e "${YELLOW}🔍 Dry run completed. Use --yes flag to apply changes.${NC}"
        fi
    else
        if [[ "$CHECK_UPGRADES" == true ]]; then
            echo -e "${GREEN}✅ GitHub Actions upgrade check completed!${NC}"
        else
            echo -e "${GREEN}✅ GitHub Actions pinning completed!${NC}"
        fi
    fi
}

# Run main function
main "$@"
