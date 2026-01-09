#!/bin/bash
#
# Cluster.sh
#
# Proxmox Cluster Topology and Node Resolution Utilities
# Provides functions for cluster membership, node queries, VM/CT listing, and validation
#
# Note: IP discovery functions have been moved to Discovery.sh
#   - get_ip_from_vmid -> Discovery.sh
#   - __get_ip_from_guest_agent__ -> Discovery.sh
#   - __get_ip_from_name__ -> Discovery.sh
#   - __get_name_from_ip__ -> Discovery.sh
#
# Dependencies:
#   - Logger.sh (for logging)
#   - API.sh (for VM/CT operations)
#
# Usage:
#   source "${UTILITYPATH}/Cluster.sh"
#
# Function Index:
#   - __query_log__
#   - __get_remote_node_ips__
#   - __check_cluster_membership__
#   - __get_number_of_cluster_nodes__
#   - __init_node_mappings__
#   - __get_server_lxc__
#   - __get_cluster_vms__
#   - __get_server_vms__
#   - __get_vm_node__
#   - __get_ct_node__
#   - __resolve_node_name__
#   - __validate_vm_id_range__
#   - __validate_vmid__
#   - __check_vm_status__
#   - __validate_ctid__
#   - __check_ct_status__
#   - __is_local_ip__
#   - __get_cluster_cts__
#   - __get_pool_vms__
#

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Source Discovery for IP/name resolution functions
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Discovery.sh" ]]; then
    # shellcheck source=Utilities/Discovery.sh
    source "${UTILITYPATH}/Discovery.sh"
fi

# Safe logging wrapper
__query_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "QUERY"
    fi
}

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
    __query_log__ "DEBUG" "Getting remote node IPs from cluster"
    local -a remote_nodes=()
    while IFS= read -r ip; do
        remote_nodes+=("$ip")
    done < <(pvecm status | awk '/^0x/ && !/\(local\)/ {print $3}')

    __query_log__ "DEBUG" "Found ${#remote_nodes[@]} remote node(s)"
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
    __query_log__ "DEBUG" "Checking cluster membership"
    local cluster_name
    cluster_name=$(pvecm status 2>/dev/null | awk -F': ' '/^Name:/ {print $2}' | xargs)

    if [[ -z "$cluster_name" ]]; then
        __query_log__ "ERROR" "Node is not recognized as part of a cluster"
        echo "Error: This node is not recognized as part of a cluster by pvecm."
        exit 3
    else
        __query_log__ "INFO" "Node is in cluster: $cluster_name"
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
    __query_log__ "DEBUG" "Counting cluster nodes"
    local node_count
    node_count=$(pvecm nodes | awk '/^[[:space:]]*[0-9]/ {count++} END {print count}')
    __query_log__ "DEBUG" "Found $node_count node(s) in cluster"
    echo "$node_count"
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
    __query_log__ "DEBUG" "Initializing node mappings"
    # Reset the arrays.
    NODEID_TO_IP=()
    NODEID_TO_NAME=()
    NAME_TO_IP=()
    IP_TO_NAME=()

    # Process the output from pvecm status.
    while IFS= read -r line; do
        # Extract the first and third fields.
        local nodeid_hex ip_part
        nodeid_hex=$(awk '{print $1}' <<<"$line" | xargs) # xargs trims whitespace.
        ip_part=$(awk '{print $3}' <<<"$line" | xargs)
        ip_part="${ip_part//(local)/}"
        ip_part=$(echo "$ip_part" | xargs) # Trim any leftover spaces.

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
        nodeid_dec=$(awk '{print $1}' <<<"$line" | xargs)
        name_part=$(awk '{print $3}' <<<"$line" | xargs)
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
            __query_log__ "TRACE" "Mapped node: $name -> $ip"
        fi
    done

    MAPPINGS_INITIALIZED=1
    __query_log__ "INFO" "Node mappings initialized: ${#NAME_TO_IP[@]} nodes"
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

    __query_log__ "DEBUG" "Retrieving LXC containers for node: $nodeSpec"

    if [[ "$nodeSpec" == "local" ]]; then
        nodeName="$(hostname -s)"
    elif [[ "$nodeSpec" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        nodeName="$(__get_name_from_ip__ "$nodeSpec")"
    else
        nodeName="$nodeSpec"
    fi

    if [[ -z "$nodeName" ]]; then
        __query_log__ "ERROR" "Unable to determine node name for: $nodeSpec"
        echo "Error: Unable to determine node name for '$nodeSpec'." >&2
        return 1
    fi

    __query_log__ "DEBUG" "Resolved node name: $nodeName"

    local lxc_list
    lxc_list=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r --arg NODENAME "$nodeName" \
            '.[] | select(.type=="lxc" and .node==$NODENAME) | .vmid')
    local count
    count=$(echo "$lxc_list" | grep -c '^' || echo 0)
    __query_log__ "DEBUG" "Found $count LXC containers on $nodeName"
    echo "$lxc_list"
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
    __query_log__ "DEBUG" "Retrieving cluster QEMU VMs"
    __install_or_prompt__ "jq"
    local vm_list
    vm_list=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r '.[] | select(.type=="qemu") | .vmid')
    local count
    count=$(echo "$vm_list" | grep -c '^' || echo 0)
    __query_log__ "DEBUG" "Found $count QEMU VMs in cluster"
    echo "$vm_list"
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

    __query_log__ "DEBUG" "Retrieving QEMU VMs for node: $nodeSpec"

    if [[ "$nodeSpec" == "local" ]]; then
        nodeName="$(hostname -s)"
    elif [[ "$nodeSpec" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        nodeName="$(__get_name_from_ip__ "$nodeSpec")"
    else
        nodeName="$nodeSpec"
    fi

    if [[ -z "$nodeName" ]]; then
        __query_log__ "ERROR" "Unable to determine node name for: $nodeSpec"
        echo "Error: Unable to determine node name for '$nodeSpec'." >&2
        return 1
    fi

    __query_log__ "DEBUG" "Resolved node name: $nodeName"

    local vm_list
    vm_list=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r --arg NODENAME "$nodeName" \
            '.[] | select(.type=="qemu" and .node==$NODENAME) | .vmid')
    local count
    count=$(echo "$vm_list" | grep -c '^' || echo 0)
    __query_log__ "DEBUG" "Found $count QEMU VMs on $nodeName"
    echo "$vm_list"
}

