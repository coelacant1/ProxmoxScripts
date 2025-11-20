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
# IMPORTANT - Reserved Variable Names:
#   Argument names are converted to UPPERCASE. Avoid these names as they conflict
#   with standard environment variables or shell built-ins:
#
#   CRITICAL (will break scripts):
#     - PATH, HOME, USER, SHELL, PWD, OLDPWD
#     - LANG, LC_*, TZ, TERM, DISPLAY
#     - IFS, PS1, PS2, PS3, PS4
#     - BASH_*, FUNCNAME, LINENO
#
#   HIGH RISK (Proxmox/system specific):
#     - HOSTNAME, LOGNAME, MAIL, EDITOR
#     - TMPDIR, TEMP, TMP
#     - UID, EUID, GID, GROUPS, PPID
#
#   MODERATE RISK (commonly used):
#     - DEBUG, VERBOSE, QUIET, FORCE
#     - CONFIG, DATA, LOG, CACHE
#
#   Alternative naming when conflicts occur:
#     - path       -> storage_path, export_path, file_path, dir_path
#     - home       -> home_dir, user_home
#     - user       -> username, userid, account
#     - shell      -> shell_type, shell_cmd
#     - host       -> hostname, host_ip, target_host
#     - temp       -> temp_dir, temp_file
#     - log        -> log_file, log_path, log_level
#
# Function Index:
#   - __argparser_log__
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

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Safe logging wrapper - works even if Logger.sh not loaded
__argparser_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "ARGPARSER"
    fi
    # Always echo errors to stderr as fallback
    if [[ "$level" == "ERROR" ]]; then
        echo "Error: $message" >&2
    fi
}

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
#   vmid, ctid            - VM/CT ID (100-999999999)
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

    __argparser_log__ "DEBUG" "=== ArgumentParser Start ==="
    __argparser_log__ "DEBUG" "Spec: $spec"
    __argparser_log__ "DEBUG" "Arguments ($#): $*"

    # Reserved variable names that MUST NOT be used
    local -a CRITICAL_RESERVED=(
        PATH HOME USER SHELL PWD OLDPWD IFS
        LANG TZ TERM TMPDIR UID EUID GID PPID
        BASH_VERSION BASH_VERSINFO FUNCNAME LINENO
    )

    # Arrays to hold spec details
    declare -a POSITIONAL_NAMES=()
    declare -a POSITIONAL_TYPES=()
    declare -a POSITIONAL_DEFAULTS=()
    declare -A FLAG_NAMES=()
    declare -A FLAG_TYPES=()
    declare -A FLAG_DEFAULTS=()

    __argparser_log__ "DEBUG" "Parsing specification..."

    # Parse specification
    for item in $spec; do
        local name type default optional

        # Check if it's a flag (starts with --)
        if [[ "$item" =~ ^-- ]]; then
            __argparser_log__ "DEBUG" "Parsing flag spec: $item"
            # Flag argument
            name="${item#--}"

            # Split name:type:default
            if [[ "$name" =~ : ]]; then
                IFS=':' read -r name type default <<<"$name"
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

            # Check for reserved variable name conflicts
            local var_name="${name^^}"
            for reserved in "${CRITICAL_RESERVED[@]}"; do
                if [[ "$var_name" == "$reserved" ]]; then
                    __argparser_log__ "ERROR" "CRITICAL: Argument name '$name' conflicts with reserved variable '$reserved'"
                    echo "ERROR: Argument '--${name}' creates variable \$$var_name which conflicts with system variable \$$reserved" >&2
                    echo "This will cause script failures. Please rename the argument." >&2
                    echo "Suggestions: ${name}_path, ${name}_dir, ${name}_file, storage_${name}, custom_${name}" >&2
                    return 1
                fi
            done

            __argparser_log__ "DEBUG" "Registered flag: --${name} -> ${name^^} (type: $type, optional: $optional)"

            # Initialize variable
            if [[ "$type" == "flag" || "$type" == "bool" ]]; then
                eval "${name^^}=false"
            else
                eval "${name^^}='${default}'"
            fi
        else
            # Positional argument
            __argparser_log__ "DEBUG" "Parsing positional spec: $item"
            name="$item"

            # Split name:type:default
            if [[ "$name" =~ : ]]; then
                IFS=':' read -r name type default <<<"$name"
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

            # Check for reserved variable name conflicts
            local var_name="${name^^}"
            for reserved in "${CRITICAL_RESERVED[@]}"; do
                if [[ "$var_name" == "$reserved" ]]; then
                    __argparser_log__ "ERROR" "CRITICAL: Argument name '$name' conflicts with reserved variable '$reserved'"
                    echo "ERROR: Positional argument '$name' creates variable \$$var_name which conflicts with system variable \$$reserved" >&2
                    echo "This will cause script failures. Please rename the argument." >&2
                    echo "Suggestions: ${name}_path, ${name}_dir, ${name}_file, storage_${name}, custom_${name}" >&2
                    return 1
                fi
            done

            __argparser_log__ "DEBUG" "Registered positional: $name (type: $type, optional: $optional)"
        fi
    done

    __argparser_log__ "DEBUG" "Spec parsing complete. Positionals: ${#POSITIONAL_NAMES[@]}, Flags: ${#FLAG_NAMES[@]}"
    __argparser_log__ "DEBUG" "Processing arguments..."

    # Parse actual arguments
    local positional_index=0

    while [[ $# -gt 0 ]]; do
        local arg="$1"
        __argparser_log__ "DEBUG" "Processing argument: '$arg'"

        # Check for help flag
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            __generate_help__ "$spec"
            exit 0
        fi

        # Check if it's a flag
        if [[ "$arg" =~ ^-- ]]; then
            local flag_name="${FLAG_NAMES[$arg]:-}"

            __argparser_log__ "DEBUG" "Detected flag: $arg"

            if [[ -z "$flag_name" ]]; then
                __argparser_log__ "ERROR" "Unknown flag: $arg"
                echo "Use --help for usage information" >&2
                return 1
            fi

            local flag_type="${FLAG_TYPES[$arg]}"
            __argparser_log__ "DEBUG" "Flag type: $flag_type, Variable: $flag_name"

            # Handle boolean flags
            if [[ "$flag_type" == "flag" || "$flag_type" == "bool" ]]; then
                eval "${flag_name}=true"
                __argparser_log__ "DEBUG" "Set boolean flag: $flag_name=true"
                shift
                continue
            fi

            # Get value for non-boolean flags
            if [[ $# -lt 2 ]]; then
                __argparser_log__ "ERROR" "Flag $arg requires a value"
                return 1
            fi

            local flag_value="$2"
            __argparser_log__ "DEBUG" "Flag value: '$flag_value'"
            shift 2

            # Validate based on type
            __argparser_log__ "DEBUG" "Validating $arg value '$flag_value' as type '$flag_type'"
            if ! __validate_value__ "$flag_value" "$flag_type" "$arg"; then
                return 1
            fi

            eval "${flag_name}='${flag_value}'"
            __argparser_log__ "DEBUG" "Set flag: $flag_name='$flag_value'"
        else
            # Positional argument
            __argparser_log__ "DEBUG" "Detected positional argument at index $positional_index"

            if [[ $positional_index -ge ${#POSITIONAL_NAMES[@]} ]]; then
                __argparser_log__ "ERROR" "Too many positional arguments"
                return 1
            fi

            local pos_name="${POSITIONAL_NAMES[$positional_index]^^}"
            local pos_type="${POSITIONAL_TYPES[$positional_index]}"

            __argparser_log__ "DEBUG" "Positional: ${POSITIONAL_NAMES[$positional_index]} -> $pos_name (type: $pos_type)"
            __argparser_log__ "DEBUG" "Value: '$arg'"

            # Validate based on type
            __argparser_log__ "DEBUG" "Validating positional value '$arg' as type '$pos_type'"
            if ! __validate_value__ "$arg" "$pos_type" "${POSITIONAL_NAMES[$positional_index]}"; then
                return 1
            fi

            eval "${pos_name}='${arg}'"
            __argparser_log__ "DEBUG" "Set positional: $pos_name='$arg'"
            ((positional_index += 1)) || true
            shift
        fi
    done

    __argparser_log__ "DEBUG" "Argument processing complete"
    __argparser_log__ "DEBUG" "=== ArgumentParser Success ==="

    # Check if all required positional arguments were provided
    for ((i = $positional_index; i < ${#POSITIONAL_NAMES[@]}; i++)); do
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

    __argparser_log__ "DEBUG" "Validating: $field_name='$value' as type '$type'"

    case "$type" in
        number | num | numeric)
            __validate_numeric__ "$value" "$field_name"
            ;;
        int | integer)
            __validate_integer__ "$value" "$field_name"
            ;;
        vmid | ctid)
            __validate_vmid__ "$value" "$field_name"
            ;;
        float | decimal)
            __validate_float__ "$value" "$field_name"
            ;;
        ip | ipv4)
            __validate_ip__ "$value" "$field_name"
            ;;
        ipv6)
            __validate_ipv6__ "$value" "$field_name"
            ;;
        cidr | network)
            __validate_cidr__ "$value" "$field_name"
            ;;
        gateway)
            __validate_ip__ "$value" "$field_name" # Gateway is just an IP
            ;;
        port)
            __validate_port__ "$value" "$field_name"
            ;;
        hostname | host)
            __validate_hostname__ "$value" "$field_name"
            ;;
        fqdn)
            __validate_fqdn__ "$value" "$field_name"
            ;;
        mac)
            __validate_mac_address__ "$value" "$field_name"
            ;;
        bool | boolean)
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
        node | nodename)
            __validate_node_name__ "$value" "$field_name"
            ;;
        pool)
            __validate_string__ "$value" "$field_name"
            ;;
        cpu | cores)
            __validate_cpu_cores__ "$value" "$field_name"
            ;;
        memory | ram)
            __validate_memory__ "$value" "$field_name"
            ;;
        disk | disksize)
            __validate_disk_size__ "$value" "$field_name"
            ;;
        onboot)
            __validate_onboot__ "$value" "$field_name"
            ;;
        ostype)
            __validate_ostype__ "$value" "$field_name"
            ;;
        path | file)
            __validate_path__ "$value" "$field_name"
            ;;
        url)
            __validate_url__ "$value" "$field_name"
            ;;
        email)
            __validate_email__ "$value" "$field_name"
            ;;
        string | str)
            # No validation needed for generic strings
            __argparser_log__ "DEBUG" "Validation passed: string type (no validation needed)"
            return 0
            ;;
        *)
            __argparser_log__ "ERROR" "Unknown type '${type}' for ${field_name}"
            echo "Error: Unknown type '${type}' for ${field_name}" >&2
            return 1
            ;;
    esac

    local validation_result=$?
    if [[ $validation_result -eq 0 ]]; then
        __argparser_log__ "DEBUG" "Validation passed for $field_name"
    else
        __argparser_log__ "ERROR" "Validation failed for $field_name"
    fi
    return $validation_result
}

