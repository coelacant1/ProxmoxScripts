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
    __install_or_prompt__ "jq"
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