# --- __get_vm_node__ ---------------------------------------------------------
# @function __get_vm_node__
# @description Gets the node name where a specific VM is located in the cluster.
#   Returns empty string if VM is not found.
# @usage local node=$(__get_vm_node__ 400)
# @param 1 The VMID to locate.
# @return Prints the node name to stdout, or empty string if not found.
# @example_output For __get_vm_node__ 400, the output might be:
#   pve01
# --- __get_vm_node__ ---------------------------------------------------------
# @function __get_vm_node__
# @description Get the node name where a VM is located
# @usage local node=$(__get_vm_node__ <vmid>)
# @param 1 VM ID
# @return Prints node name to stdout
__get_vm_node__() {
    local vmid="$1"
    __query_log__ "TRACE" "Getting node for VM: $vmid"

    if [[ -z "$vmid" ]]; then
        __query_log__ "ERROR" "No VMID provided"
        echo "Error: __get_vm_node__ requires a VMID argument." >&2
        return 1
    fi

    __install_or_prompt__ "jq"

    local node
    node=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r --arg VMID "$vmid" '.[] | select(.type=="qemu" and .vmid==($VMID|tonumber)) | .node' 2>/dev/null || true)

    if [[ -n "$node" ]]; then
        __query_log__ "DEBUG" "VM $vmid is on node: $node"
    else
        __query_log__ "WARN" "VM $vmid not found in cluster"
    fi

    echo "$node"
}

# --- __get_ct_node__ ---------------------------------------------------------
# @function __get_ct_node__
# @description Get the node name where a container is located
# @usage local node=$(__get_ct_node__ <ctid>)
# @param 1 Container ID
# @return Prints node name to stdout
__get_ct_node__() {
    local ctid="$1"
    __query_log__ "TRACE" "Getting node for CT: $ctid"

    if [[ -z "$ctid" ]]; then
        __query_log__ "ERROR" "No CTID provided"
        echo "Error: __get_ct_node__ requires a CTID argument." >&2
        return 1
    fi

    __install_or_prompt__ "jq"

    local node
    node=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r --arg CTID "$ctid" '.[] | select(.type=="lxc" and .vmid==($CTID|tonumber)) | .node' 2>/dev/null || true)

    if [[ -n "$node" ]]; then
        __query_log__ "DEBUG" "CT $ctid is on node: $node"
    else
        __query_log__ "WARN" "CT $ctid not found in cluster"
    fi

    echo "$node"
}

