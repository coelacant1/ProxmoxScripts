#!/bin/bash
#
# SetScrubInterval.sh
#
# Configures Ceph pool scrubbing schedule on local or remote Proxmox nodes.
# Disables automatic scrubbing and sets up systemd timer for manual deep-scrub scheduling.
# Supports local execution or remote deployment to cluster nodes via SSH.
#
# Usage:
#   SetScrubInterval.sh local install ceph-pool daily 02:30
#   SetScrubInterval.sh local install ceph-pool 12h
#   SetScrubInterval.sh local uninstall ceph-pool
#   SetScrubInterval.sh remote install node01 root password ceph-pool daily 02:30
#   SetScrubInterval.sh remote uninstall node01 root password ceph-pool
#
# Arguments:
#   mode              - Operation mode: 'local' or 'remote'
#   action            - Action: 'install' or 'uninstall'
#
#   For local install:
#     pool_name         - Ceph pool name
#     schedule_type     - Schedule: 'daily', '12h', '6h', or 'weekly'
#     schedule_time     - Time: '02:30' for daily, 'Sun 04:00' for weekly (optional for hourly)
#
#   For local uninstall:
#     pool_name         - Ceph pool name
#
#   For remote install:
#     node_name         - Proxmox cluster node name
#     ssh_user          - SSH username
#     ssh_pass          - SSH password
#     pool_name         - Ceph pool name
#     schedule_type     - Schedule type
#     schedule_time     - Time for schedule (optional for hourly)
#
#   For remote uninstall:
#     node_name         - Proxmox cluster node name
#     ssh_user          - SSH username
#     ssh_pass          - SSH password
#     pool_name         - Ceph pool name
#
# Schedule Types: daily, 12h, 6h, weekly
#
# Notes:
#   - Disables automatic Ceph scrubbing on specified pool
#   - Creates systemd service and timer for scheduled deep-scrub
#   - Remote mode copies this script to target node and executes locally
#   - Requires jq for local mode, jq and sshpass for remote mode
#
# Function Index:
#   - validate_custom_options
#   - derive_oncalendar_expression
#   - local_disable_scrubbing
#   - local_revert_scrubbing
#   - local_create_scrub_script
#   - local_create_systemd_units
#   - local_enable_and_start_timer
#   - local_remove_systemd_units
#   - remote_install
#   - remote_uninstall
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"
# shellcheck source=Utilities/SSH.sh
source "${UTILITYPATH}/SSH.sh"
# shellcheck source=Utilities/Discovery.sh
source "${UTILITYPATH}/Discovery.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Configuration constants
readonly SCRUB_SCRIPT_DIR="/usr/local/bin"
readonly SYSTEMD_DIR="/etc/systemd/system"

# --- validate_custom_options -------------------------------------------------
# @function validate_custom_options
# @description Validates Ceph scrub scheduler options not covered by ArgumentParser.
validate_custom_options() {
    # Validate mode
    case "${MODE}" in
        local | remote) ;;
        *)
            __err__ "Invalid mode '${MODE}'. Must be 'local' or 'remote'"
            exit 64
            ;;
    esac

    # Validate action
    case "${ACTION}" in
        install | uninstall) ;;
        *)
            __err__ "Invalid action '${ACTION}'. Must be 'install' or 'uninstall'"
            exit 64
            ;;
    esac

    # Validate schedule type if installing
    if [[ "${ACTION}" == "install" && -n "${SCHEDULE_TYPE}" ]]; then
        case "${SCHEDULE_TYPE}" in
            daily | 12h | 6h | weekly) ;;
            *)
                __err__ "Invalid schedule type '${SCHEDULE_TYPE}'"
                __err__ "Valid types: daily, 12h, 6h, weekly"
                exit 64
                ;;
        esac

        # Validate schedule time for daily/weekly
        if [[ "${SCHEDULE_TYPE}" == "daily" || "${SCHEDULE_TYPE}" == "weekly" ]]; then
            if [[ -z "${SCHEDULE_TIME}" ]]; then
                __err__ "Schedule time required for ${SCHEDULE_TYPE} schedule type"
                __err__ "Example: daily 02:30 or weekly Sun 04:00"
                exit 64
            fi
        fi
    fi
}

