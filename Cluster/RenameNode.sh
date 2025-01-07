#!/bin/bash
#
# RenameNode.sh
#
# This script runs on an existing Proxmox cluster node (with quorum)
# and renames another node from <oldnode> to <newnode>.
#
# Steps:
#   1) Verify no VMs/LXCs on <oldnode>.
#   2) pvecm delnode <oldnode> (remove from cluster membership).
#   3) Clean up cluster references (SSH known hosts, /etc/pve/nodes/<oldnode>, etc.).
#   4) SSH into <oldnode> and rename to <newnode>, remove cluster config, reboot.
#
# Usage:
#   ./RenameNode.sh <oldnodename> <newnodename>
#
# Requirements:
#   - You should have SSH access from this cluster node to <oldnode>.
#   - The cluster node running this script should have 'pvecm' and 'pvesh'.
#   - <oldnode> must NOT have VMs or containers (or script will refuse).
#   - The cluster must have quorum (especially if more than 2 nodes).
#
# After reboot, <oldnode> is now <newnode> and is standalone. You can re-add it
# to the cluster with "pvecm add <existing-cluster-IP>" or your own join script.

set -e

# ---------------------------------------------------------------------------
# @function find_utilities_script
# @description
#   Finds the root directory of the scripts folder by traversing upward until
#   it finds a folder containing a Utilities subfolder.
#   Returns the full path to Utilities/Utilities.sh if found, or exits with an
#   error if not found within 15 levels.
# ---------------------------------------------------------------------------
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
  return 1
}

###############################################################################
# Locate and source the Utilities script
###############################################################################
UTILITIES_DIR="$(find_utilities_script)"
source "${UTILITIES_DIR}/Utilities.sh"

###############################################################################
# Preliminary Checks via Utilities
###############################################################################
check_proxmox_and_root         # Ensure we're root on a valid Proxmox node
install_or_prompt "jq"         # Needed to parse JSON from pvesh
install_or_prompt "ssh"        # Required to SSH into old node
check_cluster_membership       # Ensure we have a recognized cluster membership

# Prompt to optionally remove newly installed packages upon script exit
trap prompt_keep_installed_packages EXIT

###############################################################################
# Helper: Usage
###############################################################################
usage() {
  echo "Usage: $0 <oldnode> <newnode>"
  exit 1
}

###############################################################################
# Parse Arguments
###############################################################################
OLDNODE="$1"
NEWNODE="$2"
if [[ -z "$OLDNODE" || -z "$NEWNODE" ]]; then
  usage
fi

echo "Renaming Proxmox node from '$OLDNODE' to '$NEWNODE'..."

###############################################################################
# 1) Check if <oldnode> has VMs or containers
###############################################################################
echo "Checking for VMs or containers on '$OLDNODE'..."
VM_LIST=$(
  pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
  | jq -r --arg N "$OLDNODE" '.[] | select(.node == $N) | "VMID:\(.vmid) Type:\(.type)"'
)

if [[ -n "$VM_LIST" ]]; then
  echo "Error: The following VMs/containers are still on node '$OLDNODE':"
  echo "$VM_LIST"
  echo "Please migrate or remove them first before renaming."
  exit 3
fi

###############################################################################
# 2) Remove <oldnode> from cluster membership
###############################################################################
echo "Removing node '$OLDNODE' from the cluster..."
if ! pvecm delnode "$OLDNODE"; then
  echo "Warning: 'pvecm delnode' may fail if '$OLDNODE' was already removed."
  echo "Continuing cleanup..."
fi

###############################################################################
# 3) Clean up cluster references to <oldnode>
###############################################################################
# Remove /etc/pve/nodes/<oldnode> if it still exists locally.
LOCAL_OLDNODE_DIR="/etc/pve/nodes/$OLDNODE"
if [[ -d "$LOCAL_OLDNODE_DIR" ]]; then
  echo "Removing local cluster dir $LOCAL_OLDNODE_DIR ..."
  rm -rf "$LOCAL_OLDNODE_DIR"
fi

# Also remove SSH known_hosts references to <oldnode> on this node
echo "Removing '$OLDNODE' from local known_hosts..."
ssh-keygen -R "$OLDNODE" 2>/dev/null || true
ssh-keygen -R "${OLDNODE}.local" 2>/dev/null || true

# Optionally remove from /etc/ssh/ssh_known_hosts
if [[ -f /etc/ssh/ssh_known_hosts ]]; then
  sed -i "/$OLDNODE/d" /etc/ssh/ssh_known_hosts || true
fi

###############################################################################
# 4) SSH into <oldnode>, rename system to <newnode>, remove local cluster config, reboot
###############################################################################
echo
echo "Now SSHing into '$OLDNODE' to rename it to '$NEWNODE' and remove local cluster config..."
SSH_CMD="ssh -o StrictHostKeyChecking=no root@${OLDNODE}"

# We'll run a sequence of commands on <oldnode>:
read -r -d '' REMOTE_SCRIPT <<EOF
#!/bin/bash
set -e

echo "Setting hostname to '$NEWNODE'..."
hostnamectl set-hostname "$NEWNODE"

# If you rely on /etc/hosts, update it. We'll do a simple in-place replace:
if grep -q "$OLDNODE" /etc/hosts; then
  echo "Replacing '$OLDNODE' with '$NEWNODE' in /etc/hosts..."
  sed -i "s/$OLDNODE/$NEWNODE/g" /etc/hosts
fi

echo "Stopping cluster services on '$OLDNODE'..."
systemctl stop corosync || true
systemctl stop pve-cluster || true

echo "Removing local corosync config..."
rm -f /etc/pve/corosync.conf 2>/dev/null || true
rm -rf /etc/corosync/* 2>/dev/null || true

echo "Removing local /etc/pve/nodes/$OLDNODE..."
rm -rf /etc/pve/nodes/$OLDNODE 2>/dev/null || true

echo "Restarting pve-cluster in standalone mode..."
systemctl start pve-cluster || true

echo "Disabling corosync from autostart..."
systemctl disable corosync || true
systemctl stop corosync || true

echo
echo "Rebooting now to finalize rename..."
sleep 2
reboot
EOF

echo "============================================================="
echo " Running remote rename + cleanup commands on '$OLDNODE'..."
echo "============================================================="
if ! echo "$REMOTE_SCRIPT" | $SSH_CMD bash; then
  echo
  echo "ERROR: Remote script failed. Please check connectivity or logs on '$OLDNODE'."
  exit 4
fi

echo
echo "============================================================="
echo " The node '$OLDNODE' is rebooting and will come up as '$NEWNODE'."
echo " After it boots, it will be a standalone Proxmox host named '$NEWNODE'."
echo
echo " You can re-add it to a cluster with your usual 'pvecm add' steps or scripts."
echo "============================================================="
