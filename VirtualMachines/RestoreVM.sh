#!/bin/bash
#
# RestoreVM.sh
#
# Lists available backups for a given VMID on a *source* storage, then prompts
# the user to select one for restore. If the backup is for a container
# (PBS or local LXC-style backup), it prompts whether to restore it as
# unprivileged and whether to ignore unpack errors. Finally, it restores
# to a specified *target* storage.
#
# Usage:
#   ./RestoreVM.sh <vmid> <source-storage> <target-storage>
#
# Examples:
#   # Restore backups for VMID 101 using 'IHKBackup' as source, restoring to 'local'
#   ./RestoreVM.sh 101 IHKBackup local
#
#   # Restore backups for VMID 113 using 'IHKBackup' as source, restoring to 'local-lvm'
#   ./RestoreVM.sh 113 IHKBackup local-lvm
#

source "${UTILITYPATH}/Prompts.sh"

check_root
check_proxmox

VMID="$1"
SOURCE_STORAGE="$2"
TARGET_STORAGE="$3"

###############################################################################
# Validate Input
###############################################################################
if [[ -z "$VMID"  -z "$SOURCE_STORAGE"  -z "$TARGET_STORAGE" ]]; then
  echo "Error: You must provide a VMID, a source storage, and a target storage."
  echo "Usage: $0 <vmid> <source-storage> <target-storage>"
  exit 1
fi

###############################################################################
# List Matching Backups (parse by matching the last column to the VMID)
###############################################################################
# 'pvesm list <source-storage> --content backup' output fields typically:
# 1) <STORAGE:backup/...>
# 2) <type, e.g. pbs-ct, pbs-vm, vma, ...>
# 3) <content, e.g. backup>
# 4) <size in bytes>
# 5) <VMID>
###############################################################################
mapfile -t backupLines < <(pvesm list "$SOURCE_STORAGE" --content backup | awk -v vmid="$VMID" '$NF == vmid')

if [[ ${#backupLines[@]} -eq 0 ]]; then
  echo "Error: No matching backups found for VMID \"$VMID\" on storage \"$SOURCE_STORAGE\"."
  exit 1
fi

echo "Available Backups:"
declare -a BACKUPS
idx=0
for line in "${backupLines[@]}"; do
  backupPath="$(awk '{print $1}' <<< "$line")"
  BACKUPS+=("$backupPath")
  echo "$idx) $backupPath"
  ((idx++))
done

read -rp "Select a backup index to restore: " selIndex
if [[ -z "$selIndex"  "$selIndex" -lt 0  "$selIndex" -ge ${#BACKUPS[@]} ]]; then
  echo "Invalid selection."
  exit 1
fi

selectedBackup="${BACKUPS[$selIndex]}"

###############################################################################
# Determine if Backup is Container or VM and Perform Restore
###############################################################################
typeOfBackup="$(awk '{print $2}' <<< "${backupLines[$selIndex]}")"

if [[ "$typeOfBackup" == *"ct"* || "$selectedBackup" == *"/ct/"* ]]; then
  read -rp "Restore container as unprivileged? (y/n): " unprivChoice
  read -rp "Ignore unpack errors? (y/n): " ignoreUnpackChoice

  pctCmd=( pct restore "$VMID" "$selectedBackup" --storage "$TARGET_STORAGE" )
  if [[ "$unprivChoice" == "y" ]]; then
    pctCmd+=( --unprivileged 1 )
  else
    pctCmd+=( --unprivileged 0 )
  fi
  if [[ "$ignoreUnpackChoice" == "y" ]]; then
    pctCmd+=( --ignore-unpack-errors )
  fi

  "${pctCmd[@]}"
else
  qmrestore "$selectedBackup" "$VMID" --storage "$TARGET_STORAGE"
fi

echo "Restore complete."
