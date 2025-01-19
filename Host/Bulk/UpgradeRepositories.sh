#!/bin/bash
#
# UpgradeRepositories.sh
#
# A script to:
#   1. Identify the **latest** stable Debian codename that Proxmox currently supports (by querying
#      http://download.proxmox.com/debian/pve/dists).
#   2. Update your local Proxmox repository configuration to use that codename (e.g., switch
#      from "buster" to "bullseye", or from "bullseye" to "bookworm") if it's different
#      from what you currently have.
#   3. Perform an apt-get update and apt-get dist-upgrade to pull the newest stable Proxmox
#      packages (excluding pvetest).
#
# Usage:
#   ./UpgradeRepositories.sh
#     - Automatically switches your Proxmox repo to the newest stable codename and runs dist-upgrade.
#
#   ./UpgradeRepositories.sh --dry-run
#     - Shows what changes would be made but does not apply them.
#
#   ./UpgradeRepositories.sh --help
#     - Prints this help message.
#
# Examples:
#   # Standard usage (updates local repo config to newest stable codename + dist-upgrade):
#   ./UpgradeRepositories.sh
#
#   # Check what would happen without making any changes:
#   ./UpgradeRepositories.sh --dry-run
#
# Description/Notes:
#   - "Latest" stable codename is determined by parsing the directory listing at:
#       http://download.proxmox.com/debian/pve/dists/
#     ignoring "pvetest" or "publickey" directories, then selecting the final entry (which
#     should be the newest stable release).
#
#   - The script overwrites or creates /etc/apt/sources.list.d/pve-latest.list with
#     the new codename if different from your existing config. This assumes a single
#     stable Proxmox repository file. If you use multiple .list files or have an enterprise
#     subscription, adjust accordingly.
#
#   - Make sure you have a valid snapshot/backup before switching to a new
#     distribution codename, especially for major version upgrades (e.g., from buster to bullseye).
#
#   - Always confirm your environment supports upgrading to the new major release, and
#     review official Proxmox documentation for recommended upgrade paths and caveats.
#
# Function Index:
#   - display_help
#   - get_latest_proxmox_codename
#   - ensure_latest_repo
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# Preliminary Checks via Utilities
###############################################################################
__check_root__
__check_proxmox__
__install_or_prompt__ "curl"
__check_cluster_membership__

###############################################################################
# Argument Parsing
###############################################################################
DRY_RUN=false

function display_help() {
  sed -n '2,/^# Examples:/p' "$0" | sed 's/^#//'
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      display_help
      exit 0
      ;;
    *)
      echo "Unknown argument: '$arg'"
      echo "Use --help for usage."
      exit 3
      ;;
  esac
done

###############################################################################
# Functions
###############################################################################

# ----------------------------------------------------------------------------
# get_latest_proxmox_codename
#   Queries http://download.proxmox.com/debian/pve/dists/ to find the newest
#   stable Proxmox codename by parsing out directories. Excludes "pvetest" and
#   "publickey". Assumes the final directory is the newest stable codename.
#   Prints the latest codename (e.g. "bullseye" or "bookworm"). Exits if none found.
# ----------------------------------------------------------------------------
get_latest_proxmox_codename() {
  local tmpfile
  tmpfile="$(mktemp)"

  curl -s "http://download.proxmox.com/debian/pve/dists/" > "$tmpfile"
  if [[ ! -s "$tmpfile" ]]; then
    echo "Error: Could not retrieve Proxmox 'dists' directory listing from the internet."
    rm -f "$tmpfile"
    exit 4
  fi

  local latestCodename
  latestCodename="$(
    grep -Po '(?<=href=")[^"]+(?=/")' "$tmpfile" \
      | egrep -v 'pvetest|publickey|^$' \
      | tail -n 1
  )"
  rm -f "$tmpfile"

  if [[ -z "$latestCodename" ]]; then
    echo "Error: Unable to parse a valid stable codename from Proxmox dists listing."
    exit 5
  fi

  echo "$latestCodename"
}

# ----------------------------------------------------------------------------
# ensure_latest_repo
#   Creates or updates /etc/apt/sources.list.d/pve-latest.list to reference
#   the specified Proxmox codename for the 'pve-no-subscription' repository.
# ----------------------------------------------------------------------------
ensure_latest_repo() {
  local latest="$1"
  local repoFile="/etc/apt/sources.list.d/pve-latest.list"
  local repoLine="deb http://download.proxmox.com/debian/pve '$latest' pve-no-subscription"

  if [[ ! -f "$repoFile" ]]; then
    echo "Proxmox stable repo file not found at '$repoFile'."
    if [[ "$DRY_RUN" == true ]]; then
      echo "[DRY-RUN] Would create '$repoFile' with:"
      echo "  $repoLine"
    else
      echo "Creating '$repoFile'..."
      echo "$repoLine" > "$repoFile"
    fi
    return
  fi

  if grep -Eq "^deb .*proxmox.com.* $latest .*pve-no-subscription" "$repoFile"; then
    echo "'$repoFile' already references the latest codename '$latest'. No change needed."
  else
    echo "Repository file exists but does not match the latest Proxmox codename '$latest'."
    if [[ "$DRY_RUN" == true ]]; then
      echo "[DRY-RUN] Would overwrite '$repoFile' with:"
      echo "  $repoLine"
    else
      echo "Overwriting '$repoFile' with new repo line for codename '$latest'..."
      echo "$repoLine" > "$repoFile"
    fi
  fi
}

###############################################################################
# Main Script Logic
###############################################################################
echo "Retrieving latest Proxmox stable codename from the internet..."
LATEST_CODENAME="$(get_latest_proxmox_codename)"
echo "Latest stable Proxmox codename is: '$LATEST_CODENAME'"

echo "Ensuring local repository file references '$LATEST_CODENAME'..."
ensure_latest_repo "$LATEST_CODENAME"

# Refresh package lists
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY-RUN] Would run: apt update"
else
  echo "Updating package lists..."
  apt update
fi

# Now run dist-upgrade to get the newest stable packages
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY-RUN] Would run: apt upgrade -y"
else
  echo "Performing dist-upgrade to pull the newest stable Proxmox packages..."
  apt upgrade -y
fi

echo "Repository check, upgrade, and potential distribution switch are complete."
echo "Script finished successfully."

__prompt_keep_installed_packages__
