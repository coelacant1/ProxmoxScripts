#!/bin/bash
#
# ArgumentParser.sh (v2)
#
# Simple, declarative argument parsing for ProxmoxScripts.
# One-line usage with automatic validation and help generation.
#
# Usage:
#   source "${UTILITYPATH}/ArgumentParser.sh"
#   __parse_args__ "start:number end:number --force:flag --node:string" "$@"
#
# After parsing, arguments are available as variables:
#   $START, $END, $FORCE, $NODE
#
# Function Index:
#   - __parse_args__
#   - __validate_value__
#   - __generate_help__
#   - __validate_numeric__
#   - __validate_ip__
#   - __validate_cidr__
#   - __validate_port__
#   - __validate_range__
#   - __validate_hostname__
#   - __validate_mac_address__
#   - __validate_storage__
#   - __validate_vmid_range__
#   - __validate_integer__
#   - __validate_vmid__
#   - __validate_float__
#   - __validate_ipv6__
#   - __validate_fqdn__
#   - __validate_boolean__
#   - __validate_bridge__
#   - __validate_vlan__
#   - __validate_node_name__
#   - __validate_cpu_cores__
#   - __validate_memory__
#   - __validate_disk_size__
#   - __validate_onboot__
#   - __validate_ostype__
#   - __validate_path__
#   - __validate_url__
#   - __validate_email__
#   - __validate_string__
#

set -euo pipefail

###############################################################################
# Main Parsing Function
###############################################################################

