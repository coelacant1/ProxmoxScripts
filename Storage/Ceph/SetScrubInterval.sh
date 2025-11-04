#!/bin/bash
#
# CephScrubScheduler.sh
#
# Provides two main modes: local or remote. Each can do 'install' or 'uninstall'.
#
# Usage:
#   # Install locally:
#   CephScrubScheduler.sh local install <pool_name> <schedule_type> [time]
#
#   # Uninstall locally:
#   CephScrubScheduler.sh local uninstall <pool_name>
#
#   # Install on a remote node (must provide a valid Proxmox cluster node name, not DNS):
#   CephScrubScheduler.sh remote install <node_name> <vm_user> <vm_pass> <pool_name> <schedule_type> [time]
#
#   # Uninstall on a remote node:
#   CephScrubScheduler.sh remote uninstall <node_name> <vm_user> <vm_pass> <pool_name>
#
# Example schedule_type/time combos:
#   - daily 02:30
#   - 12h
#   - 6h
#   - weekly Sun 04:00
#
# This script:
#   1) Disables automatic scrubbing on <pool_name> by setting long intervals.
#   2) Sets up or removes a systemd service/timer that periodically deep-scrubs the pool.
#
# Function Index:
#   - usage
#   - derive_oncalendar_expression
#   - local_disable_scrubbing
#   - local_revert_scrubbing
#   - local_create_scrub_script
#   - local_create_systemd_units
#   - local_enable_and_start_timer
#   - local_remove_systemd_units
#   - remote_install
#   - remote_uninstall
#

set -euo pipefail

#   - usage
#   - derive_oncalendar_expression
#   - local_disable_scrubbing
#   - local_revert_scrubbing
#   - local_create_scrub_script
#   - local_create_systemd_units
#   - local_enable_and_start_timer
#   - local_remove_systemd_units
#   - remote_install
#   - remote_uninstall
#
trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"
# shellcheck source=Utilities/SSH.sh
source "${UTILITYPATH}/SSH.sh"

set -u

###############################################################################
# ENVIRONMENT CHECKS
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# INSTALL REQUIRED PACKAGES (IF NEEDED)
###############################################################################
SCRIPT_MODE="$1"
ACTION="$2"

# Decide which utilities to ensure based on mode
if [[ "$SCRIPT_MODE" == "local" ]]; then
  __ensure_dependencies__ jq
elif [[ "$SCRIPT_MODE" == "remote" ]]; then
  __ensure_dependencies__ jq sshpass
fi

###############################################################################
# CONFIG / DEFAULTS
###############################################################################
DISABLE_SCRUB_SECONDS=2592000  # 30 days
DEFAULT_SCRUB_MIN=86400        # 24h
DEFAULT_SCRUB_MAX=604800       # 7 days
DEFAULT_DEEP_SCRUB=604800      # 7 days
SCRUB_SCRIPT_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"

###############################################################################
# HELPER: Print usage
###############################################################################
function usage() {
  echo "Usage:"
  echo "  Local Install:   $0 local install <pool_name> <schedule_type> [time]"
  echo "  Local Uninstall: $0 local uninstall <pool_name>"
  echo
  echo "  Remote Install:  $0 remote install <node_name> <vm_user> <vm_pass> <pool_name> <schedule_type> [time]"
  echo "  Remote Uninstall:$0 remote uninstall <node_name> <vm_user> <vm_pass> <pool_name>"
  echo
  echo "Schedule Types:"
  echo "  daily <HH:MM>       (e.g. daily 02:30)"
  echo "  12h                 (every 12 hours from midnight)"
  echo "  6h                  (every 6 hours from midnight)"
  echo "  weekly <DAY HH:MM>  (e.g. weekly Sun 04:00)"
  exit 1
}