# --- __resolve_node_name__ ---------------------------------------------------
# @function __resolve_node_name__
# @description Resolves a node specification (local/hostname/IP) to a node name.
#   Converts "local" to the current hostname, resolves IPs to node names.
# @usage local node=$(__resolve_node_name__ "local")
# @param 1 Node specification: "local", hostname, or IP address.
# @return Prints the resolved node name to stdout, or exits 1 if resolution fails.
# @example_output For __resolve_node_name__ "local", the output might be:
#   pve01
# @example_output For __resolve_node_name__ "192.168.1.20", the output might be:
#   pve02
__resolve_node_name__() {
    local node_spec="$1"
    local node_name

    __query_log__ "TRACE" "Resolving node spec: $node_spec"

    if [[ -z "$node_spec" ]]; then
        __query_log__ "ERROR" "No node specification provided"
        echo "Error: __resolve_node_name__ requires a node specification argument." >&2
        return 1
    fi

    if [[ "$node_spec" == "local" ]]; then
        node_name="$(hostname -s)"
        __query_log__ "DEBUG" "Resolved 'local' to: $node_name"
    elif [[ "$node_spec" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        node_name="$(__get_name_from_ip__ "$node_spec")"
        if [[ -z "$node_name" ]]; then
            __query_log__ "ERROR" "Unable to resolve IP to node name: $node_spec"
            echo "Error: Unable to resolve node name from IP: ${node_spec}" >&2
            return 1
        fi
    else
        node_name="$node_spec"
        __query_log__ "DEBUG" "Using node spec as-is: $node_name"
    fi

    echo "$node_name"
}

# --- __validate_vm_id_range__ ------------------------------------------------
# @function __validate_vm_id_range__
# @description Validates that VM IDs are numeric and in correct order.
# @usage __validate_vm_id_range__ "$START_ID" "$END_ID"
# @param 1 Start VM ID.
# @param 2 End VM ID.
# @return Returns 0 if valid, 1 if invalid (with error message to stderr).
# @example __validate_vm_id_range__ 400 430
__validate_vm_id_range__() {
    local start_id="$1"
    local end_id="$2"

    __query_log__ "TRACE" "Validating VM ID range: $start_id to $end_id"

    if [[ -z "$start_id" ]] || [[ -z "$end_id" ]]; then
        __query_log__ "ERROR" "Missing start or end VM ID"
        echo "Error: __validate_vm_id_range__ requires start and end VM IDs." >&2
        return 1
    fi

    if ! [[ "$start_id" =~ ^[0-9]+$ ]] || ! [[ "$end_id" =~ ^[0-9]+$ ]]; then
        __query_log__ "ERROR" "Non-numeric VM IDs: start=$start_id, end=$end_id"
        echo "Error: VM IDs must be numeric (got start='$start_id', end='$end_id')." >&2
        return 1
    fi

    if ((start_id > end_id)); then
        __query_log__ "ERROR" "Invalid range: start ($start_id) > end ($end_id)"
        echo "Error: Start VM ID must be less than or equal to end VM ID (got start=$start_id, end=$end_id)." >&2
        return 1
    fi

    __query_log__ "DEBUG" "VM ID range validated: $start_id-$end_id"
    return 0
}

# --- __validate_vmid__ -------------------------------------------------------
# @function __validate_vmid__
# @description Validates that a VMID exists and is a VM (qemu), not a container.
#   Exits with error if VMID doesn't exist or is not a VM.
# @usage __validate_vmid__ <vmid>
# @param vmid The VM ID to validate
# @return 0 if valid VM, exits with error otherwise
# @example_output For __validate_vmid__ 100:
#   VMID 100 is a valid VM
__validate_vmid__() {
    local vmid="$1"

    __query_log__ "TRACE" "Validating VMID: ${vmid:-<empty>}"

    if [[ -z "$vmid" ]]; then
        __query_log__ "ERROR" "VMID validation failed: VMID is required"
        echo "Error: VMID is required" >&2
        return 1
    fi

    # Validate VMID is numeric
    if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
        __query_log__ "ERROR" "VMID validation failed: '$vmid' is not numeric"
        echo "Error: Invalid VMID '${vmid}' - must be numeric" >&2
        return 1
    fi

    # Check if it's a VM
    if qm status "$vmid" &>/dev/null; then
        __query_log__ "DEBUG" "VMID $vmid validated successfully (is a VM)"
        return 0
    fi

    # Check if it's a container (not valid for this function)
    if pct status "$vmid" &>/dev/null; then
        __query_log__ "WARN" "VMID $vmid is a container, not a VM"
        echo "Error: VMID ${vmid} is a container, not a VM" >&2
        echo "Use __validate_ctid__ for containers" >&2
        return 1
    fi

    # VMID doesn't exist
    __query_log__ "ERROR" "VMID $vmid not found in system"
    echo "Error: VMID ${vmid} not found" >&2
    return 1
}

# --- __check_vm_status__ -----------------------------------------------------
# @function __check_vm_status__
# @description Checks if a VM is running and optionally stops it with user confirmation.
#   Can be used in force mode to skip confirmation.
# @usage __check_vm_status__ <vmid> [--stop] [--force]
# @param vmid The VM ID to check
# @param --stop Optional: Offer to stop the VM if running
# @param --force Optional: Stop without confirmation (requires --stop)
# @return 0 if VM is stopped, 1 if running and not stopped
# @example __check_vm_status__ 100 --stop --force
__check_vm_status__() {
    local vmid="$1"
    shift

    __query_log__ "TRACE" "Checking VM status: $vmid"

    local should_stop=false
    local force_stop=false

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stop)
                should_stop=true
                shift
                ;;
            --force)
                force_stop=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local status
    status=$(qm status "$vmid" 2>/dev/null | awk '{print $2}')
    __query_log__ "DEBUG" "VM $vmid status: $status"

    if [[ "$status" != "running" ]]; then
        __query_log__ "DEBUG" "VM $vmid is not running"
        return 0
    fi

    # VM is running
    if ! $should_stop; then
        __query_log__ "WARN" "VM $vmid is running (no --stop flag)"
        echo "Warning: VM ${vmid} is running" >&2
        return 1
    fi

    # Should stop - check if we need confirmation
    if ! $force_stop; then
        __query_log__ "INFO" "Prompting user to stop VM $vmid"
        echo "VM ${vmid} is currently running and must be stopped" >&2
        read -p "Stop VM ${vmid} now? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            __query_log__ "INFO" "User declined to stop VM $vmid"
            echo "Operation cancelled" >&2
            return 1
        fi
    fi

    # Stop the VM
    __query_log__ "INFO" "Stopping VM $vmid"
    if ! qm stop "$vmid" 2>&1; then
        __query_log__ "ERROR" "Failed to stop VM $vmid"
        echo "Error: Failed to stop VM ${vmid}" >&2
        return 1
    fi

    # Wait for VM to fully stop
    local wait_count=0
    while [[ "$(qm status "$vmid" 2>/dev/null | awk '{print $2}')" == "running" ]]; do
        sleep 2
        wait_count=$((wait_count + 1))
        if [[ $wait_count -gt 30 ]]; then
            __query_log__ "ERROR" "Timeout waiting for VM $vmid to stop"
            echo "Error: Timeout waiting for VM ${vmid} to stop" >&2
            return 1
        fi
    done

    __query_log__ "INFO" "VM $vmid stopped successfully"
    return 0
}

