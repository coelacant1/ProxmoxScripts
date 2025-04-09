#!/bin/bash
#
# Queries.sh
#
# This script provides functions for prompting users, querying node/cluster
# information, and other utility tasks on Proxmox or Debian systems.
#
# Usage:
#   source "./Queries.sh"
#
# Generally, this script is meant to be sourced by other scripts rather than
# run directly. For example:
#   source ./Queries.sh
#   readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )
#
# Function Index:
#   - __get_remote_node_ips__
#   - __check_cluster_membership__
#   - __get_number_of_cluster_nodes__
#   - __init_node_mappings__
#   - __get_ip_from_name__
#   - __get_name_from_ip__
#   - __get_cluster_lxc__
#   - __get_server_lxc__
#   - __get_cluster_vms__
#   - __get_server_vms__
#   - __get_ip_from_vmid__
#

source "${UTILITYPATH}/Prompts.sh"

__install_or_prompt__ "sshpass"
__install_or_prompt__ "arp-scan"
__install_or_prompt__ "jq"

# Global associative arrays for node mappings.
declare -A NODEID_TO_IP=()
declare -A NODEID_TO_NAME=()
declare -A NAME_TO_IP=()
declare -A IP_TO_NAME=()

# A flag to indicate whether mappings have been initialized.
MAPPINGS_INITIALIZED=0

# --- __get_remote_node_ips__ ------------------------------------------------------------
# @function __get_remote_node_ips__
# @description Gathers IPs for all cluster nodes (excluding local) from 'pvecm status'.
#   Outputs each IP on a new line, which can be captured into an array with readarray.
# @usage readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )
# @return Prints each remote node IP on a separate line to stdout.
# @example_output Given pvecm status output with remote IPs, the function might output:
#   192.168.1.2
#   192.168.1.3
__get_remote_node_ips__() {
    local -a remote_nodes=()
    while IFS= read -r ip; do
        remote_nodes+=("$ip")
    done < <(pvecm status | awk '/^0x/ && !/\(local\)/ {print $3}')

    for node_ip in "${remote_nodes[@]}"; do
        echo "$node_ip"
    done
}

# --- __check_cluster_membership__ ------------------------------------------------------------
# @function __check_cluster_membership__
# @description Checks if the node is recognized as part of a cluster by examining 'pvecm status'.
#   If no cluster name is found, it exits with an error.
# @usage __check_cluster_membership__
# @return Exits 3 if the node is not in a cluster (according to pvecm).
# @example_output If the node is in a cluster, the output is:
#   Node is in a cluster named: MyClusterName
__check_cluster_membership__() {
    local cluster_name
    cluster_name=$(pvecm status 2>/dev/null | awk -F': ' '/^Name:/ {print $2}' | xargs)

    if [[ -z "$cluster_name" ]]; then
        echo "Error: This node is not recognized as part of a cluster by pvecm."
        exit 3
    else
        echo "Node is in a cluster named: $cluster_name"
    fi
}

# --- __get_number_of_cluster_nodes__ ------------------------------------------------------------
# @function __get_number_of_cluster_nodes__
# @description Returns the total number of nodes in the cluster by counting lines matching a numeric ID from `pvecm nodes`.
# @usage local num_nodes=$(__get_number_of_cluster_nodes__)
# @return Prints the count of cluster nodes to stdout.
# @example_output If there are 3 nodes in the cluster, the output is:
#   3
__get_number_of_cluster_nodes__() {
    echo "$(pvecm nodes | awk '/^[[:space:]]*[0-9]/ {count++} END {print count}')"
}

