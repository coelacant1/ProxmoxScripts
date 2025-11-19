#!/bin/bash
#
# Logger.sh
#
# Centralized logging utility for ProxmoxScripts
# Provides consistent, structured logging across all scripts
#
# Usage:
#   source "${UTILITYPATH}/Logger.sh"
#   __log__ "INFO" "Message here"
#   __log__ "ERROR" "Something failed"
#   __log__ "DEBUG" "Debug information"
#
# Environment Variables:
#   LOG_LEVEL - Minimum level to log (DEBUG, INFO, WARN, ERROR) - default: INFO
#   LOG_FILE - Path to log file - default: /tmp/proxmox_scripts.log
#   LOG_CONSOLE - Whether to also log to console (1=yes, 0=no) - default: 1
#   LOG_TIMESTAMP - Whether to include timestamps (1=yes, 0=no) - default: 1
#
# Function Index:
#   - __get_log_priority__
#   - __log__
#   - __log_debug__
#   - __log_info__
#   - __log_warn__
#   - __log_error__
#   - __log_function_entry__
#   - __log_function_exit__
#   - __log_command__
#   - __log_var__
#   - __log_section__
#

# Default configuration
: "${LOG_LEVEL:=INFO}"
: "${LOG_FILE:=/tmp/proxmox_scripts.log}"
: "${LOG_CONSOLE:=1}"
: "${LOG_TIMESTAMP:=1}"

# Log level priorities
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# Get current log level priority
__get_log_priority__() {
    echo "${LOG_LEVELS[${1:-INFO}]:-1}"
}

# --- __log__ -------------------------------------------------------------------
# @function __log__
# @description Core logging function with level-based filtering and formatting
# @usage __log__ <level> <message> [category]
# @param level Log level (DEBUG, INFO, WARN, ERROR)
# @param message Message to log
# @param category Optional category/component name
__log__() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local category="${3:-}"

    # Check if we should log this level
    local current_priority
    local min_priority
    current_priority=$(__get_log_priority__ "$level")
    min_priority=$(__get_log_priority__ "$LOG_LEVEL")

    if [[ $current_priority -lt $min_priority ]]; then
        return 0
    fi

    # Build log entry
    local log_entry=""

    # Add timestamp if enabled
    if [[ $LOG_TIMESTAMP -eq 1 ]]; then
        # Use full path to date for environments with minimal PATH
        if command -v date >/dev/null 2>&1; then
            log_entry+="[$(date '+%Y-%m-%d %H:%M:%S')] "
        elif [[ -x /bin/date ]]; then
            log_entry+="[$(\/bin/date '+%Y-%m-%d %H:%M:%S')] "
        elif [[ -x /usr/bin/date ]]; then
            log_entry+="[$(\/usr/bin/date '+%Y-%m-%d %H:%M:%S')] "
        else
            # Fallback: no timestamp if date not available
            log_entry+="[NO-TIMESTAMP] "
        fi
    fi

    # Add level
    log_entry+="[$level] "

    # Add category if provided
    if [[ -n "$category" ]]; then
        log_entry+="[$category] "
    fi

    # Add calling script/function context
    if [[ ${#FUNCNAME[@]} -gt 2 ]]; then
        log_entry+="[${FUNCNAME[2]}] "
    fi

    # Add message
    log_entry+="$message"

    # Write to log file
    echo "$log_entry" >>"$LOG_FILE"

    # Write to console if enabled
    if [[ $LOG_CONSOLE -eq 1 ]]; then
        case "$level" in
            ERROR)
                echo -e "\033[0;31m$log_entry\033[0m" >&2
                ;;
            WARN)
                echo -e "\033[0;33m$log_entry\033[0m" >&2
                ;;
            DEBUG)
                echo -e "\033[0;36m$log_entry\033[0m"
                ;;
            *)
                echo "$log_entry"
                ;;
        esac
    fi
}

# --- __log_debug__ -------------------------------------------------------------
# @function __log_debug__
# @description Log debug message
__log_debug__() {
    __log__ "DEBUG" "$1" "${2:-}"
}

# --- __log_info__ --------------------------------------------------------------
# @function __log_info__
# @description Log info message
__log_info__() {
    __log__ "INFO" "$1" "${2:-}"
}

# --- __log_warn__ --------------------------------------------------------------
# @function __log_warn__
# @description Log warning message
__log_warn__() {
    __log__ "WARN" "$1" "${2:-}"
}

# --- __log_error__ -------------------------------------------------------------
# @function __log_error__
# @description Log error message
__log_error__() {
    __log__ "ERROR" "$1" "${2:-}"
}

# --- __log_function_entry__ ----------------------------------------------------
# @function __log_function_entry__
# @description Log function entry with parameters
__log_function_entry__() {
    local func_name="${FUNCNAME[1]}"
    local params="$*"
    __log__ "DEBUG" "Entering function: $func_name($params)" "TRACE"
}

# --- __log_function_exit__ -----------------------------------------------------
# @function __log_function_exit__
# @description Log function exit with return code
__log_function_exit__() {
    local func_name="${FUNCNAME[1]}"
    local exit_code="${1:-0}"
    __log__ "DEBUG" "Exiting function: $func_name (exit code: $exit_code)" "TRACE"
}

# --- __log_command__ -----------------------------------------------------------
# @function __log_command__
# @description Log command execution with exit code
# @usage __log_command__ "command to run"
__log_command__() {
    local cmd="$1"
    __log__ "DEBUG" "Executing: $cmd" "CMD"

    # Execute command and capture exit code
    eval "$cmd"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        __log__ "DEBUG" "Command succeeded: $cmd" "CMD"
    else
        __log__ "ERROR" "Command failed (exit $exit_code): $cmd" "CMD"
    fi

    return $exit_code
}

# --- __log_var__ ---------------------------------------------------------------
# @function __log_var__
# @description Log variable value
__log_var__() {
    local var_name="$1"
    local var_value="${!1:-<unset>}"
    __log__ "DEBUG" "$var_name='$var_value'" "VAR"
}

# --- __log_section__ -----------------------------------------------------------
# @function __log_section__
# @description Log section separator
__log_section__() {
    local section_name="$1"
    __log__ "INFO" "═══════════════════════════════════════════════════════" ""
    __log__ "INFO" "  $section_name" ""
    __log__ "INFO" "═══════════════════════════════════════════════════════" ""
}

# Initialize log file on first source
if [[ ! -f "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    __log__ "INFO" "Log initialized" "LOGGER"
fi
