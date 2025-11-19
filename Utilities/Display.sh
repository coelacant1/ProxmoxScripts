#!/bin/bash
#
# Display.sh
#
# Display utility functions for GUI applications
# Provides ASCII art management, path formatting, and UI helpers
#
# Functions:
#   __show_ascii_art__       - Display adaptive ASCII art based on terminal width
#   __display_path__         - Format paths for display with custom prefix
#   __show_script_info__     - Display script documentation header
#
# Function Index:
#   - __get_large_ascii__
#   - __get_small_ascii__
#   - __get_basic_ascii__
#   - __show_ascii_art__
#   - __display_path__
#   - __show_script_info__
#   - __show_error__
#   - __pause__
#   - __readline_input__
#

###############################################################################
# ASCII ART DEFINITIONS
###############################################################################

__get_large_ascii__() {
    cat <<'EOF'
-----------------------------------------------------------------------------------------

    ██████╗ ██████╗ ███████╗██╗      █████╗      ██████╗ █████╗ ███╗   ██╗████████╗██╗
   ██╔════╝██╔═══██╗██╔════╝██║     ██╔══██╗    ██╔════╝██╔══██╗████╗  ██║╚══██╔══╝██║
   ██║     ██║   ██║█████╗  ██║     ███████║    ██║     ███████║██╔██╗ ██║   ██║   ██║
   ██║     ██║   ██║██╔══╝  ██║     ██╔══██║    ██║     ██╔══██║██║╚██╗██║   ██║   ╚═╝
   ╚██████╗╚██████╔╝███████╗███████╗██║  ██║    ╚██████╗██║  ██║██║ ╚████║   ██║   ██╗
    ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝     ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝

    ██████╗ ██╗   ██║███████╗    ███████╗ ██████╗██████╗ ██║██████╗ ████████╗███████╗
    ██╔══██╗██║   ██║██╔════╝    ██╔════╝██╔════╝██╔══██╗██║██╔══██╗╚══██╔══╝██╔════╝
    ██████╔╝██║   ██║█████╗      ███████╗██║     ██████╔╝██║██████╔╝   ██║   ███████╗
    ██╔═══╝ ╚██╗ ██╔╝██╔══╝      ╚════██║██║     ██╔══██╗██║██╔═══╝    ██║   ╚════██║
    ██║      ╚████╔╝ ███████╗    ███████║╚██████╗██║  ██║██║██║        ██║   ███████║
    ╚═╝       ╚═══╝  ╚══════╝    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   ╚══════╝

-----------------------------------------------------------------------------------------
   User Interface for ProxmoxScripts
   Author: Coela Can't! (coelacant1)
-----------------------------------------------------------------------------------------
EOF
}

__get_small_ascii__() {
    cat <<'EOF'
--------------------------------------------
 █▀▀ █▀█ █▀▀ █   █▀█    █▀▀ █▀█ █▀█ ▀ ▀█▀ █
 █   █ █ █▀▀ █   █▀█    █   █▀█ █ █    █  ▀
 ▀▀▀ ▀▀▀ ▀▀▀ ▀▀▀ ▀ ▀    ▀▀▀ ▀ ▀ ▀ ▀    ▀  ▀

 █▀█ █ █ █▀▀    █▀▀ █▀▀ █▀▄ ▀█▀ █▀█ ▀█▀ █▀▀
 █▀▀ ▀▄▀ █▀▀    ▀▀█ █   █▀▄  █  █▀▀  █  ▀▀█
 ▀    ▀  ▀▀▀    ▀▀▀ ▀▀▀ ▀ ▀ ▀▀▀ ▀    ▀  ▀▀▀
--------------------------------------------
  ProxmoxScripts UI
  Author: Coela Can't! (coelacant1)
--------------------------------------------
EOF
}

__get_basic_ascii__() {
    cat <<'EOF'
----------------------------------------
 █▀▀ █▀▀ █▀█ █ █ █▀▀
 █   █   █▀▀ ▀▄▀ █▀▀
 ▀▀▀ ▀▀▀ ▀    ▀  ▀▀▀
----------------------------------------
EOF
}

