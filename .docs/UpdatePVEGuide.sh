#!/bin/bash
#
# UpdatePVEGuide.sh
#
# Downloads the latest Proxmox VE Administration Guide from pve.proxmox.com,
# extracts version information, renames it appropriately, and converts it to markdown.
#
# Usage:
#   ./UpdatePVEGuide.sh
#
# Requirements:
#   - wget or curl
#   - python3
#   - html_to_markdown.py (in same directory)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUIDE_URL="https://pve.proxmox.com/pve-docs/pve-admin-guide.html"
TEMP_HTML="${SCRIPT_DIR}/pve-admin-guide-temp.html"
CONVERTER_SCRIPT="${SCRIPT_DIR}/HTMLToMarkdown.py"
DIFF_SCRIPT="${SCRIPT_DIR}/GenerateContentDiff.sh"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    log_info "Checking requirements..."
    
    # Check for download tool
    if command -v wget &>/dev/null; then
        DOWNLOAD_CMD="wget -q -O"
    elif command -v curl &>/dev/null; then
        DOWNLOAD_CMD="curl -sL -o"
    else
        log_error "Neither wget nor curl found. Please install one of them."
        exit 1
    fi
    
    # Check for python3
    if ! command -v python3 &>/dev/null; then
        log_error "python3 not found. Please install python3."
        exit 1
    fi
    
    # Check for converter script
    if [[ ! -f "$CONVERTER_SCRIPT" ]]; then
        log_error "Converter script not found at: $CONVERTER_SCRIPT"
        exit 1
    fi
    
    log_success "All requirements met"
}

download_guide() {
    log_info "Downloading latest Proxmox VE Administration Guide..."
    
    if [[ "$DOWNLOAD_CMD" == "wget -q -O" ]]; then
        wget -q -O "$TEMP_HTML" "$GUIDE_URL"
    else
        curl -sL -o "$TEMP_HTML" "$GUIDE_URL"
    fi
    
    if [[ ! -f "$TEMP_HTML" ]] || [[ ! -s "$TEMP_HTML" ]]; then
        log_error "Failed to download guide from $GUIDE_URL"
        exit 1
    fi
    
    log_success "Download complete"
}

check_existing_version() {
    # Find existing PVEGuide directories for the same base version
    # Pattern: V*_*_PVEGuide (e.g., V9-1-1_01_PVEGuide)
    local existing_dirs=$(find "$SCRIPT_DIR" -maxdepth 1 -type d -name "V*_*_PVEGuide" 2>/dev/null | sort -V | tail -1)
    
    if [[ -n "$existing_dirs" ]]; then
        local latest_dir=$(basename "$existing_dirs")
        local latest_version="${latest_dir%_PVEGuide}"
        echo "$latest_version"
    else
        echo ""
    fi
}

extract_last_updated() {
    local html_file=$1
    # Extract: Last updated Wed Nov 19 13:02:23 CET 2025
    # The timestamp is on the next line after "Last updated"
    local timestamp=$(grep -A1 "Last updated" "$html_file" 2>/dev/null | tail -1 | xargs)
    echo "$timestamp"
}