# --- __init_node_mappings__ ------------------------------------------------------------
# @function __init_node_mappings__
# @description Parses `pvecm status` and `pvecm nodes` to build internal maps:
#   NODEID_TO_IP[nodeid]   -> IP, NODEID_TO_NAME[nodeid] -> Name,
#   then creates: NAME_TO_IP[name] -> IP and IP_TO_NAME[ip] -> name.
# @usage __init_node_mappings__
# @return Populates the associative arrays with node information.
# @example_output No direct output; internal mappings are initialized for later queries.
__init_node_mappings__() {
    # Reset the arrays.
    NODEID_TO_IP=()
    NODEID_TO_NAME=()
    NAME_TO_IP=()
    IP_TO_NAME=()

    # Process the output from pvecm status.
    while IFS= read -r line; do
        # Extract the first and third fields.
        local nodeid_hex ip_part
        nodeid_hex=$(awk '{print $1}' <<< "$line" | xargs)  # xargs trims whitespace.
        ip_part=$(awk '{print $3}' <<< "$line" | xargs)
        ip_part="${ip_part//(local)/}"
        ip_part=$(echo "$ip_part" | xargs)  # Trim any leftover spaces.

        # Ensure the extracted nodeid_hex starts with "0x" and valid hex digits.
        if [[ "$nodeid_hex" != 0x[0-9a-fA-F]* ]]; then
            echo "DEBUG: Skipping invalid node id: '$nodeid_hex'" >&2
            continue
        fi

        # Convert the hexadecimal string to decimal.
        local nodeid_dec=$((16#${nodeid_hex#0x}))
        NODEID_TO_IP["$nodeid_dec"]="$ip_part"
    done < <(pvecm status 2>/dev/null | awk '/^[[:space:]]*0x[0-9a-fA-F]+/ {print}')

    # Process the output from pvecm nodes.
    while IFS= read -r line; do
        local nodeid_dec name_part
        nodeid_dec=$(awk '{print $1}' <<< "$line" | xargs)
        name_part=$(awk '{print $3}' <<< "$line" | xargs)
        name_part="${name_part//(local)/}"
        name_part=$(echo "$name_part" | xargs)
        NODEID_TO_NAME["$nodeid_dec"]="$name_part"
    done < <(pvecm nodes 2>/dev/null | awk '/^[[:space:]]*[0-9]+/ {print}')

    # Build forward (NAME_TO_IP) and reverse (IP_TO_NAME) mappings.
    for nodeid in "${!NODEID_TO_NAME[@]}"; do
        local name
        local ip
        name=$(echo "${NODEID_TO_NAME[$nodeid]}" | xargs)
        ip=$(echo "${NODEID_TO_IP[$nodeid]}" | xargs)
        if [[ -n "$name" && -n "$ip" ]]; then
            NAME_TO_IP["$name"]="$ip"
            IP_TO_NAME["$ip"]="$name"
        fi
    done

    MAPPINGS_INITIALIZED=1
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
    if [[ -z "$node_name" ]]; then
        echo "Error: __get_ip_from_name__ requires a node name argument." >&2
        return 1
    fi

    # Ensure that the node mappings are initialized.
    if [[ "$MAPPINGS_INITIALIZED" -eq 0 ]]; then
        __init_node_mappings__
    fi

    local ip="${NAME_TO_IP[$node_name]}"
    if [[ -z "$ip" ]]; then
        echo "Error: Could not find IP for node name '$node_name'." >&2
        return 1
    fi

    echo "$ip"
}

# --- __get_name_from_ip__ ------------------------------------------------------------
# @function __get_name_from_ip__
# @description Given a node’s link0 IP (e.g., "172.20.83.23"), prints its name.
#   Exits if not found.
# @usage __get_name_from_ip__ "172.20.83.23"
# @param 1 The node IP.
# @return Prints the node name to stdout or exits 1 if not found.
# @example_output For __get_name_from_ip__ "172.20.83.23", the output is:
#   pve03
__get_name_from_ip__() {
    local node_ip
    node_ip=$(echo "$1" | xargs)
    if [[ -z "$node_ip" ]]; then
        echo "Error: __get_name_from_ip__ requires an IP argument." >&2
        return 1
    fi

    # Initialize mappings if needed.
    if [[ "$MAPPINGS_INITIALIZED" -eq 0 ]]; then
        __init_node_mappings__
    fi

    local name="${IP_TO_NAME[$node_ip]}"
    if [[ -z "$name" ]]; then
        echo "Error: Could not find node name for IP '$node_ip'." >&2
        return 1
    fi

    echo "$name"
}



# --- __get_cluster_lxc__ ------------------------------------------------------------
# @function __get_cluster_lxc__
# @description Retrieves the VMIDs for all LXC containers across the entire cluster.
# @usage readarray -t ALL_CLUSTER_LXC < <( __get_cluster_lxc__ )
# @return Prints each LXC VMID on a separate line.
# @example_output The function may output:
#   101
#   102
__get_cluster_lxc__() {
    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null |
        jq -r '.[] | select(.type=="lxc") | .vmid'
}

# --- __get_server_lxc__ ------------------------------------------------------------
# @function __get_server_lxc__
# @description Retrieves the VMIDs for all LXC containers on a specific server.
#   The server can be specified by hostname, IP address, or "local".
# @usage readarray -t NODE_LXC < <( __get_server_lxc__ "local" )
# @param 1 Hostname/IP/"local" specifying the server.
# @return Prints each LXC VMID on its own line.
# @example_output For __get_server_lxc__ "local", the output might be:
#   201
#   202
__get_server_lxc__() {
    local nodeSpec="$1"
    local nodeName

    if [[ "$nodeSpec" == "local" ]]; then
        nodeName="$(hostname -s)"
    elif [[ "$nodeSpec" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        nodeName="$(__get_name_from_ip__ "$nodeSpec")"
    else
        nodeName="$nodeSpec"
    fi

    if [[ -z "$nodeName" ]]; then
        echo "Error: Unable to determine node name for '$nodeSpec'." >&2
        return 1
    fi

    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null |
        jq -r --arg NODENAME "$nodeName" \
            '.[] | select(.type=="lxc" and .node==$NODENAME) | .vmid'
}

# --- __get_cluster_vms__ ------------------------------------------------------------
# @function __get_cluster_vms__
# @description Retrieves the VMIDs for all VMs (QEMU) across the entire cluster.
# @usage readarray -t ALL_CLUSTER_VMS < <( __get_cluster_vms__ )
# @return Prints each QEMU VMID on a separate line.
# @example_output The function may output:
#   301
#   302
__get_cluster_vms__() {
    __install_or_prompt__ "jq"
    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null |
        jq -r '.[] | select(.type=="qemu") | .vmid'
}

# --- __get_server_vms__ ------------------------------------------------------------
# @function __get_server_vms__
# @description Retrieves the VMIDs for all VMs (QEMU) on a specific server.
#   The server can be specified by hostname, IP address, or "local".
# @usage readarray -t NODE_VMS < <( __get_server_vms__ "local" )
# @param 1 Hostname/IP/"local" specifying the server.
# @return Prints each QEMU VMID on its own line.
# @example_output For __get_server_vms__ "local", the output might be:
#   401
#   402
__get_server_vms__() {
    local nodeSpec="$1"
    local nodeName

    if [[ "$nodeSpec" == "local" ]]; then
        nodeName="$(hostname -s)"
    elif [[ "$nodeSpec" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        nodeName="$(__get_name_from_ip__ "$nodeSpec")"
    else
        nodeName="$nodeSpec"
    fi

    if [[ -z "$nodeName" ]]; then
        echo "Error: Unable to determine node name for '$nodeSpec'." >&2
        return 1
    fi

    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null |
        jq -r --arg NODENAME "$nodeName" \
            '.[] | select(.type=="qemu" and .node==$NODENAME) | .vmid'
}

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
    if [[ -z "$vmid" ]]; then
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
        echo "Detected LXC container VMID '$vmid'..." >&2

        # 1) Try to get the IP by executing 'hostname -I' inside the container.
        local guest_ip
        guest_ip=$(pct exec "$vmid" -- hostname -I 2>/dev/null |
            awk '{ for(i=1;i<=NF;i++) { if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $i != "127.0.0.1") { print $i; exit } } }')
        if [[ -n "$guest_ip" ]]; then
            echo "$guest_ip"
            return 0
        fi

        echo " - Unable to retrieve IP from container via hostname -I. Falling back to ARP scan..." >&2

        # 2) Retrieve MAC address from container configuration (net0)
        local mac
        mac=$(pct config "$vmid" |
            grep -E '^net[0-9]+:' |
            grep -oE '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}')
        if [[ -z "$mac" ]]; then
            echo "Error: Could not retrieve net0 MAC address for container VMID '$vmid'." >&2
            return 1
        fi

        # 3) Determine the bridge from container config
        local bridge
        bridge=$(pct config "$vmid" |
            grep -E '^net[0-9]+:' |
            grep -oP 'bridge=\K[^,]+')
        if [[ -z "$bridge" ]]; then
            echo "Error: Could not determine which bridge interface is used by container VMID '$vmid'." >&2
            return 1
        fi

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
            scannedIp=$(arp-scan --interface="$bridge" --localnet 2>/dev/null |
                grep -i "$mac" |
                awk '{print $1}' | head -n1)
        else
            local base_ip
            base_ip=$(echo "$subnet_to_scan" | cut -d '/' -f1)
            base_ip="${base_ip%.*}.1"
            scannedIp=$(arp-scan --interface="$bridge" --arpspa="$base_ip" "$subnet_to_scan" 2>/dev/null |
                grep -i "$mac" |
                awk '{print $1}' | head -n1)
        fi

        if [[ -z "$scannedIp" ]]; then
            echo "Error: Could not find an IP for container VMID '$vmid' with MAC '$mac' on bridge '$bridge'." >&2
            return 1
        fi

        echo "$scannedIp"
        return 0
    elif [ -f "/etc/pve/qemu-server/${vmid}.conf" ]; then
        # --- QEMU VM --------------------------------------------------------
        echo "Detected QEMU VM VMID '$vmid'..." >&2

        # 1) Retrieve MAC address from net0
        local mac
        mac=$(
            qm config "$vmid" |
                grep -E '^net[0-9]+:' |
                grep -oE '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}'
        )
        if [[ -z "$mac" ]]; then
            echo "Error: Could not retrieve net0 MAC address for VMID '$vmid'." >&2
            return 1
        fi

        # 2) Try to retrieve IP via QEMU Guest Agent: network-get-interfaces
        local guest_ip
        guest_ip=$(
            qm guest cmd "$vmid" network-get-interfaces 2>/dev/null |
                jq -r --arg mac "$mac" '
                .[] 
                | select((.["hardware-address"] // "") 
                         | ascii_downcase == ($mac | ascii_downcase))
                | .["ip-addresses"][]?
                | select(.["ip-address-type"] == "ipv4" and .["ip-address"] != "127.0.0.1")
                | .["ip-address"]
            ' |
                head -n1
        )
        if [[ -n "$guest_ip" && "$guest_ip" != "null" ]]; then
            echo "$guest_ip"
            return 0
        fi

        echo " - Unable to retrieve IP via guest agent. Falling back to ARP scan..." >&2

        # 3) Identify the bridge from net0 config
        local bridge
        bridge=$(
            qm config "$vmid" |
                grep -E '^net[0-9]+:' |
                grep -oP 'bridge=\K[^,]+'
        )
        if [[ -z "$bridge" ]]; then
            echo "Error: Could not determine which bridge interface is used by VMID '$vmid'." >&2
            return 1
        fi

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
            scannedIp=$(arp-scan --interface="$bridge" --localnet 2>/dev/null |
                grep -i "$mac" |
                awk '{print $1}' | head -n1)
        else
            local base_ip
            base_ip=$(echo "$subnet_to_scan" | cut -d '/' -f1)
            base_ip="${base_ip%.*}.1"
            scannedIp=$(arp-scan --interface="$bridge" --arpspa="$base_ip" "$subnet_to_scan" 2>/dev/null |
                grep -i "$mac" |
                awk '{print $1}' | head -n1)
        fi

        if [[ -z "$scannedIp" ]]; then
            echo "Error: Could not find an IP for VMID '$vmid' with MAC '$mac' on bridge '$bridge'." >&2
            return 1
        fi

        echo "$scannedIp"
        return 0

    else
        echo "Error: VMID '$vmid' not found in LXC or QEMU configurations." >&2
        return 1
    fi
}