# --- derive_oncalendar_expression --------------------------------------------
# @function derive_oncalendar_expression
# @description Converts schedule type and time to systemd OnCalendar format.
# @param 1 Schedule type (daily, 12h, 6h, weekly)
# @param 2 Schedule time (e.g., '02:30', 'Sun 04:00')
# @return OnCalendar expression
derive_oncalendar_expression() {
    local scheduleType="$1"
    local scheduleTime="${2:-}"

    case "$scheduleType" in
        daily)
            echo "*-*-* ${scheduleTime}"
            ;;
        12h)
            echo "*-*-* 00,12:00:00"
            ;;
        6h)
            echo "*-*-* 00,06,12,18:00:00"
            ;;
        weekly)
            local dow="${scheduleTime%% *}"
            local tod="${scheduleTime#* }"
            echo "${dow} *-*-* ${tod}"
            ;;
        *)
            __err__ "Unknown schedule type '${scheduleType}'"
            exit 1
            ;;
    esac
}

# --- local_disable_scrubbing -------------------------------------------------
# @function local_disable_scrubbing
# @description Disables automatic Ceph scrubbing on specified pool.
# @param 1 Pool name
local_disable_scrubbing() {
    local poolName="$1"

    __info__ "Disabling automatic scrubbing for pool '${poolName}'"
    ceph osd pool set "${poolName}" noscrub true
    ceph osd pool set "${poolName}" nodeep-scrub true
    __ok__ "Disabled automatic scrubbing"
}

# --- local_revert_scrubbing --------------------------------------------------
# @function local_revert_scrubbing
# @description Reverts Ceph scrubbing settings to defaults.
# @param 1 Pool name
local_revert_scrubbing() {
    local poolName="$1"

    __info__ "Reverting scrubbing settings for pool '${poolName}'"
    ceph osd pool unset "${poolName}" noscrub
    ceph osd pool unset "${poolName}" nodeep-scrub
    __ok__ "Reverted to default scrubbing settings"
}

# --- local_create_scrub_script -----------------------------------------------
# @function local_create_scrub_script
# @description Creates executable script for manual deep-scrub.
# @param 1 Pool name
local_create_scrub_script() {
    local poolName="$1"
    local scriptName="${SCRUB_SCRIPT_DIR}/ceph-scrub-${poolName}.sh"

    __info__ "Creating scrub script: ${scriptName}"

    cat >"${scriptName}" <<EOSCRIPT
#!/bin/bash
# Auto-generated Ceph deep-scrub script for pool: ${poolName}
set -euo pipefail
echo "\$(date): Starting deep-scrub for pool '${poolName}'"
ceph pg deep-scrub \$(ceph pg ls-by-pool "${poolName}" -f json | jq -r '.[].pgid')
echo "\$(date): Deep-scrub initiated for pool '${poolName}'"
EOSCRIPT

    chmod +x "${scriptName}"
    __ok__ "Created scrub script"
}

# --- local_create_systemd_units ----------------------------------------------
# @function local_create_systemd_units
# @description Creates systemd service and timer units.
# @param 1 Pool name
# @param 2 Schedule type
# @param 3 Schedule time
local_create_systemd_units() {
    local poolName="$1"
    local scheduleType="$2"
    local scheduleTime="${3:-}"

    local serviceFile="${SYSTEMD_DIR}/ceph-scrub-${poolName}.service"
    local timerFile="${SYSTEMD_DIR}/ceph-scrub-${poolName}.timer"
    local onCalendar

    onCalendar="$(derive_oncalendar_expression "${scheduleType}" "${scheduleTime}")"

    __info__ "Creating systemd units"

    # Create service unit
    cat >"${serviceFile}" <<EOSERVICE
[Unit]
Description=Ceph deep-scrub for pool ${poolName}
After=ceph.target

[Service]
Type=oneshot
ExecStart=${SCRUB_SCRIPT_DIR}/ceph-scrub-${poolName}.sh
StandardOutput=journal
StandardError=journal
EOSERVICE

    # Create timer unit
    cat >"${timerFile}" <<EOTIMER
[Unit]
Description=Timer for Ceph deep-scrub of pool ${poolName}

[Timer]
OnCalendar=${onCalendar}
Persistent=true

[Install]
WantedBy=timers.target
EOTIMER

    __ok__ "Created systemd units (schedule: ${onCalendar})"
}

# --- local_enable_and_start_timer --------------------------------------------
# @function local_enable_and_start_timer
# @description Enables and starts systemd timer.
# @param 1 Pool name
local_enable_and_start_timer() {
    local poolName="$1"

    __info__ "Enabling and starting timer"
    systemctl daemon-reload
    systemctl enable "ceph-scrub-${poolName}.timer"
    systemctl start "ceph-scrub-${poolName}.timer"
    __ok__ "Timer enabled and started"
}

