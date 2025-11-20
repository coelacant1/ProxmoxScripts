#!/bin/bash
#
# Discovery.sh
#
# IP Discovery and Resolution Utilities for ProxmoxScripts
# Provides functions for discovering IP addresses from VMIDs, guest agents, and node names
#
# Dependencies:
#   - Cluster.sh (for node mappings via __init_node_mappings__)
#   - API.sh (for VM/CT existence checks)
#   - Logger.sh (for logging)
#
# Usage:
#   source "${UTILITYPATH}/Discovery.sh"
#
# Function Index:
#   - __discovery_log__
#   - __get_ip_from_vmid__
#   - __get_ip_from_guest_agent__
#   - __get_ip_from_name__
#   - __get_name_from_ip__
#

###############################################################################
# Configuration & Dependencies
###############################################################################

# Source Logger if available
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    source "${UTILITYPATH}/Logger.sh"
fi

# Logging wrapper
__discovery_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "DISCOVERY"
    fi
    if [[ "$level" == "ERROR" ]]; then
        echo "Error: $message" >&2
    fi
}

# Global associative arrays for node mappings (initialized by __init_node_mappings__ in Cluster.sh)
declare -gA NODE_NAME_TO_IP
declare -gA NODE_IP_TO_NAME

# Bridge subnet cache (used by get_ip_from_vmid)
declare -gA BRIDGE_SUBNET_CACHE

###############################################################################
# IP Discovery Functions
###############################################################################

