#!/bin/bash
#
# ArgumentParser.sh
#
# Centralized argument parsing and validation library for ProxmoxScripts.
# Reduces code duplication by providing reusable argument parsing functions.
#
# Usage:
#   source "${UTILITYPATH}/ArgumentParser.sh"
#
# Function Index:
#   - __validate_numeric__
#   - __validate_ip__
#   - __validate_vmid_range__
#   - __validate_storage__
#   - __parse_positional_args__
#   - __parse_named_args__
#   - __parse_getopts_args__
#

###############################################################################
# Basic Validation Functions
###############################################################################

# --- __validate_numeric__ ----------------------------------------------------
# @function __validate_numeric__
# @description Validates that a value is numeric.
# @usage __validate_numeric__ "$value" "field_name"
# @param 1 Value to validate
# @param 2 Field name for error messages
# @return 0 if valid, 1 if invalid
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
# @function __validate_ip__
# @description Validates IPv4 address format.
# @usage __validate_ip__ "$ip" "field_name"
# @param 1 IP address to validate
# @param 2 Field name for error messages
# @return 0 if valid, 1 if invalid
__validate_ip__() {
    local ip="$1"
    local field_name="${2:-IP address}"
    
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Error: ${field_name} must be a valid IPv4 address (got: '${ip}')" >&2
        return 1
    fi
    
    # Validate each octet is 0-255
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

# --- __validate_vmid_range__ -------------------------------------------------
# @function __validate_vmid_range__
# @description Validates VM/CT ID range (both IDs numeric, start <= end).
# @usage __validate_vmid_range__ "$start_id" "$end_id"
# @param 1 Start ID
# @param 2 End ID
# @return 0 if valid, 1 if invalid
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

# --- __validate_storage__ ----------------------------------------------------
# @function __validate_storage__
# @description Validates that a storage exists and optionally supports content type.
# @usage __validate_storage__ "$storage_name" ["content_type"]
# @param 1 Storage name
# @param 2 Optional content type (iso, images, backup, etc.)
# @return 0 if valid, 1 if invalid
__validate_storage__() {
    local storage="$1"
    local content_type="${2:-}"
    
    if ! pvesm status --storage "$storage" &>/dev/null; then
        echo "Error: Storage '${storage}' not found" >&2
        echo "Available storages:" >&2
        pvesm status | tail -n +2 | awk '{print "  - " $1}' >&2
        return 1
    fi
    
    if [[ -n "$content_type" ]]; then
        if ! pvesm status --storage "$storage" --content "$content_type" &>/dev/null; then
            echo "Error: Storage '${storage}' does not support content type '${content_type}'" >&2
            return 1
        fi
    fi
    
    return 0
}

###############################################################################
# Argument Parsing Functions
###############################################################################

# --- __parse_positional_args__ -----------------------------------------------
# @function __parse_positional_args__
# @description Parses positional arguments with automatic validation.
# @usage __parse_positional_args__ <spec_string> "$@"
# @param 1 Spec string: "name:type[:required]" separated by spaces
# @param @ All script arguments
# @return Sets global variables with parsed values, returns 1 on error
#
# Spec format: "VAR_NAME:type:required"
#   types: numeric, ip, storage, vmid, ctid, string, path
#   required: "required" or "optional" (default: required)
#
# Example:
#   __parse_positional_args__ "START_ID:numeric:required END_ID:numeric:required STORAGE:storage:required MODE:string:optional" "$@"
__parse_positional_args__() {
    local spec="$1"
    shift
    
    local -a specs
    read -ra specs <<< "$spec"
    
    local arg_index=0
    for spec_item in "${specs[@]}"; do
        IFS=':' read -r var_name var_type var_required <<< "$spec_item"
        var_required="${var_required:-required}"
        
        # Get argument value
        local arg_value=""
        if [[ $arg_index -lt $# ]]; then
            arg_value="${!((arg_index + 1))}"
            ((arg_index++))
        fi
        
        # Check if required argument is missing
        if [[ "$var_required" == "required" && -z "$arg_value" ]]; then
            echo "Error: Missing required argument: ${var_name}" >&2
            return 1
        fi
        
        # Skip validation if optional and not provided
        if [[ -z "$arg_value" ]]; then
            eval "${var_name}=''"
            continue
        fi
        
        # Validate based on type
        case "$var_type" in
            numeric|vmid|ctid)
                if ! __validate_numeric__ "$arg_value" "$var_name"; then
                    return 1
                fi
                ;;
            ip)
                if ! __validate_ip__ "$arg_value" "$var_name"; then
                    return 1
                fi
                ;;
            storage)
                if ! __validate_storage__ "$arg_value"; then
                    return 1
                fi
                ;;
            string|path)
                # No validation needed for generic strings/paths
                ;;
            *)
                echo "Error: Unknown validation type '${var_type}' for ${var_name}" >&2
                return 1
                ;;
        esac
        
        # Set the variable
        eval "${var_name}='${arg_value}'"
    done
    
    return 0
}

