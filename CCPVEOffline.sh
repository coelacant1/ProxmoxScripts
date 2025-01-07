#!/bin/bash
#
# CCPVEOffline.sh
#
# A menu-driven Bash script to navigate and run .sh files in the current folder (and subfolders).
# This version assumes everything is already extracted/unzipped in this directory—no download or unzip needed.
#
# Usage:
#   1) cd into the directory containing your .sh files (and this script).
#   2) chmod +x MakeScriptsExecutable.sh
#   3) ./MakeScriptsExecutable.sh
#   4) ./CCPVEOffline.sh
#
# Author: Coela Can't! (coelacant1)
# Repo: https://github.com/coelacant1/ProxmoxScripts (for reference)
#

###############################################################################
# CONFIG
###############################################################################

BASE_DIR="$(pwd)"          # We assume the script is run from the unzipped directory
DISPLAY_PREFIX="cc_pve"    # How we display the "root" in the UI
HELP_FLAG="--help"         # If your scripts support a help flag, we pass this
LAST_SCRIPT=""             # The last script run
LAST_OUTPUT=""             # Truncated output of the last script

###############################################################################
# OPTIONAL ASCII ART HEADER
###############################################################################

show_ascii_art() {
    echo "-----------------------------------------------------------------------------------------"
    echo "                                                                                         "
    echo "    ██████╗ ██████╗ ███████╗██╗      █████╗      ██████╗ █████╗ ███╗   ██╗████████╗██╗   "
    echo "   ██╔════╝██╔═══██╗██╔════╝██║     ██╔══██╗    ██╔════╝██╔══██╗████╗  ██║╚══██╔══╝██║   "
    echo "   ██║     ██║   ██║█████╗  ██║     ███████║    ██║     ███████║██╔██╗ ██║   ██║   ██║   "
    echo "   ██║     ██║   ██║██╔══╝  ██║     ██╔══██║    ██║     ██╔══██║██║╚██╗██║   ██║   ╚═╝   "
    echo "   ╚██████╗╚██████╔╝███████╗███████╗██║  ██║    ╚██████╗██║  ██║██║ ╚████║   ██║   ██╗   "
    echo "    ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝     ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝   "
    echo "                                                                                         "
    echo "    ██████╗ ██╗   ██║███████╗    ███████╗ ██████╗██████╗ ██║██████╗ ████████╗███████╗    "
    echo "    ██╔══██╗██║   ██║██╔════╝    ██╔════╝██╔════╝██╔══██╗██║██╔══██╗╚══██╔══╝██╔════╝    "
    echo "    ██████╔╝██║   ██║█████╗      ███████╗██║     ██████╔╝██║██████╔╝   ██║   ███████╗    "
    echo "    ██╔═══╝ ╚██╗ ██╔╝██╔══╝      ╚════██║██║     ██╔══██╗██║██╔═══╝    ██║   ╚════██║    "
    echo "    ██║      ╚████╔╝ ███████╗    ███████║╚██████╗██║  ██║██║██║        ██║   ███████║    "
    echo "    ╚═╝       ╚═══╝  ╚══════╝    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   ╚══════╝    "
    echo "                                                                                         "
    echo "-----------------------------------------------------------------------------------------"
    echo "   User Interface for ProxmoxScripts                                                     "
    echo "   Author: Coela Can't! (coelacant1)                                                     "
    echo "-----------------------------------------------------------------------------------------"
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

    echo "=== Top Comments for: $(display_path "$script_path") ==="
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
            echo "$line"
            printing=true
        else
            if [ "$printing" = true ]; then
                break
            fi
        fi
    done <"$script_path"

    echo
    echo "Press Enter to continue."
    read -r
}

# Attempt to find a line like '# ./something.sh ...' in the top comments
extract_dot_slash_help_line() {
    local script_path="$1"
    local found_line=""

    while IFS= read -r line; do
        # Stop if we've hit a non-# line
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
    echo "=== Showing usage for: $(display_path "$script_path") ==="
    if [ -x "$script_path" ]; then
        "$script_path" "$HELP_FLAG" 2>&1 || true
    else
        bash "$script_path" "$HELP_FLAG" 2>&1 || true
    fi
    echo
    echo "Press Enter to continue."
    read -r
}

