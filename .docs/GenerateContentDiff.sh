#!/bin/bash
#
# GenerateContentDiff.sh
#
# Generates a content-focused diff between two PVE Guide versions
# by comparing markdown files and filtering out formatting noise.
#
# Usage:
#   ./GenerateContentDiff.sh <old_version_dir> <new_version_dir> <output_file>
#
# Example:
#   ./GenerateContentDiff.sh V8-4-0_PVEGuide V9-1-1_PVEGuide V9-1-1_PVEGuide/CONTENT_DIFF.md

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [ $# -ne 3 ]; then
    log_error "Usage: $0 <old_version_dir> <new_version_dir> <output_file>"
    exit 1
fi

OLD_DIR="$1"
NEW_DIR="$2"
OUTPUT_FILE="$3"

if [ ! -d "$OLD_DIR" ]; then
    log_error "Old version directory not found: $OLD_DIR"
    exit 1
fi

if [ ! -d "$NEW_DIR" ]; then
    log_error "New version directory not found: $NEW_DIR"
    exit 1
fi

log_info "Generating content diff: $OLD_DIR → $NEW_DIR"

# Create output file with header
cat > "$OUTPUT_FILE" << EOF
# Content Changes: $(basename "$OLD_DIR") → $(basename "$NEW_DIR")

Generated: $(date '+%Y-%m-%d %H:%M:%S')

This diff shows content changes between versions, filtering out:
- Internal link reference changes (e.g., #510 → #574)
- Minor formatting differences
- HTML tag changes

---

EOF

# Find all markdown files in new version
total_files=0
changed_files=0
new_files=0
removed_files=0

for new_file in "$NEW_DIR"/*.md; do
    [ -f "$new_file" ] || continue
    
    filename=$(basename "$new_file")
    old_file="$OLD_DIR/$filename"
    
    ((total_files++)) || true
    
    # Check if file exists in old version
    if [ ! -f "$old_file" ]; then
        ((new_files++)) || true
        echo "## NEW FILE: $filename" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "This is a new chapter/section added in this version." >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "---" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        continue
    fi
    
    # Create temp files with normalized content
    temp_old=$(mktemp)
    temp_new=$(mktemp)
    
    # Normalize: remove internal link references and footnote references
    # Patterns: (#123), (#12-34), [[36](#_footnote_36)], ending with space+[[num](#_footnote_num)]
    sed -E 's/\(#[0-9][0-9-]*[0-9]*\)/(#LINK)/g; s/\s*\[\[[0-9]+\]\(#_footnote_[0-9]+\)\]\s*/ [FOOTNOTE] /g' "$old_file" > "$temp_old"
    sed -E 's/\(#[0-9][0-9-]*[0-9]*\)/(#LINK)/g; s/\s*\[\[[0-9]+\]\(#_footnote_[0-9]+\)\]\s*/ [FOOTNOTE] /g' "$new_file" > "$temp_new"
    
    # Compare normalized content
    if ! diff -q "$temp_old" "$temp_new" > /dev/null 2>&1; then
        ((changed_files++)) || true
        
        echo "## $filename" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        # Generate unified diff
        diff -u "$temp_old" "$temp_new" | tail -n +3 >> "$OUTPUT_FILE" 2>/dev/null || true
        
        echo "" >> "$OUTPUT_FILE"
        echo "---" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
    
    rm -f "$temp_old" "$temp_new"
done

# Check for removed files
for old_file in "$OLD_DIR"/*.md; do
    [ -f "$old_file" ] || continue
    
    filename=$(basename "$old_file")
    new_file="$NEW_DIR/$filename"
    
    if [ ! -f "$new_file" ]; then
        ((removed_files++)) || true
        echo "## REMOVED FILE: $filename" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "This chapter/section was removed in this version." >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "---" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done

# Add summary at the end
cat >> "$OUTPUT_FILE" << EOF

---

# Summary

- Total files compared: $total_files
- Files with content changes: $changed_files
- New files: $new_files
- Removed files: $removed_files

EOF

log_success "Content diff generated: $OUTPUT_FILE"
log_info "Files compared: $total_files"
log_info "Changed: $changed_files | New: $new_files | Removed: $removed_files"