calculate_minor_version() {
    local base_version=$1
    local existing_version=$2
    
    # If no existing version, start with 01
    if [[ -z "$existing_version" ]]; then
        echo "01"
        return
    fi
    
    # Extract base version from existing (V9-1-1_02 -> V9-1-1)
    local existing_base="${existing_version%%_*}"
    
    # If base version changed, start fresh with 01
    if [[ "$base_version" != "$existing_base" ]]; then
        echo "01"
        return
    fi
    
    # Same base version, increment minor
    local existing_minor="${existing_version##*_}"
    local new_minor=$(printf "%02d" $((10#$existing_minor + 1)))
    echo "$new_minor"
}

extract_version_info() {
    # Extract version from HTML using the revnumber span (silent, returns version only)
    # Looking for: <span id="revnumber">version 9.1.1,</span>
    local VERSION_LINE=$(grep -oP '<span id="revnumber">version\s+\K[0-9]+\.[0-9]+\.[0-9]+' "$TEMP_HTML" 2>/dev/null | head -1 || echo "")
    
    if [[ -z "$VERSION_LINE" ]]; then
        # Fallback to simpler pattern
        VERSION_LINE=$(grep -oP 'version\s+\K[0-9]+\.[0-9]+\.[0-9]+' "$TEMP_HTML" 2>/dev/null | head -1 || echo "")
    fi
    
    if [[ -z "$VERSION_LINE" ]]; then
        VERSION_LINE="unknown"
    fi
    
    # Format version for directory name (e.g., 9.1.1 -> V9-1-1)
    local BASE_VERSION="V${VERSION_LINE//./-}"
    
    echo "$BASE_VERSION"
}

needs_update() {
    local base_version=$1
    local existing_version=$2
    local new_timestamp=$3
    
    # If no existing version, definitely need update
    if [[ -z "$existing_version" ]]; then
        echo "yes"
        return
    fi
    
    # Extract base from existing version
    local existing_base="${existing_version%%_*}"
    
    # If base version changed, need update
    if [[ "$base_version" != "$existing_base" ]]; then
        echo "yes"
        return
    fi
    
    # Same base version - check timestamp
    local existing_html="${SCRIPT_DIR}/PVEGuide_${existing_version#V}.html"
    if [[ ! -f "$existing_html" ]]; then
        echo "yes"
        return
    fi
    
    local existing_timestamp=$(extract_last_updated "$existing_html")
    
    # If we can't get timestamps, assume no update needed
    if [[ -z "$new_timestamp" ]] || [[ -z "$existing_timestamp" ]]; then
        echo "no"
        return
    fi
    
    # Compare timestamps (simple string comparison works for the format used)
    if [[ "$new_timestamp" != "$existing_timestamp" ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

rename_and_organize() {
    local full_version=$1
    local renamed_html="${SCRIPT_DIR}/PVEGuide_${full_version#V}.html"
    
    # Move and rename the downloaded HTML (silent, returns path only)
    mv "$TEMP_HTML" "$renamed_html" 2>/dev/null
    
    echo "$renamed_html"
}

generate_content_diff() {
    local new_full_version=$1
    local prev_version=$2
    
    if [[ -z "$prev_version" ]]; then
        log_info "No previous version to compare against"
        return 0
    fi
    
    log_info "Generating content diff from previous version..."
    
    local prev_dir="${SCRIPT_DIR}/${prev_version}_PVEGuide"
    local new_dir="${SCRIPT_DIR}/${new_full_version}_PVEGuide"
    
    if [[ ! -d "$prev_dir" ]]; then
        log_warning "Previous version directory not found: $prev_dir"
        return 0
    fi
    
    local diff_file="${new_dir}/CONTENT_DIFF_${prev_version}_to_${new_full_version}.md"
    
    if [[ ! -f "$DIFF_SCRIPT" ]]; then
        log_warning "Content diff script not found: $DIFF_SCRIPT"
        return 0
    fi
    
    # Generate markdown-based content diff
    if "$DIFF_SCRIPT" "$prev_dir" "$new_dir" "$diff_file" > /dev/null 2>&1; then
        if [[ -f "$diff_file" ]] && [[ -s "$diff_file" ]]; then
            log_success "Content diff saved to: $(basename "$diff_file")"
            
            # Count changes
            local changed_files=$(grep -c "^## [0-9]" "$diff_file" 2>/dev/null || echo 0)
            local new_files=$(grep -c "^## NEW FILE:" "$diff_file" 2>/dev/null || echo 0)
            local removed_files=$(grep -c "^## REMOVED FILE:" "$diff_file" 2>/dev/null || echo 0)
            log_info "Changes: $changed_files files | New: $new_files | Removed: $removed_files"
        fi
    else
        log_warning "Failed to generate content diff"
    fi
}

convert_to_markdown() {
    local html_file=$1
    local full_version=$2
    local output_dir="${SCRIPT_DIR}/${full_version}_PVEGuide"
    
    log_info "Converting HTML to Markdown..."
    
    # Check if output directory already exists
    if [[ -d "$output_dir" ]]; then
        log_error "Output directory already exists: $output_dir"
        log_error "This version appears to already be processed."
        return 1
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Run the conversion script with split-chapters option and output directory
    if python3 "$CONVERTER_SCRIPT" -s "$html_file" -o "$output_dir"; then
        log_success "Conversion complete! Output directory: $output_dir"
        
        # Count the markdown files created
        local md_count=$(find "$output_dir" -name "*.md" 2>/dev/null | wc -l)
        log_info "Generated $md_count markdown files"
        
        return 0
    else
        log_error "Conversion failed"
        # Clean up failed directory
        rm -rf "$output_dir"
        return 1
    fi
}

update_readme() {
    local full_version=$1
    local readme="${SCRIPT_DIR}/README.md"
    
    if [[ -f "$readme" ]]; then
        log_info "Updating README.md with new version..."
        
        # Extract base version (V9-1-1_02 -> 9.1.1)
        local base_version="${full_version%%_*}"
        local version_num="${base_version#V}"
        version_num="${version_num//-/.}"
        
        sed -i "s/\*\*Documentation:\*\* Proxmox VE [0-9]\+\.[0-9]\+.*/**Documentation:** Proxmox VE $version_num/" "$readme"
        sed -i "s/\*\*Last Updated:\*\* [0-9-]\+/**Last Updated:** $(date +%Y-%m-%d)/" "$readme"
        
        log_success "README.md updated"
    fi
}

cleanup() {
    # Clean up any temporary files
    if [[ -f "$TEMP_HTML" ]]; then
        rm -f "$TEMP_HTML"
    fi
}

main() {
    log_info "Starting Proxmox VE Administration Guide update process..."
    echo
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Check requirements
    check_requirements
    echo
    
    # Check for existing version
    log_info "Checking for existing versions..."
    EXISTING_VERSION=$(check_existing_version)
    if [[ -n "$EXISTING_VERSION" ]]; then
        log_info "Found existing version: $EXISTING_VERSION"
    else
        log_info "No existing versions found"
    fi
    echo
    
    # Download the guide to check version
    download_guide
    echo
    
    # Extract base version and timestamp from downloaded file
    log_info "Extracting version information..."
    BASE_VERSION=$(extract_version_info)
    NEW_TIMESTAMP=$(extract_last_updated "$TEMP_HTML")
    log_success "Base version detected: $BASE_VERSION"
    log_info "Last updated: $NEW_TIMESTAMP"
    echo
    
    # Check if update is needed
    UPDATE_NEEDED=$(needs_update "$BASE_VERSION" "$EXISTING_VERSION" "$NEW_TIMESTAMP")
    
    if [[ "$UPDATE_NEEDED" == "no" ]]; then
        log_info "Latest version ($BASE_VERSION) is already downloaded and up-to-date."
        log_info "No update needed."
        cleanup
        exit 0
    fi
    
    # Calculate minor version number
    MINOR_VERSION=$(calculate_minor_version "$BASE_VERSION" "$EXISTING_VERSION")
    FULL_VERSION="${BASE_VERSION}_${MINOR_VERSION}"
    
    log_success "Update needed: $FULL_VERSION (previous: ${EXISTING_VERSION:-none})"
    if [[ -n "$EXISTING_VERSION" ]] && [[ "${EXISTING_VERSION%%_*}" == "$BASE_VERSION" ]]; then
        log_info "Minor update: Same base version with new timestamp"
    fi
    echo
    
    # Rename and organize
    log_info "Organizing files..."
    HTML_FILE=$(rename_and_organize "$FULL_VERSION")
    log_success "Renamed to: $(basename "$HTML_FILE")"
    echo
    
    # Convert to markdown
    if convert_to_markdown "$HTML_FILE" "$FULL_VERSION"; then
        echo
        
        # Generate diff if there's a previous version
        if [[ -n "$EXISTING_VERSION" ]]; then
            generate_content_diff "$FULL_VERSION" "$EXISTING_VERSION"
            echo
        fi
        
        update_readme "$FULL_VERSION"
        echo
        log_success "=== Update Complete ==="
        log_info "HTML file: $HTML_FILE"
        log_info "Markdown directory: ${SCRIPT_DIR}/${FULL_VERSION}_PVEGuide"
    else
        log_error "Update process failed during conversion"
        exit 1
    fi
}

# Run main function
main "$@"
