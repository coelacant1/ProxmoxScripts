#!/bin/bash
#
# BatchRunCLI.sh
#
# Interactive or non-interactive bulk runner for CCPVE CLI mode across a VMID range.
# Lets you browse repository folders (similar to GUI.sh), preview script headers and
# example invocations, then execute the selected script on a contiguous set of guests
# via the CCPVE one-liner.
#
# Usage:
#   ./BatchRunCLI.sh --start <vmid> --end <vmid> --ssh-user <user> --ssh-pass <pass> \
#     --run Host/QuickDiagnostic.sh [--args "arg1 arg2"]
#   ./BatchRunCLI.sh --start 300 --end 305 --ssh-user root --ssh-pass secret
#
# Function Index:
#   - usage
#   - parse_args
#   - ensure_dependencies
#   - gather_interactive_inputs
#   - show_header_block
#   - extract_example_lines
#   - choose_script_via_navigation
#   - build_remote_script_command
#   - wrap_remote_command
#   - execute_for_vmid
#   - run_bulk
#   - cleanup
#   - main
#

set -u

SCRIPT_ROOT="$(pwd)"
SHORT_URL="pve.coela.sh"

START_VMID=""
END_VMID=""
SSH_USER=""
SSH_PASS=""
RUN_SCRIPT=""
RUN_ARGS=""
EXEC_COMMAND=""
INTERACTIVE="false"

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"
# shellcheck source=Utilities/SSH.sh
source "${UTILITYPATH}/SSH.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
trap 'cleanup' EXIT

usage() {
    cat <<EOF
BatchRunCLI.sh

Bulk run CCPVE direct CLI mode across a contiguous VMID range.

Required:
  --start <vmid>         Starting VMID (inclusive)
  --end <vmid>           Ending VMID (inclusive)
  --ssh-user <user>      SSH username on guests
  --ssh-pass <pass>      SSH password on guests
  --run <scriptPath>     Relative script path (non-interactive mode)

Optional:
  --args "arg1 arg2"     Arguments passed verbatim to the target script
  -h/--help              Show this help and exit

Interactive Mode (omit --run):
  1) Collect credentials and VMID range
  2) Navigate repository tree (numbers for items, b=up, q=quit, hN=header preview)
  3) Preview script header and sample invocations
  4) Provide optional arguments
  5) Execute remotely via CCPVE one-liner

Examples:
  $0 --start 100 --end 103 --ssh-user root --ssh-pass secret \
     --run Host/QuickDiagnostic.sh
  $0 --start 200 --end 205 --ssh-user root --ssh-pass secret \
     --run Storage/Benchmark.sh --args "--device /dev/sdb --mode quick"
  $0 --start 300 --end 305 --ssh-user root --ssh-pass secret   # interactive
EOF
}

parse_args() {
    if [[ $# -eq 0 ]]; then
    --run <scriptPath>     Relative script path (non-interactive mode)
    --exec "command"       Run an arbitrary shell command on each guest (non-interactive)
        exit 64
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --start) START_VMID="$2"; shift 2 ;;
            --end) END_VMID="$2"; shift 2 ;;
            --ssh-user) SSH_USER="$2"; shift 2 ;;
            --ssh-pass) SSH_PASS="$2"; shift 2 ;;
            --run) RUN_SCRIPT="$2"; shift 2 ;;
            --args) RUN_ARGS="$2"; shift 2 ;;
            --exec) EXEC_COMMAND="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) __err__ "Unknown argument: $1"; usage; exit 64 ;;
        esac
    done

    if [[ -n "$RUN_SCRIPT" && -n "$EXEC_COMMAND" ]]; then
        __err__ "--run and --exec cannot be used together."
        exit 64
    fi

    if [[ -n "$EXEC_COMMAND" && -n "$RUN_ARGS" ]]; then
        __err__ "--args cannot be combined with --exec."
        exit 64
    fi

    if [[ -z "$RUN_SCRIPT" && -z "$EXEC_COMMAND" ]]; then
        INTERACTIVE="true"
    fi
}

