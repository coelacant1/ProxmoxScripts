#!/bin/bash
#
# This script updates the contents of the Proxmox scripts repository without replacing the top-level folder.
# It clones the repository into a temporary directory, clears the original folder's contents,
# and moves the new files into the original folder.
#
# Usage:
# ./UpdateProxmoxScripts.sh
#

# Variables
REPO_URL="https://github.com/coelacant1/proxmoxscripts"
REPO_NAME="proxmoxscripts"

# Ensure the script is run with root or equivalent permissions
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# Get the current directory
CURRENT_DIR=$(pwd)

# Ensure the script is being run from within the correct folder
if [[ "${CURRENT_DIR,,}" != *"${REPO_NAME,,}"* ]]; then
    echo "This script must be run from within the $REPO_NAME folder."
    exit 1
fi

# Create a temporary directory for cloning
TEMP_DIR=$(mktemp -d) || { echo "Failed to create a temporary directory"; exit 1; }

# Clone the repository into the temporary directory
echo "Cloning the repository into a temporary directory..."
git clone "$REPO_URL" "$TEMP_DIR/$REPO_NAME" || { echo "Failed to clone the repository"; exit 1; }

# Clear the current folder's contents (but not the folder itself)
echo "Clearing the contents of the current folder..."
find "$CURRENT_DIR" -mindepth 1 -delete || { echo "Failed to clear the folder contents"; exit 1; }

# Move new files into the current folder
echo "Moving updated files into the current folder..."
mv "$TEMP_DIR/$REPO_NAME/"* "$CURRENT_DIR" || { echo "Failed to move updated files"; exit 1; }
mv "$TEMP_DIR/$REPO_NAME/".* "$CURRENT_DIR" 2>/dev/null || true # Move hidden files, ignore errors

# Make the MakeScriptsExecutable.sh script executable
if [ -f "$CURRENT_DIR/MakeScriptsExecutable.sh" ]; then
    echo "Making MakeScriptsExecutable.sh executable..."
    chmod +x "$CURRENT_DIR/MakeScriptsExecutable.sh" || { echo "Failed to set executable permission"; exit 1; }

    # Run the MakeScriptsExecutable.sh script
    echo "Running MakeScriptsExecutable.sh..."
    "$CURRENT_DIR/MakeScriptsExecutable.sh" || { echo "Failed to execute MakeScriptsExecutable.sh"; exit 1; }
fi

# Clean up the temporary directory
rm -rf "$TEMP_DIR"

echo "Update completed successfully."
