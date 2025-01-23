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
#

source "${UTILITYPATH}/Prompts.sh"

__install_or_prompt__ "sshpass"
__install_or_prompt__ "arp-scan"
__install_or_prompt__ "jq"

###############################################################################
# Cluster/Node Functions
###############################################################################

# --- Get Remote Node IPs ---------------------------------------------------
# @function __get_remote_node_ips__
# @description Gathers IPs for all cluster nodes (excluding local) from 'pvecm status'.
#   Outputs each IP on a new line, which can be captured into an array with readarray.
# @usage
#   readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )
# @return
#   Prints each remote node IP on a separate line to stdout.
__get_remote_node_ips__() {
    local -a remote_nodes=()
    while IFS= read -r ip; do
        remote_nodes+=("$ip")
    done < <(pvecm status | awk '/^0x/ && !/\(local\)/ {print $3}')

    for node_ip in "${remote_nodes[@]}"; do
        echo "$node_ip"
    done
}

# --- Check Cluster Membership ----------------------------------------------
# @function __check_cluster_membership__
# @description Checks if the node is recognized as part of a cluster by examining
#   'pvecm status'. If no cluster name is found, it exits with an error.
# @usage
#   __check_cluster_membership__
# @return
#   Exits 3 if the node is not in a cluster (according to pvecm).
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

# --- Get Number of Cluster Nodes -------------------------------------------
# @function __get_number_of_cluster_nodes__
# @description Returns the total number of nodes in the cluster by counting
#   lines matching a numeric ID from `pvecm nodes`.
# @usage
#   local num_nodes=$(__get_number_of_cluster_nodes__)
# @return
#   Prints the count of cluster nodes to stdout.
__get_number_of_cluster_nodes__() {
    echo "$(pvecm nodes | awk '/^[[:space:]]*[0-9]/ {count++} END {print count}')"
}


###############################################################################
# Node Mapping Functions
###############################################################################

declare -A NODEID_TO_IP=()
declare -A NODEID_TO_NAME=()
declare -A NAME_TO_IP=()
declare -A IP_TO_NAME=()
MAPPINGS_INITIALIZED=0