# --- __validate_ctid__ -------------------------------------------------------
# @function __validate_ctid__
# @description Validates that a CTID exists and is a container (lxc), not a VM.
#   Exits with error if CTID doesn't exist or is not a container.
# @usage __validate_ctid__ <ctid>
# @param ctid The container ID to validate
# @return 0 if valid container, exits with error otherwise
# @example_output For __validate_ctid__ 100:
#   CTID 100 is a valid container
__validate_ctid__() {
    local ctid="$1"

    __query_log__ "TRACE" "Validating CTID: ${ctid:-<empty>}"

    if [[ -z "$ctid" ]]; then
        __query_log__ "ERROR" "CTID validation failed: CTID is required"
        echo "Error: CTID is required" >&2
        return 1
    fi

    # Validate CTID is numeric
    if ! [[ "$ctid" =~ ^[0-9]+$ ]]; then
        __query_log__ "ERROR" "CTID validation failed: '$ctid' is not numeric"
        echo "Error: Invalid CTID '${ctid}' - must be numeric" >&2
        return 1
    fi

    # Check if it's a container
    if pct status "$ctid" &>/dev/null; then
        __query_log__ "DEBUG" "CTID $ctid validated successfully (is a container)"
        return 0
    fi

    # Check if it's a VM (not valid for this function)
    if qm status "$ctid" &>/dev/null; then
        __query_log__ "WARN" "CTID $ctid is a VM, not a container"
        echo "Error: CTID ${ctid} is a VM, not a container" >&2
        echo "Use __validate_vmid__ for VMs" >&2
        return 1
    fi

    # CTID doesn't exist
    __query_log__ "ERROR" "CTID $ctid not found in system"
    echo "Error: CTID ${ctid} not found" >&2
    return 1
}

