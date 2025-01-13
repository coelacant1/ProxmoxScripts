#!/bin/bash
#
# GUI.sh
#
# A menu-driven Bash script to navigate and run .sh files in the current folder (and subfolders).
# This version assumes everything is already extracted/unzipped in this directory—no download or unzip needed.
#
# ./GUI.sh [-nh]
#
# Usage:
#   1) cd into the directory containing your .sh files (and this script).
#   2) chmod +x MakeScriptsExecutable.sh
#   3) ./MakeScriptsExecutable.sh
#   4) ./GUI.sh
#
# Author: Coela Can't! (coelacant1)
# Repo: https://github.com/coelacant1/ProxmoxScripts
#

set -e

###############################################################################
# CONFIG
###############################################################################

BASE_DIR="$(pwd)"       # We assume the script is run from the unzipped directory
DISPLAY_PREFIX="cc_pve" # How we display the "root" in the UI
HELP_FLAG="--help"      # If your scripts support a help flag, we pass this
LAST_SCRIPT=""          # The last script run
LAST_OUTPUT=""          # Truncated output of the last script
SHOW_HEADER="true"

###############################################################################
# IMPORT UTILITY FUNCTIONS FOR SCRIPTS AND COLOR GRADIENT LIBRARY
###############################################################################

source "./Utilities/Utilities.sh"
source "./Utilities/Colors.sh"

###############################################################################
# HEADER MANAGEMENT
###############################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -nh)
            SHOW_HEADER="false"
            shift
            ;;
        *)
            echo "Error: Unknown argument '$1'"
            exit 1
            ;;
    esac
done

###############################################################################
# ASCII ART HEADER
###############################################################################

# Original (large) ASCII art as a single multi-line string
LARGE_ASCII=$(cat <<'EOF'
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
)
LARGE_LENGTH=89

# A smaller ASCII/text fallback
SMALL_ASCII=$(cat <<'EOF'
--------------------------------------------
 █▀▀ █▀█ █▀▀ █   █▀█    █▀▀ █▀█ █▀█ ▀ ▀█▀ █ 
 █   █ █ █▀▀ █   █▀█    █   █▀█ █ █    █  ▀ 
 ▀▀▀ ▀▀▀ ▀▀▀ ▀▀▀ ▀ ▀    ▀▀▀ ▀ ▀ ▀ ▀    ▀  ▀ 
                                            
 █▀█ █ █ █▀▀    █▀▀ █▀▀ █▀▄ ▀█▀ █▀█ ▀█▀ █▀▀ 
 █▀▀ ▀▄▀ █▀▀    ▀▀█ █   █▀▄  █  █▀▀  █  ▀▀█ 
 ▀    ▀  ▀▀▀    ▀▀▀ ▀▀▀ ▀ ▀ ▀▀▀ ▀    ▀  ▀▀▀ 
--------------------------------------------
  ProxmoxScripts UI                         
  Author: Coela Can't! (coelacant1)         
--------------------------------------------
EOF
)
SMALL_LENGTH=44

BASIC_ASCII=$(cat <<'EOF'
----------------------------------------
 █▀▀ █▀▀ █▀█ █ █ █▀▀                    
 █   █   █▀▀ ▀▄▀ █▀▀                    
 ▀▀▀ ▀▀▀ ▀    ▀  ▀▀▀                    
----------------------------------------
EOF
)

show_ascii_art() {
    local width
    width=$(tput cols)

    # We'll pick a gradient from purple (128,0,128) to cyan (0,255,255)
    if [ "$SHOW_HEADER" != "true" ]; then
        echo "$BASIC_ASCII"
    elif ((LARGE_LENGTH <= width)); then
        gradient_print "$LARGE_ASCII" 128 0 128 0 255 255 "█"
    else
        gradient_print "$SMALL_ASCII" 128 0 128 0 255 255
    fi

    echo
}

###############################################################################
# UTILITY FUNCTIONS
###############################################################################