###############################################################################
# Help Generation
###############################################################################

__generate_help__() {
    local spec="$1"

    __argparser_log__ "DEBUG" "Generating help message"

    echo "Usage: ${0##*/} [OPTIONS]"
    echo ""
    echo "Positional Arguments:"

    for item in $spec; do
        if [[ ! "$item" =~ ^-- ]]; then
            local name type default
            IFS=':' read -r name type default <<<"$item"

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
            IFS=':' read -r name type default <<<"$name"

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

    __argparser_log__ "TRACE" "Validating numeric: $field_name='$value'"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: $field_name is not numeric"
        echo "Error: ${field_name} must be numeric (got: '${value}')" >&2
        return 1
    fi
    __argparser_log__ "TRACE" "Validation passed: $field_name is numeric"
    return 0
}

# --- __validate_ip__ ---------------------------------------------------------
__validate_ip__() {
    local ip="$1"
    local field_name="${2:-IP address}"

    __argparser_log__ "TRACE" "Validating IP: $field_name='$ip'"

    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: $field_name has invalid format"
        echo "Error: ${field_name} must be a valid IPv4 address (got: '${ip}')" >&2
        return 1
    fi

    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if ((octet > 255)); then
            __argparser_log__ "DEBUG" "Validation failed: octet $octet exceeds 255"
            echo "Error: Invalid ${field_name} - octet value ${octet} exceeds 255" >&2
            return 1
        fi
    done
    __argparser_log__ "TRACE" "Validation passed: valid IP address"
    return 0
}

