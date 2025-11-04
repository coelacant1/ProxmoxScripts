#!/bin/bash
#
# FirstTimeProxmoxSetup.sh
#
# This script performs initial setup for a Proxmox VE cluster:
#   1. Removes enterprise repositories (both Proxmox and Ceph enterprise repos).
#   2. Adds/enables the free (no-subscription) repository, auto-detecting the
#      correct Debian/Proxmox codename (e.g., buster, bullseye, bookworm).
#   3. Disables the subscription nag for all nodes in the cluster.
#
# Usage:
#   FirstTimeProxmoxSetup.sh
#
# Example:
#   FirstTimeProxmoxSetup.sh
#
# Further details:
#   This script will attempt to gather the IP addresses of all remote nodes in
#   the cluster and apply repository changes/disable nag screens on each one.
#   It then applies the same changes locally. At the end of the process,
#   it will prompt whether to keep or remove any packages installed during this
#   session (if any).
#
# Function Index:
#   - setup_repositories
#   - disable_subscription_nag
#

set -euo pipefail

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# Preliminary Checks
###############################################################################
__check_root__
__check_proxmox__
__check_cluster_membership__

ceph_version="ceph-squid"

###############################################################################
# Functions
###############################################################################
setup_repositories() {
    echo "Setting up repositories on node: \"$(hostname)\""

    # Remove the Proxmox enterprise repository if it exists
    if [[ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]]; then
        rm "/etc/apt/sources.list.d/pve-enterprise.list"
        echo " - Removed Proxmox enterprise repository."
    else
        echo " - Proxmox enterprise repository not found; skipping removal."
    fi

    # Remove the Ceph enterprise repository if it exists
    if [[ -f "/etc/apt/sources.list.d/ceph.list" ]]; then
        rm "/etc/apt/sources.list.d/ceph.list"
        echo " - Removed Ceph enterprise repository."
    fi

    # Attempt to detect the codename from /etc/os-release
    local codename="bookworm"
    if [[ -f "/etc/os-release" ]]; then
        # shellcheck source=/dev/null
        . "/etc/os-release"
        codename="${VERSION_CODENAME:-bookworm}"
    else
        echo " - /etc/os-release not found. Defaulting to \"${codename}\"."
    fi

    echo " - Detected codename: \"${codename}\""

    # Check if the no-subscription repo is already in /etc/apt/sources.list
    if ! grep -q "deb http://download.proxmox.com/debian/pve ${codename} pve-no-subscription" "/etc/apt/sources.list"; then
        echo "deb http://download.proxmox.com/debian/pve ${codename} pve-no-subscription" >> "/etc/apt/sources.list"
        echo " - Added Proxmox no-subscription repository for \"${codename}\"."
    else
        echo " - Proxmox no-subscription repository already present."
    fi

    # Check if the no-subscription repo is already in /etc/apt/sources.list.d/ceph.list
    if ! grep -q "deb http://download.proxmox.com/debian/${ceph_version} ${codename} no-subscription" "/etc/apt/sources.list.d/ceph.list"; then
        echo "deb http://download.proxmox.com/debian/${ceph_version} ${codename} no-subscription" >> "/etc/apt/sources.list.d/ceph.list"
        echo " - Added Ceph no-subscription repository for \"${codename}\"."
    else
        echo " - Ceph no-subscription repository already present."
    fi
}

disable_subscription_nag() {
    echo "Disabling subscription nag on node: \"$(hostname)\""
    local jsPath="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

    if [[ -f "${jsPath}" ]]; then
        sed -i.bak "s/data.status !== 'Active'/false/g" "${jsPath}"
        echo " - Subscription nag disabled."
    else
        echo " - Proxmox JavaScript file not found; skipping subscription nag removal."
    fi
}

###############################################################################
# Main Script Logic
###############################################################################
echo "Gathering remote node IPs..."
readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )

if [[ "${#REMOTE_NODES[@]}" -eq 0 ]]; then
    echo " - No remote nodes detected; this might be a single-node setup."
fi

# Apply repository and subscription nag fixes on each remote node
for nodeIp in "${REMOTE_NODES[@]}"; do
    echo "Connecting to node IP: \"${nodeIp}\""
    ssh root@"${nodeIp}" "$(declare -f setup_repositories); setup_repositories"
    ssh root@"${nodeIp}" "$(declare -f disable_subscription_nag); disable_subscription_nag"
    echo " - Setup completed for node IP: \"${nodeIp}\""
    echo
done

# Apply the setup locally
echo "Applying first-time setup on the local node..."
setup_repositories
disable_subscription_nag

echo "Proxmox first-time setup completed for all reachable nodes!"

###############################################################################
# Prompt to keep or remove packages installed during this session
###############################################################################
__prompt_keep_installed_packages__

###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
