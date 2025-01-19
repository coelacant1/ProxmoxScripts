#!/bin/bash
#
# BulkAddSSHKey.sh
#
# This script adds an SSH public key to a range of virtual machines (VMs) 
# within a Proxmox VE environment. It appends a new SSH public key for each VM 
# and regenerates the Cloud-Init image to apply the changes.
#
# Usage:
#   ./BulkAddSSHKey.sh <start_vm_id> <end_vm_id> <ssh_public_key>
#
# Example:
#   # Adds the specified SSH key to all VMs with IDs between 400 and 430
#   ./BulkAddSSHKey.sh 400 430 "ssh-rsa AAAAB3Nza... user@host"
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Validate environment and arguments
###############################################################################
__check_root__
__check_proxmox__

if [ "$#" -ne 3 ]; then
  echo "Error: Wrong number of arguments." >&2
  echo "Usage: $0 <start_vm_id> <end_vm_id> <ssh_public_key>" >&2
  exit 1
fi

START_VM_ID="$1"
END_VM_ID="$2"
SSH_PUBLIC_KEY="$3"

###############################################################################
# Main logic
###############################################################################
for (( vmId=START_VM_ID; vmId<=END_VM_ID; vmId++ )); do
  if qm status "$vmId" &>/dev/null; then
    echo "Adding SSH public key to VM ID: $vmId"
    tempFile="$(mktemp)"
    qm cloudinit get "$vmId" ssh-authorized-keys > "$tempFile"
    echo "$SSH_PUBLIC_KEY" >> "$tempFile"
    qm set "$vmId" --sshkeys "$tempFile"
    rm "$tempFile"
    qm cloudinit dump "$vmId"
    echo " - SSH public key appended for VM ID: $vmId."
  else
    echo "VM ID: $vmId does not exist. Skipping..."
  fi
done

###############################################################################
# Wrap-up
###############################################################################
echo "SSH public key addition process completed!"