ensure_dependencies() {
    __ensure_dependencies__ sshpass
}

gather_interactive_inputs() {
    __info__ "Entering interactive mode (no --run provided)."

    if [[ -z "$START_VMID" ]]; then
        read -r -p "Start VMID: " START_VMID
    fi
    if [[ -z "$END_VMID" ]]; then
        read -r -p "End VMID: " END_VMID
    fi
    if [[ -z "$SSH_USER" ]]; then
        read -r -p "SSH username: " SSH_USER
    fi
    if [[ -z "$SSH_PASS" ]]; then
        read -r -s -p "SSH password for ${SSH_USER}: " SSH_PASS
        echo
    fi

    choose_script_via_navigation || {
        __err__ "No script selected; aborting."
        exit 1
    }

    read -r -p "Optional arguments for ${RUN_SCRIPT} (leave blank for none): " RUN_ARGS
}

show_header_block() {
    local file_path="$1"
    local printing=false

    while IFS= read -r line; do
        [[ $line =~ ^#!/bin/bash$ ]] && continue
        if [[ $line == "#" ]]; then
            continue
        fi
        if [[ $line =~ ^# ]]; then
            echo "${line#\# }"
            printing=true
        else
            [[ $printing == true ]] && break
        fi
    done <"$file_path"
}

extract_example_lines() {
    local file_path="$1"
    grep -E '^# *\./' "$file_path" | sed -E 's/^# *//'
}

choose_script_via_navigation() {
    local current_dir="$SCRIPT_ROOT"

    while true; do
        echo
        __info__ "Current directory: ${current_dir#$SCRIPT_ROOT/}"
        echo "--------------------------------------------------"

        mapfile -t DIRS < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type d ! -name 'Utilities' ! -name '.*' | sort)
        mapfile -t SCRIPTS < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type f -name '*.sh' \
            ! -path '*/Utilities/*' ! -name 'CCPVE.sh' ! -name 'GUI.sh' ! -name 'MakeScriptsExecutable.sh' | sort)

        local index=1
        local -A choices=()

        for dir_path in "${DIRS[@]}"; do
            printf "%2d) %s/\n" "$index" "$(basename "$dir_path")"
            choices[$index]="DIR::$dir_path"
            ((index++))
        done

        for script_path in "${SCRIPTS[@]}"; do
            printf "%2d) %s\n" "$index" "$(basename "$script_path")"
            choices[$index]="SCR::$script_path"
            ((index++))
        done

        echo " hN) Show header for item N"
        echo " b) Up directory          q) Quit selection"
        echo "--------------------------------------------------"

        read -r -p "Select script or folder: " choice

        case "$choice" in
            q)
                return 1 ;;
            b)
                if [[ "$current_dir" == "$SCRIPT_ROOT" ]]; then
                    __info__ "Already at repository root."
                else
                    current_dir="$(dirname "$current_dir")"
                fi
                ;;
            h[0-9]*)
                local num="${choice#h}"
                local entry="${choices[$num]:-}"
                if [[ -z "$entry" ]]; then
                    __err__ "Invalid item number."; continue
                fi
                if [[ ${entry%%::*} == SCR ]]; then
                    local file="${entry#*::}"
                    echo "--- HEADER: $(basename "$file") ---"
                    show_header_block "$file"
                    echo "--- Example Invocations ---"
                    extract_example_lines "$file" || true
                    echo "-----------------------------"
                else
                    __info__ "Directories do not have headers."
                fi
                ;;
            ''|*[!0-9]*)
                __err__ "Invalid selection." ;;
            *)
                if [[ -z "${choices[$choice]:-}" ]]; then
                    __err__ "Selection out of range."; continue
                fi
                local entry="${choices[$choice]}"
                local type="${entry%%::*}"
                local path="${entry#*::}"
                if [[ "$type" == DIR ]]; then
                    current_dir="$path"
                    continue
                fi
                RUN_SCRIPT="${path#$SCRIPT_ROOT/}"
                local local_full="$path"
                echo
                __info__ "Selected script: ${RUN_SCRIPT}"
                echo "--- Top Comments ---"
                show_header_block "$local_full" || true
                echo "--- Example Invocations ---"
                extract_example_lines "$local_full" || echo "(none)"
                return 0
                ;;
        esac
    done
}

