#!/bin/bash
#
# UpdateProxmoxScripts.sh
#
# Updates ProxmoxScripts repository from GitHub without replacing root folder.
#
# Usage:
#   UpdateProxmoxScripts.sh
#
# Examples:
#   UpdateProxmoxScripts.sh
#

set -euo pipefail

REPO_URL="https://github.com/coelacant1/proxmoxscripts"
REPO_NAME="proxmoxscripts"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Get current directory
CURRENT_DIR=$(pwd)

# Verify we're in the correct folder
if [[ "${CURRENT_DIR,,}" != *"${REPO_NAME,,}"* ]]; then
    echo "Error: Must be run from within $REPO_NAME folder" >&2
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d) || {
    echo "Error: Failed to create temporary directory" >&2
    exit 1
}

echo "Cloning repository..."
if ! git clone "$REPO_URL" "$TEMP_DIR/$REPO_NAME"; then
    echo "Error: Failed to clone repository" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Clearing current folder contents..."
if ! find "$CURRENT_DIR" -mindepth 1 -delete; then
    echo "Error: Failed to clear folder contents" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Moving updated files..."
if ! mv "$TEMP_DIR/$REPO_NAME/"* "$CURRENT_DIR"; then
    echo "Error: Failed to move updated files" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Move hidden files (ignore errors for missing files)
mv "$TEMP_DIR/$REPO_NAME/".* "$CURRENT_DIR" 2>/dev/null || true

# Make scripts executable
if [[ -f "$CURRENT_DIR/MakeScriptsExecutable.sh" ]]; then
    echo "Making scripts executable..."
    chmod +x "$CURRENT_DIR/MakeScriptsExecutable.sh"
    "$CURRENT_DIR/MakeScriptsExecutable.sh"
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo "Update completed successfully!"
