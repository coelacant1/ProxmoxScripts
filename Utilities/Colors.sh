#!/usr/bin/env bash
#
# Colors.sh
#
# Provides 24-bit gradient printing and asynchronous "blink" simulation.
#
# Function Index:
#   - __int_lerp__
#   - __gradient_print__
#   - __line_gradient__
#   - __line_rgb__
#   - __simulate_blink_async__
#

###############################################################################
# GLOBALS
###############################################################################
# Just for completeness, define a RESET to revert terminal colors.
RESET="\033[0m"

# --- __int_lerp__ ------------------------------------------------------------
# @function __int_lerp__
# @description Performs integer linear interpolation between START and END
#   using FRACTION (0 to 100). Calculates: start + ((end - start) * fraction) / 100.
# @usage
#   __int_lerp__ <start> <end> <fraction>
# @param start The starting integer value.
# @param end The ending integer value.
# @param fraction The interpolation fraction (0 to 100).
# @return
#   Prints the interpolated integer value.
# @example_output
#   For __int_lerp__ 10 20 50, the output is: 15
__int_lerp__() {
    local start=$1
    local end=$2
    local fraction=$3
    local diff=$((end - start))
    local val=$((start + (diff * fraction) / 100))
    echo "$val"
}

# --- __gradient_print__ ------------------------------------------------------
# @function __gradient_print__
# @description Prints multi-line text with a vertical color gradient.
#   Interpolates colors from (R1,G1,B1) to (R2,G2,B2) line-by-line.
#   For a single line, prints in the end color.
# @usage
#   __gradient_print__ "multi-line text" R1 G1 B1 R2 G2 B2 [excluded_chars]
# @param text The multi-line text to print.
# @param R1 G1 B1 The starting RGB color.
# @param R2 G2 B2 The ending RGB color.
# @param excluded_chars (Optional) String of characters to exclude from coloring.
# @return
#   Prints the text with a gradient applied.
# @example_output
#   When given ASCII art and colors from (128,0,128) to (0,255,255),
#   the output is the ASCII art printed with a vertical gradient.
__gradient_print__() {
    local text="$1"
    local R1="$2"
    local G1="$3"
    local B1="$4"
    local R2="$5"
    local G2="$6"
    local B2="$7"
    local excluded_chars="${8:-}"  # string of characters to exclude from coloring

    # Read multiline input into an array
    mapfile -t lines <<< "$text"

    local total_lines=${#lines[@]}
    if (( total_lines <= 1 )); then
        # If only 1 line, just print it in the end color (except excludes)
        local lineColorPrefix="\033[38;2;${R2};${G2};${B2}m"
        local lineColorSuffix="\033[0m"
        local single_line="${lines[0]}"
        
        # Print char by char, skipping excludes
        for (( i=0; i<${#single_line}; i++ )); do
            local ch="${single_line:i:1}"
            if [[ "$excluded_chars" == *"$ch"* ]]; then
                # Print excluded char with no color
                echo -n "$ch"
            else
                # Print normal char with color
                echo -en "${lineColorPrefix}${ch}${lineColorSuffix}"
            fi
        done
        echo
        return
    fi

    # Multiple lines => top-to-bottom gradient
    for (( i=0; i<total_lines; i++ )); do
        local fraction=$(( i * 100 / (total_lines - 1) ))
        
        # Interpolate color
        local R=$(__int_lerp__ "$R1" "$R2" "$fraction")
        local G=$(__int_lerp__ "$G1" "$G2" "$fraction")
        local B=$(__int_lerp__ "$B1" "$B2" "$fraction")

        # Color codes for the line
        local lineColorPrefix="\033[38;2;${R};${G};${B}m"
        local lineColorSuffix="\033[0m"

        # Print line char by char, skipping excludes
        local line="${lines[$i]}"
        for (( j=0; j<${#line}; j++ )); do
            local ch="${line:j:1}"
            
            # If ch is in the excluded list, print it uncolored
            if [[ "$excluded_chars" == *"$ch"* ]]; then
                echo -n "$ch"
            else
                # Otherwise print with the line's color
                echo -en "${lineColorPrefix}${ch}${lineColorSuffix}"
            fi
        done
        echo
    done
}

# --- __line_gradient__ -------------------------------------------------------
# @function __line_gradient__
# @description Applies a left-to-right color gradient to a single line of text.
#   Interpolates each character from (R1,G1,B1) to (R2,G2,B2).
# @usage
#   __line_gradient__ "text" R1 G1 B1 R2 G2 B2
# @param text The text to print.
# @param R1 G1 B1 The starting RGB color.
# @param R2 G2 B2 The ending RGB color.
# @return
#   Prints the text with a horizontal gradient applied.
# @example_output
#   For __line_gradient__ "Hello" 255 0 0 0 0 255,
#   the output is "Hello" printed with a gradient transitioning from red to blue.
__line_gradient__() {
  local text="$1"
  local R1="$2"
  local G1="$3"
  local B1="$4"
  local R2="$5"
  local G2="$6"
  local B2="$7"

  local length=${#text}

  # If empty or a single character, just print in end color
  if (( length <= 1 )); then
    echo -e "\033[38;2;${R2};${G2};${B2}m${text}${RESET}"
    return
  fi

  for (( i=0; i<length; i++ )); do
    local fraction=$(( i * 100 / (length - 1) ))
    local R=$(__int_lerp__ "$R1" "$R2" "$fraction")
    local G=$(__int_lerp__ "$G1" "$G2" "$fraction")
    local B=$(__int_lerp__ "$B1" "$B2" "$fraction")

    # Extract single character
    local c="${text:$i:1}"
    echo -en "\033[38;2;${R};${G};${B}m${c}"
  done

  # Newline + reset
  echo -e "${RESET}"
}

# --- __line_rgb__ ------------------------------------------------------------
# @function __line_rgb__
# @description Prints a line of text in a single, solid RGB color.
# @usage
#   __line_rgb__ "text" R G B
# @param text The text to print.
# @param R G B The RGB color values.
# @return
#   Prints the text in the specified color.
# @example_output
#   For __line_rgb__ "Static Text" 0 255 0,
#   the output is "Static Text" printed in bright green.
__line_rgb__() {
  local text="$1"
  local R="$2"
  local G="$3"
  local B="$4"

  echo -e "\033[38;2;${R};${G};${B}m${text}${RESET}"
}

# --- __simulate_blink_async__ ------------------------------------------------
# @function __simulate_blink_async__
# @description Simulates a blinking effect by toggling between bright and dim text asynchronously.
#   Runs in a background subshell, allowing the main script to continue.
# @usage
#   __simulate_blink_async__ "text to blink" [times] [delay]
# @param text The text to blink.
# @param times (Optional) Number of blink cycles (default: 5).
# @param delay (Optional) Delay between toggles in seconds (default: 0.3).
# @return
#   Prints the blinking text effect asynchronously.
# @example_output
#   For __simulate_blink_async__ "Blinking" 5 0.3,
#   the output is "Blinking" toggling between bright and dim (observed asynchronously).
__simulate_blink_async__() {
    local text="$1"
    local times="${2:-5}"
    local delay="${3:-0.3}"

    local BRIGHT="\033[1m"
    local DIM="\033[2m"

    (
        # Save cursor position to overwrite the same spot
        tput sc

        for ((i = 0; i < times; i++)); do
            # Print bright
            echo -en "${BRIGHT}${text}${RESET}"
            sleep "$delay"
            # Restore cursor, print dim
            tput rc
            echo -en "${DIM}${text}${RESET}"
            sleep "$delay"
            # Restore again
            tput rc
        done

        # Leave it normal, then newline
        echo -e "${RESET}${text}"
    ) &
}
