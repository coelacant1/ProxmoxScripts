#!/bin/bash
#
# Utilities.sh
#
# Provides reusable functions for Proxmox management and automation.
# Typically, it is not run directly. Instead, you source this script from your own.
#
# Usage:
#   source "Utilities.sh"
#   # Then call any of the utility functions below, for example:
#   check_root
#   check_proxmox
#   install_or_prompt "curl"
#   ...
#
# Further Explanation:
# - This library is designed for Proxmox version 8 by default.
# - Each function includes its own usage block in the comments.
# - Not all functions require root privileges, but your calling script might.
# - If a package is not available in a default Proxmox 8 install, call install_or_prompt.
# - You can call prompt_keep_installed_packages at the end of your script to offer
#   removal of session-installed packages.
#

set -e

###############################################################################
# GLOBALS
###############################################################################
# Array to keep track of packages installed by install_or_prompt() in this session.
SESSION_INSTALLED_PACKAGES=()
SPINNER_PID=""

###############################################################################
# 1. Misc Functions
###############################################################################

# --- Check Root User -------------------------------------------------------
# @function check_root
# @description Checks if the current user is root. Exits if not.
# @usage
#   check_root
# @return
#   Exits 1 if not root.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root (sudo)."
        exit 1
    fi
}

# --- Check Proxmox ---------------------------------------------------------
# @function check_proxmox
# @description Checks if this is a Proxmox node. Exits if not.
# @usage
#   check_proxmox
# @return
#   Exits 2 if not Proxmox.
check_proxmox() {
    if ! command -v pveversion &>/dev/null; then
        echo "Error: 'pveversion' command not found. Are you sure this is a Proxmox node?"
        exit 2
    fi
}