# --- get_ip_from_vmid ------------------------------------------------------------
# @function get_ip_from_vmid
# @description Retrieves the IP address of a VM by using its net0 MAC address for an ARP scan on the default interface (vmbr0).
#   Prints the IP if found.
# @usage get_ip_from_vmid 100
# @param 1 The VMID.
# @return Prints the discovered IP or exits 1 if not found.
# @example_output For get_ip_from_vmid 100, the output might be:
#   192.168.1.100
__get_ip_from_vmid__() {
    local vmid="$1"

    __discovery_log__ "INFO" "Getting IP address for VMID $vmid"

    if [[ -z "$vmid" ]]; then
        __discovery_log__ "ERROR" "VMID argument is required"
        echo "Error: get_ip_from_vmid requires a VMID argument." >&2
        return 1
    fi

    #
    # Check whether the VMID belongs to an LXC container or a QEMU VM.
    # (This example assumes that container configs live in /etc/pve/lxc/ and
    # QEMU configs in /etc/pve/qemu-server/.)
    #
    if [ -f "/etc/pve/lxc/${vmid}.conf" ]; then
        # --- LXC CONTAINER -------------------------------------------------
        __discovery_log__ "DEBUG" "Detected LXC container VMID $vmid"
        echo "Detected LXC container VMID '$vmid'..." >&2

        # 1) Try to get the IP by executing 'hostname -I' inside the container.
        local guest_ip
        guest_ip=$(pct exec "$vmid" -- hostname -I 2>/dev/null \
            | awk '{ for(i=1;i<=NF;i++) { if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $i != "127.0.0.1") { print $i; exit } } }')
        if [[ -n "$guest_ip" ]]; then
            __discovery_log__ "INFO" "Retrieved IP $guest_ip from LXC container $vmid via hostname"
            echo "$guest_ip"
            return 0
        fi

        __discovery_log__ "DEBUG" "Unable to retrieve IP from container via hostname, falling back to ARP scan"
        echo " - Unable to retrieve IP from container via hostname -I. Falling back to ARP scan..." >&2

        # 2) Retrieve MAC address from container configuration (net0)
        local mac
        mac=$(pct config "$vmid" \
            | grep -E '^net[0-9]+:' \
            | grep -oE '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}')
        if [[ -z "$mac" ]]; then
            __discovery_log__ "ERROR" "Could not retrieve MAC address for container $vmid"
            echo "Error: Could not retrieve net0 MAC address for container VMID '$vmid'." >&2
            return 1
        fi

        __discovery_log__ "DEBUG" "Container $vmid MAC address: $mac"

        # 3) Determine the bridge from container config
        local bridge
        bridge=$(pct config "$vmid" \
            | grep -E '^net[0-9]+:' \
            | grep -oP 'bridge=\K[^,]+')
        if [[ -z "$bridge" ]]; then
            __discovery_log__ "ERROR" "Could not determine bridge for container $vmid"
            echo "Error: Could not determine which bridge interface is used by container VMID '$vmid'." >&2
            return 1
        fi

        __discovery_log__ "DEBUG" "Container $vmid bridge: $bridge"

        # 4) Check whether the host’s bridge has an IP address.
        local interface_ip
        interface_ip=$(ip -o -4 addr show dev "$bridge" | awk '{print $4}' | head -n1)

        local subnet_to_scan
        if [[ -z "$interface_ip" ]]; then
            if [[ -n "${BRIDGE_SUBNET_CACHE[$bridge]}" ]]; then
                subnet_to_scan="${BRIDGE_SUBNET_CACHE[$bridge]}"
                echo " - Using cached subnet '$subnet_to_scan' for bridge '$bridge'" >&2
            else
                read -r -p "Bridge '$bridge' has no IP. Enter the subnet to scan (e.g. 192.168.13.0/24): " subnet_to_scan
                BRIDGE_SUBNET_CACHE[$bridge]="$subnet_to_scan"
            fi
        else
            subnet_to_scan="--localnet"
        fi

        # 5) Run arp-scan on the determined subnet to find the matching MAC address.
        local scannedIp
        if [[ "$subnet_to_scan" == "--localnet" ]]; then
            scannedIp=$(arp-scan --interface="$bridge" --localnet 2>/dev/null \
                | grep -i "$mac" \
                | awk '{print $1}' | head -n1)
        else
            local base_ip
            base_ip=$(echo "$subnet_to_scan" | cut -d '/' -f1)
            base_ip="${base_ip%.*}.1"
            scannedIp=$(arp-scan --interface="$bridge" --arpspa="$base_ip" "$subnet_to_scan" 2>/dev/null \
                | grep -i "$mac" \
                | awk '{print $1}' | head -n1)
        fi

        if [[ -z "$scannedIp" ]]; then
            __discovery_log__ "ERROR" "Could not find IP for container $vmid with MAC $mac on bridge $bridge"
            echo "Error: Could not find an IP for container VMID '$vmid' with MAC '$mac' on bridge '$bridge'." >&2
            return 1
        fi

        __discovery_log__ "INFO" "Found IP $scannedIp for container $vmid via ARP scan"
        echo "$scannedIp"
        return 0
    elif [ -f "/etc/pve/qemu-server/${vmid}.conf" ]; then
        # --- QEMU VM --------------------------------------------------------
        __discovery_log__ "DEBUG" "Detected QEMU VM VMID $vmid"
        echo "Detected QEMU VM VMID '$vmid'..." >&2

        # 1) Retrieve MAC address from net0
        local mac
        mac=$(
            qm config "$vmid" \
                | grep -E '^net[0-9]+:' \
                | grep -oE '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}'
        )
        if [[ -z "$mac" ]]; then
            __discovery_log__ "ERROR" "Could not retrieve MAC address for VM $vmid"
            echo "Error: Could not retrieve net0 MAC address for VMID '$vmid'." >&2
            return 1
        fi

        __discovery_log__ "DEBUG" "VM $vmid MAC address: $mac"

        # 2) Try to retrieve IP via QEMU Guest Agent: network-get-interfaces
        local guest_ip
        guest_ip=$(
            qm guest cmd "$vmid" network-get-interfaces 2>/dev/null \
                | jq -r --arg mac "$mac" '
                .[]
                | select((.["hardware-address"] // "")
                         | ascii_downcase == ($mac | ascii_downcase))
                | .["ip-addresses"][]?
                | select(.["ip-address-type"] == "ipv4" and .["ip-address"] != "127.0.0.1")
                | .["ip-address"]
            ' \
                | head -n1
        )
        if [[ -n "$guest_ip" && "$guest_ip" != "null" ]]; then
            __discovery_log__ "INFO" "Retrieved IP $guest_ip from VM $vmid via guest agent"
            echo "$guest_ip"
            return 0
        fi

        __discovery_log__ "DEBUG" "Unable to retrieve IP via guest agent, falling back to ARP scan"
        echo " - Unable to retrieve IP via guest agent. Falling back to ARP scan..." >&2

        # 3) Identify the bridge from net0 config
        local bridge
        bridge=$(
            qm config "$vmid" \
                | grep -E '^net[0-9]+:' \
                | grep -oP 'bridge=\K[^,]+'
        )
        if [[ -z "$bridge" ]]; then
            __discovery_log__ "ERROR" "Could not determine bridge for VM $vmid"
            echo "Error: Could not determine which bridge interface is used by VMID '$vmid'." >&2
            return 1
        fi

        __discovery_log__ "DEBUG" "VM $vmid bridge: $bridge"

        # 4) Check if the bridge has an IP address on the host
        local interface_ip
        interface_ip=$(ip -o -4 addr show dev "$bridge" | awk '{print $4}' | head -n1)

        local subnet_to_scan
        if [[ -z "$interface_ip" ]]; then
            if [[ -n "${BRIDGE_SUBNET_CACHE[$bridge]}" ]]; then
                subnet_to_scan="${BRIDGE_SUBNET_CACHE[$bridge]}"
                echo " - Using cached subnet '$subnet_to_scan' for bridge '$bridge'" >&2
            else
                read -r -p "Bridge '$bridge' has no IP. Enter the subnet to scan (e.g. 192.168.13.0/24): " subnet_to_scan
                BRIDGE_SUBNET_CACHE[$bridge]="$subnet_to_scan"
            fi
        else
            subnet_to_scan="--localnet"
        fi

        # 5) Run arp-scan on the determined subnet to find the matching MAC address.
        local scannedIp
        if [[ "$subnet_to_scan" == "--localnet" ]]; then
            scannedIp=$(arp-scan --interface="$bridge" --localnet 2>/dev/null \
                | grep -i "$mac" \
                | awk '{print $1}' | head -n1)
        else
            local base_ip
            base_ip=$(echo "$subnet_to_scan" | cut -d '/' -f1)
            base_ip="${base_ip%.*}.1"
            scannedIp=$(arp-scan --interface="$bridge" --arpspa="$base_ip" "$subnet_to_scan" 2>/dev/null \
                | grep -i "$mac" \
                | awk '{print $1}' | head -n1)
        fi

        if [[ -z "$scannedIp" ]]; then
            __discovery_log__ "ERROR" "Could not find IP for VM $vmid with MAC $mac on bridge $bridge"
            echo "Error: Could not find an IP for VMID '$vmid' with MAC '$mac' on bridge '$bridge'." >&2
            return 1
        fi

        __discovery_log__ "INFO" "Found IP $scannedIp for VM $vmid via ARP scan"
        echo "$scannedIp"
        return 0

    else
        __discovery_log__ "ERROR" "VMID $vmid not found in LXC or QEMU configurations"
        echo "Error: VMID '$vmid' not found in LXC or QEMU configurations." >&2
        return 1
    fi
}

# --- __get_ip_from_guest_agent__ -------------------------------------------
# @function __get_ip_from_guest_agent__
# @description Attempts to retrieve the first non-loopback IP address reported by the QEMU guest agent for a VM.
# @usage __get_ip_from_guest_agent__ --vmid <vmid> [--retries <count>] [--delay <seconds>] [--ip-family <ipv4|ipv6>] [--include-loopback] [--allow-link-local]
# @flags
#   --vmid <vmid>             Target VMID (required).
#   --retries <count>         Number of attempts to query the guest agent (default: 30).
#   --delay <seconds>         Delay between attempts (default: 2 seconds).
#   --ip-family <family>      IP family to return: ipv4 (default) or ipv6.
#   --include-loopback        Include loopback interfaces (default excludes them).
#   --allow-link-local        Allow link-local IPv6 addresses (default skips fe80::/10).
# @return Prints the discovered IP on success; exits with status 1 otherwise.
# @example __get_ip_from_guest_agent__ --vmid 105 --retries 60 --delay 5
__get_ip_from_guest_agent__() {
    local vmid=""
    local retries=30
    local delaySeconds=2
    local ipFamily="ipv4"
    local includeLoopback=0
    local allowLinkLocal=0

    __discovery_log__ "DEBUG" "Getting IP from guest agent"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --vmid)
                vmid="$2"
                shift 2
                ;;
            --retries)
                retries="$2"
                shift 2
                ;;
            --delay)
                delaySeconds="$2"
                shift 2
                ;;
            --ip-family)
                ipFamily="$2"
                shift 2
                ;;
            --ipv6)
                ipFamily="ipv6"
                shift
                ;;
            --include-loopback)
                includeLoopback=1
                shift
                ;;
            --allow-link-local)
                allowLinkLocal=1
                shift
                ;;
            --)
                shift
                ;;
            *)
                __discovery_log__ "ERROR" "Unknown option: $1"
                echo "Error: Unknown option '$1' passed to __get_ip_from_guest_agent__." >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$vmid" ]]; then
        __discovery_log__ "ERROR" "VMID is required"
        echo "Error: __get_ip_from_guest_agent__ requires --vmid." >&2
        return 1
    fi

    if [[ "$ipFamily" != "ipv4" && "$ipFamily" != "ipv6" ]]; then
        __discovery_log__ "ERROR" "Invalid IP family: $ipFamily"
        echo "Error: __get_ip_from_guest_agent__ --ip-family must be 'ipv4' or 'ipv6'." >&2
        return 1
    fi

    __discovery_log__ "INFO" "Querying guest agent for VM $vmid (family=$ipFamily, retries=$retries)"

    local attempt
    for ((attempt = 1; attempt <= retries; attempt++)); do
        __discovery_log__ "DEBUG" "Guest agent query attempt $attempt/$retries for VM $vmid"

        if ! qm agent "$vmid" ping >/dev/null 2>&1; then
            sleep "$delaySeconds"
            continue
        fi

        local json
        json=$(qm agent "$vmid" network-get-interfaces 2>/dev/null)
        if [[ -z "$json" || "$json" == "null" ]]; then
            sleep "$delaySeconds"
            continue
        fi

        local ip
        ip=$(echo "$json" | jq -r \
            --arg family "$ipFamily" \
            --argjson includeLoopback "$includeLoopback" \
            --argjson allowLinkLocal "$allowLinkLocal" \
            '
            .[]
            | select($includeLoopback == 1 or .name != "lo")
            | .["ip-addresses"][]?
            | select(. ["ip-address-type"] == $family)
            | select(
                $family != "ipv6"
                or $allowLinkLocal == 1
                or (. ["ip-address"] | startswith("fe80") | not)
            )
            | .["ip-address"]
            ' | head -n1)

        if [[ -n "$ip" && "$ip" != "null" ]]; then
            __discovery_log__ "INFO" "Retrieved IP $ip from guest agent for VM $vmid (attempt $attempt)"
            echo "$ip"
            return 0
        fi

        sleep "$delaySeconds"
    done

    __discovery_log__ "ERROR" "Failed to retrieve IP from guest agent for VM $vmid after $retries attempts"
    return 1
}

