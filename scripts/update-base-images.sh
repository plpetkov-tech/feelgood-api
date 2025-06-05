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
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
FORCE_UPDATE=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Check for newer versions of Docker base images in Dockerfiles and update to latest SHA digests

OPTIONS:
    -d, --dry-run       Show what would be changed without making changes
    -y, --yes           Automatically confirm changes (skip prompts)
    -f, --force         Force update even if current image is recent
    -t, --token TOKEN   GitHub token for API access (or set GITHUB_TOKEN env var)
    -h, --help          Show this help message

EXAMPLES:
    $0 --dry-run                    # Preview changes (safe, no modifications)
    $0 --yes                        # Apply changes automatically (no prompts)
    $0                              # Interactive mode (prompts for each change)
    $0 --force --dry-run            # Check for updates even for recent images

IMPORTANT:
    - Without --dry-run: Script can modify Dockerfiles
    - Without --yes: Script will prompt for confirmation before each change
    - With --yes: Script applies all changes automatically
    - With --dry-run: Script only shows what would change (safest option)
    
NOTES:
    - Requires docker, curl, and jq to be installed
    - Script is idempotent - can be run multiple times safely
    - Only updates images that have newer versions available
EOF
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in docker curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}" >&2
        echo "Please install them and try again." >&2
        exit 1
    fi
}

# Function to extract image name and digest from FROM line
parse_from_line() {
    local line="$1"
    local image=""
    local digest=""
    local tag=""
    
    # Handle various FROM line formats:
    # FROM image:tag@sha256:digest
    # FROM image:tag@sha256:digest as stage
    # FROM registry/image:tag@sha256:digest
    
    if [[ "$line" =~ FROM[[:space:]]+([^@[:space:]]+)(@sha256:[a-f0-9]+)?([[:space:]]+[aA][sS][[:space:]]+[^[:space:]]+)? ]]; then
        image="${BASH_REMATCH[1]}"
        digest="${BASH_REMATCH[2]}"
        
        # Extract tag from image
        if [[ "$image" =~ ^(.+):([^:]+)$ ]]; then
            image="${BASH_REMATCH[1]}"
            tag="${BASH_REMATCH[2]}"
        else
            tag="latest"
        fi
    fi
    
    echo "$image|$tag|$digest"
}

# Function to get the latest digest for an image:tag
get_latest_digest() {
    local image="$1"
    local tag="$2"
    local full_image="$image:$tag"
    
    echo -n "  🔍 Checking $full_image for updates... " >&2
    
    # Pull the image to ensure we have the latest version
    if ! docker pull "$full_image" >/dev/null 2>&1; then
        echo -e "${RED}✗ Failed to pull image${NC}" >&2
        return 1
    fi
    
    # Get the digest from the pulled image
    local digest
    if ! digest=$(docker inspect "$full_image" --format='{{index .RepoDigests 0}}' 2>/dev/null); then
        echo -e "${RED}✗ Failed to get digest${NC}" >&2
        return 1
    fi
    
    # Extract just the sha256 part
    if [[ "$digest" =~ @(sha256:[a-f0-9]+)$ ]]; then
        digest="${BASH_REMATCH[1]}"
    else
        echo -e "${RED}✗ Invalid digest format${NC}" >&2
        return 1
    fi
    
    if [[ -z "$digest" || "$digest" == "null" ]]; then
        echo -e "${RED}✗ No digest found${NC}" >&2
        return 1
    fi
    
    echo "$digest"
}

# Function to get image creation date
get_image_creation_date() {
    local image="$1"
    local tag="$2"
    local digest="$3"
    local full_image
    
    if [[ -n "$digest" ]]; then
        full_image="$image:$tag$digest"
    else
        full_image="$image:$tag"
    fi
    
    # Get image creation date from docker inspect
    local created
    if ! created=$(docker inspect "$full_image" --format='{{.Created}}' 2>/dev/null); then
        return 1
    fi
    
    echo "$created"
}

# Function to compare dates (returns 0 if date1 > date2)
date_is_newer() {
    local date1="$1"
    local date2="$2"
    
    # Convert to Unix timestamps for comparison
    local ts1 ts2
    ts1=$(date -d "$date1" +%s 2>/dev/null || echo "0")
    ts2=$(date -d "$date2" +%s 2>/dev/null || echo "0")
    
    [[ "$ts1" -gt "$ts2" ]]
}

