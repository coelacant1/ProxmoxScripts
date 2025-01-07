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
check_proxmox_and_root              # Must be root on a Proxmox node
install_or_prompt "curl"            # Needed to query latest stable codename
check_cluster_membership            # Confirm node is in a Proxmox cluster

# Prompt to possibly remove installed packages at script exit
trap prompt_keep_installed_packages EXIT

###############################################################################
# Argument Parsing
###############################################################################
DRY_RUN=false

function display_help() {
  sed -n '2,/^# --- Preliminary/p' "$0" | sed 's/^#//'
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
      echo "Unknown argument: $arg"
      echo "Use --help for usage."
      exit 3
      ;;
  esac
done

###############################################################################
# Functions
###############################################################################

# ----------------------------------------------------------------------------
# @function get_latest_proxmox_codename
# @description
#   Queries http://download.proxmox.com/debian/pve/dists/ and finds the newest 
#   stable Proxmox codename by parsing out directories. Excludes "pvetest" and 
#   "publickey". Assumes the final directory is the newest stable codename.
# @return
#   Prints the latest codename to stdout (e.g. "bullseye" or "bookworm").
#   Exits if no valid codename is found or if the curl operation fails.
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

  # Extract directory names from the HTML listing:
  #   Looks for <a href="buster/"> etc. Then filters out "pvetest" and "publickey"
  local latest_codename
  latest_codename="$(
    grep -Po '(?<=href=")[^"]+(?=/")' "$tmpfile" \
    | egrep -v 'pvetest|publickey|^$' \
    | tail -n 1
  )"

  rm -f "$tmpfile"

  if [[ -z "$latest_codename" ]]; then
    echo "Error: Unable to parse a valid stable codename from Proxmox dists listing."
    exit 5
  fi

  echo "$latest_codename"
}

# ----------------------------------------------------------------------------
# @function ensure_latest_repo
# @description
#   Creates or updates /etc/apt/sources.list.d/pve-latest.list to reference 
#   the specified Proxmox codename for the 'pve-no-subscription' repository.
# @param 1 The latest Proxmox codename (e.g. "bullseye").
# ----------------------------------------------------------------------------
ensure_latest_repo() {
  local latest="$1"
  local repo_file="/etc/apt/sources.list.d/pve-latest.list"
  local repo_line="deb http://download.proxmox.com/debian/pve $latest pve-no-subscription"

  # If file doesn't exist, create it
  if [[ ! -f "$repo_file" ]]; then
    echo "Proxmox stable repo file not found at $repo_file."
    if [[ "$DRY_RUN" == true ]]; then
      echo "[DRY-RUN] Would create $repo_file with:"
      echo "  $repo_line"
    else
      echo "Creating $repo_file..."
      echo "$repo_line" > "$repo_file"
    fi
    return
  fi

  # If file exists, check if it already references the same codename
  if grep -Eq "^deb .*proxmox.com.* $latest .*pve-no-subscription" "$repo_file"; then
    echo "The $repo_file already references the latest codename '$latest'. No change needed."
  else
    # Otherwise, we rewrite the file
    echo "Repository file exists but does not match the latest Proxmox codename '$latest'."
    if [[ "$DRY_RUN" == true ]]; then
      echo "[DRY-RUN] Would overwrite $repo_file with:"
      echo "  $repo_line"
    else
      echo "Overwriting $repo_file with new repo line for codename '$latest'..."
      echo "$repo_line" > "$repo_file"
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