# Display path relative to BASE_DIR, prefixed with DISPLAY_PREFIX
display_path() {
    local fullpath="$1"
    local relative="${fullpath#$BASE_DIR}"
    relative="${relative#/}"   # remove leading slash if present

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
    clear
    show_ascii_art

    local ds_line
    ds_line=$(extract_dot_slash_help_line "$script_path")

    clear
    show_ascii_art
    if [ -n "$ds_line" ]; then
        echo "Example usage (from script comments):"
        echo "  $ds_line"
        echo
    else
        show_top_comments "$script_path"
        echo
    fi

    echo "=== Enter parameters for $(display_path "$script_path") (type 'c' to cancel or leave empty to run no-args):"
    read -r param_line

    if [ "$param_line" = "c" ]; then
        return
    fi

    echo
    echo "=== Running: $(display_path "$script_path") $param_line ==="

    IFS=' ' read -r -a param_array <<<"$param_line"

    # Capture script output in an array, to truncate if needed
    declare -a output_lines
    if [ -x "$script_path" ]; then
        mapfile -t output_lines < <("$script_path" "${param_array[@]}")
    else
        mapfile -t output_lines < <(bash "$script_path" "${param_array[@]}")
    fi

    LAST_SCRIPT="$(display_path "$script_path")"

    # Build truncated output: first 3 lines, then '...', then last 9 lines
    local total_lines="${#output_lines[@]}"
    if (( total_lines <= 12 )); then
        # No need to truncate
        LAST_OUTPUT="$(printf '%s\n' "${output_lines[@]}")"
    else
        # Show first 3 lines, then '...', then last 9 lines
        local truncated_output=""
        for (( i=0; i<3; i++ )); do
            truncated_output+="${output_lines[$i]}\n"
        done
        truncated_output+="...\n"
        local start_index=$(( total_lines - 9 ))
        for (( i=start_index; i<total_lines; i++ )); do
            truncated_output+="${output_lines[$i]}\n"
        done
        LAST_OUTPUT="$truncated_output"
    fi

    # Print the truncated output to the screen
    echo -e "$LAST_OUTPUT"
    echo
    echo "Press Enter to continue."
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
        echo "CURRENT DIRECTORY: $(display_path "$current_dir")"
        echo
        echo "Folders and scripts:"
        echo "--------------------"

        # Gather subdirectories and .sh scripts
        mapfile -t dirs < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type d ! -name ".*" | sort)
        mapfile -t scripts < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type f -name "*.sh" ! -name ".*" | sort)

        local index=1
        declare -A menu_map=()

        # List directories
        for d in "${dirs[@]}"; do
            local dname
            dname="$(basename "$d")"
            echo "$index) $dname/"
            menu_map[$index]="$d"
            ((index++))
        done

        # List scripts
        for s in "${scripts[@]}"; do
            local sname
            sname="$(basename "$s")"
            echo "$index) $sname"
            menu_map[$index]="$s"
            ((index++))
        done

        echo
        echo "--------------------"
        echo
        echo "Type 'h<number>' to show top comments for a script."
        echo "Type 'b' to go up one directory."
        echo "Type 'e' to exit."
        echo
        echo "--------------------"

        # Show the last script's truncated output
        if [ -n "$LAST_OUTPUT" ]; then
            echo "Last Script Called: $LAST_SCRIPT"
            echo "Output (truncated if large):"
            echo "$LAST_OUTPUT"
            echo
            echo "--------------------"
        fi

        echo -n "Enter choice: "
        read -r choice

        # 'b' => go up
        if [[ "$choice" == "b" ]]; then
            if [ "$current_dir" = "$BASE_DIR" ]; then
                echo "Exiting..."
                exit 0
            else
                return
            fi
        fi

        # 'e' => exit
        if [[ "$choice" == "e" ]]; then
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

# Start navigation from the current directory
navigate "$BASE_DIR"
