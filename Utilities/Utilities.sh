#!/bin/bash
#
# Utilities.sh
#
# A script containing reusable functions for Proxmox management and automation.
# Designed to be sourced and used as a library in other scripts.
#

set -e

###############################################################################
# GLOBALS
###############################################################################
# Array to keep track of packages installed by install_or_prompt() in this session.
SESSION_INSTALLED_PACKAGES=()


###############################################################################
# 1. Misc Functions
###############################################################################

# --- Check Proxmox and Root User -------------------------------------------
# @function check_proxmox_and_root
# @description Checks if the current user is root and if this is a Proxmox node.
# Exits if either condition is not met.
# @usage
#   check_proxmox_and_root
# @return
#   Exits 1 if not root, exits 2 if not Proxmox.
check_proxmox_and_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root (sudo)."
        exit 1
    fi

    if ! command -v pveversion &>/dev/null; then
        echo "Error: 'pveversion' command not found. Are you sure this is a Proxmox node?"
        exit 2
    fi
}

# --- Install or Prompt Function --------------------------------------------
# @function install_or_prompt
# @description Checks if a specified command is available. If not, prompts
# the user to install it via apt-get. Exits if the user declines.
# Also keeps track of installed packages in SESSION_INSTALLED_PACKAGES.
# @usage
#   install_or_prompt <command_name>
# @param command_name The name of the command to check and install if missing.
# @return
#   Exits 1 if user declines the installation.
install_or_prompt() {
    local cmd="$1"

    if ! command -v "$cmd" &>/dev/null; then
        echo "The '$cmd' utility is required but is not installed."
        read -r -p "Would you like to install '$cmd' now? [y/N]: " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            apt-get install -y "$cmd"
            # Keep track of what we've installed in this session
            SESSION_INSTALLED_PACKAGES+=("$cmd")
        else
            echo "Aborting script because '$cmd' is not installed."
            exit 1
        fi
    fi
}