# --- __parse_args__ --------------------------------------------------------------
# @function __parse_args__
# @description One-line declarative argument parser with automatic validation
# @usage __parse_args__ "spec" "$@"
#
# Spec Format:
#   "name:type name:type --flag:type --opt:type:default"
#
# Types:
#   number, num, numeric   - Numeric value (0-9+)
#   int, integer          - Integer (can be negative)
#   vmid                  - VM/CT ID (100-999999999)
#   float, decimal        - Decimal number (e.g., 1.5)
#
#   ip, ipv4              - IPv4 address (192.168.1.100)
#   ipv6                  - IPv6 address
#   cidr, network         - CIDR notation (192.168.1.0/24)
#   gateway               - Gateway IP address
#
#   port                  - Port number (1-65535)
#   hostname, host        - Hostname (RFC 1123)
#   fqdn                  - Fully qualified domain name
#   mac                   - MAC address (XX:XX:XX:XX:XX:XX)
#
#   string, str           - Any string
#   path, file            - File/directory path
#   url                   - URL (http/https)
#   email                 - Email address
#
#   bool, boolean         - Boolean value (true/false, yes/no, 1/0)
#   flag                  - Boolean flag (--flag sets to true)
#
#   storage               - Proxmox storage name
#   bridge                - Network bridge (vmbr0, vmbr1, etc.)
#   vlan                  - VLAN ID (1-4094)
#
#   node, nodename        - Proxmox node name
#   pool                  - Resource pool name
#
#   cpu, cores            - CPU cores (1-max)
#   memory, ram           - Memory in MB (min 16)
#   disk, disksize        - Disk size (with units: 10G, 500M)
#
#   onboot                - OnBoot setting (0 or 1)
#   ostype                - OS type (l26, l24, win10, etc.)
#
#   range                 - Number range (start-end)
#
# Optional/Default:
#   name:type:default     - Optional with default value
#   name:type:?           - Optional, empty if not provided
#
# Examples:
#   __parse_args__ "vmid:number --force:flag" "$@"
#   __parse_args__ "start:number end:number --node:string:?" "$@"
#   __parse_args__ "ip:ip port:port:22" "$@"
#
# @return Sets global variables with uppercase names, returns 1 on error
__parse_args__() {
    local spec="$1"
    shift

    # Arrays to hold spec details
    declare -a POSITIONAL_NAMES=()
    declare -a POSITIONAL_TYPES=()
    declare -a POSITIONAL_DEFAULTS=()
    declare -A FLAG_NAMES=()
    declare -A FLAG_TYPES=()
    declare -A FLAG_DEFAULTS=()

    # Parse specification
    for item in $spec; do
        local name type default optional

        # Check if it's a flag (starts with --)
        if [[ "$item" =~ ^-- ]]; then
            # Flag argument
            name="${item#--}"

            # Split name:type:default
            if [[ "$name" =~ : ]]; then
                IFS=':' read -r name type default <<< "$name"
            else
                type="flag"
                default=""
            fi

            # Determine if optional
            if [[ "$default" == "?" ]]; then
                optional=true
                default=""
            elif [[ -n "$default" ]]; then
                optional=true
            else
                optional=false
            fi

            FLAG_NAMES["--${name}"]="${name^^}"
            FLAG_TYPES["--${name}"]="$type"
            FLAG_DEFAULTS["--${name}"]="$default"

            # Initialize variable
            if [[ "$type" == "flag" || "$type" == "bool" ]]; then
                eval "${name^^}=false"
            else
                eval "${name^^}='${default}'"
            fi
        else
            # Positional argument
            name="$item"

            # Split name:type:default
            if [[ "$name" =~ : ]]; then
                IFS=':' read -r name type default <<< "$name"
            else
                type="string"
                default=""
            fi

            # Determine if optional
            if [[ "$default" == "?" ]]; then
                optional=true
                default=""
            elif [[ -n "$default" ]]; then
                optional=true
            else
                optional=false
            fi

            POSITIONAL_NAMES+=("$name")
            POSITIONAL_TYPES+=("$type")
            POSITIONAL_DEFAULTS+=("$default")
        fi
    done

    # Parse actual arguments
    local positional_index=0

    while [[ $# -gt 0 ]]; do
        local arg="$1"

        # Check for help flag
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            __generate_help__ "$spec"
            exit 0
        fi

        # Check if it's a flag
        if [[ "$arg" =~ ^-- ]]; then
            local flag_name="${FLAG_NAMES[$arg]:-}"

            if [[ -z "$flag_name" ]]; then
                echo "Error: Unknown flag: $arg" >&2
                echo "Use --help for usage information" >&2
                return 1
            fi

            local flag_type="${FLAG_TYPES[$arg]}"

            # Handle boolean flags
            if [[ "$flag_type" == "flag" || "$flag_type" == "bool" ]]; then
                eval "${flag_name}=true"
                shift
                continue
            fi

            # Get value for non-boolean flags
            if [[ $# -lt 2 ]]; then
                echo "Error: Flag $arg requires a value" >&2
                return 1
            fi

            local flag_value="$2"
            shift 2

            # Validate based on type
            if ! __validate_value__ "$flag_value" "$flag_type" "$arg"; then
                return 1
            fi

            eval "${flag_name}='${flag_value}'"
        else
            # Positional argument
            if [[ $positional_index -ge ${#POSITIONAL_NAMES[@]} ]]; then
                echo "Error: Too many positional arguments" >&2
                return 1
            fi

            local pos_name="${POSITIONAL_NAMES[$positional_index]^^}"
            local pos_type="${POSITIONAL_TYPES[$positional_index]}"

            # Validate based on type
            if ! __validate_value__ "$arg" "$pos_type" "${POSITIONAL_NAMES[$positional_index]}"; then
                return 1
            fi

            eval "${pos_name}='${arg}'"
            ((positional_index++))
            shift
        fi
    done

    # Check if all required positional arguments were provided
    for (( i=$positional_index; i<${#POSITIONAL_NAMES[@]}; i++ )); do
        local default="${POSITIONAL_DEFAULTS[$i]}"
        if [[ -z "$default" && "$default" != "?" ]]; then
            echo "Error: Missing required argument: ${POSITIONAL_NAMES[$i]}" >&2
            return 1
        fi

        local pos_name="${POSITIONAL_NAMES[$i]^^}"
        eval "${pos_name}='${default}'"
    done

    # Special handling for VMID ranges
    if [[ -n "${START:-}" && -n "${END:-}" ]]; then
        if ! __validate_vmid_range__ "$START" "$END"; then
            return 1
        fi
    fi

    return 0
}

###############################################################################
# Validation Helper
###############################################################################

__validate_value__() {
    local value="$1"
    local type="$2"
    local field_name="${3:-value}"

    case "$type" in
        number|num|numeric)
            __validate_numeric__ "$value" "$field_name"
            ;;
        int|integer)
            __validate_integer__ "$value" "$field_name"
            ;;
        vmid)
            __validate_vmid__ "$value" "$field_name"
            ;;
        float|decimal)
            __validate_float__ "$value" "$field_name"
            ;;
        ip|ipv4)
            __validate_ip__ "$value" "$field_name"
            ;;
        ipv6)
            __validate_ipv6__ "$value" "$field_name"
            ;;
        cidr|network)
            __validate_cidr__ "$value" "$field_name"
            ;;
        gateway)
            __validate_ip__ "$value" "$field_name"  # Gateway is just an IP
            ;;
        port)
            __validate_port__ "$value" "$field_name"
            ;;
        hostname|host)
            __validate_hostname__ "$value" "$field_name"
            ;;
        fqdn)
            __validate_fqdn__ "$value" "$field_name"
            ;;
        mac)
            __validate_mac_address__ "$value" "$field_name"
            ;;
        bool|boolean)
            __validate_boolean__ "$value" "$field_name"
            ;;
        storage)
            __validate_storage__ "$value"
            ;;
        bridge)
            __validate_bridge__ "$value" "$field_name"
            ;;
        vlan)
            __validate_vlan__ "$value" "$field_name"
            ;;
        node|nodename)
            __validate_node_name__ "$value" "$field_name"
            ;;
        pool)
            __validate_string__ "$value" "$field_name"
            ;;
        cpu|cores)
            __validate_cpu_cores__ "$value" "$field_name"
            ;;
        memory|ram)
            __validate_memory__ "$value" "$field_name"
            ;;
        disk|disksize)
            __validate_disk_size__ "$value" "$field_name"
            ;;
        onboot)
            __validate_onboot__ "$value" "$field_name"
            ;;
        ostype)
            __validate_ostype__ "$value" "$field_name"
            ;;
        path|file)
            __validate_path__ "$value" "$field_name"
            ;;
        url)
            __validate_url__ "$value" "$field_name"
            ;;
        email)
            __validate_email__ "$value" "$field_name"
            ;;
        string|str)
            # No validation needed for generic strings
            return 0
            ;;
        *)
            echo "Error: Unknown type '${type}' for ${field_name}" >&2
            return 1
            ;;
    esac
}