# --- __get_ip_from_name__ ------------------------------------------------------------
# @function __get_ip_from_name__
# @description Given a node’s name (e.g., "pve01"), prints its link0 IP address.
#   Exits if not found.
# @usage __get_ip_from_name__ "pve03"
# @param 1 The node name.
# @return Prints the IP to stdout or exits 1 if not found.
# @example_output For __get_ip_from_name__ "pve03", the output is:
#   192.168.83.23
__get_ip_from_name__() {
    local node_name
    node_name=$(echo "$1" | xargs)
    __discovery_log__ "TRACE" "Resolving node name to IP: $node_name"

    if [[ -z "$node_name" ]]; then
        __discovery_log__ "ERROR" "No node name provided"
        echo "Error: __get_ip_from_name__ requires a node name argument." >&2
        return 1
    fi

    # Ensure that the node mappings are initialized.
    if [[ "$MAPPINGS_INITIALIZED" -eq 0 ]]; then
        __init_node_mappings__
    fi

    local ip="${NAME_TO_IP[$node_name]}"
    if [[ -z "$ip" ]]; then
        __discovery_log__ "ERROR" "No IP found for node: $node_name"
        echo "Error: Could not find IP for node name '$node_name'." >&2
        return 1
    fi

    __discovery_log__ "DEBUG" "Resolved $node_name -> $ip"
    echo "$ip"
}

