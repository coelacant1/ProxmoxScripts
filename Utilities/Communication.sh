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
#   - __spin__
#   - __stop_spin__
#   - __info__
#   - __update__
#   - __ok__
#   - __err__
#   - __warn__
#   - __handle_err__
#   - __show_script_header__
#   - __show_script_examples__
#   - __display_script_info__
#

###############################################################################
# GLOBALS
###############################################################################
SPINNER_PID=""

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
# @usage __spin__ &
# @return Runs indefinitely until terminated.
# @example_output When executed in the background, the spinner animates through rainbow colors.
__spin__() {
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_i=0
    local color_i=0
    local interval=0.025
    
    printf "\e[?25l"  # hide cursor
    
    while true; do
        local rgb="${RAINBOW_COLORS[color_i]}"
        # Move to start of line, then move 2 characters right to avoid text overlap
        printf "\r\033[2C\033[38;2;${rgb}m%s\033[0m " "${frames[spin_i]}"
        spin_i=$(( (spin_i + 1) % ${#frames[@]} ))
        color_i=$(( (color_i + 1) % ${#RAINBOW_COLORS[@]} ))
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
    if [[ -n "$SPINNER_PID" ]] && ps -p "$SPINNER_PID" &>/dev/null; then
        kill "$SPINNER_PID" &>/dev/null
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    printf "\e[?25h"  # show cursor
}

# --- __info__ ------------------------------------------------------------
# @function __info__
# @description Prints an informational message in bold yellow and starts the rainbow spinner.
#              If a spinner is already running, it stops the old one first.
# @usage __info__ "message"
# @param msg The message to display.
# @return Displays the message and starts the spinner.
# @example_output "Processing..." is displayed in bold yellow with an active spinner.
__info__() {
    local msg="$1"
    
    # Stop any existing spinner first
    if [[ -n "$SPINNER_PID" ]] && ps -p "$SPINNER_PID" &>/dev/null; then
        kill "$SPINNER_PID" &>/dev/null
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    
    # Clear the line and start fresh
    echo -ne "\r\033[K"
    echo -ne "  ${YELLOW}${BOLD}${msg}${RESET} "
    
    # Start new spinner
    __spin__ &
    SPINNER_PID=$!
}

# --- __update__ ------------------------------------------------------------
# @function __update__
# @description Updates the text displayed next to the spinner without stopping it.
# @usage __update__ "new message"
# @param new message The updated text to display.
# @return Updates the spinner line text.
# @example_output The text next to the spinner is replaced with "new message".
__update__() {
    # Move to column 4 (after the spinner position) and clear to end of line
    echo -ne "\r\033[4C\033[K$1"
}

# --- __ok__ ------------------------------------------------------------
# @function __ok__
# @description Stops the spinner and prints a success message in green.
# @usage __ok__ "success message"
# @param msg The success message to display.
# @return Terminates the spinner and displays the success message.
# @example_output The spinner stops and "Completed successfully!" is printed in green bold.
__ok__() {
    __stop_spin__
    echo -ne "\r\033[K"   # Clear the line first
    local msg="$1"
    echo -e "${GREEN}${BOLD}${msg}${RESET}"
}

# --- __warn__ ----------------------------------------------------------------
# @function __warn__
# @description Stops the spinner and prints a warning message in yellow.
# @usage __warn__ "warning message"
# @param msg The warning message to display.
# @return Terminates the spinner and displays the warning message.
# @example_output The spinner stops and "Warning: check configuration!" is printed in yellow bold.
__warn__() {
    __stop_spin__
    echo -ne "\r\033[K"   # Clear the line first
    local msg="$1"
    echo -e "${YELLOW}${BOLD}${msg}${RESET}"
}

# --- __err__ ------------------------------------------------------------
# @function __err__
# @description Stops the spinner and prints an error message in red.
# @usage __err__ "error message"
# @param msg The error message to display.
# @return Terminates the spinner and displays the error message.
# @example_output The spinner stops and "Operation failed!" is printed in red bold.
__err__() {
    __stop_spin__
    echo -ne "\r\033[K"   # Clear the line first
    local msg="$1"
    echo -e "${RED}${BOLD}${msg}${RESET}"
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
    __stop_spin__
    echo -ne "\r\033[K"   # Clear the line first
    echo -e "${RED}[ERROR]${RESET} line ${RED}${line_number}${RESET}, exit code ${RED}${exit_code}${RESET} while executing: ${YELLOW}${command}${RESET}"
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
    
    # Source Colors.sh if __line_rgb__ is not available
    if ! declare -f __line_rgb__ >/dev/null 2>&1; then
        if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Colors.sh" ]]; then
            source "${UTILITYPATH}/Colors.sh"
        fi
    fi
    
    local printing=false
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
        else
            # Stop at first non-comment line after comments started
            [[ $printing == true ]] && break
        fi
    done <"$script_path"
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
    
    # Source Colors.sh if __line_rgb__ is not available
    if ! declare -f __line_rgb__ >/dev/null 2>&1; then
        if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Colors.sh" ]]; then
            source "${UTILITYPATH}/Colors.sh"
        fi
    fi
    
    local found_any=false
    grep -E '^# *\./' "$script_path" 2>/dev/null | sed -E 's/^# *//' | while IFS= read -r line; do
        __line_rgb__ "$line" 0 255 0
        found_any=true
    done
    
    # If no examples found, show message
    if [[ $found_any == false ]]; then
        echo "(none)"
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
}

