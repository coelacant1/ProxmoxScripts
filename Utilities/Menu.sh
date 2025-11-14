#!/bin/bash
#
# Menu.sh
#
# Utilities for creating consistent menu interfaces
#
# Functions:
#   __menu_choice__       - Handle menu choice with common options
#   __menu_display__      - Display menu items in consistent format
#   __menu_header__       - Display menu header
#   __menu_footer__       - Display menu footer with common options
#

# Display menu header
# Args: title
__menu_header__() {
    local title="$1"
    echo "$title"
    echo "----------------------------------------"
}

# Display menu footer with common navigation options
# Args: show_help (true/false) show_back (true/false) show_exit (true/false)
__menu_footer__() {
    local show_help="${1:-true}"
    local show_back="${2:-true}"
    local show_exit="${3:-true}"
    
    echo
    echo "----------------------------------------"
    echo
    [[ "$show_help" == "true" ]] && echo "Type 'h' or '?' for help"
    [[ "$show_back" == "true" ]] && echo "Type 'b' to go back"
    [[ "$show_exit" == "true" ]] && echo "Type 'e' to exit"
    echo
    echo "----------------------------------------"
}

# Display menu items
# Args: item_type (numbered|lettered) items_array
__menu_display__() {
    local item_type="$1"
    shift
    local items=("$@")
    
    local i=1
    for item in "${items[@]}"; do
        if [[ "$item_type" == "numbered" ]]; then
            __line_rgb__ "$i) $item" 0 200 200
            ((i++))
        else
            # Handle custom formatting if needed
            echo "$item"
        fi
    done
}

# Handle common menu choice responses
# Args: choice
# Returns: 0 for handled choice (should continue), 1 for back, 2 for exit, 3 for help, 4 for unhandled (custom)
__menu_choice__() {
    local choice="$1"
    
    case "$choice" in
        h|\?)
            return 3  # Help
            ;;
        b|B)
            return 1  # Back
            ;;
        e|E)
            return 2  # Exit
            ;;
        *)
            return 4  # Unhandled - let caller handle it
            ;;
    esac
}