###############################################################################
# DISPLAY FUNCTIONS
###############################################################################

__show_ascii_art__() {
    local mode="${1:-basic}" # basic, small, large, auto
    local width
    width=$(tput cols 2>/dev/null || echo 80)

    local LARGE_LENGTH=89
    local SMALL_LENGTH=44

    case "$mode" in
        basic)
            __get_basic_ascii__
            ;;
        small)
            if command -v __gradient_print__ &>/dev/null; then
                __gradient_print__ "$(__get_small_ascii__)" 128 0 128 0 255 255
            else
                __get_small_ascii__
            fi
            ;;
        large)
            if command -v __gradient_print__ &>/dev/null; then
                __gradient_print__ "$(__get_large_ascii__)" 128 0 128 0 255 255 "█"
            else
                __get_large_ascii__
            fi
            ;;
        auto)
            if ((LARGE_LENGTH <= width)); then
                __show_ascii_art__ large
            elif ((SMALL_LENGTH <= width)); then
                __show_ascii_art__ small
            else
                __show_ascii_art__ basic
            fi
            ;;
        *)
            __get_basic_ascii__
            ;;
    esac
}

__display_path__() {
    local fullpath="$1"
    local base_dir="${2:-.}"
    local prefix="${3:-cc_pve}"

    local relative="${fullpath#$base_dir}"
    relative="${relative#/}"

    if [[ -z "$relative" ]]; then
        echo "$prefix"
    else
        echo "$prefix/$relative"
    fi
}

__show_script_info__() {
    local script_path="$1"
    local display_path="${2:-$script_path}"

    if [[ ! -f "$script_path" ]]; then
        echo "Error: Script not found: $script_path"
        return 1
    fi

    __line_rgb__ "--- Top Comments ---" 255 200 0 2>/dev/null || echo "--- Top Comments ---"
    echo

    local in_header=true
    while IFS= read -r line; do
        if [[ "$line" =~ ^#!/ ]]; then
            continue
        fi

        if [[ "$line" =~ ^#(.*)$ ]]; then
            local content="${BASH_REMATCH[1]}"
            content="${content# }"
            echo "$content"
        elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        else
            break
        fi
    done <"$script_path"

    echo
    __line_rgb__ "--- Example Invocations ---" 255 200 0 2>/dev/null || echo "--- Example Invocations ---"
    echo

    if grep -q "^# Example:" "$script_path"; then
        grep "^# Example:" "$script_path" | sed 's/^# Example: //'
    else
        echo "(none)"
    fi

    echo
}

###############################################################################
# ERROR DISPLAY
###############################################################################

__show_error__() {
    local line_num="${1:-unknown}"
    local bash_command="${2:-unknown}"
    local exit_code="${3:-1}"
    local script_name="${4:-${BASH_SOURCE[1]##*/}}"

    echo
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                      ERROR DETECTED                            ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo
    echo "Script: $script_name"
    echo "Line: $line_num"
    echo "Command: $bash_command"
    echo "Exit Code: $exit_code"
    echo

    if [[ "${SHOW_STACK_TRACE:-true}" == "true" ]]; then
        echo "Call Stack:"
        local i=1
        while caller $i 2>/dev/null; do
            ((i += 1))
        done
        echo
    fi
}

###############################################################################
# INTERACTIVE HELPERS
###############################################################################

__pause__() {
    local message="${1:-Press Enter to continue.}"

    if command -v __line_rgb__ &>/dev/null; then
        __line_rgb__ "$message" 0 255 255
    else
        echo "$message"
    fi

    read -r
}

__readline_input__() {
    local prompt="$1"
    local default="${2:-}"
    local result

    if [[ -n "$default" ]]; then
        read -e -i "$default" -p "$prompt" result
    else
        read -e -p "$prompt" result
    fi

    echo "$result"
}