# --- Initialize Node Mappings ----------------------------------------------
# @function __init_node_mappings__
# @description Parses `pvecm status` and `pvecm nodes` to build internal maps:
#   NODEID_TO_IP[nodeid]   -> IP
#   NODEID_TO_NAME[nodeid] -> Name
#   Then creates:
#   NAME_TO_IP[name]       -> IP
#   IP_TO_NAME[ip]         -> name
# @usage
#   __init_node_mappings__
# @return
#   Populates the associative arrays above with node info.
__init_node_mappings__() {
    NODEID_TO_IP=()
    NODEID_TO_NAME=()
    NAME_TO_IP=()
    IP_TO_NAME=()

    while IFS= read -r line; do
        local nodeid_hex
        local ip_part
        nodeid_hex=$(awk '{print $1}' <<<"$line")
        ip_part=$(awk '{print $3}' <<<"$line")
        ip_part="${ip_part//(local)/}"
        local nodeid_dec=$((16#${nodeid_hex#0x}))
        NODEID_TO_IP["$nodeid_dec"]="$ip_part"
    done < <(pvecm status 2>/dev/null | awk '/^0x/{print}')

    while IFS= read -r line; do
        local nodeid_dec
        local name_part
        nodeid_dec=$(awk '{print $1}' <<<"$line")
        name_part=$(awk '{print $3}' <<<"$line")
        name_part="${name_part//(local)/}"
        NODEID_TO_NAME["$nodeid_dec"]="$name_part"
    done < <(pvecm nodes 2>/dev/null | awk '/^[[:space:]]*[0-9]/ {print}')

    for nodeid in "${!NODEID_TO_NAME[@]}"; do
        local name="${NODEID_TO_NAME[$nodeid]}"
        local ip="${NODEID_TO_IP[$nodeid]}"
        if [[ -n "$name" && -n "$ip" ]]; then
            NAME_TO_IP["$name"]="$ip"
            IP_TO_NAME["$ip"]="$name"
        fi
    done

    MAPPINGS_INITIALIZED=1
}

# --- Get IP from Node Name -------------------------------------------------
# @function __get_ip_from_name__
# @description Given a node’s name (e.g., "IHK01"), prints its link0 IP address.
#   Exits if not found.
# @usage
#   __get_ip_from_name__ "IHK03"
# @param 1 The node name
# @return
#   Prints the IP to stdout or exits 1 if not found.
__get_ip_from_name__() {
    local node_name="$1"
    if [[ -z "$node_name" ]]; then
        echo "Error: __get_ip_from_name__ requires a node name argument." >&2
        return 1
    fi

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

# --- Get Name from Node IP -------------------------------------------------
# @function __get_name_from_ip__
# @description Given a node’s link0 IP (e.g., "172.20.83.23"), prints its name.
#   Exits if not found.
# @usage
#   __get_name_from_ip__ "172.20.83.23"
# @param 1 The node IP
# @return
#   Prints the node name to stdout or exits 1 if not found.
__get_name_from_ip__() {
    local node_ip="$1"
    if [[ -z "$node_ip" ]]; then
        echo "Error: __get_name_from_ip__ requires an IP argument." >&2
        return 1
    fi

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

###############################################################################
# Container and VM Queries
###############################################################################

# --- Get All LXC Containers in Cluster --------------------------------------
# @function __get_cluster_lxc__
# @description Retrieves the VMIDs for all LXC containers across the entire cluster.
#   Outputs each LXC VMID on its own line.
# @usage
#   readarray -t ALL_CLUSTER_LXC < <( __get_cluster_lxc__ )
# @return
#   Prints each LXC VMID on a separate line.
__get_cluster_lxc__() {
    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r '.[] | select(.type=="lxc") | .vmid'
}

# --- Get All LXC Containers on a Server ------------------------------------
# @function __get_server_lxc__
# @description Retrieves the VMIDs for all LXC containers on a specific server.
#   The server can be specified by hostname, IP address, or "local".
# @usage
#   readarray -t NODE_LXC < <( __get_server_lxc__ "local" )
# @param 1 Hostname/IP/"local" specifying the server.
# @return
#   Prints each LXC VMID on its own line.
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

    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r --arg NODENAME "$nodeName" \
            '.[] | select(.type=="lxc" and .node==$NODENAME) | .vmid'
}

# --- Get All VMs in Cluster ------------------------------------------------
# @function __get_cluster_vms__
# @description Retrieves the VMIDs for all VMs (QEMU) across the entire cluster.
#   Outputs each VM ID on its own line.
# @usage
#   readarray -t ALL_CLUSTER_VMS < <( __get_cluster_vms__ )
# @return
#   Prints each QEMU VMID on a separate line.
__get_cluster_vms__() {
    __install_or_prompt__ "jq"
    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r '.[] | select(.type=="qemu") | .vmid'
}

# --- Get All VMs on a Server -----------------------------------------------
# @function __get_server_vms__
# @description Retrieves the VMIDs for all VMs (QEMU) on a specific server.
#   The server can be specified by hostname, IP address, or "local".
# @usage
#   readarray -t NODE_VMS < <( __get_server_vms__ "local" )
# @param 1 Hostname/IP/"local" specifying the server.
# @return
#   Prints each QEMU VMID on its own line.
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

    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r --arg NODENAME "$nodeName" \
            '.[] | select(.type=="qemu" and .node==$NODENAME) | .vmid'
}

# GLOBAL associative array to remember user-subnet inputs per bridge
declare -A BRIDGE_SUBNET_CACHE
# --- Get IP from a QEMU VMID -----------------------------------------------
# @function __get_ip_from_vmid__
# @description Retrieves the IP address of a VM by using its net0 MAC address
#   for an ARP scan on the default interface (vmbr0). Prints the IP if found.
# @usage
#   __get_ip_from_vmid__ 100
# @param 1 The VMID
# @return
#   Prints the discovered IP or exits 1 if not found.
__get_ip_from_vmid__() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        echo "Error: __get_ip_from_vmid__ requires a VMID argument." >&2
        return 1
    fi

    # 1) Retrieve MAC address from net0
    local mac
    mac=$(
        qm config "$vmid" \
        | grep -E '^net[0-9]+:' \
        | grep -oE '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}'
    )
    if [[ -z "$mac" ]]; then
        echo "Error: Could not retrieve net0 MAC address for VMID '$vmid'." >&2
        return 1
    fi

    # 1) Try to retrieve IP via QEMU Guest Agent: network-get-interfaces
    #
    #    This works on both Linux and Windows if the guest agent is installed & running.
    #    We parse JSON with jq to get the first IPv4 address we find.
    #
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
    
    # If the result is empty or "null," we didn't get any valid IP from the guest.
    if [[ -n "$guest_ip" && "$guest_ip" != "null" ]]; then
        echo "$guest_ip"
        return 0
    fi

    echo " - Unable to retrieve IP via guest agent. Falling back to ARP scan..."

    # 3) Identify the bridge from net0 config
    local bridge
    bridge=$(
        qm config "$vmid" \
        | grep -E '^net[0-9]+:' \
        | grep -oP 'bridge=\K[^,]+'
    )
    if [[ -z "$bridge" ]]; then
        echo "Error: Could not determine which bridge interface is used by VMID '$vmid'." >&2
        return 1
    fi

    # 4) Check if the bridge has an IP address on the host
    #    If not, we'll need to prompt for a subnet, unless already cached.
    local interface_ip
    interface_ip=$(ip -o -4 addr show dev "$bridge" | awk '{print $4}' | head -n1)  # e.g. "192.168.13.1/24"

    # If there's no IP on the bridge, either use a cached user subnet or prompt
    local subnet_to_scan
    if [[ -z "$interface_ip" ]]; then
        # Check if we already asked the user this session
        if [[ -n "${BRIDGE_SUBNET_CACHE[$bridge]}" ]]; then
            subnet_to_scan="${BRIDGE_SUBNET_CACHE[$bridge]}"
            echo " - Using cached subnet '$subnet_to_scan' for bridge '$bridge'"
        else
            # Prompt user for the subnet in CIDR format
            read -r -p "Bridge '$bridge' has no IP. Enter the subnet to scan (e.g. 192.168.13.0/24): " subnet_to_scan
            BRIDGE_SUBNET_CACHE[$bridge]="$subnet_to_scan"
        fi
    else
        # If the bridge has an IP, let's assume we can do --localnet
        # e.g. interface_ip is "192.168.13.1/24", so we can parse out the network part
        # But typically, --localnet should just work. We'll just use it directly:
        subnet_to_scan="--localnet"
    fi

    # 5) ARP scan
    #    If the user gave a CIDR block (like 192.168.13.0/24), use it
    #    Optionally set --arpspa if the interface doesn't have an IP
    local scannedIp
    if [[ "$subnet_to_scan" == "--localnet" ]]; then
        # The bridge has an IP, so we can do localnet:
        scannedIp=$(arp-scan --interface="$bridge" --localnet 2>/dev/null \
            | grep -i "$mac" \
            | awk '{print $1}' \
            | head -n1)
    else
        # The user-specified subnet in CIDR form, like "192.168.13.0/24"
        # For the ARP Source Protocol Address (arpspa), we can pick a random IP or parse it from user input
        # but let's just do a "fake" IP from that subnet or rely on user to input an IP we can use. 
        # We'll parse out "192.168.13.0" from the subnet to compute a .1 address, if desired.
        # For simplicity: just run with no ARP source or prompt for one. We'll demonstrate a minimal approach.

        # Example of computing an arpspa from user input "192.168.13.0/24" -> "192.168.13.1"
        # This is simplistic. If user typed "10.0.12.5/22", we'd need more robust logic. 
        # We'll just replace the last octet with .1 if it ends in .0
        local base_ip
        base_ip=$(echo "$subnet_to_scan" | cut -d '/' -f1)  # e.g. "192.168.13.0"
        base_ip="${base_ip%.*}.1"                           # e.g. "192.168.13.1"

        scannedIp=$(arp-scan --interface="$bridge" --arpspa="$base_ip" "$subnet_to_scan" 2>/dev/null \
            | grep -i "$mac" \
            | awk '{print $1}' \
            | head -n1)
    fi

    if [[ -z "$scannedIp" ]]; then
        echo "Error: Could not find an IP for VMID '$vmid' with MAC '$mac' on bridge '$bridge'." >&2
        return 1
    fi

    # Return the IP address
    echo "$scannedIp"
    return 0
}