###############################################################################
# Help Generation
###############################################################################

__generate_help__() {
    local spec="$1"

    echo "Usage: ${0##*/} [OPTIONS]"
    echo ""
    echo "Positional Arguments:"

    for item in $spec; do
        if [[ ! "$item" =~ ^-- ]]; then
            local name type default
            IFS=':' read -r name type default <<< "$item"

            if [[ -n "$default" && "$default" != "?" ]]; then
                echo "  ${name}  (${type}, default: ${default})"
            elif [[ "$default" == "?" ]]; then
                echo "  [${name}]  (${type}, optional)"
            else
                echo "  ${name}  (${type}, required)"
            fi
        fi
    done

    echo ""
    echo "Options:"

    for item in $spec; do
        if [[ "$item" =~ ^-- ]]; then
            local name="${item#--}"
            local type default
            IFS=':' read -r name type default <<< "$name"

            if [[ "$type" == "flag" || "$type" == "bool" ]]; then
                echo "  --${name}  (flag)"
            elif [[ -n "$default" && "$default" != "?" ]]; then
                echo "  --${name} <value>  (${type}, default: ${default})"
            elif [[ "$default" == "?" ]]; then
                echo "  --${name} <value>  (${type}, optional)"
            else
                echo "  --${name} <value>  (${type}, required)"
            fi
        fi
    done

    echo "  -h, --help  Show this help message"
}

