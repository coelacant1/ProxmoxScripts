#!/bin/bash
#
# RestartMonitors.sh
#
# Restarts every Ceph Monitor (mon) on the cluster one at a time.
#
# Usage:
#   ./RestartMonitors.sh
#
# This script retrieves the Ceph monitor information from the cluster and
# restarts each monitor service sequentially from the main node. The service
# names use the format ceph-mon@<nodeName>.
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
# Retrieve Ceph monitor information in JSON format
###############################################################################
monJSON=$(ceph mon dump --format json 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$monJSON" ]; then
    __err__ "Failed to retrieve Ceph monitor dump. Ensure Ceph is running."
    exit 1
fi

###############################################################################
# Parse monitor details and build arrays for monitor names and their IPs
###############################################################################
# The JSON is expected to have a "mons" array with objects containing "name" and "addr".
# We extract the IP from the "addr" field (format: IP:port/...) and verify the monitor name.
monInfo=$(echo "$monJSON" | jq -r '.mons[] | "\(.name) \(.addr)"')

declare -a monNames
declare -a monIPs

while read -r name addr; do
    # Extract the IP portion from the address (before the first colon)
    monIP="${addr%%:*}"

    # If the monitor name is missing or null, attempt to resolve it using its IP.
    if [ -z "$name" ] || [ "$name" = "null" ]; then
        name="$(__get_name_from_ip__ "$monIP")"
    fi

    monNames+=("$name")
    monIPs+=("$monIP")
done <<< "$monInfo"

totalMons="${#monNames[@]}"
if [ "$totalMons" -eq 0 ]; then
    __info__ "No Ceph monitors found. Exiting."
    exit 0
fi

__info__ "Found ${totalMons} Ceph monitor(s). Restarting them one at a time."

###############################################################################
# Function: is_local_ip
# Checks if the provided IP address is one of the local system's IPs.
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
# Function: wait_for_mon_active
# Waits until the ceph-mon@<monName> service is active on the given target host
# (either local or remote) or a timeout is reached.
# Timeout is set to 120 seconds.
###############################################################################
wait_for_mon_active(){
    local targetHost="$1"
    local monName="$2"
    local timeout=120
    local elapsed=0
    local status=""
    while true; do
        if [ "$targetHost" = "local" ]; then
            status=$(systemctl is-active "ceph-mon@${monName}")
        else
            status=$(ssh root@"${targetHost}" "systemctl is-active ceph-mon@${monName}" 2>/dev/null)
        fi
        if [ "$status" = "active" ]; then
            break
        fi
        sleep 5
        elapsed=$((elapsed+5))
        if [ $elapsed -ge $timeout ]; then
            __err__ "Monitor ceph-mon@${monName} did not become active after restart on ${targetHost}."
            break
        fi
    done
}

###############################################################################
# Loop through each monitor, determine if it is local or remote, restart it,
# and wait until its service is active.
###############################################################################
currentMon=1
for index in "${!monNames[@]}"; do
    monName="${monNames[$index]}"
    monIP="${monIPs[$index]}"

    __update__ "Processing monitor ${currentMon} of ${totalMons}: ceph-mon@${monName}"

    # Determine the target host for the monitor service.
    if is_local_ip "$monIP"; then
        targetHost="local"
    else
        # Resolve remote monitor IP using the initialized node mapping.
        targetHost="$(__get_ip_from_name__ "$monName")"
        if [ -z "$targetHost" ]; then
            __err__ "Failed to resolve IP for monitor '$monName'. Skipping."
            currentMon=$((currentMon+1))
            continue
        fi
    fi

    # Restart the monitor service on the appropriate host.
    if [ "$targetHost" = "local" ]; then
        systemctl restart "ceph-mon@${monName}"
        if [ $? -eq 0 ]; then
            __ok__ "Successfully restarted ceph-mon@${monName} on local."
        else
            __err__ "Failed to restart ceph-mon@${monName} on local."
        fi
    else
        ssh root@"${targetHost}" "systemctl restart ceph-mon@${monName}"
        if [ $? -eq 0 ]; then
            __ok__ "Successfully restarted ceph-mon@${monName} on ${targetHost}."
        else
            __err__ "Failed to restart ceph-mon@${monName} on ${targetHost}."
        fi
    fi

    # Wait until the monitor service is back active on the target host.
    wait_for_mon_active "${targetHost}" "${monName}"

    sleep 5
    currentMon=$((currentMon+1))
done

__ok__ "All Ceph monitors processed."