# --- __validate_cidr__ -------------------------------------------------------
__validate_cidr__() {
    local cidr="$1"
    local field_name="${2:-IP/CIDR}"

    __argparser_log__ "TRACE" "Validating CIDR: $field_name='$cidr'"

    if ! [[ "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: invalid CIDR format"
        echo "Error: ${field_name} must be in format IP/CIDR (e.g., 192.168.1.0/24)" >&2
        return 1
    fi

    local ip="${cidr%/*}"
    local mask="${cidr#*/}"

    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if ((octet > 255)); then
            __argparser_log__ "DEBUG" "Validation failed: octet $octet exceeds 255"
            echo "Error: Invalid ${field_name} - octet value ${octet} exceeds 255" >&2
            return 1
        fi
    done

    if ((mask > 32)); then
        __argparser_log__ "DEBUG" "Validation failed: mask $mask exceeds 32"
        echo "Error: Invalid ${field_name} - CIDR mask ${mask} exceeds 32" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid CIDR"
    return 0
}

# --- __validate_port__ -------------------------------------------------------
__validate_port__() {
    local port="$1"
    local field_name="${2:-port}"

    __argparser_log__ "TRACE" "Validating port: $field_name='$port'"

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: port is not numeric"
        echo "Error: ${field_name} must be numeric (got: '${port}')" >&2
        return 1
    fi

    if ((port < 1 || port > 65535)); then
        __argparser_log__ "DEBUG" "Validation failed: port $port out of range"
        echo "Error: ${field_name} must be between 1 and 65535 (got: ${port})" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid port"
    return 0
}

# --- __validate_range__ ------------------------------------------------------
__validate_range__() {
    local value="$1"
    local min="$2"
    local max="$3"
    local field_name="${4:-value}"

    __argparser_log__ "TRACE" "Validating range: $field_name='$value' (min=$min, max=$max)"

    if ! __validate_numeric__ "$value" "$field_name"; then
        return 1
    fi

    if ((value < min || value > max)); then
        __argparser_log__ "DEBUG" "Validation failed: $value not in range [$min, $max]"
        echo "Error: ${field_name} must be between ${min} and ${max} (got: ${value})" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: value in range"
    return 0
}

# --- __validate_hostname__ ---------------------------------------------------
__validate_hostname__() {
    local hostname="$1"
    local field_name="${2:-hostname}"

    __argparser_log__ "TRACE" "Validating hostname: $field_name='$hostname'"

    if ! [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: invalid hostname format"
        echo "Error: Invalid ${field_name} '${hostname}'" >&2
        echo "  Hostname must contain only alphanumeric characters and hyphens" >&2
        return 1
    fi

    if ((${#hostname} > 253)); then
        __argparser_log__ "DEBUG" "Validation failed: hostname exceeds 253 characters"
        echo "Error: ${field_name} exceeds maximum length of 253 characters" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid hostname"
    return 0
}

# --- __validate_mac_address__ ------------------------------------------------
__validate_mac_address__() {
    local mac="$1"
    local field_name="${2:-MAC address}"

    __argparser_log__ "TRACE" "Validating MAC address: $field_name='$mac'"

    if ! [[ "$mac" =~ ^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: invalid MAC address format"
        echo "Error: Invalid ${field_name} '${mac}'" >&2
        echo "  Expected format: XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid MAC address"
    return 0
}

# --- __validate_storage__ ----------------------------------------------------
__validate_storage__() {
    local storage="$1"

    __argparser_log__ "TRACE" "Validating storage: '$storage'"

    if ! command -v pvesm &>/dev/null; then
        __argparser_log__ "DEBUG" "pvesm not available, skipping validation"
        # Not on Proxmox, skip validation
        return 0
    fi

    if ! pvesm status --storage "$storage" &>/dev/null; then
        __argparser_log__ "DEBUG" "Validation failed: storage '$storage' not found"
        echo "Error: Storage '${storage}' not found" >&2
        echo "Available storages:" >&2
        pvesm status 2>/dev/null | tail -n +2 | awk '{print "  - " $1}' >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: storage exists"
    return 0
}

# --- __validate_vmid_range__ -------------------------------------------------
__validate_vmid_range__() {
    local start_id="$1"
    local end_id="$2"

    __argparser_log__ "TRACE" "Validating VMID range: $start_id to $end_id"

    if ! __validate_numeric__ "$start_id" "start_id"; then
        return 1
    fi

    if ! __validate_numeric__ "$end_id" "end_id"; then
        return 1
    fi

    if ((start_id > end_id)); then
        __argparser_log__ "DEBUG" "Validation failed: start_id > end_id"
        echo "Error: start_id (${start_id}) must be <= end_id (${end_id})" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid range"
    return 0
}

# --- __validate_integer__ ----------------------------------------------------
__validate_integer__() {
    local value="$1"
    local field_name="${2:-integer}"

    __argparser_log__ "TRACE" "Validating integer: $field_name='$value'"

    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: not an integer"
        echo "Error: ${field_name} must be an integer (got: '${value}')" >&2
        return 1
    fi
    __argparser_log__ "TRACE" "Validation passed: valid integer"
    return 0
}

# --- __validate_vmid__ -------------------------------------------------------
__validate_vmid__() {
    local value="$1"
    local field_name="${2:-VMID}"

    __argparser_log__ "TRACE" "Validating VMID: $field_name='$value'"

    if ! __validate_numeric__ "$value" "$field_name"; then
        return 1
    fi

    if ((value < 100 || value > 999999999)); then
        __argparser_log__ "DEBUG" "Validation failed: VMID out of range"
        echo "Error: ${field_name} must be between 100 and 999999999 (got: ${value})" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid VMID"
    return 0
}

# --- __validate_float__ ------------------------------------------------------
__validate_float__() {
    local value="$1"
    local field_name="${2:-float}"

    __argparser_log__ "TRACE" "Validating float: $field_name='$value'"

    if ! [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: not a decimal number"
        echo "Error: ${field_name} must be a decimal number (got: '${value}')" >&2
        return 1
    fi
    __argparser_log__ "TRACE" "Validation passed: valid float"
    return 0
}

# --- __validate_ipv6__ -------------------------------------------------------
__validate_ipv6__() {
    local ip="$1"
    local field_name="${2:-IPv6 address}"

    __argparser_log__ "TRACE" "Validating IPv6: $field_name='$ip'"

    # Basic IPv6 validation (simplified)
    if ! [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: invalid IPv6 format"
        echo "Error: ${field_name} must be a valid IPv6 address (got: '${ip}')" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid IPv6"
    return 0
}

# --- __validate_fqdn__ -------------------------------------------------------
__validate_fqdn__() {
    local fqdn="$1"
    local field_name="${2:-FQDN}"

    __argparser_log__ "TRACE" "Validating FQDN: $field_name='$fqdn'"

    # FQDN must have at least one dot and follow hostname rules
    if ! [[ "$fqdn" =~ \. ]]; then
        __argparser_log__ "DEBUG" "Validation failed: no dot in FQDN"
        echo "Error: ${field_name} must be a fully qualified domain name with at least one dot" >&2
        return 1
    fi

    __validate_hostname__ "$fqdn" "$field_name"
}

# --- __validate_boolean__ ----------------------------------------------------
__validate_boolean__() {
    local value="$1"
    local field_name="${2:-boolean}"

    __argparser_log__ "TRACE" "Validating boolean: $field_name='$value'"

    # Convert to lowercase
    local lower_value="${value,,}"

    if ! [[ "$lower_value" =~ ^(true|false|yes|no|1|0|on|off)$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: not a boolean value"
        echo "Error: ${field_name} must be a boolean (true/false, yes/no, 1/0, on/off) (got: '${value}')" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid boolean"
    return 0
}

# --- __validate_bridge__ -----------------------------------------------------
__validate_bridge__() {
    local bridge="$1"
    local field_name="${2:-bridge}"

    __argparser_log__ "TRACE" "Validating bridge: $field_name='$bridge'"

    # Bridge format: vmbr followed by a number
    if ! [[ "$bridge" =~ ^vmbr[0-9]+$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: invalid bridge format"
        echo "Error: ${field_name} must be in format vmbrN (e.g., vmbr0, vmbr1) (got: '${bridge}')" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid bridge"
    return 0
}

# --- __validate_vlan__ -------------------------------------------------------
__validate_vlan__() {
    local vlan="$1"
    local field_name="${2:-VLAN ID}"

    __argparser_log__ "TRACE" "Validating VLAN: $field_name='$vlan'"

    if ! __validate_numeric__ "$vlan" "$field_name"; then
        return 1
    fi

    if ((vlan < 1 || vlan > 4094)); then
        __argparser_log__ "DEBUG" "Validation failed: VLAN out of range"
        echo "Error: ${field_name} must be between 1 and 4094 (got: ${vlan})" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid VLAN"
    return 0
}

# --- __validate_node_name__ --------------------------------------------------
__validate_node_name__() {
    local node="$1"
    local field_name="${2:-node name}"

    __argparser_log__ "TRACE" "Validating node name: $field_name='$node'"

    # Node names should be valid hostnames (lowercase, alphanumeric, hyphens)
    if ! [[ "$node" =~ ^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: invalid node name format"
        echo "Error: ${field_name} must be a valid node name (lowercase, alphanumeric, hyphens)" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid node name"
    return 0
}

# --- __validate_cpu_cores__ --------------------------------------------------
__validate_cpu_cores__() {
    local cores="$1"
    local field_name="${2:-CPU cores}"

    __argparser_log__ "TRACE" "Validating CPU cores: $field_name='$cores'"

    if ! __validate_numeric__ "$cores" "$field_name"; then
        return 1
    fi

    if ((cores < 1 || cores > 512)); then
        __argparser_log__ "DEBUG" "Validation failed: cores out of range"
        echo "Error: ${field_name} must be between 1 and 512 (got: ${cores})" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid CPU cores"
    return 0
}

# --- __validate_memory__ -----------------------------------------------------
__validate_memory__() {
    local memory="$1"
    local field_name="${2:-memory}"

    __argparser_log__ "TRACE" "Validating memory: $field_name='$memory'"

    if ! __validate_numeric__ "$memory" "$field_name"; then
        return 1
    fi

    if ((memory < 16)); then
        __argparser_log__ "DEBUG" "Validation failed: memory below minimum"
        echo "Error: ${field_name} must be at least 16 MB (got: ${memory})" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid memory"
    return 0
}

# --- __validate_disk_size__ --------------------------------------------------
__validate_disk_size__() {
    local size="$1"
    local field_name="${2:-disk size}"

    __argparser_log__ "TRACE" "Validating disk size: $field_name='$size'"

    # Disk size can be: 10G, 500M, 1T, or just a number (assumed GB)
    if ! [[ "$size" =~ ^[0-9]+[KMGT]?$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: invalid disk size format"
        echo "Error: ${field_name} must be a number optionally followed by K/M/G/T (e.g., 10G, 500M) (got: '${size}')" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid disk size"
    return 0
}

# --- __validate_onboot__ -----------------------------------------------------
__validate_onboot__() {
    local value="$1"
    local field_name="${2:-onboot}"

    __argparser_log__ "TRACE" "Validating onboot: $field_name='$value'"

    if ! [[ "$value" =~ ^[01]$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: onboot must be 0 or 1"
        echo "Error: ${field_name} must be 0 or 1 (got: '${value}')" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid onboot"
    return 0
}

# --- __validate_ostype__ -----------------------------------------------------
__validate_ostype__() {
    local ostype="$1"
    local field_name="${2:-OS type}"

    __argparser_log__ "TRACE" "Validating OS type: $field_name='$ostype'"

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
        __argparser_log__ "DEBUG" "Validation failed: invalid OS type"
        echo "Error: ${field_name} must be a valid OS type (e.g., l26, win10, win11)" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid OS type"
    return 0
}

# --- __validate_path__ -------------------------------------------------------
__validate_path__() {
    local path="$1"
    local field_name="${2:-path}"

    __argparser_log__ "TRACE" "Validating path: $field_name='$path'"

    # Basic path validation - just check it's not empty
    if [[ -z "$path" ]]; then
        __argparser_log__ "DEBUG" "Validation failed: path is empty"
        echo "Error: ${field_name} cannot be empty" >&2
        return 1
    fi

    # Note: Bash cannot handle null bytes in strings (they terminate the string),
    # so we don't need to explicitly check for them. Any path that makes it here
    # as a string is already free of null bytes.

    __argparser_log__ "TRACE" "Validation passed: valid path"
    return 0
}

# --- __validate_url__ --------------------------------------------------------
__validate_url__() {
    local url="$1"
    local field_name="${2:-URL}"

    __argparser_log__ "TRACE" "Validating URL: $field_name='$url'"

    # Basic URL validation
    if ! [[ "$url" =~ ^https?://[a-zA-Z0-9\.\-]+([:/][^[:space:]]*)?$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: invalid URL format"
        echo "Error: ${field_name} must be a valid HTTP/HTTPS URL (got: '${url}')" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid URL"
    return 0
}

# --- __validate_email__ ------------------------------------------------------
__validate_email__() {
    local email="$1"
    local field_name="${2:-email}"

    __argparser_log__ "TRACE" "Validating email: $field_name='$email'"

    # Basic email validation
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        __argparser_log__ "DEBUG" "Validation failed: invalid email format"
        echo "Error: ${field_name} must be a valid email address (got: '${email}')" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid email"
    return 0
}

# --- __validate_string__ -----------------------------------------------------
__validate_string__() {
    local value="$1"
    local field_name="${2:-string}"

    __argparser_log__ "TRACE" "Validating string: $field_name='$value'"

    # Just check it's not empty
    if [[ -z "$value" ]]; then
        __argparser_log__ "DEBUG" "Validation failed: string is empty"
        echo "Error: ${field_name} cannot be empty" >&2
        return 1
    fi

    __argparser_log__ "TRACE" "Validation passed: valid string"
    return 0
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

