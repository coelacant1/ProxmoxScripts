#!/bin/bash
#
# BulkAddSSHKey.sh
#
# This script appends an SSH public key to the root user's authorized_keys
# for a specified range of LXC containers (no existing keys are removed).
#
# Usage:
#   ./BulkAddSSHKey.sh <start_ct_id> <end_ct_id> "<ssh_public_key>"
#
# Example:
#   ./BulkAddSSHKey.sh 400 402 "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."
#
# Notes:
#   - Containers must be running for 'pct exec' to succeed.
#   - If you want to add keys for another user, replace '/root/.ssh' with that user’s home directory.
#   - This script must be run as root on a Proxmox node.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# MAIN
###############################################################################

# Parse arguments
if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <start_ct_id> <end_ct_id> \"<ssh_public_key>\""
  echo "Example:"
  echo "  $0 400 402 \"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...\""
  exit 1
fi

startCtId="$1"
endCtId="$2"
sshKey="$3"

# Basic checks
__check_root__
__check_proxmox__

echo "=== Starting SSH key addition for containers from \"$startCtId\" to \"$endCtId\" ==="
echo " - SSH key to append: \"$sshKey\""

# Main loop
for (( ctId=startCtId; ctId<=endCtId; ctId++ )); do
  if pct config "$ctId" &>/dev/null; then
    echo "Adding SSH key to container \"$ctId\"..."
    pct exec "$ctId" -- bash -c "
      mkdir -p /root/.ssh &&
      chmod 700 /root/.ssh &&
      echo \"$sshKey\" >> /root/.ssh/authorized_keys &&
      chmod 600 /root/.ssh/authorized_keys
    "
    if [[ $? -eq 0 ]]; then
      echo " - Successfully appended SSH key for CT \"$ctId\"."
    else
      echo " - Failed to append SSH key for CT \"$ctId\" (container stopped or other error?)."
    fi
  else
    echo " - Container \"$ctId\" does not exist. Skipping."
  fi
done

echo "=== Bulk SSH key addition process complete! ==="
