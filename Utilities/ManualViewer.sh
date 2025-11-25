#!/bin/bash
#
# ManualViewer.sh
#
# Utility for viewing ProxmoxScripts manuals in the terminal
# with clean formatting and pagination.
#
# Usage:
#   source "${UTILITYPATH}/ManualViewer.sh"
#   __show_manual__ "getting-started"
#   __list_manuals__
#   __manual_menu__
#
# Function Index:
#   - get_manual_dir
#   - __list_manuals__
#   - __show_manual__
#   - __manual_menu__
#   - __quick_help__
#

# Get manual directory path
get_manual_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    echo "${script_dir}/Manuals"
}

# List available manuals
__list_manuals__() {
    local manual_dir
    manual_dir="$(get_manual_dir)"

    if [[ ! -d "$manual_dir" ]]; then
        echo "Manual directory not found: $manual_dir" >&2
        return 1
    fi

    local manuals
    mapfile -t manuals < <(find "$manual_dir" -name "*.txt" -type f | sort)

    if [[ ${#manuals[@]} -eq 0 ]]; then
        echo "No manuals found in $manual_dir" >&2
        return 1
    fi

    for manual in "${manuals[@]}"; do
        basename "$manual" .txt
    done
}

# Show a specific manual
__show_manual__() {
    local manual_name="$1"
    local manual_dir
    manual_dir="$(get_manual_dir)"

    # Add .txt if not present
    if [[ ! "$manual_name" =~ \.txt$ ]]; then
        manual_name="${manual_name}.txt"
    fi

    local manual_path="${manual_dir}/${manual_name}"

    if [[ ! -f "$manual_path" ]]; then
        echo "Manual not found: $manual_name" >&2
        echo "Available manuals:" >&2
        __list_manuals__ >&2
        return 1
    fi

    # Use less with appropriate options for clean viewing
    if command -v less &>/dev/null; then
        # -R: raw control chars (for colors if any)
        # -X: don't clear screen on exit
        # -F: quit if one screen
        # -S: chop long lines
        less -R -X -F "$manual_path"
    else
        # Fallback to cat
        cat "$manual_path"
        echo ""
        read -r -p "Press Enter to continue..."
    fi
}

# Interactive manual menu
__manual_menu__() {
    local manual_dir
    manual_dir="$(get_manual_dir)"

    # Check if we have an interactive terminal
    if [[ ! -t 0 ]]; then
        echo "Error: Manual menu requires an interactive terminal" >&2
        return 1
    fi

    # Check if manual directory exists
    if [[ ! -d "$manual_dir" ]]; then
        clear
        echo "========================================"
        echo "   PROXMOXSCRIPTS MANUAL SYSTEM"
        echo "========================================"
        echo ""
        echo "ERROR: Manual directory not found!"
        echo "Expected location: $manual_dir"
        echo ""
        echo "Please ensure you're running GUI.sh from the"
        echo "ProxmoxScripts repository root directory."
        echo ""
        read -r -p "Press Enter to continue..."
        return 1
    fi

    while true; do
        clear

        # Show ASCII art header if available
        if declare -f show_ascii_art >/dev/null 2>&1; then
            show_ascii_art
        fi

        echo "Available Manuals:"
        echo "----------------------------------------"

        local manuals
        mapfile -t manuals < <(find "$manual_dir" -maxdepth 1 -name "*.txt" -type f 2>/dev/null | sort)

        # Debug: Show what we found
        if [[ ${#manuals[@]} -eq 0 ]]; then
            echo "No manuals found!"
            echo ""
            echo "Manual directory: $manual_dir"
            echo "Directory exists: $([ -d "$manual_dir" ] && echo "yes" || echo "no")"
            echo "PWD: $(pwd)"
            echo ""
            echo "Searching for: *.txt files in $manual_dir"
            echo ""
            echo "Contents of manual directory:"
            find "$manual_dir" -maxdepth 1 -type f -printf "%p\n" 2>&1 | head -10
            echo ""
            read -r -p "Press Enter to continue..." || return 1
            return 1
        fi

        local i=1
        declare -A manual_map
        for manual in "${manuals[@]}"; do
            local name description
            name=$(basename "$manual" .txt)

            # Try to extract description from manual (first non-empty, non-header line)
            # Use || true to prevent pipefail from exiting on grep failures
            description=$(grep -v "^====" "$manual" 2>/dev/null | grep -v "^----" | grep -v "^$" | head -1 | sed 's/^[[:space:]]*//' || true)

            if [[ -z "$description" ]]; then
                description="(no description)"
            fi

            # Truncate description if too long
            if [[ ${#description} -gt 50 ]]; then
                description="${description:0:47}..."
            fi

            # Use color styling if available
            if declare -f __line_rgb__ >/dev/null 2>&1; then
                __line_rgb__ "$(printf "%d) %-25s %s" "$i" "$name" "$description")" 0 200 200
            else
                printf "  %2d) %-25s %s\n" "$i" "$name" "$description"
            fi
            manual_map[$i]="$manual"
            ((i += 1))
        done

        echo ""
        echo "----------------------------------------"
        echo ""
        echo "Enter manual number to view, or:"
        echo "  'b' to go back"
        echo "  'e' to exit"
        echo ""
        echo "----------------------------------------"
        read -rp "Choice: " choice || return 1

        case "$choice" in
            b | B)
                return 0
                ;;
            e | E)
                return 1
                ;;
            '' | *[!0-9]*)
                echo "Invalid choice!"
                sleep 1
                ;;
            *)
                if [[ -n "${manual_map[$choice]:-}" ]]; then
                    __show_manual__ "$(basename "${manual_map[$choice]}")"
                else
                    echo "Invalid manual number!"
                    sleep 1
                fi
                ;;
        esac
    done
}

# Quick help - show getting-started manual
__quick_help__() {
    __show_manual__ "getting-started"
}

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Validation against CONTRIBUTING.md and fixed ShellCheck warnings
# - Initial creation: Manual viewer utility for Manuals/ directory
#
# Fixes:
# - 2025-11-24: Fixed SC2162 warnings by adding -r flag to all read commands
# - 2025-11-24: Fixed SC2012 by replacing ls with find for file listing
#
# Known issues:
# -
#

