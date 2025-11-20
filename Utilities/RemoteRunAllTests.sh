#!/bin/bash
#
# RemoteRunAllTests.sh
#
# Run all test suites on remote Proxmox nodes using RemoteExecutor.sh (same as GUI.sh).
# Copies entire repository and executes RunAllTests.sh on remote nodes.
#
# Usage:
#   RemoteRunAllTests.sh --node pt01
#   RemoteRunAllTests.sh --node 192.168.1.81
#   RemoteRunAllTests.sh --all-nodes
#   RemoteRunAllTests.sh --node pt01 --verbose
#   RemoteRunAllTests.sh --all-nodes --debug
#
# Options:
#   --node NODE      Run tests on specific node (hostname or IP from nodes.json)
#   --all-nodes      Run tests on all nodes in nodes.json
#   --verbose        Show INFO level logs (default: ERROR only)
#   --debug          Show DEBUG level logs (very verbose)
#   --help           Show this help message
#
# Notes:
#   - Requires nodes.json configuration file in repository root
#   - Uses same RemoteExecutor.sh as GUI.sh for consistency
#   - Automatically transfers all files to remote node
#   - Executes RunAllTests.sh on remote node
#   - Results are captured and displayed
#   - SSH keys are preferred; password authentication supported via sshpass
#   - Tests run in isolated temporary directory on remote node
#
# Function Index:
#   - validate_node_connection
#   - run_tests_on_node
#   - run_tests_on_all_nodes
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

# Default configuration
TARGET_NODE=""
ALL_NODES=false
LOG_LEVEL="ERROR"
NODES_FILE="${REPO_ROOT}/nodes.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

###############################################################################
# FUNCTIONS
###############################################################################

validate_node_connection() {
    local node_name="$1"
    local node_ip="$2"

    echo -e "${BLUE}->${RESET} Validating connection to ${BOLD}${node_name}${RESET} (${node_ip})..."

    # Quick SSH connection test with short timeout
    if timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=yes "root@${node_ip}" "echo ok" &>/dev/null; then
        echo -e "${GREEN}✓${RESET} SSH key authentication works"
        return 0
    fi

    # Check if sshpass is available for password auth
    if ! command -v sshpass &>/dev/null; then
        echo -e "${RED}✗${RESET} SSH keys not configured and sshpass not available"
        return 1
    fi

    echo -e "${YELLOW}⚠${RESET} SSH keys not configured, will need password"
    return 0
}

run_tests_on_node() {
    local node_name="$1"
    local node_ip="$2"
    local password="${3:-}"

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}Running tests on: ${node_name} (${node_ip})${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    # Build command to execute RunAllTests.sh
    local remote_cmd="bash Utilities/RunAllTests.sh"

    # Use RemoteExecutor.sh to handle file transfer and execution
    local executor_cmd=(
        "bash"
        "${SCRIPT_DIR}/RemoteExecutor.sh"
        "--host" "${node_ip}"
        "--user" "root"
        "--command" "${remote_cmd}"
        "--log-level" "${LOG_LEVEL}"
    )

    # Add password if provided
    if [[ -n "${password}" ]]; then
        executor_cmd+=("--password" "${password}")
    fi

    # Execute and capture result
    if "${executor_cmd[@]}"; then
        echo ""
        echo -e "${GREEN}✓${RESET} Tests completed successfully on ${node_name}"
        return 0
    else
        local exit_code=$?
        echo ""
        echo -e "${RED}✗${RESET} Tests failed on ${node_name} (exit code: ${exit_code})"
        return ${exit_code}
    fi
}

