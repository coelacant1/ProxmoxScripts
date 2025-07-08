#!/bin/bash
#
# RestartMetadata.sh
#
# Restarts every Ceph Metadata Server (MDS) on the cluster one at a time.
#
# Usage:
#   ./RestartMetadata.sh
#
# This script retrieves Ceph MDS information in JSON format, parses each MDS's
# name and address, and restarts the corresponding MDS service (ceph-mds@<mdsName>).
# If the MDS is hosted on a remote node, the restart and subsequent check for
# active status are executed via SSH.
#

source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# Check prerequisites: root privileges and Proxmox environment
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Ensure required commands are installed
###############################################################################
__install_or_prompt__ "jq"

###############################################################################
# Retrieve Ceph filesystem information in JSON format
###############################################################################
fsJSON=$(ceph fs dump --format json 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$fsJSON" ]; then
    __err__ "Failed to retrieve Ceph filesystem dump. Ensure Ceph is running."
    exit 1
fi

###############################################################################
# Parse active and standby MDS details from the filesystem dump
###############################################################################
# Active MDS details are under "filesystems[].mdsmap.info" (an object, convert to array)
# Standby MDS details are in the top-level "standbys" array.
#
# Each line output is in the format: "mdsName mdsAddr"
#
# Note: The address is of the format IP:port/nonce. We extract the IP before the first colon.
mdsInfo=$(
  {
    echo "$fsJSON" | jq -r '.filesystems[] | .mdsmap.info | to_entries[] | "\(.value.name) \(.value.addr)"'
    echo "$fsJSON" | jq -r '.standbys[] | "\(.name) \(.addr)"'
  }
)

declare -a mdsNames
declare -a mdsIPs

while read -r name addr; do
    # Extract the IP portion from the address (the part before the first colon)
    mdsIP="${addr%%:*}"
    # If the MDS name is missing or "null", try resolving it from the IP.
    if [ -z "$name" ] || [ "$name" = "null" ]; then
        name="$(__get_name_from_ip__ "$mdsIP")"
    fi
    mdsNames+=("$name")
    mdsIPs+=("$mdsIP")
done <<< "$mdsInfo"

totalMDS="${#mdsNames[@]}"
if [ "$totalMDS" -eq 0 ]; then
    __info__ "No Ceph Metadata Servers found. Exiting."
    exit 0
fi

__info__ "Found ${totalMDS} Ceph Metadata Server(s). Restarting them one at a time."

###############################################################################
# Function: is_local_ip
# Checks if the provided IP address belongs to the local system.
###############################################################################
is_local_ip(){
    local ipToCheck="$1"
    local localIPs
    local ip
    localIPs=$(hostname -I)
    for ip in $localIPs; do
        if [ "$ip" = "$ipToCheck" ]; then
            return 0
        fi
    done
    return 1
}

###############################################################################
# Function: wait_for_mds_active
# Waits until the ceph-mds@<mdsName> service is active on the specified target host
# (local or remote), or until a timeout (120 seconds) is reached.
###############################################################################
wait_for_mds_active(){
    local targetHost="$1"
    local mdsName="$2"
    local timeout=120
    local elapsed=0
    local status=""
    while true; do
        if [ "$targetHost" = "local" ]; then
            status=$(systemctl is-active "ceph-mds@${mdsName}")
        else
            status=$(ssh root@"${targetHost}" "systemctl is-active ceph-mds@${mdsName}" 2>/dev/null)
        fi
        if [ "$status" = "active" ]; then
            break
        fi
        sleep 5
        elapsed=$((elapsed+5))
        if [ $elapsed -ge $timeout ]; then
            __err__ "MDS ceph-mds@${mdsName} did not become active after restart on ${targetHost}."
            break
        fi
    done
}

###############################################################################
# Loop through each MDS, determine if it's local or remote, restart it,
# and wait until its service becomes active.
###############################################################################
currentMDS=1
for index in "${!mdsNames[@]}"; do
    mdsName="${mdsNames[$index]}"
    mdsIP="${mdsIPs[$index]}"

    __update__ "Processing MDS ${currentMDS} of ${totalMDS}: ceph-mds@${mdsName}"

    # Determine the target host: if the MDS IP is one of the local IPs, it's local.
    if is_local_ip "$mdsIP"; then
        targetHost="local"
    else
        # Attempt to resolve the node IP using the MDS name via the node mappings.
        targetHost="$(__get_ip_from_name__ "$mdsName")"
        if [ -z "$targetHost" ]; then
            # Fall back to the extracted MDS IP if resolution fails.
            targetHost="$mdsIP"
        fi
    fi

    # Restart the MDS service on the appropriate host.
    if [ "$targetHost" = "local" ]; then
        systemctl restart "ceph-mds@${mdsName}"
        if [ $? -eq 0 ]; then
            __ok__ "Successfully restarted ceph-mds@${mdsName} on local."
        else
            __err__ "Failed to restart ceph-mds@${mdsName} on local."
        fi
    else
        ssh root@"${targetHost}" "systemctl restart ceph-mds@${mdsName}"
        if [ $? -eq 0 ]; then
            __ok__ "Successfully restarted ceph-mds@${mdsName} on ${targetHost}."
        else
            __err__ "Failed to restart ceph-mds@${mdsName} on ${targetHost}."
        fi
    fi

    # Wait until the MDS service is active on the target host.
    wait_for_mds_active "${targetHost}" "${mdsName}"

    sleep 5
    currentMDS=$((currentMDS+1))
done

__ok__ "All Ceph Metadata Servers processed."