build_remote_script_command() {
    local script_path="$1"
    local args="$2"
    local base

    base=$(printf 'bash <(curl -fsSL %s) --run %q' "$SHORT_URL" "$script_path")

    if [[ -n "$args" ]]; then
        printf '%s --args %q' "$base" "$args"
    else
        printf '%s' "$base"
    fi
}

wrap_remote_command() {
    local raw="$1"
    printf 'bash -lc %q' "$raw"
}

execute_for_vmid() {
    local vmid="$1"
    local ip

    __update__ "Processing VMID ${vmid}"

    if ! ip=$( __get_ip_from_vmid__ "$vmid" ); then
        __err__ "VMID ${vmid}: unable to resolve IP; skipping."
        return
    fi
    __info__ "VMID ${vmid}: IP ${ip}"

    if ! __wait_for_ssh__ "$ip" "$SSH_USER" "$SSH_PASS"; then
        __err__ "VMID ${vmid}: SSH unreachable; skipping."
        return
    fi

    local remote_line
    if [[ -n "$EXEC_COMMAND" ]]; then
        remote_line="set -e; ${EXEC_COMMAND}"
    else
        remote_line="$(build_remote_script_command "$RUN_SCRIPT" "$RUN_ARGS")"
    fi

    local remote_cmd
    remote_cmd="$(wrap_remote_command "$remote_line")"

    if ! __ssh_exec__ --host "$ip" --user "$SSH_USER" --password "$SSH_PASS" --command "$remote_cmd"; then
        __err__ "VMID ${vmid}: remote execution failed."
        return
    fi

    __ok__ "VMID ${vmid}: completed"
}

run_bulk() {
    if ! [[ $START_VMID =~ ^[0-9]+$ && $END_VMID =~ ^[0-9]+$ ]]; then
        __err__ "--start and --end must be numeric."
        exit 64
    fi

    if (( END_VMID < START_VMID )); then
        __err__ "--end cannot be less than --start."
        exit 64
    fi

    __info__ "Running CCPVE CLI bulk execution: VMIDs ${START_VMID}-${END_VMID}"
    if [[ -n "$EXEC_COMMAND" ]]; then
        __info__ "Command: ${EXEC_COMMAND}"
    else
        __info__ "Target script: ${RUN_SCRIPT}"
        if [[ -n "$RUN_ARGS" ]]; then
            __info__ "Script args: ${RUN_ARGS}"
        fi
    fi

    local vmid
    for vmid in $(seq "$START_VMID" "$END_VMID"); do
        execute_for_vmid "$vmid"
    done

    __ok__ "Batch execution finished."
}

cleanup() {
    : # Placeholder for future temp file cleanup.
}

main() {
    parse_args "$@"
    ensure_dependencies

    if [[ "$INTERACTIVE" == "true" ]]; then
        gather_interactive_inputs
    fi

    local required_vars=(START_VMID END_VMID SSH_USER SSH_PASS)
    if [[ -z "$EXEC_COMMAND" ]]; then
        required_vars+=(RUN_SCRIPT)
    fi

    local required
    for required in "${required_vars[@]}"; do
        if [[ -z "${!required}" ]]; then
            __err__ "Missing required parameter: ${required}"
            usage
            exit 64
        fi
    done

    run_bulk
}

main "$@"

# Testing status:
#   - 2025-10-03: Pending manual verification on staging cluster.
