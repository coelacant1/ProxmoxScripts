#!/bin/bash
#
# DisableHAOnNode.sh
#
# This script disables High Availability (HA) on a single Proxmox node by:
#   1. Disabling or removing any HA resources tied to this node.
#   2. Stopping and disabling the HA services (pve-ha-crm, pve-ha-lrm) on the node.
#
# Usage:
#   ./DisableHAOnNode.sh <node_name>
#
# Example:
#   ./DisableHAOnNode.sh pve-node2
#
# Notes:
#   - If you're using a multi-node cluster, ensure that no critical HA resources rely on this node.
#   - A single-node "cluster" does not benefit from HA, so this script effectively cleans up HA configs.
#   - This script expects passwordless SSH or valid root credentials for the target node.
#   - You must run this script as root on a Proxmox node that is part of the same cluster as <node_name>.
#

set -e

# -----------------------------------------------------------------------------
# @function find_utilities_script
# @description
#   Finds the root directory of the scripts folder by traversing upward until
#   it finds a folder containing a Utilities subfolder.
#   Returns the full path to Utilities/Utilities.sh if found, or exits with an
#   error if not found within 15 levels.
# -----------------------------------------------------------------------------
find_utilities_script() {
  # Check current directory first
  if [[ -d "./Utilities" ]]; then
    echo "./Utilities"
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
      echo "$rel_path/Utilities"
      return 0
    fi
  done

  echo "Error: Could not find 'Utilities' folder within 15 levels." >&2
  exit 1
}

###############################################################################
# LOCATE AND SOURCE UTILITIES
###############################################################################
UTILITIES_DIR="$(find_utilities_script)"
# shellcheck source=/dev/null
source "${UTILITIES_DIR}/Utilities.sh"

###############################################################################
# MAIN
###############################################################################
main() {
  # 1. Validate input
  if [[ -z "$1" ]]; then
    echo "Usage: $0 <node_name>"
    echo "Example: $0 pve-node2"
    exit 1
  fi
  local target_node_name="$1"

  # 2. Basic checks
  check_proxmox_and_root    # Must be root and on a Proxmox node
  check_cluster_membership  # Ensure this machine is in a cluster

  # 3. Ensure required commands are installed
  install_or_prompt "jq"
  install_or_prompt "ssh"

  echo "=== Disabling HA on node: $target_node_name ==="

  # 4. Convert node name to IP for SSH calls
  #    (If the user provided an IP already, get_ip_from_name still works but may fail if
  #     there's no matching entry. In that case, you can bypass or handle errors as needed.)
  echo "=== Resolving IP address for node '$target_node_name' ==="
  node_ip=""
  if ! node_ip="$(get_ip_from_name "$target_node_name")"; then
    echo "Error: Could not resolve node name '$target_node_name' to an IP."
    exit 1
  fi
  echo " - Node '$target_node_name' resolved to IP: $node_ip"
  echo

  # 5. Identify HA resources referencing this node by name.
  #    This uses 'pvesh get /cluster/ha/resources' + 'jq' to filter resources
  #    that have the node name in 'statePath'. Adjust if you prefer a different filter.
  echo "=== Checking for HA resources on node '$target_node_name'... ==="
  ha_resources="$(pvesh get /cluster/ha/resources --output-format json \
                 | jq -r '.[] | select(.statePath | contains("'"$target_node_name"'")) | .sid')"

  if [[ -z "$ha_resources" ]]; then
    echo " - No HA resources found referencing node '$target_node_name'."
  else
    echo " - Found HA resources referencing node '$target_node_name':"
    echo "$ha_resources"
    echo
    # Remove these HA resources
    for res in $ha_resources; do
      echo "Removing HA resource $res ..."
      if pvesh delete "/cluster/ha/resources/${res}"; then
        echo " - Successfully removed HA resource: $res"
      else
        echo " - Failed to remove HA resource: $res"
      fi
      echo
    done
  fi

  # 6. Stop and disable HA services on the target node
  echo "=== Stopping and disabling HA services on node '$target_node_name' ==="
  echo "Stopping pve-ha-crm and pve-ha-lrm on IP: $node_ip ..."
  ssh "root@${node_ip}" "systemctl stop pve-ha-crm pve-ha-lrm"

  echo "Disabling pve-ha-crm and pve-ha-lrm on IP: $node_ip ..."
  ssh "root@${node_ip}" "systemctl disable pve-ha-crm pve-ha-lrm"

  echo "=== HA has been disabled on node: $target_node_name (IP: $node_ip) ==="
  echo "You can verify via: ssh root@${node_ip} 'systemctl status pve-ha-crm pve-ha-lrm'"
  echo

  # 7. Prompt to remove any packages installed during this session
  prompt_keep_installed_packages
}

# -----------------------------------------------------------------------------
# Run the main function
# -----------------------------------------------------------------------------
main
