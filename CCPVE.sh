#!/bin/bash
#
# CCPVE.sh
#
# The main script to download and extract the ProxmoxScripts repository, then make all scripts
# in the repository executable and finally call CCPVEOffline.sh.
#
# Usage:
#   ./CCPVE.sh
#
# This script requires 'unzip' and 'wget'. If not installed, it will prompt to install them.
#
# Example:
#   bash -c "$(wget -qLO - https://github.com/coelacant1/ProxmoxScripts/raw/main/CCPVE.sh)"
#

set -e

# --- Check Dependencies -----------------------------------------------------
if ! command -v unzip &>/dev/null; then
    echo "The 'unzip' utility is required to extract the downloaded files but is not installed."
    read -r -p "Would you like to install 'unzip' now? [y/N]: " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        apt-get install -y unzip
    else
        echo "Aborting script because 'unzip' is not installed."
        exit 1
    fi
fi

if ! command -v wget &>/dev/null; then
    echo "The 'wget' utility is required to download the repository ZIP but is not installed."
    read -r -p "Would you like to install 'wget' now? [y/N]: " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        apt-get install -y wget
    else
        echo "Aborting script because 'wget' is not installed."
        exit 1
    fi
fi

# --- Configuration ----------------------------------------------------------
REPO_ZIP_URL="https://github.com/coelacant1/ProxmoxScripts/archive/refs/heads/main.zip"
TARGET_DIR="/tmp/cc_pve"

# --- Download and Extract ---------------------------------------------------
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

echo "Downloading repository ZIP from $REPO_ZIP_URL..."
if ! wget -q -O "$TARGET_DIR/repo.zip" "$REPO_ZIP_URL"; then
    echo "Error: Failed to download from $REPO_ZIP_URL"
    exit 1
fi

echo "Extracting ZIP..."
if ! unzip -q "$TARGET_DIR/repo.zip" -d "$TARGET_DIR"; then
    echo "Error: Failed to unzip the downloaded file."
    exit 1
fi

# Find the first extracted folder that isn't a dot-folder
BASE_EXTRACTED_DIR=$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" | head -n1)
if [ -z "$BASE_EXTRACTED_DIR" ]; then
    echo "Error: No extracted content found."
    exit 1
fi

echo "Repository extracted into: $BASE_EXTRACTED_DIR"

# --- Make Scripts Executable -----------------------------------------------
echo "Making all scripts executable..."
cd "$BASE_EXTRACTED_DIR" || exit 1
if [ -f "./MakeScriptsExecutable.sh" ]; then
    bash "./MakeScriptsExecutable.sh"
else
    echo "Warning: MakeScriptsExecutable.sh not found. Skipping."
fi

# --- Call CCPVEOffline.sh --------------------------------------------------
if [ -f "./CCPVEOffline.sh" ]; then
    echo "Calling CCPVEOffline.sh..."
    bash "./CCPVEOffline.sh"
else
    echo "Warning: CCPVEOffline.sh not found. Skipping."
fi

echo "Done."