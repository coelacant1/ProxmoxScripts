#!/bin/bash
#
# UpdateNotesWithIP.sh
#
# This script retrieves the IP address of each LXC container in the local Proxmox VE node
# and updates/appends this information to the description field of the respective container.
# If the container does not provide an IP via 'pct exec', it attempts to scan the network
# for the IP based on the container's MAC address using arp-scan.
#
# If the description already contains an "IP Address:" line, that line is updated; otherwise,
# the IP Address line is appended.
#
# Usage:
#   ./UpdateNotesWithIP.sh
#

source "${UTILITYPATH}/Prompts.sh"

__check_root__
__check_proxmox__
__install_or_prompt__ "arp-scan"

###############################################################################
# Main Logic
###############################################################################
readarray -t containerIds < <(pct list | awk 'NR>1 {print $1}')

for ctId in "${containerIds[@]}"; do
    echo "Processing LXC container ID: \"$ctId\""

    # Attempt to retrieve the IP from inside the container (assuming eth0).
    ipAddress=$(pct exec "$ctId" -- bash -c "ip -o -4 addr list eth0 | awk '{print \$4}' | cut -d/ -f1" 2>/dev/null)
    
    if [ -z "$ipAddress" ]; then
        echo " - Unable to retrieve IP address via pct exec for container \"$ctId\"."

        # Attempt to discover the IP by scanning the bridge/VLAN for the MAC.
        macAddress=$(pct config "$ctId" \
            | grep -E '^net[0-9]+:' \
            | grep -oP 'hwaddr=\K[^,]+'
        )
        if [ -z "$macAddress" ]; then
            echo " - Could not retrieve MAC address for container \"$ctId\". Skipping."
            continue
        fi
        
        vlan=$(pct config "$ctId" \
            | grep -E '^net[0-9]+:' \
            | grep -oP 'bridge=\K[^,]+'
        )
        if [ -z "$vlan" ]; then
            echo " - Unable to retrieve VLAN/bridge info for container \"$ctId\". Skipping."
            continue
        fi

        # Use arp-scan to find the IP based on the MAC address on the given interface.
        # You can customize the options below if needed (e.g., setting a specific IP range).
        ipAddress=$(
            arp-scan --interface="$vlan" --localnet 2>/dev/null \
            | grep -i "$macAddress" \
            | awk '{print $1}'
        )
        
        if [ -z "$ipAddress" ]; then
            ipAddress="Could not determine IP address"
            echo " - Unable to determine IP via arp-scan for container \"$ctId\"."
        else
            echo " - Retrieved IP address via arp-scan: \"$ipAddress\""
        fi
    else
        echo " - Retrieved IP address via pct exec: \"$ipAddress\""
    fi

    # Retrieve existing description/notes.
    existingNotes=$(pct config "$ctId" | sed -n 's/^notes: //p')
    if [ -z "$existingNotes" ]; then
        existingNotes=""
    fi

    # If there's an existing line with "IP Address:", update it; otherwise append.
    if echo "$existingNotes" | grep -q "^IP Address:"; then
        updatedNotes=$(echo "$existingNotes" | sed -E "s|^IP Address:.*|IP Address: $ipAddress|")
    else
        updatedNotes="${existingNotes}

IP Address: $ipAddress"
    fi

    # Update the container description
    pct set "$ctId" --description "$updatedNotes"
    echo " - Updated description for container \"$ctId\""
    echo
done

echo "=== LXC container description update process completed! ==="