# --- __parse_named_args__ ----------------------------------------------------
# @function __parse_named_args__
# @description Parses named arguments (--flag value style).
# @usage __parse_named_args__ <spec_string> "$@"
# @param 1 Spec string: "name:type:required:default" separated by spaces
# @param @ All script arguments
# @return Sets global variables with parsed values, returns 1 on error
#
# Spec format: "VAR_NAME:flag:type:required:default"
#   flag: --flag-name
#   type: numeric, ip, storage, boolean, string
#   required: "required" or "optional"
#   default: default value if not provided
#
# Example:
#   __parse_named_args__ "VMID:--vmid:numeric:required BACKUP:--backup:boolean:optional:false" "$@"
__parse_named_args__() {
    local spec="$1"
    shift
    
    local -a specs
    read -ra specs <<< "$spec"
    
    # Initialize all variables with defaults
    declare -A var_map
    declare -A type_map
    declare -A required_map
    
    for spec_item in "${specs[@]}"; do
        IFS=':' read -r var_name flag_name var_type var_required var_default <<< "$spec_item"
        var_required="${var_required:-optional}"
        var_default="${var_default:-}"
        
        var_map["$flag_name"]="$var_name"
        type_map["$flag_name"]="$var_type"
        required_map["$flag_name"]="$var_required"
        
        # Set default value
        eval "${var_name}='${var_default}'"
    done
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        local flag="$1"
        
        if [[ ! "${var_map[$flag]+isset}" ]]; then
            echo "Error: Unknown flag: ${flag}" >&2
            return 1
        fi
        
        local var_name="${var_map[$flag]}"
        local var_type="${type_map[$flag]}"
        
        # Handle boolean flags
        if [[ "$var_type" == "boolean" ]]; then
            eval "${var_name}=true"
            shift
            continue
        fi
        
        # Get value for non-boolean flags
        if [[ $# -lt 2 ]]; then
            echo "Error: Flag ${flag} requires a value" >&2
            return 1
        fi
        
        local arg_value="$2"
        shift 2
        
        # Validate based on type
        case "$var_type" in
            numeric)
                if ! __validate_numeric__ "$arg_value" "$flag"; then
                    return 1
                fi
                ;;
            ip)
                if ! __validate_ip__ "$arg_value" "$flag"; then
                    return 1
                fi
                ;;
            storage)
                if ! __validate_storage__ "$arg_value"; then
                    return 1
                fi
                ;;
            string)
                # No validation needed
                ;;
            *)
                echo "Error: Unknown type '${var_type}' for ${flag}" >&2
                return 1
                ;;
        esac
        
        # Set the variable
        eval "${var_name}='${arg_value}'"
    done
    
    # Check required arguments
    for flag in "${!required_map[@]}"; do
        if [[ "${required_map[$flag]}" == "required" ]]; then
            local var_name="${var_map[$flag]}"
            local var_value
            eval "var_value=\${${var_name}}"
            if [[ -z "$var_value" ]]; then
                echo "Error: Required flag ${flag} not provided" >&2
                return 1
            fi
        fi
    done
    
    return 0
}

###############################################################################
# Common Argument Patterns
###############################################################################

# --- __parse_vmid_range_args__ -----------------------------------------------
# @function __parse_vmid_range_args__
# @description Common pattern: parse start/end VM IDs with validation.
# @usage __parse_vmid_range_args__ "$@"
# @param 1 Start VM ID
# @param 2 End VM ID
# @return Sets START_VMID and END_VMID globals, returns 1 on error
__parse_vmid_range_args__() {
    if [[ $# -lt 2 ]]; then
        echo "Error: start_vmid and end_vmid are required" >&2
        return 1
    fi
    
    START_VMID="$1"
    END_VMID="$2"
    
    if ! __validate_vmid_range__ "$START_VMID" "$END_VMID"; then
        return 1
    fi
    
    return 0
}

# --- __parse_bulk_operation_args__ -------------------------------------------
# @function __parse_bulk_operation_args__
# @description Common pattern for bulk operations: vmid range + additional params.
# @usage __parse_bulk_operation_args__ <required_count> <param_spec> "$@"
# @param 1 Required argument count (including vmid range)
# @param 2 Parameter spec for additional args after vmid range
# @param @ All script arguments
# @return Sets START_VMID, END_VMID and other variables, returns 1 on error
#
# Example:
#   __parse_bulk_operation_args__ 4 "STORAGE:storage:required MODE:string:optional" "$@"
__parse_bulk_operation_args__() {
    local required_count="$1"
    local param_spec="$2"
    shift 2
    
    if [[ $# -lt $required_count ]]; then
        echo "Error: Expected at least ${required_count} arguments" >&2
        return 1
    fi
    
    # Parse VM ID range
    if ! __parse_vmid_range_args__ "$1" "$2"; then
        return 1
    fi
    shift 2
    
    # Parse additional parameters
    if [[ -n "$param_spec" ]]; then
        if ! __parse_positional_args__ "$param_spec" "$@"; then
            return 1
        fi
    fi
    
    return 0
}
