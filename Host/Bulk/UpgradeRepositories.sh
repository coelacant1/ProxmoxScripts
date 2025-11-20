#!/bin/bash
#
# UpgradeRepositories.sh
#
# Updates Proxmox repository to latest stable Debian codename and performs upgrade.
# Queries download.proxmox.com to determine newest stable release.
#
# Usage:
#   UpgradeRepositories.sh [--dry-run]
#
# Arguments:
#   --dry-run - Show changes without applying them
#
# Examples:
#   UpgradeRepositories.sh
#   UpgradeRepositories.sh --dry-run
#
# Function Index:
#   - get_latest_proxmox_codename
#   - ensure_latest_repo
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "--dry-run:flag" "$@"

# --- get_latest_proxmox_codename ---------------------------------------------
get_latest_proxmox_codename() {
    local tmpfile
    tmpfile=$(mktemp)

    if ! curl -s "http://download.proxmox.com/debian/pve/dists/" >"$tmpfile"; then
        __err__ "Could not retrieve Proxmox dists directory"
        rm -f "$tmpfile"
        exit 1
    fi

    local latest_codename
    latest_codename=$(
        grep -Po '(?<=href=")[^"]+(?=/")' "$tmpfile" \
            | grep -Ev 'pvetest|publickey|^$' \
            | tail -n 1
    )
    rm -f "$tmpfile"

    if [[ -z "$latest_codename" ]]; then
        __err__ "Unable to parse valid stable codename"
        exit 1
    fi

    echo "$latest_codename"
}

# --- ensure_latest_repo ------------------------------------------------------
ensure_latest_repo() {
    local latest="$1"
    local repo_file="/etc/apt/sources.list.d/pve-latest.list"
    local repo_line="deb http://download.proxmox.com/debian/pve $latest pve-no-subscription"

    if [[ ! -f "$repo_file" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            __info__ "[DRY-RUN] Would create $repo_file"
        else
            __info__ "Creating $repo_file"
            echo "$repo_line" >"$repo_file"
            __ok__ "Repository file created"
        fi
        return
    fi

    if grep -Eq "^deb .*proxmox.com.* $latest .*pve-no-subscription" "$repo_file"; then
        __ok__ "Repository already references latest codename: $latest"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            __info__ "[DRY-RUN] Would update $repo_file to codename: $latest"
        else
            __info__ "Updating repository to codename: $latest"
            echo "$repo_line" >"$repo_file"
            __ok__ "Repository updated"
        fi
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "curl"
    __check_cluster_membership__

    __warn__ "This will update Proxmox repositories and perform system upgrade"
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! __prompt_user_yn__ "Proceed with repository upgrade?"; then
            __info__ "Operation cancelled"
            exit 0
        fi
    else
        __info__ "Dry-run mode enabled"
    fi

    __info__ "Retrieving latest Proxmox stable codename"
    local latest_codename
    latest_codename=$(get_latest_proxmox_codename)
    __ok__ "Latest stable codename: $latest_codename"

    __info__ "Updating repository configuration"
    ensure_latest_repo "$latest_codename"

    # Update package lists
    if [[ "$DRY_RUN" == "true" ]]; then
        __info__ "[DRY-RUN] Would run: apt update"
        __info__ "[DRY-RUN] Would run: apt dist-upgrade -y"
    else
        __info__ "Updating package lists"
        if apt-get update -qq 2>&1; then
            __ok__ "Package lists updated"
        else
            __err__ "Failed to update package lists"
            exit 1
        fi

        __info__ "Performing system upgrade"
        if apt-get dist-upgrade -y 2>&1; then
            __ok__ "System upgraded successfully"
        else
            __err__ "Failed to upgrade system"
            exit 1
        fi
    fi

    echo
    __ok__ "Repository upgrade completed successfully!"
    __info__ "Verify with: apt-cache policy pve-manager"

    __prompt_keep_installed_packages__
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Pending validation
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