# --- __check_ct_status__ -----------------------------------------------------
# @function __check_ct_status__
# @description Checks if a container is running and optionally stops it with user confirmation.
#   Can be used in force mode to skip confirmation.
# @usage __check_ct_status__ <ctid> [--stop] [--force]
# @param ctid The container ID to check
# @param --stop Optional: Offer to stop the container if running
# @param --force Optional: Stop without confirmation (requires --stop)
# @return 0 if container is stopped, 1 if running and not stopped
# @example __check_ct_status__ 100 --stop --force
__check_ct_status__() {
    local ctid="$1"
    shift

    __query_log__ "TRACE" "Checking container status: $ctid"

    local should_stop=false
    local force_stop=false

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stop)
                should_stop=true
                shift
                ;;
            --force)
                force_stop=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local status
    status=$(pct status "$ctid" 2>/dev/null | awk '{print $2}')
    __query_log__ "DEBUG" "Container $ctid status: $status"

    if [[ "$status" != "running" ]]; then
        __query_log__ "DEBUG" "Container $ctid is not running"
        return 0
    fi

    # Container is running
    if ! $should_stop; then
        __query_log__ "WARN" "Container $ctid is running (no --stop flag)"
        echo "Warning: Container ${ctid} is running" >&2
        return 1
    fi

    # Should stop - check if we need confirmation
    if ! $force_stop; then
        __query_log__ "INFO" "Prompting user to stop container $ctid"
        echo "Container ${ctid} is currently running and must be stopped" >&2
        read -p "Stop container ${ctid} now? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            __query_log__ "INFO" "User declined to stop container $ctid"
            echo "Operation cancelled" >&2
            return 1
        fi
    fi

    # Stop the container
    __query_log__ "INFO" "Stopping container $ctid"
    if ! pct stop "$ctid" 2>&1; then
        __query_log__ "ERROR" "Failed to stop container $ctid"
        echo "Error: Failed to stop container ${ctid}" >&2
        return 1
    fi

    # Wait for container to fully stop
    local wait_count=0
    while [[ "$(pct status "$ctid" 2>/dev/null | awk '{print $2}')" == "running" ]]; do
        sleep 2
        wait_count=$((wait_count + 1))
        if [[ $wait_count -gt 30 ]]; then
            __query_log__ "ERROR" "Timeout waiting for container $ctid to stop"
            echo "Error: Timeout waiting for container ${ctid} to stop" >&2
            return 1
        fi
    done

    __query_log__ "INFO" "Container $ctid stopped successfully"
    return 0
}

# --- __is_local_ip__ ---------------------------------------------------------
# Check if a given IP address belongs to the local node.
#
# Parameters:
#   $1 - IP address to check
#
# Returns:
#   0 if IP is local, 1 otherwise
#
# Example:
#   if __is_local_ip__ "192.168.1.100"; then
#       echo "IP is local"
#   fi
#
__is_local_ip__() {
    local ip_to_check="$1"
    local local_ips ip

    __query_log__ "TRACE" "Checking if IP is local: $ip_to_check"

    local_ips=$(hostname -I)

    for ip in $local_ips; do
        if [[ "$ip" == "$ip_to_check" ]]; then
            __query_log__ "DEBUG" "IP $ip_to_check is local"
            return 0
        fi
    done

    __query_log__ "DEBUG" "IP $ip_to_check is not local"
    return 1
}

# --- __get_cluster_cts__ -----------------------------------------------------
# @function __get_cluster_cts__
# @description Get all container IDs across the cluster
# @usage mapfile -t cts < <(__get_cluster_cts__)
# @return Prints container IDs, one per line
__get_cluster_cts__() {
    __query_log__ "DEBUG" "Getting all cluster containers"
    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r '.[] | select(.type == "lxc") | .vmid' | sort -n
}

# --- __get_pool_vms__ --------------------------------------------------------
# @function __get_pool_vms__
# @description Get all VM IDs in a specific pool
# @usage mapfile -t vms < <(__get_pool_vms__ "pool_name")
# @param 1 Pool name
# @return Prints VM IDs, one per line
__get_pool_vms__() {
    local pool_name="$1"
    __query_log__ "DEBUG" "Getting VMs from pool: $pool_name"
    pvesh get "/pools/$pool_name" --output-format json 2>/dev/null \
        | jq -r '.members[]? | select(.type == "qemu") | .vmid' | sort -n
}

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2026-01-08
#
# Changes:
# - 2026-01-08: Implemented file-based query caching
# - 2026-01-08: Added query result caching for __get_vm_node__ and __get_ct_node__
# - 2025-11-24: Validated against CONTRIBUTING.md and PVE Guide Chapter 5
# - 2025-11-24: Fixed ShellCheck warnings (SC2155 - declare/assign separation)
# - Initial creation
#
# Fixes:
# - 2025-11-24: Separated variable declarations from assignments to avoid masking return values
#
# Known issues:
# - IP_TO_NAME and MAPPINGS_INITIALIZED marked as unused by ShellCheck (intentional - used by external callers)
#