# --- Install or Prompt Function --------------------------------------------
# @function install_or_prompt
# @description Checks if a specified command is available. If not, prompts
#   the user to install it via apt-get. Exits if the user declines.
#   Also keeps track of installed packages in SESSION_INSTALLED_PACKAGES.
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
#   were installed in this session via install_or_prompt(). If the user chooses
#   "No", each package in SESSION_INSTALLED_PACKAGES is removed.
# @usage
#   prompt_keep_installed_packages
# @return
#   Removes packages if user says "No", otherwise does nothing.
prompt_keep_installed_packages() {
    if [[ ${#SESSION_INSTALLED_PACKAGES[@]} -eq 0 ]]; then
        return
    fi

    echo "The following packages were installed during this session:"
    printf ' - %s\n' "${SESSION_INSTALLED_PACKAGES[@]}"
    read -r -p "Do you want to KEEP these packages? [Y/n]: " response

    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo "Removing the packages installed in this session..."
        apt-get remove -y "${SESSION_INSTALLED_PACKAGES[@]}"
        # Optional: apt-get purge -y "${SESSION_INSTALLED_PACKAGES[@]}"
        SESSION_INSTALLED_PACKAGES=()
        echo "Packages removed."
    else
        echo "Keeping all installed packages."
    fi
}

###############################################################################
# 2. Cluster/Node Functions
###############################################################################

# --- Get Remote Node IPs ---------------------------------------------------
# @function get_remote_node_ips
# @description Gathers IPs for all cluster nodes (excluding local) from 'pvecm status'.
#   Outputs each IP on a new line, which can be captured into an array with readarray.
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
#   'pvecm status'. If no cluster name is found, it exits with an error.
# @usage
#   check_cluster_membership
# @return
#   Exits 3 if the node is not in a cluster (according to pvecm).
check_cluster_membership() {
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
# @function get_number_of_cluster_nodes
# @description Returns the total number of nodes in the cluster by counting
#   lines matching a numeric ID from `pvecm nodes`.
# @usage
#   local num_nodes=$(get_number_of_cluster_nodes)
# @return
#   Prints the count of cluster nodes to stdout.
get_number_of_cluster_nodes() {
    echo "$(pvecm nodes | awk '/^[[:space:]]*[0-9]/ {count++} END {print count}')"
}

###############################################################################
# 3. IP Conversion Utilities
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
    IFS=. read -r a b c d <<<"$1"
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
        "$((($1 >> 24) & 255))" \
        "$((($1 >> 16) & 255))" \
        "$((($1 >> 8) & 255))" \
        "$(($1 & 255))")
    echo "$ip"
}

###############################################################################
# 4. Node Mapping Functions
###############################################################################

declare -A NODEID_TO_IP=()
declare -A NODEID_TO_NAME=()
declare -A NAME_TO_IP=()
declare -A IP_TO_NAME=()
MAPPINGS_INITIALIZED=0

# --- Initialize Node Mappings ----------------------------------------------
# @function init_node_mappings
# @description Parses `pvecm status` and `pvecm nodes` to build internal maps:
#   NODEID_TO_IP[nodeid]   -> IP
#   NODEID_TO_NAME[nodeid] -> Name
#   Then creates:
#   NAME_TO_IP[name]       -> IP
#   IP_TO_NAME[ip]         -> name
# @usage
#   init_node_mappings
# @return
#   Populates the associative arrays above with node info.
init_node_mappings() {
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
# @function get_ip_from_name
# @description Given a node’s name (e.g., "IHK01"), prints its link0 IP address.
#   Exits if not found.
# @usage
#   get_ip_from_name "IHK03"
# @param 1 The node name
# @return
#   Prints the IP to stdout or exits 1 if not found.
get_ip_from_name() {
    local node_name="$1"
    if [[ -z "$node_name" ]]; then
        echo "Error: get_ip_from_name requires a node name argument." >&2
        return 1
    fi

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

# --- Get Name from Node IP -------------------------------------------------
# @function get_name_from_ip
# @description Given a node’s link0 IP (e.g., "172.20.83.23"), prints its name.
#   Exits if not found.
# @usage
#   get_name_from_ip "172.20.83.23"
# @param 1 The node IP
# @return
#   Prints the node name to stdout or exits 1 if not found.
get_name_from_ip() {
    local node_ip="$1"
    if [[ -z "$node_ip" ]]; then
        echo "Error: get_name_from_ip requires an IP argument." >&2
        return 1
    fi

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
# 5. Container and VM Queries
###############################################################################

# --- Get All LXC Containers in Cluster --------------------------------------
# @function get_cluster_lxc
# @description Retrieves the VMIDs for all LXC containers across the entire cluster.
#   Outputs each LXC VMID on its own line.
# @usage
#   readarray -t ALL_CLUSTER_LXC < <( get_cluster_lxc )
# @return
#   Prints each LXC VMID on a separate line.
get_cluster_lxc() {
    install_or_prompt "jq"
    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r '.[] | select(.type=="lxc") | .vmid'
}

# --- Get All LXC Containers on a Server ------------------------------------
# @function get_server_lxc
# @description Retrieves the VMIDs for all LXC containers on a specific server.
#   The server can be specified by hostname, IP address, or "local".
# @usage
#   readarray -t NODE_LXC < <( get_server_lxc "local" )
# @param 1 Hostname/IP/"local" specifying the server.
# @return
#   Prints each LXC VMID on its own line.
get_server_lxc() {
    local nodeSpec="$1"
    local nodeName

    if [[ "$nodeSpec" == "local" ]]; then
        nodeName="$(hostname -s)"
    elif [[ "$nodeSpec" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        nodeName="$(get_name_from_ip "$nodeSpec")"
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
# @function get_cluster_vms
# @description Retrieves the VMIDs for all VMs (QEMU) across the entire cluster.
#   Outputs each VM ID on its own line.
# @usage
#   readarray -t ALL_CLUSTER_VMS < <( get_cluster_vms )
# @return
#   Prints each QEMU VMID on a separate line.
get_cluster_vms() {
    install_or_prompt "jq"
    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
        | jq -r '.[] | select(.type=="qemu") | .vmid'
}

# --- Get All VMs on a Server -----------------------------------------------
# @function get_server_vms
# @description Retrieves the VMIDs for all VMs (QEMU) on a specific server.
#   The server can be specified by hostname, IP address, or "local".
# @usage
#   readarray -t NODE_VMS < <( get_server_vms "local" )
# @param 1 Hostname/IP/"local" specifying the server.
# @return
#   Prints each QEMU VMID on its own line.
get_server_vms() {
    local nodeSpec="$1"
    local nodeName

    if [[ "$nodeSpec" == "local" ]]; then
        nodeName="$(hostname -s)"
    elif [[ "$nodeSpec" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        nodeName="$(get_name_from_ip "$nodeSpec")"
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

###############################################################################
# 6. Color Definitions and Spinner
###############################################################################
RESET="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BOLD="\033[1m"

# 24-bit rainbow colors for an animated spinner
RAINBOW_COLORS=(
  "255;0;0"
  "255;127;0"
  "255;255;0"
  "0;255;0"
  "0;255;255"
  "0;127;255"
  "0;0;255"
  "127;0;255"
  "255;0;255"
  "255;0;127"
)

###############################################################################
# RAINBOW SPINNER (INFINITE LOOP)
###############################################################################
# @function spin
# @description Runs an infinite spinner with rainbow color cycling in the background.
# @usage
#   spin &
#   SPINNER_PID=$!
spin() {
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spin_i=0
  local color_i=0
  local interval=0.025

  printf "\e[?25l"  # hide cursor

  while true; do
    local rgb="${RAINBOW_COLORS[color_i]}"
    printf "\r\033[38;2;${rgb}m%s\033[0m " "${frames[spin_i]}"
    spin_i=$(( (spin_i + 1) % ${#frames[@]} ))
    color_i=$(( (color_i + 1) % ${#RAINBOW_COLORS[@]} ))
    sleep "$interval"
  done
}

###############################################################################
# STOPPING THE SPINNER
###############################################################################
# @function stop_spin
# @description Kills the spinner background process, if any, and restores the cursor.
# @usage
#   stop_spin
stop_spin() {
  if [[ -n "$SPINNER_PID" ]] && ps -p "$SPINNER_PID" &>/dev/null; then
    kill "$SPINNER_PID" &>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi
  printf "\e[?25h"  # show cursor
}

###############################################################################
# INFO MESSAGE + START SPINNER
###############################################################################
# @function info
# @description Prints a message in bold yellow, then starts the rainbow spinner.
# @usage
#   info "Doing something..."
info() {
  local msg="$1"
  echo -ne "  ${YELLOW}${BOLD}${msg}${RESET} "
  spin &
  SPINNER_PID=$!
}

###############################################################################
# UPDATE SPINNER TEXT
###############################################################################
# @function update_spin_text
# @description Updates the text that appears in the same line as the spinner
#              without stopping the spinner.
# @usage
#   update_spin_text "New message here"
update_spin_text() {
  echo -ne "\r\033[2C\033[K$1"
}

###############################################################################
# SUCCESS MESSAGE (Stops Spinner)
###############################################################################
# @function ok
# @description Kills spinner, prints success message in green.
# @usage
#   ok "Everything done!"
ok() {
  stop_spin
  echo -ne "\r\033[K"   # Clear the line first
  local msg="$1"
  echo -e "${GREEN}${BOLD}${msg}${RESET}"
}

###############################################################################
# ERROR MESSAGE (Stops Spinner)
###############################################################################
# @function err
# @description Kills spinner, prints error message in red.
# @usage
#   err "Something went wrong!"
err() {
  stop_spin
  echo -ne "\r\033[K"   # Clear the line first
  local msg="$1"
  echo -e "${RED}${BOLD}${msg}${RESET}"
}

###############################################################################
# ERROR HANDLER
###############################################################################
# @function handle_err
# @description Error handler to show line number, exit code, and failing command.
# @usage
#   trap 'handle_err $LINENO "$BASH_COMMAND"' ERR
handle_err() {
  local line_number="$1"
  local command="$2"
  local exit_code="$?"
  stop_spin
  echo -ne "\r\033[K"   # Clear the line first
  echo -e "${RED}[ERROR]${RESET} line ${RED}${line_number}${RESET}, exit code ${RED}${exit_code}${RESET} while executing: ${YELLOW}${command}${RESET}"
}

trap 'handle_err $LINENO "$BASH_COMMAND"' ERR
