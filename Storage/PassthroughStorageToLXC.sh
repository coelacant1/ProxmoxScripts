#!/bin/bash
#
# PassthroughStorageToLXC.sh
#
# A script to pass through a host directory into one or more LXC containers for shared storage.
# It will automatically detect whether each container is unprivileged and convert it to privileged
# if necessary, then mount the specified host directory inside the container with the given permissions.
#
# Usage:
#   ./PassthroughStorageToLXC.sh <host-directory> <permission> <container-IDs...>
#
# Example:
#   # Mounts /mnt/data with read-write permissions into containers 101 and 102
#   ./PassthroughStorageToLXC.sh /mnt/data rw 101 102
#
#   # Mounts /mnt/logs with read-only permissions into containers 101, 102, and 103
#   ./PassthroughStorageToLXC.sh /mnt/logs ro 101 102 103
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Pre-Execution Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Parse Arguments
###############################################################################
if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <host-directory> <permission> <container-IDs...>"
  echo "Example: $0 /mnt/data rw 101 102"
  exit 1
fi

HOST_DIRECTORY="$1"
MOUNT_PERMISSION="$2"
shift 2
CONTAINERS=("$@")

if [[ ! -d "$HOST_DIRECTORY" ]]; then
  echo "Error: Host directory \"$HOST_DIRECTORY\" does not exist."
  exit 2
fi

if [[ "$MOUNT_PERMISSION" != "ro" && "$MOUNT_PERMISSION" != "rw" ]]; then
  echo "Error: Permission must be either \"ro\" or \"rw\"."
  exit 3
fi

roFlag=0
if [[ "$MOUNT_PERMISSION" == "ro" ]]; then
  roFlag=1
fi

###############################################################################
# Main Logic
###############################################################################
for CTID in "${CONTAINERS[@]}"; do
  echo "Processing container ID: \"$CTID\"..."

  if ! pct status "$CTID" &>/dev/null; then
    echo "Warning: LXC container \"$CTID\" not found. Skipping."
    continue
  fi

  unprivilegedSetting="$(pct config "$CTID" | awk '/^unprivileged:/ {print $2}')"
  if [[ "$unprivilegedSetting" == "1" ]]; then
    echo "Container \"$CTID\" is unprivileged. Converting to privileged..."
    pct set "$CTID" -unprivileged 0 --force
    echo "Stopping container \"$CTID\" to apply changes..."
    pct stop "$CTID"
    echo "Starting container \"$CTID\" after privilege change..."
    pct start "$CTID"
  fi

  mountPoint="/mnt/$(basename "$HOST_DIRECTORY")"
  nextMpIndex=0
  while pct config "$CTID" | grep -q "^mp${nextMpIndex}:"; do
    ((nextMpIndex++))
  done

  echo "Mounting \"$HOST_DIRECTORY\" at \"$mountPoint\" (ro=$roFlag) in container \"$CTID\"..."
  pct set "$CTID" -mp${nextMpIndex} "${HOST_DIRECTORY},mp=${mountPoint},ro=${roFlag},backup=0"

  echo "Successfully mounted in container \"$CTID\"."
  echo "------------------------------------------------------"
done

echo "All specified containers processed. Done."
