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
#   ./BatchRunCLI.sh --start <vmid> --end <vmid> --ssh-user <user> --ssh-pass <pass> --run Host/QuickDiagnostic.sh [--args "arg1 arg2"] [--branch <branch>]
#   ./BatchRunCLI.sh --start 300 --end 305 --ssh-user root --ssh-pass secret
#   ./BatchRunCLI.sh --start 100 --end 103 --ssh-user root --ssh-pass secret --run Host/QuickDiagnostic.sh --branch testing
#
# Function Index:
#   - usage
#   - parse_args
#   - ensure_dependencies
#   - enter_alternate_screen
#   - exit_alternate_screen
#   - gather_interactive_inputs
#   - choose_script_via_navigation
#   - build_remote_script_command
#   - wrap_remote_command
#   - execute_for_vmid
#   - run_bulk
#   - cleanup
#   - main
#

set -euo pipefail

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
GIT_BRANCH="main"
INTERACTIVE="false"
ALT_SCREEN_ACTIVE="false"

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"
# shellcheck source=Utilities/SSH.sh
source "${UTILITYPATH}/SSH.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Colors.sh
source "${UTILITYPATH}/Colors.sh"

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
  --branch <branch>      Git branch to use (default: main)
  --exec "command"       Run an arbitrary shell command on each guest instead of a script
  -h/--help              Show this help and exit

Interactive Mode (omit --run):
  1) Collect credentials and VMID range
  2) Navigate repository tree (numbers for items, b=up, q=quit, hN=header preview)
  3) Preview script header and sample invocations
  4) Provide optional arguments
  5) Execute remotely via CCPVE one-liner

Examples:
  $0 --start 100 --end 103 --ssh-user root --ssh-pass secret --run Host/QuickDiagnostic.sh
  $0 --start 200 --end 205 --ssh-user root --ssh-pass secret --run Storage/Benchmark.sh --args "--device /dev/sdb --mode quick"
  $0 --start 100 --end 103 --ssh-user root --ssh-pass secret --run Host/QuickDiagnostic.sh --branch testing
  $0 --start 300 --end 305 --ssh-user root --ssh-pass secret   # interactive
EOF
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        INTERACTIVE="true"
        return
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --start) START_VMID="$2"; shift 2 ;;
            --end) END_VMID="$2"; shift 2 ;;
            --ssh-user) SSH_USER="$2"; shift 2 ;;
            --ssh-pass) SSH_PASS="$2"; shift 2 ;;
            --run) RUN_SCRIPT="$2"; shift 2 ;;
            --args) RUN_ARGS="$2"; shift 2 ;;
            --branch) GIT_BRANCH="$2"; shift 2 ;;
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

enter_alternate_screen() {
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        if tput smcup >/dev/null 2>&1; then
            ALT_SCREEN_ACTIVE="true"
        fi
    fi
}

exit_alternate_screen() {
    if [[ "$ALT_SCREEN_ACTIVE" == "true" ]]; then
        tput rmcup >/dev/null 2>&1 || true
        ALT_SCREEN_ACTIVE="false"
    fi
}

gather_interactive_inputs() {
    if [[ "$ALT_SCREEN_ACTIVE" != "true" ]]; then
        enter_alternate_screen
    fi
    clear
    echo
    __line_rgb__ "=== Interactive Batch Mode ===" 0 255 255
    echo

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

    read -r -p "Git branch to use (default: main): " branch_input
    if [[ -n "$branch_input" ]]; then
        GIT_BRANCH="$branch_input"
    fi

    choose_script_via_navigation || {
        __err__ "No script selected; aborting."
        exit 1
    }

    read -r -p "Optional arguments for ${RUN_SCRIPT} (leave blank for none): " RUN_ARGS
}

