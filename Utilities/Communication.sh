#!/bin/bash
#
# Communication.sh
#
# Provides spinner animation, color-coded printing, and error handling utilities
# for other Bash scripts.
#
# Usage:
#   source "Communication.sh"
#
# Example:
#   #!/bin/bash
#   source "./Communication.sh"
#   info "Performing tasks..."
#   # ... do work ...
#   __ok__ "Tasks completed successfully!"
#
# Function Index:
#   - __comm_log__
#   - __spin__
#   - __stop_spin__
#   - __info__
#   - __update__
#   - __ok__
#   - __success__
#   - __warn__
#   - __err__
#   - __handle_err__
#   - __show_script_header__
#   - __show_script_examples__
#   - __display_script_info__
#

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Safe logging wrapper - works even if Logger.sh not loaded
__comm_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "COMM"
    fi
}

###############################################################################
# GLOBALS
###############################################################################
SPINNER_PID=""
CURRENT_MESSAGE=""
QUIET_MODE="${QUIET_MODE:-false}"

###############################################################################
# Color Definitions and Spinner
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

# --- __spin__ ------------------------------------------------------------
# @function __spin__
# @description Runs an infinite spinner with rainbow color cycling in the background.
#              Reads CURRENT_MESSAGE to display alongside the spinner.
# @usage __spin__ &
# @return Runs indefinitely until terminated.
# @example_output When executed in the background, the spinner animates through rainbow colors.
__spin__() {
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_i=0
    local color_i=0
    local interval=0.05

    __comm_log__ "DEBUG" "Spinner loop started"
    printf "\e[?25l" # hide cursor

    while true; do
        local rgb="${RAINBOW_COLORS[color_i]}"

        # Clear entire line, then print spinner and message
        printf "\r\033[K"
        printf "\033[38;2;${rgb}m%s\033[0m " "${frames[spin_i]}"
        printf "%b" "$CURRENT_MESSAGE"

        spin_i=$(((spin_i + 1) % ${#frames[@]}))
        color_i=$(((color_i + 1) % ${#RAINBOW_COLORS[@]}))
        sleep "$interval"
    done
}

# --- __stop_spin__ ------------------------------------------------------------
# @function __stop_spin__
# @description Stops the running spinner process (if any) and restores the cursor.
# @usage __stop_spin__
# @return Terminates the spinner and resets SPINNER_PID.
# @example_output The spinner process is terminated and the cursor is made visible.
__stop_spin__() {
    # Kill any existing spinner process
    if [[ -n "${SPINNER_PID:-}" ]]; then
        if ps -p "$SPINNER_PID" &>/dev/null 2>&1; then
            kill "$SPINNER_PID" &>/dev/null 2>&1 || true
            wait "$SPINNER_PID" 2>/dev/null || true
            __comm_log__ "DEBUG" "Stopped spinner (PID: $SPINNER_PID)"
        fi
    fi

    # Always reset the PID
    SPINNER_PID=""

    # Clear the spinner line
    printf "\r\033[K"
    printf "\e[?25h" # show cursor
}

# --- __info__ ------------------------------------------------------------
# @function __info__
# @description Prints an informational message in bold yellow and starts the rainbow spinner.
#              If a spinner is already running, it stops the old one first.
#              In non-interactive mode, prints a simple text message without spinner.
# @usage __info__ "message"
# @param msg The message to display.
# @return Displays the message and starts the spinner (or simple text in non-interactive mode).
# @example_output "Processing..." is displayed in bold yellow with an active spinner.
__info__() {
    local msg="$1"

    __comm_log__ "DEBUG" "__info__ called: $msg"

    # Skip spinner in non-interactive mode or when not a TTY
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] || [[ ! -t 1 ]]; then
        echo "[INFO] $msg"
        __comm_log__ "INFO" "$msg"
        return 0
    fi

    # Skip in quiet mode
    [[ "$QUIET_MODE" == "true" ]] && return 0

    # Stop any existing spinner first
    __stop_spin__
    __comm_log__ "DEBUG" "Stopped existing spinner (if any)"

    # Update message buffer with colored text
    CURRENT_MESSAGE="${YELLOW}${BOLD}${msg}${RESET}"

    # Clear any existing line content
    printf "\r\033[K"

    # Start new spinner (it will read CURRENT_MESSAGE)
    __spin__ &
    SPINNER_PID=$!
    __comm_log__ "DEBUG" "Started spinner (PID: $SPINNER_PID)"

    # Give spinner a moment to render first frame
    sleep 0.01
}

# --- __update__ ------------------------------------------------------------
# @function __update__
# @description Updates the text displayed next to the spinner without stopping it.
#              In non-interactive mode, prints a simple text message.
# @usage __update__ "new message"
# @param new message The updated text to display.
# @return Updates the spinner line text.
# @example_output The text next to the spinner is replaced with "new message".
__update__() {
    local msg="$1"

    __comm_log__ "DEBUG" "__update__ called: $msg"

    # Simple echo in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
        echo "[INFO] $msg"
        __comm_log__ "INFO" "Update (non-interactive): $msg"
        return 0
    fi

    # Skip in quiet mode
    [[ "$QUIET_MODE" == "true" ]] && return 0

    # Update the message buffer
    # The spinner loop will pick it up on next iteration
    CURRENT_MESSAGE="$msg"
    __comm_log__ "DEBUG" "Message buffer updated"
}

# --- __ok__ ------------------------------------------------------------
# @function __ok__
# @description Stops the spinner and prints a success message in green.
# @usage __ok__ "success message"
# @param msg The success message to display.
# @return Terminates the spinner and displays the success message.
# @example_output The spinner stops and "Completed successfully!" is printed in green bold.
__ok__() {
    local msg="$1"

    __comm_log__ "DEBUG" "__ok__ called: $msg"

    __stop_spin__

    # Skip output in quiet mode
    [[ "$QUIET_MODE" == "true" ]] && return 0

    echo -e "${GREEN}${BOLD}✓${RESET} ${msg}"
    __comm_log__ "INFO" "Success: $msg"
}

# --- __success__ -------------------------------------------------------------
# @function __success__
# @description Alias for __ok__ for backward compatibility
# @usage __success__ "success message"
# @param msg The success message to display.
__success__() {
    __ok__ "$@"
}

# --- __warn__ ----------------------------------------------------------------
# @function __warn__
# @description Stops the spinner and prints a warning message in yellow.
# @usage __warn__ "warning message"
# @param msg The warning message to display.
# @return Terminates the spinner and displays the warning message.
# @example_output The spinner stops and "Warning: check configuration!" is printed in yellow bold.
__warn__() {
    local msg="$1"

    __comm_log__ "WARN" "$msg"

    __stop_spin__

    # Always show warnings even in quiet mode
    echo -e "${YELLOW}${BOLD}⚠${RESET} ${msg}" >&2
}

# --- __err__ ------------------------------------------------------------
# @function __err__
# @description Stops the spinner and prints an error message in red.
# @usage __err__ "error message"
# @param msg The error message to display.
# @return Terminates the spinner and displays the error message.
# @example_output The spinner stops and "Operation failed!" is printed in red bold.
__err__() {
    local msg="$1"

    __comm_log__ "ERROR" "$msg"

    __stop_spin__

    # Always show errors even in quiet mode
    echo -e "${RED}${BOLD}✗${RESET} ${msg}" >&2
}

# --- __handle_err__ ------------------------------------------------------------
# @function __handle_err__
# @description Handles errors by stopping the spinner and printing error details
#   including the line number, exit code, and failing command.
# @usage trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
# @param line_number The line number where the error occurred.
# @param command The command that caused the error.
# @return Displays error details and stops the spinner.
# @example_output Error details with line number, exit code, and failing command are printed.
__handle_err__() {
    local line_number="$1"
    local command="$2"
    local exit_code="$?"

    __comm_log__ "ERROR" "Error at line $line_number, exit code $exit_code: $command"

    __stop_spin__

    echo -e "${RED}${BOLD}[ERROR]${RESET} at line ${RED}${line_number}${RESET}, exit code ${RED}${exit_code}${RESET}" >&2
    echo -e "  Command: ${YELLOW}${command}${RESET}" >&2
}

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- __show_script_header__ ------------------------------------------------------------
# @function __show_script_header__
# @description Displays the top commented section of a script file in green.
# @usage __show_script_header__ <script_path>
# @param script_path The path to the script file.
# @return Displays the header comments in green (0, 255, 0).
# @example_output Shows script description, usage, arguments, etc. in green.
__show_script_header__() {
    local script_path="$1"

    __comm_log__ "DEBUG" "Displaying script header for: $script_path"

    # Source Colors.sh if __line_rgb__ is not available
    if ! declare -f __line_rgb__ >/dev/null 2>&1; then
        if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Colors.sh" ]]; then
            source "${UTILITYPATH}/Colors.sh"
        fi
    fi

    local printing=false
    local line_count=0
    while IFS= read -r line; do
        # Skip shebang line
        if [[ "$line" =~ ^#!/bin/bash$ ]]; then
            continue
        fi
        # Skip empty comment lines
        if [[ "$line" == "#" ]]; then
            continue
        fi
        # Process comment lines
        if [[ "$line" =~ ^# ]]; then
            __line_rgb__ "${line#\# }" 0 255 0
            printing=true
            ((line_count += 1))
        else
            # Stop at first non-comment line after comments started
            [[ $printing == true ]] && break
        fi
    done <"$script_path"

    __comm_log__ "DEBUG" "Displayed $line_count header lines"
}

# --- __show_script_examples__ ----------------------------------------------------------
# @function __show_script_examples__
# @description Extracts and displays example invocation lines (lines starting with '# ./') in green.
# @usage __show_script_examples__ <script_path>
# @param script_path The path to the script file.
# @return Displays example invocation lines in green (0, 255, 0).
# @example_output Shows lines like "./script.sh arg1 arg2" in green.
__show_script_examples__() {
    local script_path="$1"

    __comm_log__ "DEBUG" "Displaying script examples for: $script_path"

    # Source Colors.sh if __line_rgb__ is not available
    if ! declare -f __line_rgb__ >/dev/null 2>&1; then
        if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Colors.sh" ]]; then
            source "${UTILITYPATH}/Colors.sh"
        fi
    fi

    local found_any=false
    local example_count=0
    grep -E '^# *\./' "$script_path" 2>/dev/null | sed -E 's/^# *//' | while IFS= read -r line; do
        __line_rgb__ "$line" 0 255 0
        found_any=true
        ((example_count += 1))
    done

    __comm_log__ "DEBUG" "Displayed $example_count examples"

    # If no examples found, show message
    if [[ $found_any == false ]]; then
        echo "(none)"
        __comm_log__ "DEBUG" "No examples found"
    fi
}

# --- __display_script_info__ -----------------------------------------------------------
# @function __display_script_info__
# @description Displays complete script information with headers and examples in a consistent format.
# @usage __display_script_info__ <script_path> [script_display_name]
# @param script_path The path to the script file.
# @param script_display_name Optional display name (defaults to script_path).
# @return Displays formatted script information with colored headers and content.
# @example_output Shows "Selected script", top comments, and example invocations sections.
__display_script_info__() {
    local script_path="$1"
    local display_name="${2:-$script_path}"

    __comm_log__ "DEBUG" "Displaying script info for: $display_name (path: $script_path)"

    # Source Colors.sh if __line_rgb__ is not available
    if ! declare -f __line_rgb__ >/dev/null 2>&1; then
        if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Colors.sh" ]]; then
            source "${UTILITYPATH}/Colors.sh"
        fi
    fi

    echo
    __line_rgb__ "Selected script: ${display_name}" 0 255 255
    echo
    __line_rgb__ "--- Top Comments ---" 255 255 0
    echo
    __show_script_header__ "$script_path"
    echo
    __line_rgb__ "--- Example Invocations ---" 255 255 0
    echo
    __show_script_examples__ "$script_path"
    echo

    __comm_log__ "DEBUG" "Script info display complete"
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

