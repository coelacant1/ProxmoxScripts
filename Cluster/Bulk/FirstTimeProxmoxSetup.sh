#!/bin/bash
#
# FirstTimeProxmoxSetup.sh
#
# This script performs initial setup for a Proxmox VE cluster:
#   1. Removes enterprise repositories (both Proxmox and Ceph enterprise repos).
#   2. Adds/Enables the free (no-subscription) repository, auto-detecting the
#      correct Debian/Proxmox codename (e.g., buster, bullseye, bookworm).
#   3. Disables the subscription nag for all nodes in the cluster.
#
# Usage:
#   ./FirstTimeProxmoxSetup.sh
#
# Example:
#   ./FirstTimeProxmoxSetup.sh
#
# Dependencies:
#   - scriptdir/Utilities/Utilities.sh (found via find_utilities_script).
#

###############################################################################
# Function to find and source the Utilities.sh script
###############################################################################
set -e

# ---------------------------------------------------------------------------
# @function find_utilities_script
# @description
#   Finds the root directory of the scripts folder by traversing upward until
#   it finds a folder containing "ProxmoxScripts" and a Utilities subfolder.
#   Returns the full path to Utilities/Utilities.sh if found, or exits with an
#   error if not found within 15 levels.
# @usage
#   UTILITIES_SCRIPT="$(find_utilities_script)" || exit 1
#   source "$UTILITIES_SCRIPT"
# ---------------------------------------------------------------------------
find_utilities_script() {
  # Check current directory first
  if [[ -d "./Utilities" ]]; then
    echo "./Utilities/Utilities.sh"
    return 0
  fi

  local rel_path=""
  for _ in {1..15}; do
    cd ..
    # If rel_path is empty, set it to '..' else prepend '../'
    if [[ -z "$rel_path" ]]; then
      rel_path=".."
    else
      rel_path="../$rel_path"
    fi

    if [[ -d "./Utilities" ]]; then
      echo "$rel_path/Utilities/Utilities.sh"
      return 0
    fi
  done

  echo "Error: Could not find 'Utilities' folder within 15 levels." >&2
  return 1
}

# ---------------------------------------------------------------------------
# Locate and source the Utilities script
# ---------------------------------------------------------------------------
UTILITIES_SCRIPT="$(find_utilities_script)" || exit 1
source "$UTILITIES_SCRIPT"

###############################################################################
# Preliminary Checks
###############################################################################
check_proxmox_and_root
check_cluster_membership

# Ensure required commands are installed or prompt user to install.
for cmd in ssh awk sed; do
    install_or_prompt "$cmd"
done

###############################################################################
# Functions
###############################################################################
setup_repositories() {
    echo "Setting up repositories on node: $(hostname)"

    # Remove the enterprise repository if it exists
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
        rm /etc/apt/sources.list.d/pve-enterprise.list
        echo " - Removed Proxmox enterprise repository."
    else
        echo " - Proxmox enterprise repository not found; skipping removal."
    fi

    # Remove Ceph enterprise repository if it exists
    if [[ -f /etc/apt/sources.list.d/ceph-enterprise.list ]]; then
        rm /etc/apt/sources.list.d/ceph-enterprise.list
        echo " - Removed Ceph enterprise repository."
    fi

    # Attempt to detect the codename from /etc/os-release
    local CODENAME="bullseye"
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        CODENAME="${VERSION_CODENAME:-bullseye}"
    else
        echo " - /etc/os-release not found. Defaulting to '${CODENAME}'."
    fi

    echo " - Detected codename: ${CODENAME}"

    # Check if the no-subscription repo is already in /etc/apt/sources.list
    if ! grep -q "deb http://download.proxmox.com/debian/pve ${CODENAME} pve-no-subscription" /etc/apt/sources.list; then
        echo "deb http://download.proxmox.com/debian/pve ${CODENAME} pve-no-subscription" >> /etc/apt/sources.list
        echo " - Added Proxmox no-subscription repository for '${CODENAME}'."
    else
        echo " - Proxmox no-subscription repository already present."
    fi
}

disable_subscription_nag() {
    echo "Disabling subscription nag on node: $(hostname)"
    # Patch the JavaScript file to disable the subscription message
    local JS_PATH="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    if [[ -f "$JS_PATH" ]]; then
        sed -i.bak "s/data.status !== 'Active'/false/g" "$JS_PATH"
        echo " - Subscription nag disabled."
    else
        echo " - Proxmox JavaScript file not found; skipping subscription nag removal."
    fi
}

###############################################################################
# Main Script Logic
###############################################################################
echo "Gathering remote node IPs..."
readarray -t REMOTE_NODES < <( get_remote_node_ips )

if [[ ${#REMOTE_NODES[@]} -eq 0 ]]; then
    echo " - No remote nodes detected; this might be a single-node setup."
fi

# Apply repository and subscription nag fixes on each remote node
for NODE_IP in "${REMOTE_NODES[@]}"; do
    echo "Connecting to node IP: $NODE_IP"
    ssh root@"$NODE_IP" "$(declare -f setup_repositories); setup_repositories"
    ssh root@"$NODE_IP" "$(declare -f disable_subscription_nag); disable_subscription_nag"
    echo " - Setup completed for node IP: $NODE_IP"
    echo
done

# Apply the setup locally
echo "Applying first-time setup on the local node..."
setup_repositories
disable_subscription_nag

echo "Proxmox first-time setup completed for all reachable nodes!"

###############################################################################
# Prompt to keep or remove packages installed during this session
###############################################################################
prompt_keep_installed_packages