# Function to process a single Dockerfile
process_dockerfile() {
    local dockerfile="$1"
    local changes_made=false
    local temp_file
    temp_file=$(mktemp)
    
    echo -e "${BLUE}Processing: $dockerfile${NC}"
    
    local line_number=0
    while IFS= read -r line; do
        ((line_number++))
        
        # Check if this is a FROM line with an image
        if [[ "$line" =~ ^[[:space:]]*FROM[[:space:]] ]]; then
            local parsed
            parsed=$(parse_from_line "$line")
            IFS='|' read -r image tag current_digest <<< "$parsed"
            
            if [[ -z "$image" ]]; then
                echo "  ➤ Line $line_number: Could not parse FROM line, skipping"
                echo "$line" >> "$temp_file"
                continue
            fi
            
            # Skip scratch images or local images
            if [[ "$image" == "scratch" || "$image" =~ ^\.\/ ]]; then
                echo "  ➤ Line $line_number: Skipping special image: $image"
                echo "$line" >> "$temp_file"
                continue
            fi
            
            echo "  📦 Line $line_number: Found image $image:$tag"
            
            # Get the latest digest
            local latest_digest
            if ! latest_digest=$(get_latest_digest "$image" "$tag"); then
                echo -e "    ${RED}✗ Failed to get latest digest${NC}"
                echo "$line" >> "$temp_file"
                continue
            fi
            
            echo -e "    ${GREEN}✓ Latest digest available${NC}"
            
            # Compare digests
            local current_digest_clean="${current_digest#@}"
            local latest_digest_clean="${latest_digest#sha256:}"
            latest_digest_clean="sha256:$latest_digest_clean"
            
            if [[ "$current_digest_clean" == "$latest_digest_clean" ]]; then
                echo "    ✅ Already using latest digest"
                echo "$line" >> "$temp_file"
                continue
            fi
            
            # Check if we should update (compare creation dates)
            if [[ "$FORCE_UPDATE" == false && -n "$current_digest" ]]; then
                local current_date latest_date
                current_date=$(get_image_creation_date "$image" "$tag" "$current_digest")
                latest_date=$(get_image_creation_date "$image" "$tag" "@$latest_digest_clean")
                
                if [[ -n "$current_date" && -n "$latest_date" ]]; then
                    if ! date_is_newer "$latest_date" "$current_date"; then
                        echo "    ➤ Current image is already recent (created: $current_date)"
                        echo "$line" >> "$temp_file"
                        continue
                    else
                        echo "    📅 Newer image available:"
                        echo "      Current: $current_date"
                        echo "      Latest:  $latest_date"
                    fi
                fi
            fi
            
            # Prepare the new line
            local new_line
            if [[ -n "$current_digest" ]]; then
                # Replace existing digest
                new_line=$(echo "$line" | sed "s|$current_digest|@$latest_digest_clean|")
            else
                # Add digest to image:tag
                new_line=$(echo "$line" | sed "s|$image:$tag|$image:$tag@$latest_digest_clean|")
            fi
            
            echo "    📝 Update available:"
            echo "      Current: $image:$tag$current_digest"
            echo "      Latest:  $image:$tag@$latest_digest_clean"
            
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "    ${YELLOW}WOULD CHANGE:${NC}"
                echo "      FROM: $line"
                echo "      TO:   $new_line"
                echo "$line" >> "$temp_file"  # Keep original in dry-run
            else
                local should_update=false
                if [[ "$AUTO_YES" == true ]]; then
                    echo "    ✅ Auto-updating (--yes flag)"
                    should_update=true
                else
                    echo -n "    Update this image? [y/N]: "
                    read -r response
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        should_update=true
                    fi
                fi
                
                if [[ "$should_update" == true ]]; then
                    echo "    ✅ Updated to latest digest"
                    echo "$new_line" >> "$temp_file"
                    changes_made=true
                else
                    echo "    ➤ Keeping current version"
                    echo "$line" >> "$temp_file"
                fi
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$dockerfile"
    
    # Replace original file if changes were made (and not dry-run)
    if [[ "$DRY_RUN" == false && "$changes_made" == true ]]; then
        mv "$temp_file" "$dockerfile"
        echo -e "  ${GREEN}✓ Updated $dockerfile${NC}"
        return 0  # Signal that changes were made
    else
        rm "$temp_file"
        if [[ "$changes_made" == false && "$DRY_RUN" == false ]]; then
            echo "  ➤ No changes needed"
        fi
        return 1  # Signal that no changes were made
    fi
}

# Function to find all Dockerfiles
find_dockerfiles() {
    # Look for Dockerfiles in common locations
    find . -type f \( -name "Dockerfile" -o -name "Dockerfile.*" -o -name "*.Dockerfile" \) 2>/dev/null | sort
}

# Function to create a summary of changes
create_change_summary() {
    local files_changed=("$@")
    
    if [[ ${#files_changed[@]} -eq 0 ]]; then
        return
    fi
    
    echo ""
    echo -e "${GREEN}📋 Summary of Changes:${NC}"
    echo "===================="
    
    for file in "${files_changed[@]}"; do
        echo "✅ Updated: $file"
        
        # Show what changed in this file
        if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
            echo "   Changes:"
            git diff --no-index /dev/null "$file" 2>/dev/null | grep "^+FROM" | sed 's/^+/     + /' || true
        fi
    done
    
    echo ""
    echo -e "${BLUE}💡 Recommended next steps:${NC}"
    echo "1. Review the changes above"
    echo "2. Test your application with the new base images"
    echo "3. Run your security pipeline to verify compatibility"
    echo "4. Commit the changes if everything looks good"
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
        -f|--force)
            FORCE_UPDATE=true
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
    echo -e "${BLUE}Docker Base Image Update Script${NC}"
    echo "==============================="
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Find all Dockerfiles
    echo "🔍 Finding Dockerfiles..."
    local dockerfiles
    mapfile -t dockerfiles < <(find_dockerfiles)
    
    if [[ ${#dockerfiles[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No Dockerfiles found in current directory.${NC}"
        exit 0
    fi
    
    echo "Found ${#dockerfiles[@]} Dockerfile(s):"
    printf '  %s\n' "${dockerfiles[@]}"
    echo ""
    
    # Confirm execution (unless auto-yes or dry-run)
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
    elif [[ "$AUTO_YES" == false ]]; then
        echo -n "Proceed with checking for base image updates? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
    
    echo ""
    
    # Process each Dockerfile
    local files_changed=()
    for dockerfile in "${dockerfiles[@]}"; do
        if process_dockerfile "$dockerfile"; then
            files_changed+=("$dockerfile")
        fi
        echo ""
    done
    
    # Show summary
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}🔍 Dry run completed. Use without --dry-run to apply changes.${NC}"
    else
        if [[ ${#files_changed[@]} -gt 0 ]]; then
            create_change_summary "${files_changed[@]}"
            echo -e "${GREEN}✅ Base image update completed!${NC}"
        else
            echo -e "${GREEN}✅ All base images are already up to date!${NC}"
        fi
    fi
}

# Run main function
main "$@"