# --- Prompt to Keep or Remove Installed Packages ----------------------------
# @function prompt_keep_installed_packages
# @description Prompts the user whether to keep or remove all packages that
# were installed in this session via install_or_prompt(). If the user chooses
# "No", each package in SESSION_INSTALLED_PACKAGES is removed.
# @usage
#   prompt_keep_installed_packages
# @return
#   Removes packages if user says "No", otherwise does nothing.
prompt_keep_installed_packages() {
    # If no packages were installed this session, there's nothing to remove
    if [[ ${#SESSION_INSTALLED_PACKAGES[@]} -eq 0 ]]; then
        return
    fi

    echo "The following packages were installed during this session:"
    printf ' - %s\n' "${SESSION_INSTALLED_PACKAGES[@]}"
    read -r -p "Do you want to KEEP these packages? [Y/n]: " response

    # Default is 'Yes' (keep them)
    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo "Removing the packages installed in this session..."
        apt-get remove -y "${SESSION_INSTALLED_PACKAGES[@]}"
        # Optionally remove them completely (configs, etc.) with apt-get purge:
        # apt-get purge -y "${SESSION_INSTALLED_PACKAGES[@]}"
        SESSION_INSTALLED_PACKAGES=()
        echo "Packages removed."
    else
        echo "Keeping all installed packages."
    fi
}

# --- Get Remote Node IPs ---------------------------------------------------
# @function get_remote_node_ips
# @description Gathers IPs for all cluster nodes (excluding local) from 'pvecm status'.
# Outputs each IP on a new line, which can be captured into an array with readarray.
# @usage
#   readarray -t REMOTE_NODES < <( get_remote_node_ips )
# @return
#   Prints each remote node IP on a separate line to stdout.
get_remote_node_ips() {
    local -a remote_nodes=()
    while IFS= read -r ip; do
        remote_nodes+=("$ip")
    done < <(pvecm status | awk '/^0x/ && !/\(local\)/ {print $3}')

    for node_ip in "${remote_nodes[@]}"; do
        echo "$node_ip"
    done
}

# --- Check Cluster Membership ----------------------------------------------
# @function check_cluster_membership
# @description Checks if the node is recognized as part of a cluster by examining
# 'pvecm status'. If no cluster name is found, it exits with an error.
# @usage
#   check_cluster_membership
# @return
#   Exits 3 if the node is not in a cluster (according to pvecm).
check_cluster_membership() {
    local cluster_name
    # Extract the cluster name from the line beginning with "Name:"
    cluster_name=$(pvecm status 2>/dev/null | awk -F': ' '/^Name:/ {print $2}' | xargs)

    if [[ -z "$cluster_name" ]]; then
        echo "Error: This node is not recognized as part of a cluster by pvecm."
        exit 3
    else
        echo "Node is in a cluster named: $cluster_name"
    fi
}

# ---------------------------------------------------------------------------
# @function get_number_of_cluster_nodes
# @description
#   Returns the total number of nodes in the cluster by counting lines matching
#   a numeric ID from `pvecm nodes`.
# @usage
#   local num_nodes=$(get_number_of_cluster_nodes)
# @return
#   Prints the count of cluster nodes to stdout.
# ---------------------------------------------------------------------------
get_number_of_cluster_nodes() {
    echo "$(pvecm nodes | awk '/^[[:space:]]*[0-9]/ {count++} END {print count}')"
}



###############################################################################
# 2. IP CONVERSION UTILITIES
###############################################################################

# --- IP to Integer ---------------------------------------------------------
# @function ip_to_int
# @description Converts a dotted IPv4 address string to its 32-bit integer equivalent.
# @usage
#   local ip_integer=$(ip_to_int "127.0.0.1")
# @param 1 Dotted IPv4 address string (e.g., "192.168.1.10")
# @return
#   Prints the 32-bit integer representation of the IP to stdout.
ip_to_int() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    echo "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
}

# --- Integer to IP ---------------------------------------------------------
# @function int_to_ip
# @description Converts a 32-bit integer to its dotted IPv4 address equivalent.
# @usage
#   local ip_string=$(int_to_ip 2130706433)
# @param 1 32-bit integer
# @return
#   Prints the dotted IPv4 address string to stdout.
int_to_ip() {
    local ip
    ip=$(printf "%d.%d.%d.%d" \
        "$(( ($1 >> 24) & 255 ))" \
        "$(( ($1 >> 16) & 255 ))" \
        "$(( ($1 >> 8)  & 255 ))" \
        "$((  $1        & 255 ))")
    echo "$ip"
}

# Declare global associative arrays to store node mappings
declare -A NODEID_TO_IP=()
declare -A NODEID_TO_NAME=()
declare -A NAME_TO_IP=()
declare -A IP_TO_NAME=()

# Flag to track whether we have already built the maps
MAPPINGS_INITIALIZED=0

# ---------------------------------------------------------------------------
# @function init_node_mappings
# @description
#   Parses `pvecm status` and `pvecm nodes` to build internal maps:
#     NODEID_TO_IP[nodeid]   -> IP
#     NODEID_TO_NAME[nodeid] -> Name
#   Then creates:
#     NAME_TO_IP[name]       -> IP
#     IP_TO_NAME[ip]         -> name
#   This function is called automatically by get_ip_from_name/get_name_from_ip
#   if maps are not yet built.
# ---------------------------------------------------------------------------
init_node_mappings() {
  # Clear arrays in case this function is rerun
  NODEID_TO_IP=()
  NODEID_TO_NAME=()
  NAME_TO_IP=()
  IP_TO_NAME=()

  # 1) Build { nodeid_decimal => IP } from `pvecm status`
  #    Example lines:
  #    0x00000001          1 172.20.83.21
  while IFS= read -r line; do
    # Each line has 3+ fields:
    #   $1=0xHEX, $2=Votes, $3=IP (possibly with '(local)')
    # We extract nodeid_hex and ip.
    # Example: "0x00000001          1 172.20.83.21"
    nodeid_hex=$(awk '{print $1}' <<< "$line")
    ip_part=$(awk '{print $3}' <<< "$line")

    # Strip "(local)" from the IP if present
    ip_part="${ip_part//(local)/}"

    # Convert hex nodeid to decimal (e.g., 0x00000001 -> 1)
    nodeid_dec=$((16#${nodeid_hex#0x}))

    # Store in associative array
    NODEID_TO_IP["$nodeid_dec"]="$ip_part"
  done < <(pvecm status 2>/dev/null | awk '/^0x/{print}')

  # 2) Build { nodeid_decimal => Name } from `pvecm nodes`
  #    Example lines:
  #    1          1 IHK01
  while IFS= read -r line; do
    # Each line has 3+ fields:
    #   $1=nodeid_decimal, $2=Votes, $3=Name (possibly with '(local)')
    nodeid_dec=$(awk '{print $1}' <<< "$line")
    name_part=$(awk '{print $3}' <<< "$line")

    # Strip "(local)" from the name if present
    name_part="${name_part//(local)/}"

    # Store in associative array
    NODEID_TO_NAME["$nodeid_dec"]="$name_part"
  done < <(pvecm nodes 2>/dev/null | awk '/^[[:space:]]*[0-9]/ {print}')

  # 3) Combine them into NAME_TO_IP and IP_TO_NAME
  for nodeid in "${!NODEID_TO_NAME[@]}"; do
    local name="${NODEID_TO_NAME[$nodeid]}"
    local ip="${NODEID_TO_IP[$nodeid]}"

    # Skip if either is empty (meaning we didn’t find a match in the other command)
    if [[ -n "$name" && -n "$ip" ]]; then
      NAME_TO_IP["$name"]="$ip"
      IP_TO_NAME["$ip"]="$name"
    fi
  done

  MAPPINGS_INITIALIZED=1
}

# ---------------------------------------------------------------------------
# @function get_ip_from_name
# @description
#   Given a node’s name (e.g., "IHK01"), prints its link0 IP address to stdout.
#   If not found, prints an error and exits 1.
# @usage
#   get_ip_from_name "IHK03"
# @param 1 The node name
# @return
#   Prints the IP to stdout or exits 1 if not found.
# ---------------------------------------------------------------------------
get_ip_from_name() {
  local node_name="$1"
  if [[ -z "$node_name" ]]; then
    echo "Error: get_ip_from_name requires a node name argument." >&2
    return 1
  fi

  # Initialize mappings if not done yet
  if [[ "$MAPPINGS_INITIALIZED" -eq 0 ]]; then
    init_node_mappings
  fi

  local ip="${NAME_TO_IP[$node_name]}"
  if [[ -z "$ip" ]]; then
    echo "Error: Could not find IP for node name '$node_name'." >&2
    return 1
  fi

  echo "$ip"
}

# ---------------------------------------------------------------------------
# @function get_name_from_ip
# @description
#   Given a node’s link0 IP (e.g., "172.20.83.23"), prints its node name (e.g., "IHK03").
#   If not found, prints an error and exits 1.
# @usage
#   get_name_from_ip "172.20.83.23"
# @param 1 The node IP
# @return
#   Prints the node name to stdout or exits 1 if not found.
# ---------------------------------------------------------------------------
get_name_from_ip() {
  local node_ip="$1"
  if [[ -z "$node_ip" ]]; then
    echo "Error: get_name_from_ip requires an IP argument." >&2
    return 1
  fi

  # Initialize mappings if not done yet
  if [[ "$MAPPINGS_INITIALIZED" -eq 0 ]]; then
    init_node_mappings
  fi

  local name="${IP_TO_NAME[$node_ip]}"
  if [[ -z "$name" ]]; then
    echo "Error: Could not find node name for IP '$node_ip'." >&2
    return 1
  fi

  echo "$name"
}

###############################################################################
# 3. CONTAINER AND VM QUERIES
###############################################################################

# --- Get All LXC Containers in Cluster --------------------------------------
# @function get_cluster_lxc
# @description Retrieves the VMIDs for all LXC containers across the entire cluster.
# Outputs each LXC VMID on its own line, which can be captured into an array.
# @usage
#   readarray -t ALL_CLUSTER_LXC < <( get_cluster_lxc )
# @return
#   Prints each LXC VMID on a separate line.
get_cluster_lxc() {
    local -a container_ids=()
    while IFS= read -r vmid; do
        container_ids+=("$vmid")
    done < <(pvesh get /cluster/resources --type lxc --output-format json 2>/dev/null \
                | awk -F'[:,"]' '/"vmid"/ {gsub(/ /,"",$3); print $3}' )

    for id in "${container_ids[@]}"; do
        echo "$id"
    done
}

# --- Get All LXC Containers on a Server ------------------------------------
# @function get_server_lxc
# @description Retrieves the VMIDs for all LXC containers on a specific server.
# The server can be specified by hostname, IP address, or the word "local" (for this node).
# Outputs each LXC VMID on its own line, which can be captured into an array.
# @usage
#   readarray -t NODE_LXC < <( get_server_lxc "local" )
#   readarray -t NODE_LXC < <( get_server_lxc "172.20.83.21" )
# @param 1 Hostname/IP/"local" specifying the server.
# @return
#   Prints each LXC VMID on a separate line.
get_server_lxc() {
    local server="$1"

    if [[ "$server" == "local" ]]; then
        server="$(hostname)"
    fi

    local -a container_ids=()
    while IFS= read -r vmid; do
        container_ids+=("$vmid")
    done < <(pvesh get "/nodes/${server}/lxc" --output-format json 2>/dev/null \
                | awk -F'[:,"]' '/"vmid"/ {gsub(/ /,"",$3); print $3}' )

    for id in "${container_ids[@]}"; do
        echo "$id"
    done
}

# --- Get All VMs in Cluster ------------------------------------------------
# @function get_cluster_vms
# @description Retrieves the VMIDs for all VMs (QEMU) across the entire cluster.
# Outputs each VM ID on its own line, which can be captured into an array.
# @usage
#   readarray -t ALL_CLUSTER_VMS < <( get_cluster_vms )
# @return
#   Prints each QEMU VMID on a separate line.
get_cluster_vms() {
    local -a vm_ids=()
    while IFS= read -r vmid; do
        vm_ids+=("$vmid")
    done < <(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
                | awk -F'[:,"]' '/"vmid"/ {gsub(/ /,"",$3); print $3}' )

    for id in "${vm_ids[@]}"; do
        echo "$id"
    done
}

# --- Get All VMs on a Server -----------------------------------------------
# @function get_server_vms
# @description Retrieves the VMIDs for all VMs (QEMU) on a specific server.
# The server can be specified by hostname, IP address, or the word "local" (for this node).
# Outputs each VM ID on its own line, which can be captured into an array.
# @usage
#   readarray -t NODE_VMS < <( get_server_vms "local" )
#   readarray -t NODE_VMS < <( get_server_vms "node1.mydomain.local" )
# @param 1 Hostname/IP/"local" specifying the server.
# @return
#   Prints each QEMU VMID on a separate line.
get_server_vms() {
    local server="$1"

    if [[ "$server" == "local" ]]; then
        server="$(hostname)"
    fi

    local -a vm_ids=()
    while IFS= read -r vmid; do
        vm_ids+=("$vmid")
    done < <(pvesh get "/nodes/${server}/qemu" --output-format json 2>/dev/null \
                | awk -F'[:,"]' '/"vmid"/ {gsub(/ /,"",$3); print $3}' )

    for id in "${vm_ids[@]}"; do
        echo "$id"
    done
}