###############################################################################
# HELPER: Derive systemd OnCalendar= expression
###############################################################################
function derive_oncalendar_expression() {
  local scheduleType="$1"
  local scheduleTime="$2"

  case "$scheduleType" in
    daily)
      if [[ -z "$scheduleTime" ]]; then
        echo "Error: 'daily' schedule requires a time in HH:MM format." >&2
        exit 2
      fi
      echo "*-*-* $scheduleTime:00"
      ;;
    12h)
      echo "0/12:00:00"
      ;;
    6h)
      echo "0/6:00:00"
      ;;
    weekly)
      if [[ -z "$scheduleTime" ]]; then
        echo "Error: 'weekly' schedule requires day/time like 'Sun 04:00'." >&2
        exit 2
      fi
      echo "$scheduleTime:00"
      ;;
    *)
      echo "Error: Unsupported schedule_type '$scheduleType'." >&2
      exit 2
      ;;
  esac
}

###############################################################################
# LOCAL FUNCTIONS
###############################################################################
function local_disable_scrubbing() {
  local poolName="$1"
  echo "Disabling automatic scrubbing on pool '${poolName}' to '${DISABLE_SCRUB_SECONDS}' seconds..."
  ceph osd pool set "${poolName}" scrub_min_interval "${DISABLE_SCRUB_SECONDS}"
  ceph osd pool set "${poolName}" scrub_max_interval "${DISABLE_SCRUB_SECONDS}"
  ceph osd pool set "${poolName}" deep_scrub_interval "${DISABLE_SCRUB_SECONDS}"
}

function local_revert_scrubbing() {
  local poolName="$1"
  echo "Reverting scrubbing intervals on pool '${poolName}' to defaults..."
  ceph osd pool set "${poolName}" scrub_min_interval "${DEFAULT_SCRUB_MIN}"
  ceph osd pool set "${poolName}" scrub_max_interval "${DEFAULT_SCRUB_MAX}"
  ceph osd pool set "${poolName}" deep_scrub_interval "${DEFAULT_DEEP_SCRUB}"
}

function local_create_scrub_script() {
  local poolName="$1"
  local scriptPath="${SCRUB_SCRIPT_DIR}/scrub-${poolName}.sh"

  echo "Creating scrub script at '${scriptPath}' ..."
  cat <<EOF > "${scriptPath}"
#!/bin/bash

POOL="${poolName}"
pgs=\$(ceph pg ls-by-pool "\$POOL" -f json | jq -r '.[].pgid')

if [ -z "\$pgs" ]; then
  echo "No PGs found for pool \$POOL."
  exit 0
fi

echo "Starting deep-scrub on pool \$POOL ..."
for pg in \$pgs; do
  echo "  -> Deep-scrubbing PG \$pg"
  ceph pg deep-scrub "\$pg"
done

echo "All deep-scrub commands issued for pool \$POOL."
EOF

  chmod +x "${scriptPath}"
}