# --- __get_name_from_ip__ ------------------------------------------------------------
# @function __get_name_from_ip__
# @description Given a node’s link0 IP (e.g., "192.168.1.23"), prints its name.
#   Exits if not found.
# @usage __get_name_from_ip__ "192.168.1.23"
# @param 1 The node IP.
# @return Prints the node name to stdout or exits 1 if not found.
# @example_output For __get_name_from_ip__ "192.168.1.23", the output is:
#   pve03
__get_name_from_ip__() {
    local node_ip
    node_ip=$(echo "$1" | xargs)
    __discovery_log__ "TRACE" "Resolving IP to node name: $node_ip"

    if [[ -z "$node_ip" ]]; then
        __discovery_log__ "ERROR" "No IP provided"
        echo "Error: __get_name_from_ip__ requires an IP argument." >&2
        return 1
    fi

    # Initialize mappings if needed.
    if [[ "$MAPPINGS_INITIALIZED" -eq 0 ]]; then
        __init_node_mappings__
    fi

    local name="${IP_TO_NAME[$node_ip]}"
    if [[ -z "$name" ]]; then
        __discovery_log__ "ERROR" "No node name found for IP: $node_ip"
        echo "Error: Could not find node name for IP '$node_ip'." >&2
        return 1
    fi

    __discovery_log__ "DEBUG" "Resolved $node_ip -> $name"
    echo "$name"
}

###############################################################################
# Script notes:
###############################################################################
# Last checked: YYYY-MM-DD
#
# Changes:
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

