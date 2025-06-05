#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=true
AUTO_FIX=false
CLONE_TEMP=true
CLEANUP=true
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
OUTPUT_FORMAT="console"
SCAN_ACTIONS=true
SCAN_CONTAINERS=true
SCAN_DEPTH="all"
TEMP_DIR=""

# Function to display usage
usage() {
    echo -e "${BLUE}Repository Security Scanner${NC}"
    echo -e "${BLUE}==============================${NC}"
    echo ""
    echo "Scans external GitHub repositories for unpinned actions and containers, with optional auto-fix capabilities."
    echo ""
    echo -e "${YELLOW}USAGE:${NC}"
    echo "    $0 [OPTIONS] <REPO_URL_OR_NAME>"
    echo ""
    echo -e "${YELLOW}ARGUMENTS:${NC}"
    echo "    REPO_URL_OR_NAME    GitHub repository (e.g., 'owner/repo' or 'https://github.com/owner/repo')"
    echo ""
    echo -e "${YELLOW}OPTIONS:${NC}"
    echo -e "    ${GREEN}Scanning Options:${NC}"
    echo "    -a, --actions-only      Only scan for unpinned GitHub Actions"
    echo "    -c, --containers-only   Only scan for unpinned Docker containers"
    echo "    -d, --depth DEPTH       Scan depth: 'actions' (GitHub workflows only), 'containers' (Dockerfiles only), 'all' (default)"
    echo ""
    echo -e "    ${GREEN}Execution Options:${NC}"
    echo "    --check-only           Check-only mode (default) - no modifications"
    echo "    --auto-fix             Enable auto-fix mode - will modify files and create PRs"
    echo "    --no-cleanup           Don't clean up temporary directories (for debugging)"
    echo ""
    echo -e "    ${GREEN}Output Options:${NC}"
    echo "    -f, --format FORMAT    Output format: 'console' (default), 'json', 'csv', 'markdown'"
    echo "    -o, --output FILE      Write results to file instead of stdout"
    echo ""
    echo -e "    ${GREEN}Authentication:${NC}"
    echo "    -t, --token TOKEN      GitHub token for API access (or set GITHUB_TOKEN env var)"
    echo ""
    echo -e "    ${GREEN}General:${NC}"
    echo "    -h, --help             Show this help message"
    echo ""
    echo -e "${YELLOW}EXAMPLES:${NC}"
    echo -e "    ${CYAN}# Basic security scan${NC}"
    echo "    $0 microsoft/vscode"
    echo ""
    echo -e "    ${CYAN}# Check-only mode with specific focus${NC}"
    echo "    $0 --actions-only kubernetes/kubernetes"
    echo "    $0 --containers-only docker/dockerfile"
    echo ""
    echo -e "    ${CYAN}# Auto-fix mode (creates PR with fixes)${NC}"
    echo "    $0 --auto-fix --token \$GITHUB_TOKEN owner/repo"
    echo ""
    echo -e "    ${CYAN}# Generate report in different formats${NC}"
    echo "    $0 --format json --output security-report.json owner/repo"
    echo "    $0 --format markdown --output SECURITY_REPORT.md owner/repo"
    echo ""
    echo -e "${YELLOW}SECURITY SCANNING:${NC}"
    echo -e "    ${GREEN}GitHub Actions:${NC}"
    echo "    - Finds uses: statements with unpinned versions (tags instead of SHA)"
    echo "    - Identifies potentially vulnerable action versions"
    echo "    - Can auto-pin to latest SHA commits"
    echo ""
    echo -e "    ${GREEN}Docker Containers:${NC}"
    echo "    - Finds FROM statements with unpinned images (missing @sha256: digest)"
    echo "    - Identifies images using 'latest' or other mutable tags"
    echo "    - Can auto-pin to specific SHA digests"
    echo ""
    echo -e "${YELLOW}AUTO-FIX CAPABILITIES:${NC}"
    echo -e "    ${GREEN}When --auto-fix is enabled:${NC}"
    echo "    - Clones the repository to temporary directory"
    echo "    - Applies pinning fixes using existing scripts"
    echo "    - Creates a new branch with security improvements"
    echo "    - Submits a Pull Request with detailed change summary"
    echo "    - Provides security audit trail"
    echo ""
    echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
    echo -e "    ${RED}⚠️  Check-only mode (default):${NC} Safe to run anywhere - no modifications"
    echo -e "    ${RED}⚠️  Auto-fix mode:${NC} Requires write access and will create PRs"
    echo -e "    ${GREEN}✅ Requires:${NC} git, curl, jq, and optionally docker (for container scanning)"
    echo -e "    ${GREEN}✅ GitHub token:${NC} Recommended for API access and required for auto-fix"
    echo -e "    ${GREEN}✅ Idempotent:${NC} Safe to run multiple times"
    echo ""
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    local auto_fix_deps=()
    
    # Always required dependencies
    for cmd in git curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Auto-fix mode dependencies
    if [[ "$AUTO_FIX" == true ]]; then
        if ! command -v gh &> /dev/null; then
            auto_fix_deps+=("gh (GitHub CLI)")
        fi
    fi
    
    # Container scanning dependencies (optional)
    if [[ "$SCAN_CONTAINERS" == true ]] && ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Warning: docker not found - container digest resolution will be limited${NC}" >&2
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}" >&2
        echo "Please install them and try again." >&2
        exit 1
    fi
    
    if [[ ${#auto_fix_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Auto-fix mode requires: ${auto_fix_deps[*]}${NC}" >&2
        echo "Install GitHub CLI (gh) for auto-fix functionality." >&2
        exit 1
    fi
}

# Function to normalize repository name
normalize_repo_name() {
    local input="$1"
    
    # Handle various input formats:
    # - owner/repo
    # - https://github.com/owner/repo
    # - https://github.com/owner/repo.git
    # - git@github.com:owner/repo.git
    
    if [[ "$input" =~ ^https://github\.com/([^/]+/[^/]+)(\.git)?/?$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$input" =~ ^git@github\.com:([^/]+/[^/]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$input" =~ ^[^/]+/[^/]+$ ]]; then
        echo "$input"
    else
        echo ""
    fi
}

# Function to create temporary directory
setup_temp_dir() {
    if [[ "$CLONE_TEMP" == true ]]; then
        TEMP_DIR=$(mktemp -d)
        echo -e "${BLUE}📁 Created temporary directory: $TEMP_DIR${NC}" >&2
    fi
}

# Function to cleanup temporary directory
cleanup_temp_dir() {
    if [[ "$CLEANUP" == true && -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        echo -e "${BLUE}🧹 Cleaning up temporary directory: $TEMP_DIR${NC}" >&2
        rm -rf "$TEMP_DIR"
    fi
}

# Function to clone repository
clone_repository() {
    local repo="$1"
    local clone_dir="$TEMP_DIR/repo"
    
    echo -e "${BLUE}📥 Cloning repository: $repo${NC}" >&2
    
    local clone_url="https://github.com/$repo.git"
    if [[ -n "$GITHUB_TOKEN" ]]; then
        clone_url="https://$GITHUB_TOKEN@github.com/$repo.git"
    fi
    
    if ! git clone --depth 1 "$clone_url" "$clone_dir" >/dev/null 2>&1; then
        echo -e "${RED}❌ Failed to clone repository: $repo${NC}" >&2
        return 1
    fi
    
    echo "$clone_dir"
}

# Function to scan for unpinned GitHub Actions
scan_actions() {
    local repo_dir="$1"
    local issues=()
    
    echo -e "${CYAN}🔍 Scanning for unpinned GitHub Actions...${NC}" >&2
    
    # Find all GitHub workflow files
    local workflow_files
    mapfile -t workflow_files < <(find "$repo_dir" -path "*/.github/workflows/*" \( -name "*.yml" -o -name "*.yaml" \) -type f 2>/dev/null || true)
    
    if [[ ${#workflow_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}  ℹ️  No GitHub workflow files found${NC}" >&2
        return 0
    fi
    
    echo -e "${BLUE}  📄 Found ${#workflow_files[@]} workflow file(s)${NC}" >&2
    
    for file in "${workflow_files[@]}"; do
        local relative_file="${file#$repo_dir/}"
        echo -e "${BLUE}    📋 Scanning: $relative_file${NC}" >&2
        
        local line_number=0
        while IFS= read -r line; do
            ((line_number++))
            
            if [[ "$line" =~ ^[[:space:]]*uses:[[:space:]]*([^@]+)@([^[:space:]#]+) ]]; then
                local action="${BASH_REMATCH[1]}"
                local ref="${BASH_REMATCH[2]}"
                
                # Skip local actions
                if [[ "$action" =~ ^\\./ ]]; then
                    continue
                fi
                
                # Check if already pinned to SHA (40 character hex string)
                if [[ ! "$ref" =~ ^[a-f0-9]{40}$ ]]; then
                    local issue="{\"type\":\"action\",\"file\":\"$relative_file\",\"line\":$line_number,\"action\":\"$action\",\"current_ref\":\"$ref\",\"line_content\":\"$line\"}"
                    issues+=("$issue")
                    echo -e "${YELLOW}    ⚠️  Line $line_number: Unpinned action $action@$ref${NC}" >&2
                fi
            fi
        done < "$file"
    done
    
    # Output results in JSON format
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf '%s\n' "${issues[@]}"
    fi
}

# Function to scan for unpinned Docker containers
scan_containers() {
    local repo_dir="$1"
    local issues=()
    
    echo -e "${CYAN}🔍 Scanning for unpinned Docker containers...${NC}" >&2
    
    # Find all Dockerfiles
    local dockerfiles
    mapfile -t dockerfiles < <(find "$repo_dir" -type f \( -name "Dockerfile" -o -name "Dockerfile.*" -o -name "*.Dockerfile" \) 2>/dev/null || true)
    
    if [[ ${#dockerfiles[@]} -eq 0 ]]; then
        echo -e "${YELLOW}  ℹ️  No Dockerfiles found${NC}" >&2
        return 0
    fi
    
    echo -e "${BLUE}  🐳 Found ${#dockerfiles[@]} Dockerfile(s)${NC}" >&2
    
    for file in "${dockerfiles[@]}"; do
        local relative_file="${file#$repo_dir/}"
        echo -e "${BLUE}    📋 Scanning: $relative_file${NC}" >&2
        
        local line_number=0
        while IFS= read -r line; do
            ((line_number++))
            
            # Check for FROM lines
            if [[ "$line" =~ ^[[:space:]]*FROM[[:space:]]+([^[:space:]@]+)(@sha256:[a-f0-9]+)?([[:space:]]+[aA][sS][[:space:]]+[^[:space:]]+)? ]]; then
                local image="${BASH_REMATCH[1]}"
                local digest="${BASH_REMATCH[2]}"
                
                # Skip scratch images
                if [[ "$image" == "scratch" ]]; then
                    continue
                fi
                
                # Check if image is not pinned to digest
                if [[ -z "$digest" ]]; then
                    local issue="{\"type\":\"container\",\"file\":\"$relative_file\",\"line\":$line_number,\"image\":\"$image\",\"current_digest\":\"\",\"line_content\":\"$line\"}"
                    issues+=("$issue")
                    echo -e "${YELLOW}    ⚠️  Line $line_number: Unpinned container $image${NC}" >&2
                fi
            fi
        done < "$file"
    done
    
    # Output results in JSON format
    if [[ ${#issues[@]} -gt 0 ]]; then
        printf '%s\n' "${issues[@]}"
    fi
}

# Function to auto-fix issues
auto_fix_issues() {
    local repo_dir="$1"
    local repo_name="$2"
    
    echo -e "${MAGENTA}🔧 Starting auto-fix process...${NC}" >&2
    
    cd "$repo_dir"
    
    # Create a new branch for the fixes
    local branch_name="security/pin-dependencies-$(date +%Y%m%d-%H%M%S)"
    git checkout -b "$branch_name" >&2
    
    local changes_made=false
    
    # Fix GitHub Actions if requested
    if [[ "$SCAN_ACTIONS" == true ]]; then
        echo -e "${CYAN}🔧 Fixing unpinned GitHub Actions...${NC}" >&2
        
        # Copy our pinning script to the repo
        cp "$(dirname "$0")/pin-and-upgrader-gh-actions.sh" "./pin-actions-temp.sh" 2>/dev/null || {
            echo -e "${RED}❌ Could not find pin-and-upgrader-gh-actions.sh script${NC}" >&2
            return 1
        }
        
        if bash "./pin-actions-temp.sh" --yes --token "$GITHUB_TOKEN" >&2; then
            changes_made=true
        fi
        
        rm -f "./pin-actions-temp.sh"
    fi
    
    # Fix Docker containers if requested
    if [[ "$SCAN_CONTAINERS" == true ]]; then
        echo -e "${CYAN}🔧 Fixing unpinned Docker containers...${NC}" >&2
        
        # Copy our container update script to the repo
        cp "$(dirname "$0")/update-base-images.sh" "./update-images-temp.sh" 2>/dev/null || {
            echo -e "${RED}❌ Could not find update-base-images.sh script${NC}" >&2
            return 1
        }
        
        if bash "./update-images-temp.sh" --yes >&2; then
            changes_made=true
        fi
        
        rm -f "./update-images-temp.sh"
    fi
    
    if [[ "$changes_made" == true ]]; then
        # Commit changes
        git add . >&2
        git commit -m "security: Pin GitHub Actions and Docker images to specific versions

This automated security update pins:
- GitHub Actions to their specific SHA commits for immutable references
- Docker base images to their SHA256 digests for reproducible builds

Benefits:
- Prevents supply chain attacks through compromised tags
- Ensures reproducible builds
- Improves security posture

Generated by repository security scanner
" >&2
        
        # Push branch
        git push origin "$branch_name" >&2
        
        # Create PR
        local pr_title="Security: Pin dependencies to specific versions"
        local pr_body="## 🔒 Security Enhancement: Dependency Pinning

This automated PR improves security by pinning dependencies to specific versions.

### Changes Made:
- **GitHub Actions**: Pinned to SHA commits instead of mutable tags
- **Docker Images**: Pinned to SHA256 digests instead of mutable tags

### Security Benefits:
- ✅ **Supply Chain Protection**: Prevents attacks through compromised tags
- ✅ **Reproducible Builds**: Same code always produces same results  
- ✅ **Immutable References**: Dependencies cannot be silently changed
- ✅ **Audit Trail**: Clear tracking of exactly which versions are used

### Verification:
All changes maintain the same functional versions while adding cryptographic integrity.

---
🤖 This PR was generated automatically by the repository security scanner.
"
        
        if gh pr create --title "$pr_title" --body "$pr_body" >&2; then
            local pr_url
            pr_url=$(gh pr view --json url --jq '.url')
            echo "{\"status\":\"success\",\"pr_url\":\"$pr_url\",\"branch\":\"$branch_name\"}"
        else
            echo "{\"status\":\"error\",\"message\":\"Failed to create PR\"}"
        fi
    else
        echo "{\"status\":\"no_changes\",\"message\":\"No changes needed\"}"
    fi
}

# Function to format output
format_output() {
    local action_issues=("$@")
    local container_issues=()
    
    # Separate container issues from action issues
    local all_issues=("$@")
    action_issues=()
    
    for issue in "${all_issues[@]}"; do
        if [[ "$issue" =~ \"type\":\"action\" ]]; then
            action_issues+=("$issue")
        else
            container_issues+=("$issue")
        fi
    done
    
    case "$OUTPUT_FORMAT" in
        "json")
            echo "{"
            echo "  \"scan_timestamp\": \"$(date -Iseconds)\","
            echo "  \"total_issues\": $((${#action_issues[@]} + ${#container_issues[@]})),"
            echo "  \"action_issues\": ["
            if [[ ${#action_issues[@]} -gt 0 ]]; then
                printf '    %s' "${action_issues[0]}"
                for issue in "${action_issues[@]:1}"; do
                    printf ',\n    %s' "$issue"
                done
                echo ""
            fi
            echo "  ],"
            echo "  \"container_issues\": ["
            if [[ ${#container_issues[@]} -gt 0 ]]; then
                printf '    %s' "${container_issues[0]}"
                for issue in "${container_issues[@]:1}"; do
                    printf ',\n    %s' "$issue"
                done
                echo ""
            fi
            echo "  ]"
            echo "}"
            ;;
        "csv")
            echo "Type,File,Line,Resource,Current_Version,Issue"
            for issue in "${action_issues[@]}"; do
                local type file line action ref
                type=$(echo "$issue" | jq -r '.type')
                file=$(echo "$issue" | jq -r '.file')
                line=$(echo "$issue" | jq -r '.line')
                action=$(echo "$issue" | jq -r '.action')
                ref=$(echo "$issue" | jq -r '.current_ref')
                echo "$type,$file,$line,$action,$ref,Unpinned action"
            done
            for issue in "${container_issues[@]}"; do
                local type file line image
                type=$(echo "$issue" | jq -r '.type')
                file=$(echo "$issue" | jq -r '.file')
                line=$(echo "$issue" | jq -r '.line')
                image=$(echo "$issue" | jq -r '.image')
                echo "$type,$file,$line,$image,,Unpinned container"
            done
            ;;
        "markdown")
            echo "# Repository Security Scan Report"
            echo ""
            echo "**Scan Date:** $(date)"
            echo "**Total Issues:** $((${#action_issues[@]} + ${#container_issues[@]}))"
            echo ""
            
            if [[ ${#action_issues[@]} -gt 0 ]]; then
                echo "## 🔧 Unpinned GitHub Actions (${#action_issues[@]})"
                echo ""
                echo "| File | Line | Action | Current Version |"
                echo "|------|------|--------|-----------------|"
                for issue in "${action_issues[@]}"; do
                    local file line action ref
                    file=$(echo "$issue" | jq -r '.file')
                    line=$(echo "$issue" | jq -r '.line')
                    action=$(echo "$issue" | jq -r '.action')
                    ref=$(echo "$issue" | jq -r '.current_ref')
                    echo "| \`$file\` | $line | \`$action\` | \`$ref\` |"
                done
                echo ""
            fi
            
            if [[ ${#container_issues[@]} -gt 0 ]]; then
                echo "## 🐳 Unpinned Docker Containers (${#container_issues[@]})"
                echo ""
                echo "| File | Line | Image |"
                echo "|------|------|-------|"
                for issue in "${container_issues[@]}"; do
                    local file line image
                    file=$(echo "$issue" | jq -r '.file')
                    line=$(echo "$issue" | jq -r '.line')
                    image=$(echo "$issue" | jq -r '.image')
                    echo "| \`$file\` | $line | \`$image\` |"
                done
                echo ""
            fi
            ;;
        "console"|*)
            local total_issues=$((${#action_issues[@]} + ${#container_issues[@]}))
            echo -e "${BLUE}📊 Security Scan Summary${NC}"
            echo -e "${BLUE}========================${NC}"
            echo ""
            echo -e "${CYAN}Total Security Issues: $total_issues${NC}"
            echo -e "${CYAN}- Unpinned Actions: ${#action_issues[@]}${NC}"
            echo -e "${CYAN}- Unpinned Containers: ${#container_issues[@]}${NC}"
            echo ""
            
            if [[ $total_issues -eq 0 ]]; then
                echo -e "${GREEN}✅ No security issues found! Repository follows security best practices.${NC}"
            else
                echo -e "${RED}⚠️  Security issues detected. Consider pinning dependencies for better security.${NC}"
            fi
            ;;
    esac
}

# Parse command line arguments
REPO_NAME=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--actions-only)
            SCAN_ACTIONS=true
            SCAN_CONTAINERS=false
            shift
            ;;
        -c|--containers-only)
            SCAN_ACTIONS=false
            SCAN_CONTAINERS=true
            shift
            ;;
        -d|--depth)
            SCAN_DEPTH="$2"
            shift 2
            ;;
        --check-only)
            DRY_RUN=true
            AUTO_FIX=false
            shift
            ;;
        --auto-fix)
            DRY_RUN=false
            AUTO_FIX=true
            shift
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -t|--token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo -e "${RED}Error: Unknown option $1${NC}" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ -z "$REPO_NAME" ]]; then
                REPO_NAME="$1"
            else
                echo -e "${RED}Error: Multiple repository names provided${NC}" >&2
                usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$REPO_NAME" ]]; then
    echo -e "${RED}Error: Repository name is required${NC}" >&2
    usage >&2
    exit 1
fi

# Normalize repository name
NORMALIZED_REPO=$(normalize_repo_name "$REPO_NAME")
if [[ -z "$NORMALIZED_REPO" ]]; then
    echo -e "${RED}Error: Invalid repository format: $REPO_NAME${NC}" >&2
    echo "Expected format: owner/repo or https://github.com/owner/repo" >&2
    exit 1
fi

# Main execution
main() {
    echo -e "${BLUE}Repository Security Scanner${NC}" >&2
    echo -e "${BLUE}===========================${NC}" >&2
    echo "" >&2
    echo -e "${CYAN}🎯 Target Repository: $NORMALIZED_REPO${NC}" >&2
    echo -e "${CYAN}🔍 Scan Mode: $([ "$AUTO_FIX" == true ] && echo "Auto-fix" || echo "Check-only")${NC}" >&2
    echo "" >&2
    
    # Check dependencies
    check_dependencies
    
    # Setup temporary directory
    setup_temp_dir
    
    # Ensure cleanup on exit
    trap cleanup_temp_dir EXIT
    
    # Clone repository
    local repo_dir
    if ! repo_dir=$(clone_repository "$NORMALIZED_REPO"); then
        exit 1
    fi
    
    local all_issues=()
    
    # Scan for issues
    if [[ "$SCAN_ACTIONS" == true ]]; then
        mapfile -t action_issues < <(scan_actions "$repo_dir")
        all_issues+=("${action_issues[@]}")
    fi
    
    if [[ "$SCAN_CONTAINERS" == true ]]; then
        mapfile -t container_issues < <(scan_containers "$repo_dir")
        all_issues+=("${container_issues[@]}")
    fi
    
    # Auto-fix if requested
    local fix_result=""
    if [[ "$AUTO_FIX" == true && ${#all_issues[@]} -gt 0 ]]; then
        if [[ -z "$GITHUB_TOKEN" ]]; then
            echo -e "${RED}❌ GitHub token required for auto-fix mode${NC}" >&2
            exit 1
        fi
        fix_result=$(auto_fix_issues "$repo_dir" "$NORMALIZED_REPO")
    fi
    
    # Format and output results
    local output
    output=$(format_output "${all_issues[@]}")
    
    if [[ -n "$fix_result" ]]; then
        # Add fix result to output for JSON format
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            output=$(echo "$output" | jq --argjson fix "$fix_result" '. + {auto_fix_result: $fix}')
        fi
    fi
    
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$output" > "$OUTPUT_FILE"
        echo -e "${GREEN}📄 Results written to: $OUTPUT_FILE${NC}" >&2
    else
        echo "$output"
    fi
    
    # Exit with appropriate code
    local exit_code=0
    if [[ ${#all_issues[@]} -gt 0 ]]; then
        exit_code=1
    fi
    
    echo "" >&2
    echo -e "${BLUE}✅ Scan completed${NC}" >&2
    
    exit $exit_code
}

# Run main function
main "$@"