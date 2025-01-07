#!/bin/bash
#
# ProxmoxEnableMicrocode.sh
#
# This script enables microcode updates for all nodes in a Proxmox VE cluster.
#
# Usage:
#   ./ProxmoxEnableMicrocode.sh
#
# Example:
#   ./ProxmoxEnableMicrocode.sh
#
# Description:
#   1. Checks prerequisites (root privileges, Proxmox environment, cluster membership).
#   2. Installs or prompts to install required commands (ssh, pvecm).
#   3. Enables microcode updates (intel-microcode, amd64-microcode) on each remote node
#      in the cluster via SSH.
#   4. Enables microcode updates on the local node.
#   5. Prompts whether to remove any newly installed packages afterward.
#
# Dependencies:
#   - Utilities/Utilities.sh
#     (Adjust the path if Utilities.sh is located elsewhere relative to this script.)
#

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

# --- Preliminary Checks ----------------------------------------------------
set -e
check_proxmox_and_root
check_cluster_membership

# Ensure required commands are installed or prompt user to install.
for cmd in ssh pvecm; do
    install_or_prompt "$cmd"
done

# --- Function to enable microcode updates ----------------------------------
enable_microcode() {
    echo "Enabling microcode updates on node: $(hostname)"
    apt-get update
    apt-get install -y intel-microcode amd64-microcode
    echo " - Microcode updates enabled."
}

# --- Main Script Logic -----------------------------------------------------
echo "Gathering remote node IPs..."
readarray -t REMOTE_NODES < <( get_remote_node_ips )

if [[ ${#REMOTE_NODES[@]} -eq 0 ]]; then
    echo " - No remote nodes detected; this might be a single-node cluster."
fi

# Enable microcode updates on each remote node
for NODE_IP in "${REMOTE_NODES[@]}"; do
    echo "Connecting to node: $NODE_IP"
    ssh root@"$NODE_IP" "$(declare -f enable_microcode); enable_microcode"
    echo " - Microcode update completed for node: $NODE_IP"
    echo
done

# Enable microcode updates on the local node
enable_microcode
echo "Microcode updates enabled on the local node."

# --- Prompt to keep or remove packages installed this session -------------
prompt_keep_installed_packages

echo "Microcode updates have been enabled on all nodes!"