###############################################################################
# Validation Functions
###############################################################################

# --- __validate_numeric__ ----------------------------------------------------
__validate_numeric__() {
    local value="$1"
    local field_name="${2:-value}"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "Error: ${field_name} must be numeric (got: '${value}')" >&2
        return 1
    fi
    return 0
}

# --- __validate_ip__ ---------------------------------------------------------
__validate_ip__() {
    local ip="$1"
    local field_name="${2:-IP address}"

    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Error: ${field_name} must be a valid IPv4 address (got: '${ip}')" >&2
        return 1
    fi

    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if (( octet > 255 )); then
            echo "Error: Invalid ${field_name} - octet value ${octet} exceeds 255" >&2
            return 1
        fi
    done
    return 0
}

# --- __validate_cidr__ -------------------------------------------------------
__validate_cidr__() {
    local cidr="$1"
    local field_name="${2:-IP/CIDR}"

    if ! [[ "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: ${field_name} must be in format IP/CIDR (e.g., 192.168.1.0/24)" >&2
        return 1
    fi

    local ip="${cidr%/*}"
    local mask="${cidr#*/}"

    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if (( octet > 255 )); then
            echo "Error: Invalid ${field_name} - octet value ${octet} exceeds 255" >&2
            return 1
        fi
    done

    if (( mask > 32 )); then
        echo "Error: Invalid ${field_name} - CIDR mask ${mask} exceeds 32" >&2
        return 1
    fi

    return 0
}

# --- __validate_port__ -------------------------------------------------------
__validate_port__() {
    local port="$1"
    local field_name="${2:-port}"

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "Error: ${field_name} must be numeric (got: '${port}')" >&2
        return 1
    fi

    if (( port < 1 || port > 65535 )); then
        echo "Error: ${field_name} must be between 1 and 65535 (got: ${port})" >&2
        return 1
    fi

    return 0
}

# --- __validate_range__ ------------------------------------------------------
__validate_range__() {
    local value="$1"
    local min="$2"
    local max="$3"
    local field_name="${4:-value}"

    if ! __validate_numeric__ "$value" "$field_name"; then
        return 1
    fi

    if (( value < min || value > max )); then
        echo "Error: ${field_name} must be between ${min} and ${max} (got: ${value})" >&2
        return 1
    fi

    return 0
}

# --- __validate_hostname__ ---------------------------------------------------
__validate_hostname__() {
    local hostname="$1"
    local field_name="${2:-hostname}"

    if ! [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo "Error: Invalid ${field_name} '${hostname}'" >&2
        echo "  Hostname must contain only alphanumeric characters and hyphens" >&2
        return 1
    fi

    if (( ${#hostname} > 253 )); then
        echo "Error: ${field_name} exceeds maximum length of 253 characters" >&2
        return 1
    fi

    return 0
}

# --- __validate_mac_address__ ------------------------------------------------
__validate_mac_address__() {
    local mac="$1"
    local field_name="${2:-MAC address}"

    if ! [[ "$mac" =~ ^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$ ]]; then
        echo "Error: Invalid ${field_name} '${mac}'" >&2
        echo "  Expected format: XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX" >&2
        return 1
    fi

    return 0
}

# --- __validate_storage__ ----------------------------------------------------
__validate_storage__() {
    local storage="$1"

    if ! command -v pvesm &>/dev/null; then
        # Not on Proxmox, skip validation
        return 0
    fi

    if ! pvesm status --storage "$storage" &>/dev/null; then
        echo "Error: Storage '${storage}' not found" >&2
        echo "Available storages:" >&2
        pvesm status 2>/dev/null | tail -n +2 | awk '{print "  - " $1}' >&2
        return 1
    fi

    return 0
}

# --- __validate_vmid_range__ -------------------------------------------------
__validate_vmid_range__() {
    local start_id="$1"
    local end_id="$2"

    if ! __validate_numeric__ "$start_id" "start_id"; then
        return 1
    fi

    if ! __validate_numeric__ "$end_id" "end_id"; then
        return 1
    fi

    if (( start_id > end_id )); then
        echo "Error: start_id (${start_id}) must be <= end_id (${end_id})" >&2
        return 1
    fi

    return 0
}

# --- __validate_integer__ ----------------------------------------------------
__validate_integer__() {
    local value="$1"
    local field_name="${2:-integer}"

    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        echo "Error: ${field_name} must be an integer (got: '${value}')" >&2
        return 1
    fi
    return 0
}

# --- __validate_vmid__ -------------------------------------------------------
__validate_vmid__() {
    local value="$1"
    local field_name="${2:-VMID}"

    if ! __validate_numeric__ "$value" "$field_name"; then
        return 1
    fi

    if (( value < 100 || value > 999999999 )); then
        echo "Error: ${field_name} must be between 100 and 999999999 (got: ${value})" >&2
        return 1
    fi

    return 0
}

# --- __validate_float__ ------------------------------------------------------
__validate_float__() {
    local value="$1"
    local field_name="${2:-float}"

    if ! [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        echo "Error: ${field_name} must be a decimal number (got: '${value}')" >&2
        return 1
    fi
    return 0
}

# --- __validate_ipv6__ -------------------------------------------------------
__validate_ipv6__() {
    local ip="$1"
    local field_name="${2:-IPv6 address}"

    # Basic IPv6 validation (simplified)
    if ! [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        echo "Error: ${field_name} must be a valid IPv6 address (got: '${ip}')" >&2
        return 1
    fi

    return 0
}

# --- __validate_fqdn__ -------------------------------------------------------
__validate_fqdn__() {
    local fqdn="$1"
    local field_name="${2:-FQDN}"

    # FQDN must have at least one dot and follow hostname rules
    if ! [[ "$fqdn" =~ \. ]]; then
        echo "Error: ${field_name} must be a fully qualified domain name with at least one dot" >&2
        return 1
    fi

    __validate_hostname__ "$fqdn" "$field_name"
}

# --- __validate_boolean__ ----------------------------------------------------
__validate_boolean__() {
    local value="$1"
    local field_name="${2:-boolean}"

    # Convert to lowercase
    local lower_value="${value,,}"

    if ! [[ "$lower_value" =~ ^(true|false|yes|no|1|0|on|off)$ ]]; then
        echo "Error: ${field_name} must be a boolean (true/false, yes/no, 1/0, on/off) (got: '${value}')" >&2
        return 1
    fi

    return 0
}

# --- __validate_bridge__ -----------------------------------------------------
__validate_bridge__() {
    local bridge="$1"
    local field_name="${2:-bridge}"

    # Bridge format: vmbr followed by a number
    if ! [[ "$bridge" =~ ^vmbr[0-9]+$ ]]; then
        echo "Error: ${field_name} must be in format vmbrN (e.g., vmbr0, vmbr1) (got: '${bridge}')" >&2
        return 1
    fi

    return 0
}

# --- __validate_vlan__ -------------------------------------------------------
__validate_vlan__() {
    local vlan="$1"
    local field_name="${2:-VLAN ID}"

    if ! __validate_numeric__ "$vlan" "$field_name"; then
        return 1
    fi

    if (( vlan < 1 || vlan > 4094 )); then
        echo "Error: ${field_name} must be between 1 and 4094 (got: ${vlan})" >&2
        return 1
    fi

    return 0
}

# --- __validate_node_name__ --------------------------------------------------
__validate_node_name__() {
    local node="$1"
    local field_name="${2:-node name}"

    # Node names should be valid hostnames (lowercase, alphanumeric, hyphens)
    if ! [[ "$node" =~ ^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$ ]]; then
        echo "Error: ${field_name} must be a valid node name (lowercase, alphanumeric, hyphens)" >&2
        return 1
    fi

    return 0
}

# --- __validate_cpu_cores__ --------------------------------------------------
__validate_cpu_cores__() {
    local cores="$1"
    local field_name="${2:-CPU cores}"

    if ! __validate_numeric__ "$cores" "$field_name"; then
        return 1
    fi

    if (( cores < 1 || cores > 512 )); then
        echo "Error: ${field_name} must be between 1 and 512 (got: ${cores})" >&2
        return 1
    fi

    return 0
}

# --- __validate_memory__ -----------------------------------------------------
__validate_memory__() {
    local memory="$1"
    local field_name="${2:-memory}"

    if ! __validate_numeric__ "$memory" "$field_name"; then
        return 1
    fi

    if (( memory < 16 )); then
        echo "Error: ${field_name} must be at least 16 MB (got: ${memory})" >&2
        return 1
    fi

    return 0
}

# --- __validate_disk_size__ --------------------------------------------------
__validate_disk_size__() {
    local size="$1"
    local field_name="${2:-disk size}"

    # Disk size can be: 10G, 500M, 1T, or just a number (assumed GB)
    if ! [[ "$size" =~ ^[0-9]+[KMGT]?$ ]]; then
        echo "Error: ${field_name} must be a number optionally followed by K/M/G/T (e.g., 10G, 500M) (got: '${size}')" >&2
        return 1
    fi

    return 0
}

# --- __validate_onboot__ -----------------------------------------------------
__validate_onboot__() {
    local value="$1"
    local field_name="${2:-onboot}"

    if ! [[ "$value" =~ ^[01]$ ]]; then
        echo "Error: ${field_name} must be 0 or 1 (got: '${value}')" >&2
        return 1
    fi

    return 0
}

# --- __validate_ostype__ -----------------------------------------------------
__validate_ostype__() {
    local ostype="$1"
    local field_name="${2:-OS type}"

    # Common Proxmox OS types
    local valid_ostypes=(
        "l26" "l24" "other"
        "wxp" "w2k" "w2k3" "w2k8" "wvista" "win7" "win8" "win10" "win11"
        "solaris"
    )

    local valid=false
    for valid_ostype in "${valid_ostypes[@]}"; do
        if [[ "$ostype" == "$valid_ostype" ]]; then
            valid=true
            break
        fi
    done

    if ! $valid; then
        echo "Error: ${field_name} must be a valid OS type (e.g., l26, win10, win11)" >&2
        return 1
    fi

    return 0
}

# --- __validate_path__ -------------------------------------------------------
__validate_path__() {
    local path="$1"
    local field_name="${2:-path}"

    # Basic path validation - just check it's not empty and doesn't have invalid chars
    if [[ -z "$path" ]]; then
        echo "Error: ${field_name} cannot be empty" >&2
        return 1
    fi

    # Check for null bytes or other dangerous characters
    if [[ "$path" =~ $'\0' ]]; then
        echo "Error: ${field_name} contains invalid characters" >&2
        return 1
    fi

    return 0
}

# --- __validate_url__ --------------------------------------------------------
__validate_url__() {
    local url="$1"
    local field_name="${2:-URL}"

    # Basic URL validation
    if ! [[ "$url" =~ ^https?://[a-zA-Z0-9\.\-]+([:/][^[:space:]]*)?$ ]]; then
        echo "Error: ${field_name} must be a valid HTTP/HTTPS URL (got: '${url}')" >&2
        return 1
    fi

    return 0
}

# --- __validate_email__ ------------------------------------------------------
__validate_email__() {
    local email="$1"
    local field_name="${2:-email}"

    # Basic email validation
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "Error: ${field_name} must be a valid email address (got: '${email}')" >&2
        return 1
    fi

    return 0
}

# --- __validate_string__ -----------------------------------------------------
__validate_string__() {
    local value="$1"
    local field_name="${2:-string}"

    # Just check it's not empty
    if [[ -z "$value" ]]; then
        echo "Error: ${field_name} cannot be empty" >&2
        return 1
    fi

    return 0
}