function local_create_systemd_units() {
  local poolName="$1"
  local scheduleType="$2"
  local scheduleTime="$3"

  local serviceFile="${SYSTEMD_DIR}/ceph-scrub-${poolName}.service"
  local timerFile="${SYSTEMD_DIR}/ceph-scrub-${poolName}.timer"
  local onCalendar
  onCalendar="$(derive_oncalendar_expression "${scheduleType}" "${scheduleTime}")"

  echo "Creating systemd service unit at '${serviceFile}' ..."
  cat <<EOF > "${serviceFile}"
[Unit]
Description=Manual Ceph deep-scrub for pool '${poolName}'

[Service]
Type=oneshot
ExecStart=${SCRUB_SCRIPT_DIR}/scrub-${poolName}.sh
EOF

  echo "Creating systemd timer unit at '${timerFile}' ..."
  cat <<EOF > "${timerFile}"
[Unit]
Description=Timer for Ceph scrub on pool '${poolName}'

[Timer]
OnCalendar=${onCalendar}
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

function local_enable_and_start_timer() {
  local poolName="$1"
  local timerName="ceph-scrub-${poolName}.timer"

  echo "Reloading systemd..."
  systemctl daemon-reload

  echo "Enabling and starting the timer '${timerName}'..."
  systemctl enable "${timerName}"
  systemctl start "${timerName}"

  echo "Done. Timer status:"
  systemctl list-timers --all | grep "${timerName}" || true
}

function local_remove_systemd_units() {
  local poolName="$1"
  local serviceFile="${SYSTEMD_DIR}/ceph-scrub-${poolName}.service"
  local timerFile="${SYSTEMD_DIR}/ceph-scrub-${poolName}.timer"
  local scriptPath="${SCRUB_SCRIPT_DIR}/scrub-${poolName}.sh"

  echo "Stopping and disabling systemd timer for pool '${poolName}'..."
  systemctl stop "ceph-scrub-${poolName}.timer" 2>/dev/null || true
  systemctl disable "ceph-scrub-${poolName}.timer" 2>/dev/null || true

  echo "Removing service file: '${serviceFile}'"
  rm -f "${serviceFile}"

  echo "Removing timer file: '${timerFile}'"
  rm -f "${timerFile}"

  echo "Removing scrub script: '${scriptPath}'"
  rm -f "${scriptPath}"

  systemctl daemon-reload
}

###############################################################################
# REMOTE FUNCTIONS
###############################################################################
function remote_install() {
  local vmHost="$1"
  local vmUser="$2"
  local vmPass="$3"
  local poolName="$4"
  local scheduleType="$5"
  local scheduleTime="$6"

  local -a connection_flags=(--host "$vmHost" --user "$vmUser" --password "$vmPass")

  echo "Installing ceph-common on remote node '${vmHost}'..."
  __ssh_exec__ \
    "${connection_flags[@]}" \
    --sudo \
    --shell bash \
    --command "apt-get update -y && apt-get install -y ceph-common"

  echo "Ensuring /etc/ceph on remote..."
  __ssh_exec__ \
    "${connection_flags[@]}" \
    --sudo \
    --command "mkdir -p /etc/ceph && chmod 755 /etc/ceph"

  echo "Copying ceph.conf and ceph.client.admin.keyring to remote..."
  __scp_send__ \
    "${connection_flags[@]}" \
    --source /etc/ceph/ceph.conf \
    --destination /tmp/ceph.conf
  __scp_send__ \
    "${connection_flags[@]}" \
    --source /etc/ceph/ceph.client.admin.keyring \
    --destination /tmp/ceph.client.admin.keyring

  __ssh_exec__ \
    "${connection_flags[@]}" \
    --sudo \
    --shell bash \
    --command "mv /tmp/ceph.conf /etc/ceph/ && chown root:root /etc/ceph/ceph.conf && chmod 644 /etc/ceph/ceph.conf"
  __ssh_exec__ \
    "${connection_flags[@]}" \
    --sudo \
    --shell bash \
    --command "mv /tmp/ceph.client.admin.keyring /etc/ceph/ && chown root:root /etc/ceph/ceph.client.admin.keyring && chmod 600 /etc/ceph/ceph.client.admin.keyring"

  local localScriptPath
  localScriptPath="$(realpath "$0")"
  local remoteScriptName="CephScrubScheduler-remote.sh"
  echo "Copying this script to remote as /tmp/${remoteScriptName} ..."
  __scp_send__ \
    "${connection_flags[@]}" \
    --source "$localScriptPath" \
    --destination "/tmp/${remoteScriptName}"

  printf -v remoteInstallCmd 'bash /tmp/%s local install "%s" "%s" "%s"' \
    "$remoteScriptName" "$poolName" "$scheduleType" "$scheduleTime"

  echo "Running 'local install' on remote..."
  __ssh_exec__ \
    "${connection_flags[@]}" \
    --sudo \
    --shell bash \
    --command "$remoteInstallCmd"
}

function remote_uninstall() {
  local vmHost="$1"
  local vmUser="$2"
  local vmPass="$3"
  local poolName="$4"

  local -a connection_flags=(--host "$vmHost" --user "$vmUser" --password "$vmPass")

  echo "Uninstalling on remote node '${vmHost}'..."
  __ssh_exec__ \
    "${connection_flags[@]}" \
    --sudo \
    --shell bash \
    --command "bash /tmp/CephScrubScheduler-remote.sh local uninstall \"${poolName}\""

  __ssh_exec__ \
    "${connection_flags[@]}" \
    --sudo \
    --command "rm -f /tmp/CephScrubScheduler-remote.sh"
}

###############################################################################
# MAIN LOGIC
###############################################################################
if [[ $# -lt 2 ]]; then
  usage
fi

case "$SCRIPT_MODE" in
  local)
    case "$ACTION" in
      install)
        if [[ $# -lt 4 ]]; then
          usage
        fi
        POOL_NAME="$3"
        SCHEDULE_TYPE="$4"
        SCHEDULE_TIME="$5"

        local_disable_scrubbing "${POOL_NAME}"
        local_create_scrub_script "${POOL_NAME}"
        local_create_systemd_units "${POOL_NAME}" "${SCHEDULE_TYPE}" "${SCHEDULE_TIME}"
        local_enable_and_start_timer "${POOL_NAME}"

        echo
        echo "Scrubbing for pool '${POOL_NAME}' is disabled (intervals set to '${DISABLE_SCRUB_SECONDS}')."
        echo "A systemd timer is configured for manual deep-scrub on schedule [${SCHEDULE_TYPE} ${SCHEDULE_TIME}]."
        ;;
      uninstall)
        if [[ $# -lt 3 ]]; then
          usage
        fi
        POOL_NAME="$3"

        local_remove_systemd_units "${POOL_NAME}"
        local_revert_scrubbing "${POOL_NAME}"

        echo
        echo "Pool '${POOL_NAME}' scrubbing intervals reverted to defaults."
        echo "Systemd service/timer removed."
        ;;
      *)
        usage
        ;;
    esac
    ;;
  remote)
    case "$ACTION" in
      install)
        if [[ $# -lt 6 ]]; then
          usage
        fi

        REMOTE_NODE_NAME="$3"
        VM_USER="$4"
        VM_PASS="$5"
        POOL_NAME="$6"
        SCHEDULE_TYPE="$7"
        SCHEDULE_TIME="$8"

        # Convert node name to IP using Proxmox cluster info
        readarray -t REMOTE_NODE_IPS < <( __get_remote_node_ips__ )
        VM_HOST="$(__get_ip_from_name__ "${REMOTE_NODE_NAME}")"

        # Verify that the IP is recognized in the cluster
        if [[ ! " ${REMOTE_NODE_IPS[@]} " =~ " ${VM_HOST} " ]]; then
          echo "Error: Node '${REMOTE_NODE_NAME}' does not correspond to a valid IP in this cluster."
          exit 1
        fi

        remote_install "${VM_HOST}" "${VM_USER}" "${VM_PASS}" "${POOL_NAME}" "${SCHEDULE_TYPE}" "${SCHEDULE_TIME}"
        ;;
      uninstall)
        if [[ $# -lt 6 ]]; then
          usage
        fi

        REMOTE_NODE_NAME="$3"
        VM_USER="$4"
        VM_PASS="$5"
        POOL_NAME="$6"

        readarray -t REMOTE_NODE_IPS < <( __get_remote_node_ips__ )
        VM_HOST="$(__get_ip_from_name__ "${REMOTE_NODE_NAME}")"

        if [[ ! " ${REMOTE_NODE_IPS[@]} " =~ " ${VM_HOST} " ]]; then
          echo "Error: Node '${REMOTE_NODE_NAME}' does not correspond to a valid IP in this cluster."
          exit 1
        fi

        remote_uninstall "${VM_HOST}" "${VM_USER}" "${VM_PASS}" "${POOL_NAME}"
        ;;
      *)
        usage
        ;;
    esac
    ;;
  *)
    usage
    ;;
esac

__prompt_keep_installed_packages__
