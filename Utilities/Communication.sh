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

###############################################################################
# RAINBOW SPINNER (INFINITE LOOP)
###############################################################################
# @function spin
# @description Runs an infinite spinner with rainbow color cycling in the background.
# @usage
#   spin &
#   SPINNER_PID=$!
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

###############################################################################
# STOPPING THE SPINNER
###############################################################################
# @function stop_spin
# @description Kills the spinner background process, if any, and restores the cursor.
# @usage
#   stop_spin
__stop_spin__() {
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
__info__() {
  local msg="$1"
  echo -ne "  ${YELLOW}${BOLD}${msg}${RESET} "
  __spin__ &
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
__update__() {
  echo -ne "\r\033[2C\033[K$1"
}

###############################################################################
# SUCCESS MESSAGE (Stops Spinner)
###############################################################################
# @function ok
# @description Kills spinner, prints success message in green.
# @usage
#   __ok__ "Everything done!"
__ok__() {
  __stop_spin__
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
#   __err__ "Something went wrong!"
__err__() {
  __stop_spin__
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
#   trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
__handle_err__() {
  local line_number="$1"
  local command="$2"
  local exit_code="$?"
  __stop_spin__
  echo -ne "\r\033[K"   # Clear the line first
  echo -e "${RED}[ERROR]${RESET} line ${RED}${line_number}${RESET}, exit code ${RED}${exit_code}${RESET} while executing: ${YELLOW}${command}${RESET}"
}

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
