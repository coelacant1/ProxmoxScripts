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
#   - __handle_err__
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
    printf "\r\033[38;2;${rgb}m%s\033[0m " "${frames[spin_i]}"
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
# @usage __info__ "message"
# @param msg The message to display.
# @return Displays the message and starts the spinner.
# @example_output "Processing..." is displayed in bold yellow with an active spinner.
__info__() {
  local msg="$1"
  echo -ne "  ${YELLOW}${BOLD}${msg}${RESET} "
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
  echo -ne "\r\033[2C\033[K$1"
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