# --- local_remove_systemd_units ----------------------------------------------
# @function local_remove_systemd_units
# @description Removes systemd units and script.
# @param 1 Pool name
local_remove_systemd_units() {
    local poolName="$1"
    local serviceFile="${SYSTEMD_DIR}/ceph-scrub-${poolName}.service"
    local timerFile="${SYSTEMD_DIR}/ceph-scrub-${poolName}.timer"
    local scriptFile="${SCRUB_SCRIPT_DIR}/ceph-scrub-${poolName}.sh"

    __info__ "Removing systemd units"

    # Stop and disable timer if active
    if systemctl is-active "ceph-scrub-${poolName}.timer" &>/dev/null; then
        systemctl stop "ceph-scrub-${poolName}.timer"
    fi
    if systemctl is-enabled "ceph-scrub-${poolName}.timer" &>/dev/null; then
        systemctl disable "ceph-scrub-${poolName}.timer"
    fi

    # Remove files
    rm -f "${timerFile}" "${serviceFile}" "${scriptFile}"
    systemctl daemon-reload
    __ok__ "Removed systemd units and script"
}

# --- remote_install ----------------------------------------------------------
# @function remote_install
# @description Installs scrub scheduler on remote node via SSH.
# @param 1 VM host IP
# @param 2 SSH user
# @param 3 SSH password
# @param 4 Pool name
# @param 5 Schedule type
# @param 6 Schedule time
remote_install() {
    local vmHost="$1"
    local vmUser="$2"
    local vmPass="$3"
    local poolName="$4"
    local scheduleType="$5"
    local scheduleTime="${6:-}"

    __info__ "Installing scrub scheduler on remote node: ${vmHost}"

    # Copy this script to remote host
    local tempScript="/tmp/CephScrubScheduler-remote.sh"
    __scp_send__ "${vmHost}" "${vmUser}" "${vmPass}" "$0" "${tempScript}"

    # Execute install command remotely
    local connection_flags=(
        --host "${vmHost}"
        --user "${vmUser}"
        --password "${vmPass}"
    )

    __ssh_exec__ \
        "${connection_flags[@]}" \
        --sudo \
        --shell bash \
        --command "bash ${tempScript} local install \"${poolName}\" \"${scheduleType}\" \"${scheduleTime}\""

    # Cleanup
    __ssh_exec__ \
        "${connection_flags[@]}" \
        --sudo \
        --command "rm -f ${tempScript}"

    __ok__ "Remote install completed on ${vmHost}"
}