run_tests_on_all_nodes() {
    if [[ ! -f "${NODES_FILE}" ]]; then
        echo -e "${RED}Error:${RESET} nodes.json not found at ${NODES_FILE}" >&2
        return 1
    fi

    # Read nodes from JSON
    local nodes_count
    nodes_count=$(jq -r '.nodes | length' "${NODES_FILE}")

    if [[ ${nodes_count} -eq 0 ]]; then
        echo -e "${RED}Error:${RESET} No nodes configured in nodes.json" >&2
        return 1
    fi

    echo -e "${BOLD}Found ${nodes_count} node(s) in configuration${RESET}"
    echo ""

    local success_count=0
    local failure_count=0
    local failed_nodes=()

    # Iterate through nodes
    for ((i = 0; i < nodes_count; i++)); do
        local node_name=$(jq -r ".nodes[${i}].name" "${NODES_FILE}")
        local node_ip=$(jq -r ".nodes[${i}].ip" "${NODES_FILE}")
        local node_password=$(jq -r ".nodes[${i}].password // empty" "${NODES_FILE}")

        # Validate connection first
        if ! validate_node_connection "${node_name}" "${node_ip}"; then
            echo -e "${RED}✗${RESET} Skipping ${node_name} - connection validation failed"
            failure_count=$((failure_count + 1))
            failed_nodes+=("${node_name}")
            continue
        fi

        # Run tests
        if run_tests_on_node "${node_name}" "${node_ip}" "${node_password}"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
            failed_nodes+=("${node_name}")
        fi

        echo ""
    done

    # Print summary
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}Test Execution Summary${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${RESET}"
    echo -e "Total nodes:      ${nodes_count}"
    echo -e "${GREEN}Successful:${RESET}       ${success_count}"
    echo -e "${RED}Failed:${RESET}           ${failure_count}"

    if [[ ${failure_count} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Failed nodes:${RESET}"
        for node in "${failed_nodes[@]}"; do
            echo -e "  - ${node}"
        done
    fi
    echo ""

    return ${failure_count}
}

###############################################################################
# MAIN
###############################################################################

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --node)
            TARGET_NODE="$2"
            shift 2
            ;;
        --all-nodes)
            ALL_NODES=true
            shift
            ;;
        --verbose)
            LOG_LEVEL="INFO"
            shift
            ;;
        --debug)
            LOG_LEVEL="DEBUG"
            shift
            ;;
        --help | -h)
            # Show usage from header
            head -38 "$0" | grep -E "^#" | sed 's/^# //'
            exit 0
            ;;
        *)
            echo -e "${RED}Error:${RESET} Unknown option: $1" >&2
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "${TARGET_NODE}" ]] && [[ "${ALL_NODES}" != true ]]; then
    echo -e "${RED}Error:${RESET} Must specify either --node or --all-nodes" >&2
    echo "Use --help for usage information"
    exit 1
fi

if [[ -n "${TARGET_NODE}" ]] && [[ "${ALL_NODES}" == true ]]; then
    echo -e "${RED}Error:${RESET} Cannot use both --node and --all-nodes" >&2
    exit 1
fi

# Check dependencies
if ! command -v jq &>/dev/null; then
    echo -e "${RED}Error:${RESET} jq is required but not installed" >&2
    exit 1
fi

# Display header
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║${RESET} ${BOLD}Remote Test Execution${RESET}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "Log Level: ${LOG_LEVEL}"
echo ""

# Execute based on mode
if [[ "${ALL_NODES}" == true ]]; then
    run_tests_on_all_nodes
    exit $?
else
    # Single node execution
    # Check if target is in nodes.json
    if [[ -f "${NODES_FILE}" ]]; then
        node_json=$(jq -r ".nodes[] | select(.name == \"${TARGET_NODE}\" or .ip == \"${TARGET_NODE}\")" "${NODES_FILE}")

        if [[ -n "${node_json}" ]]; then
            node_name=$(echo "${node_json}" | jq -r '.name')
            node_ip=$(echo "${node_json}" | jq -r '.ip')
            node_password=$(echo "${node_json}" | jq -r '.password // empty')

            if validate_node_connection "${node_name}" "${node_ip}"; then
                run_tests_on_node "${node_name}" "${node_ip}" "${node_password}"
                exit $?
            else
                echo -e "${RED}Error:${RESET} Connection validation failed" >&2
                exit 1
            fi
        else
            # Not in nodes.json, treat as direct IP
            echo -e "${YELLOW}Note:${RESET} Node not found in nodes.json, using as direct connection"
            if validate_node_connection "${TARGET_NODE}" "${TARGET_NODE}"; then
                run_tests_on_node "${TARGET_NODE}" "${TARGET_NODE}" ""
                exit $?
            else
                echo -e "${RED}Error:${RESET} Connection validation failed" >&2
                exit 1
            fi
        fi
    else
        # No nodes.json, use target as direct IP
        if validate_node_connection "${TARGET_NODE}" "${TARGET_NODE}"; then
            run_tests_on_node "${TARGET_NODE}" "${TARGET_NODE}" ""
            exit $?
        else
            echo -e "${RED}Error:${RESET} Connection validation failed" >&2
            exit 1
        fi
    fi
fi

###############################################################################
# Script notes:
###############################################################################
# Last checked: YYYY-MM-DD
#
# Changes:
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