choose_script_via_navigation() {
    local current_dir="$SCRIPT_ROOT"

    while true; do
        clear
        echo
        echo -n "CURRENT DIRECTORY: "
        __line_rgb__ "./${current_dir#$SCRIPT_ROOT/}" 0 255 0
        echo
        __line_rgb__ "Folders and scripts:" 200 200 200
        echo "--------------------------------------------------"

        mapfile -t DIRS < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type d ! -name 'Utilities' ! -name '.*' | sort)
        mapfile -t SCRIPTS < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type f -name '*.sh' \
            ! -path '*/Utilities/*' ! -name 'CCPVE.sh' ! -name 'GUI.sh' ! -name 'MakeScriptsExecutable.sh' | sort)

        local index=1
        local -A choices=()

        for dir_path in "${DIRS[@]}"; do
            __line_rgb__ "$(printf "%2d) %s/" "$index" "$(basename "$dir_path")")" 0 200 200
            choices[$index]="DIR::$dir_path"
            ((index++))
        done

        for script_path in "${SCRIPTS[@]}"; do
            __line_rgb__ "$(printf "%2d) %s" "$index" "$(basename "$script_path")")" 100 200 100
            choices[$index]="SCR::$script_path"
            ((index++))
        done

        echo
        echo "--------------------------------------------------"
        __line_rgb__ " hN) Show header for item N" 150 150 150
        __line_rgb__ " b) Up directory          q) Quit selection" 150 150 150
        echo "--------------------------------------------------"
        echo

        read -r -p "Select script or folder: " choice

        case "$choice" in
            q)
                return 1 ;;
            b)
                if [[ "$current_dir" == "$SCRIPT_ROOT" ]]; then
                    __err__ "Already at repository root."
                    sleep 1
                else
                    current_dir="$(dirname "$current_dir")"
                fi
                ;;
            h[0-9]*)
                local num="${choice#h}"
                local entry="${choices[$num]:-}"
                if [[ -z "$entry" ]]; then
                    __err__ "Invalid item number."
                    sleep 1
                    continue
                fi
                if [[ ${entry%%::*} == SCR ]]; then
                    local file="${entry#*::}"
                    clear
                    __display_script_info__ "$file" "$(basename "$file")"
                    read -r -p "Press Enter to continue..."
                else
                    __info__ "Directories do not have headers."
                    sleep 1
                fi
                ;;
            ''|*[!0-9]*)
                __err__ "Invalid selection."
                sleep 1
                ;;
            *)
                if [[ -z "${choices[$choice]:-}" ]]; then
                    __err__ "Selection out of range."
                    sleep 1
                    continue
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
                clear
                __display_script_info__ "$local_full" "${RUN_SCRIPT}"
                return 0
                ;;
        esac
    done
}

build_remote_script_command() {
    local script_path="$1"
    local args="$2"
    local base

    base=$(printf 'bash <(curl -fsSL %s) --run %q --branch %q' "$SHORT_URL" "$script_path" "$GIT_BRANCH")

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
    local output
    local exit_code

    __info__ "Processing VMID ${vmid}"

    # Capture IP resolution output and suppress stderr
    if ! ip=$( __get_ip_from_vmid__ "$vmid" 2>/dev/null ); then
        __err__ "VMID ${vmid}: unable to resolve IP; skipping."
        return
    fi
    __update__ "VMID ${vmid}: IP ${ip}"

    # Wait for SSH with suppressed output
    if ! __wait_for_ssh__ "$ip" "$SSH_USER" "$SSH_PASS" >/dev/null 2>&1; then
        __err__ "VMID ${vmid}: SSH unreachable; skipping."
        return
    fi
    __update__ "VMID ${vmid}: SSH ready, executing script..."

    local remote_line
    if [[ -n "$EXEC_COMMAND" ]]; then
        remote_line="set -e; ${EXEC_COMMAND}"
    else
        remote_line="$(build_remote_script_command "$RUN_SCRIPT" "$RUN_ARGS")"
    fi

    local remote_cmd
    remote_cmd="$(wrap_remote_command "$remote_line")"

    # Capture output and exit code
    output=$(__ssh_exec__ --host "$ip" --user "$SSH_USER" --password "$SSH_PASS" --command "$remote_cmd" 2>&1)
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        __err__ "VMID ${vmid}: remote execution failed (exit code: ${exit_code})"
        if [[ -n "$output" ]]; then
            echo "  Output: ${output}" >&2
        fi
        return
    fi

    __ok__ "VMID ${vmid}: completed successfully"
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

    echo
    __line_rgb__ "=== Running CCPVE CLI bulk execution ===" 0 255 255
    __line_rgb__ "VMIDs: ${START_VMID}-${END_VMID}" 200 200 200
    __line_rgb__ "Branch: ${GIT_BRANCH}" 200 200 200
    if [[ -n "$EXEC_COMMAND" ]]; then
        __line_rgb__ "Command: ${EXEC_COMMAND}" 200 200 200
    else
        __line_rgb__ "Target script: ${RUN_SCRIPT}" 200 200 200
        if [[ -n "$RUN_ARGS" ]]; then
            __line_rgb__ "Script args: ${RUN_ARGS}" 200 200 200
        fi
    fi
    echo

    local vmid
    for vmid in $(seq "$START_VMID" "$END_VMID"); do
        execute_for_vmid "$vmid"
    done

    echo
    __line_rgb__ "Batch execution finished." 0 255 0
    echo
}

cleanup() {
    exit_alternate_screen
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