# --- remote_uninstall --------------------------------------------------------
# @function remote_uninstall
# @description Uninstalls scrub scheduler on remote node via SSH.
# @param 1 VM host IP
# @param 2 SSH user
# @param 3 SSH password
# @param 4 Pool name
remote_uninstall() {
    local vmHost="$1"
    local vmUser="$2"
    local vmPass="$3"
    local poolName="$4"

    __info__ "Uninstalling scrub scheduler on remote node: ${vmHost}"

    # Copy this script to remote host
    local tempScript="/tmp/CephScrubScheduler-remote.sh"
    __scp_send__ "${vmHost}" "${vmUser}" "${vmPass}" "$0" "${tempScript}"

    # Execute uninstall command remotely
    local connection_flags=(
        --host "${vmHost}"
        --user "${vmUser}"
        --password "${vmPass}"
    )

    __ssh_exec__ \
        "${connection_flags[@]}" \
        --sudo \
        --shell bash \
        --command "bash ${tempScript} local uninstall \"${poolName}\""

    # Cleanup
    __ssh_exec__ \
        "${connection_flags[@]}" \
        --sudo \
        --command "rm -f ${tempScript}"

    __ok__ "Remote uninstall completed on ${vmHost}"
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Parse mode and action first (manual parsing for first 2 args)
    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments: mode and action"
        __err__ "Usage: SetScrubInterval.sh <mode> <action> [arguments...]"
        exit 64
    fi

    MODE="$1"
    ACTION="$2"
    shift 2

    # Validate mode and action early
    validate_custom_options

    # Install dependencies based on mode
    if [[ "$MODE" == "local" ]]; then
        __ensure_dependencies__ jq
    elif [[ "$MODE" == "remote" ]]; then
        __ensure_dependencies__ jq sshpass
    fi

    # Parse remaining arguments and execute based on mode and action
    case "$MODE" in
        local)
            case "$ACTION" in
                install)
                    __parse_args__ "pool_name:string schedule_type:string schedule_time:string:?" "$@"

                    __info__ "Configuring Ceph scrub schedule"
                    __info__ "  Pool: ${POOL_NAME}"
                    __info__ "  Schedule: ${SCHEDULE_TYPE} ${SCHEDULE_TIME}"

                    if ! __prompt_user_yn__ "Install scrub scheduler for pool '${POOL_NAME}'?"; then
                        __info__ "Operation cancelled"
                        exit 0
                    fi

                    local_disable_scrubbing "${POOL_NAME}"
                    local_create_scrub_script "${POOL_NAME}"
                    local_create_systemd_units "${POOL_NAME}" "${SCHEDULE_TYPE}" "${SCHEDULE_TIME}"
                    local_enable_and_start_timer "${POOL_NAME}"

                    echo ""
                    __ok__ "Scrub scheduler installed successfully"
                    __info__ "Pool '${POOL_NAME}' automatic scrubbing: disabled"
                    __info__ "Manual scrub schedule: ${SCHEDULE_TYPE} ${SCHEDULE_TIME}"
                    __info__ "Check status: systemctl status ceph-scrub-${POOL_NAME}.timer"
                    ;;
                uninstall)
                    __parse_args__ "pool_name:string" "$@"

                    __info__ "Removing Ceph scrub schedule"
                    __info__ "  Pool: ${POOL_NAME}"

                    if ! __prompt_user_yn__ "Uninstall scrub scheduler for pool '${POOL_NAME}'?"; then
                        __info__ "Operation cancelled"
                        exit 0
                    fi

                    local_remove_systemd_units "${POOL_NAME}"
                    local_revert_scrubbing "${POOL_NAME}"

                    echo ""
                    __ok__ "Scrub scheduler removed successfully"
                    __info__ "Pool '${POOL_NAME}' reverted to default scrubbing"
                    ;;
            esac
            ;;
        remote)
            case "$ACTION" in
                install)
                    __parse_args__ "node_name:string ssh_user:string ssh_pass:string pool_name:string schedule_type:string schedule_time:string:?" "$@"

                    # Convert node name to IP
                    readarray -t REMOTE_NODE_IPS < <(__get_remote_node_ips__)
                    VM_HOST="$(__get_ip_from_name__ "${NODE_NAME}")"

                    # Verify node is in cluster
                    if [[ ! " ${REMOTE_NODE_IPS[*]} " =~ \ ${VM_HOST}\  ]]; then
                        __err__ "Node '${NODE_NAME}' not found in cluster"
                        exit 1
                    fi

                    __info__ "Remote installation on node '${NODE_NAME}' (${VM_HOST})"
                    __info__ "  Pool: ${POOL_NAME}"
                    __info__ "  Schedule: ${SCHEDULE_TYPE} ${SCHEDULE_TIME}"

                    if ! __prompt_user_yn__ "Install scrub scheduler on remote node?"; then
                        __info__ "Operation cancelled"
                        exit 0
                    fi

                    remote_install "${VM_HOST}" "${SSH_USER}" "${SSH_PASS}" "${POOL_NAME}" "${SCHEDULE_TYPE}" "${SCHEDULE_TIME}"
                    ;;
                uninstall)
                    __parse_args__ "node_name:string ssh_user:string ssh_pass:string pool_name:string" "$@"

                    # Convert node name to IP
                    readarray -t REMOTE_NODE_IPS < <(__get_remote_node_ips__)
                    VM_HOST="$(__get_ip_from_name__ "${NODE_NAME}")"

                    # Verify node is in cluster
                    if [[ ! " ${REMOTE_NODE_IPS[*]} " =~ \ ${VM_HOST}\  ]]; then
                        __err__ "Node '${NODE_NAME}' not found in cluster"
                        exit 1
                    fi

                    __info__ "Remote uninstallation on node '${NODE_NAME}' (${VM_HOST})"
                    __info__ "  Pool: ${POOL_NAME}"

                    if ! __prompt_user_yn__ "Uninstall scrub scheduler on remote node?"; then
                        __info__ "Operation cancelled"
                        exit 0
                    fi

                    remote_uninstall "${VM_HOST}" "${SSH_USER}" "${SSH_PASS}" "${POOL_NAME}"
                    ;;
            esac
            ;;
    esac

    __prompt_keep_installed_packages__
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-21
#
# Changes:
# - 2025-11-04: Fully refactored to match BulkConfigureCPU.sh standards
# - 2025-11-20: Follows CONTRIBUTING.md Section 3.10 patterns
# - 2025-11-20: Uses Communication.sh functions (__info__, __ok__, __err__)
# - 2025-11-20: Uses __prompt_user_yn__ for confirmations
# - 2025-11-20: Proper function documentation with @function, @description, @param
# - 2025-11-20: Readonly constants for configuration
# - 2025-11-20: Consistent spacing and structure
# - 2025-11-20: Better user feedback with detailed status messages
# - 2025-11-21: Removed unused DISABLE_SCRUB_SECONDS constant
# - 2025-11-21: Fixed regex quotes in IP address matching (SC2076)
#
# Fixes:
# -
#
# Known issues:
# -
#