# Show the top commented lines from a .sh file, ignoring:
# - '#!/bin/bash'
# - lines that are only '#'
# until we reach a non-# line
show_top_comments() {
    local script_path="$1"
    clear
    show_ascii_art

    line_rgb "=== Top Comments for: $(display_path "$script_path") ===" 200 200 0
    echo

    local printing=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^#! ]] && [[ "$line" =~ "bash" ]]; then
            continue
        fi
        if [[ "$line" == "#" ]]; then
            continue
        fi
        if [[ "$line" =~ ^# ]]; then
            line_rgb "$line" 0 200 0
            printing=true
        else
            if [ "$printing" = true ]; then
                break
            fi
        fi
    done <"$script_path"

    echo
    line_rgb "Press Enter to continue." 0 255 255
    read -r
}

# Attempt to find a line like '# ./something.sh ...' in the top comments

extract_dot_slash_help_line() {
    local script_path="$1"
    local found_line=""
    while IFS= read -r line; do
        if [[ ! "$line" =~ ^# ]]; then
            break
        fi
        local stripped="${line#\#}"
        stripped="${stripped#"${stripped%%[![:space:]]*}"}"
        if [[ "$stripped" =~ ^\./ ]]; then
            found_line="$stripped"
            break
        fi
    done <"$script_path"
    echo "$found_line"
}

# If the script is executable with a '--help' usage, we can try to show that.
show_script_usage() {
    local script_path="$1"
    line_rgb "=== Showing usage for: $(display_path "$script_path") ===" 2000 200 0
    if [ -x "$script_path" ]; then
        "$script_path" "$HELP_FLAG" 2>&1 || true
    else
        bash "$script_path" "$HELP_FLAG" 2>&1 || true
    fi
    echo
    line_rgb "Press Enter to continue." 0 255 255
    read -r
}

# Display path relative to BASE_DIR, prefixed with DISPLAY_PREFIX
display_path() {
    local fullpath="$1"
    local relative="${fullpath#$BASE_DIR}"
    relative="${relative#/}" # remove leading slash if present

    if [ -z "$relative" ]; then
        echo "$DISPLAY_PREFIX"
    else
        echo "$DISPLAY_PREFIX/$relative"
    fi
}

###############################################################################
# SCRIPT RUNNER
###############################################################################
run_script() {
    local script_path="$1"
    local ds_line
    ds_line=$(extract_dot_slash_help_line "$script_path")

    clear
    show_ascii_art
    if [ -n "$ds_line" ]; then
        line_rgb "Example usage (from script comments):" 0 200 0
        echo "  $ds_line"
        echo
    else
        line_rgb show_top_comments "$script_path" 0 200 0
        echo
    fi

    line_rgb "=== Enter parameters for $(display_path "$script_path") (type 'c' to cancel or leave empty to run no-args):" 200 200 0
    read -r param_line

    if [ "$param_line" = "c" ]; then
        return
    fi

    echo
    line_rgb "=== Running: $(display_path "$script_path") $param_line ===" 200 200 0

    IFS=' ' read -r -a param_array <<<"$param_line"
    param_line=$(echo "$param_line" | tr -d '\r')

    mkdir -p .log
    touch .log/out.log

    export UTILITIES="$(realpath ./Utilities/Utilities.sh)"

    escaped_args=()
    for arg in "${param_array[@]}"; do
        escaped_args+=("$(printf '%q' "$arg")")
    done
    cmd_string="$(printf '%s ' "${escaped_args[@]}")"
    cmd_string="${script_path} ${cmd_string}"

    script -q -c "$cmd_string" .log/out.log

    declare -a output_lines
    mapfile -t output_lines < <(sed '/^Script started on /d; /^Script done on /d' .log/out.log)
    rm .log/out.log

    LAST_SCRIPT="$(display_path "$script_path")"

    local total_lines="${#output_lines[@]}"
    if ((total_lines <= 12)); then
        LAST_OUTPUT="$(printf '%s\n' "${output_lines[@]}")"
    else
        local truncated_output=""
        for ((i = 0; i < 3; i++)); do
            truncated_output+="${output_lines[$i]}"
            truncated_output+=$'\n'
        done
        truncated_output+="...\n"
        local start_index=$((total_lines - 9))
        for ((i = start_index; i < total_lines; i++)); do
            truncated_output+="${output_lines[$i]}"
            truncated_output+=$'\n'
        done
        LAST_OUTPUT="$truncated_output"
    fi

    echo
    line_rgb "Press Enter to continue." 0 255 0
    read -r
}

###############################################################################
# DIRECTORY NAVIGATOR
###############################################################################
navigate() {
    local current_dir="$1"

    while true; do
        clear
        show_ascii_art
        echo -n "CURRENT DIRECTORY: "
        line_rgb "./$(display_path "$current_dir")" 0 255 0
        echo
        echo "Folders and scripts:"
        echo "----------------------------------------"

        mapfile -t dirs < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type d ! -name ".*" | sort)
        mapfile -t scripts < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type f -name "*.sh" ! -name ".*" | sort)

        local index=1
        declare -A menu_map=()

        # List directories
        for d in "${dirs[@]}"; do
            local dname="$(basename "$d")"
            line_rgb "$index) $dname/" 0 200 200
            menu_map[$index]="$d"
            ((index++))
        done

        # List scripts
        for s in "${scripts[@]}"; do
            local sname
            sname="$(basename "$s")"
            line_rgb "$index) $sname" 100 200 100
            menu_map[$index]="$s"
            ((index++))
        done

        echo
        echo "----------------------------------------"
        echo
        echo "Type 'h<number>' to show script comments."
        echo "Type 'b' to go up one directory."
        echo "Type 'e' to exit."
        echo
        echo "----------------------------------------"

        if [ -n "$LAST_OUTPUT" ]; then
            echo "Last Script Called: $LAST_SCRIPT"
            echo "Output (truncated if large):"
            echo "$LAST_OUTPUT"
            echo
            echo "----------------------------------------"
        fi

        
        echo -n "Enter choice: "

        IFS= read -r choice

        # 'b' => go up
        if [[ "$choice" == "b" ]]; then
            if [ "$current_dir" = "$BASE_DIR" ]; then
                line_rgb "Exiting..." 255 0 0
                exit 0
            else
                echo "Going up..."
                return
            fi
        fi

        # 'e' => exit
        if [[ "$choice" == "e" ]]; then
            line_rgb "Exiting..." 255 0 0
            exit 0
        fi

        # 'hN' => show top comments
        if [[ "$choice" =~ ^h[0-9]+$ ]]; then
            local num="${choice#h}"
            if [ -n "${menu_map[$num]}" ]; then
                local selected_path="${menu_map[$num]}"
                if [ -d "$selected_path" ]; then
                    echo "Can't show top comments for a directory. Press Enter to continue."
                    read -r
                else
                    show_top_comments "$selected_path"
                fi
            else
                echo "Invalid selection. Press Enter to continue."
                read -r
            fi
            continue
        fi

        # Numeric => either a directory or a script
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ -z "${menu_map[$choice]}" ]; then
                echo "Invalid numeric choice. Press Enter to continue."
                read -r
                continue
            fi
            local selected_item="${menu_map[$choice]}"

            if [ -d "$selected_item" ]; then
                navigate "$selected_item"
            else
                run_script "$selected_item"
            fi
            continue
        fi

        echo "Invalid input. Press Enter to continue."
        read -r
    done
}

###############################################################################
# MAIN
###############################################################################

./MakeScriptsExecutable.sh
navigate "$BASE_DIR"
