#!/bin/bash
#
# DellServerFanControl.sh
#
# Installs or removes a systemd service to control Dell server fans via IPMI.
# By default, it will prompt for IPMI credentials and temperature/fan thresholds,
# store them in /etc/dell_fan_control.conf, and create a background control script.
#
# Usage:
#   DellServerFanControl.sh install
#   DellServerFanControl.sh remove
#
# Examples:
#   # Install all components and enable the service
#   DellServerFanControl.sh install
#
#   # Remove everything (service, config, run script)
#   DellServerFanControl.sh remove
#
# This script requires IPMI utilities, which will be installed if missing.
#
# Function Index:
#   - prompt_user_config
#   - create_run_script
#   - enable_fan_control
#   - set_fan_speed
#   - get_temperatures
#   - calculate_fan_speed
#   - main_loop
#   - create_systemd_service
#   - enable_and_start_service
#   - remove_service_and_files
#   - show_usage
#

set -euo pipefail

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Global Variables
###############################################################################
CONFIG_FILE="/etc/dell_fan_control.conf"
SERVICE_FILE="/etc/systemd/system/DellServerFanControl.service"
RUN_SCRIPT="/usr/bin/DellServerFanControl-run.sh"

###############################################################################
# User Configuration Prompt
###############################################################################
prompt_user_config() {
    echo "Enter the IPMI host (IP or hostname):"
    read -r ipmiHost

    echo "Enter the IPMI username:"
    read -r ipmiUser

    echo "Enter the IPMI password:"
    read -r ipmiPass

    echo "Enter MIN temperature (e.g., 30):"
    read -r minTemp

    echo "Enter MAX temperature (e.g., 75):"
    read -r maxTemp

    echo "Enter MIN fan speed in percent (e.g., 10):"
    read -r minFanSpeed

    echo "Enter MAX fan speed in percent (e.g., 100):"
    read -r maxFanSpeed

    cat <<EOF > "${CONFIG_FILE}"
IPMI_HOST="${ipmiHost}"
IPMI_USER="${ipmiUser}"
IPMI_PASS="${ipmiPass}"
MIN_TEMP=${minTemp}
MAX_TEMP=${maxTemp}
MIN_FAN_SPEED=${minFanSpeed}
MAX_FAN_SPEED=${maxFanSpeed}
EOF

    chmod 600 "${CONFIG_FILE}"
    echo "Saved configuration to \"${CONFIG_FILE}\""
}

###############################################################################
# Create Background Run Script
###############################################################################
create_run_script() {
    echo "Creating background run script at \"${RUN_SCRIPT}\" ..."
    cat <<'EOF' > "${RUN_SCRIPT}"
#!/bin/bash
#
# /usr/bin/DellServerFanControl-run.sh
#
# This script runs in the background (invoked by systemd) to control Dell server fans via IPMI.
# It loads the config from /etc/dell_fan_control.conf, monitors CPU temps (0Eh, 0Fh),
# and sets fan speeds accordingly.

CONFIG_FILE="/etc/dell_fan_control.conf"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Error: \"${CONFIG_FILE}\" not found!"
    exit 1
fi
# shellcheck disable=SC1091
source "${CONFIG_FILE}"

enable_fan_control() {
    ipmitool -I lanplus -H "${IPMI_HOST}" -U "${IPMI_USER}" -P "${IPMI_PASS}" raw 0x30 0x30 0x01 0x00
}

set_fan_speed() {
    local percentage="$1"
    local raw_speed
    raw_speed=$(awk -v p="${percentage}" 'BEGIN { printf "%.0f", p*2.55 }')
    local hex_speed
    hex_speed=$(printf "%02x" "${raw_speed}")

    echo "   => Setting fan speed to ${percentage}% (0x${hex_speed})"
    ipmitool -I lanplus -H "${IPMI_HOST}" -U "${IPMI_USER}" -P "${IPMI_PASS}" raw 0x30 0x30 0x02 0xff "0x${hex_speed}"
}

get_temperatures() {
    local output
    output=$(ipmitool -I lanplus -H "${IPMI_HOST}" -U "${IPMI_USER}" -P "${IPMI_PASS}" sdr type temperature || true)

    CPU1_TEMP=""
    CPU2_TEMP=""
    while IFS= read -r line; do
        if [[ "${line}" =~ "0Eh" && "${line}" =~ "degrees C" ]]; then
            CPU1_TEMP=$(echo "${line}" | awk -F'|' '{print $5}' | awk '{print $1}')
        elif [[ "${line}" =~ "0Fh" && "${line}" =~ "degrees C" ]]; then
            CPU2_TEMP=$(echo "${line}" | awk -F'|' '{print $5}' | awk '{print $1}')
        fi
    done <<< "${output}"
}

calculate_fan_speed() {
    local temperature="$1"

    if (( $(awk -v t="${temperature}" -v m="${MIN_TEMP}" 'BEGIN{print (t <= m)}') )); then
        echo "${MIN_FAN_SPEED}"
        return
    fi

    if (( $(awk -v t="${temperature}" -v M="${MAX_TEMP}" 'BEGIN{print (t >= M)}') )); then
        echo "${MAX_FAN_SPEED}"
        return
    fi

    local slope
    slope=$(awk -v minf="${MIN_FAN_SPEED}" -v maxf="${MAX_FAN_SPEED}" -v mint="${MIN_TEMP}" -v maxt="${MAX_TEMP}" '
        BEGIN {
            if ((maxt - mint) == 0) {
                print 0
            } else {
                print (maxf - minf) / (maxt - mint)
            }
        }
    ')

    local fan_speed
    fan_speed=$(awk -v slope="${slope}" -v minf="${MIN_FAN_SPEED}" -v t="${temperature}" -v mint="${MIN_TEMP}" '
        BEGIN {
            print minf + slope * (t - mint)
        }
    ')

    fan_speed=$(awk -v fs="${fan_speed}" 'BEGIN { printf "%.0f", fs }')
    echo "${fan_speed}"
}

main_loop() {
    enable_fan_control
    local start_time
    start_time=$(date +%s)

    while true; do
        local now
        now=$(date +%s)
        local elapsed=$((now - start_time))

        if (( elapsed >= 86400 )); then
            echo "24 hours elapsed; restarting..."
            exec "$0"
        fi

        get_temperatures
        if [[ -z "${CPU1_TEMP}" || -z "${CPU2_TEMP}" ]]; then
            echo "Error: Could not read CPU temps. Sleeping 60s..."
            sleep 60
            continue
        fi

        local max_temp
        max_temp=$(awk -v c1="${CPU1_TEMP}" -v c2="${CPU2_TEMP}" 'BEGIN { if (c1 > c2) print c1; else print c2 }')
        local fan_speed
        fan_speed=$(calculate_fan_speed "${max_temp}")

        echo "CPU1: ${CPU1_TEMP}C, CPU2: ${CPU2_TEMP}C => Fan: ${fan_speed}%"
        set_fan_speed "${fan_speed}"

        sleep 3
    done
}

main_loop
EOF

    chmod +x "${RUN_SCRIPT}"
    echo "Created \"${RUN_SCRIPT}\""
}

###############################################################################
# Create Systemd Service
###############################################################################
create_systemd_service() {
    echo "Creating systemd service at \"${SERVICE_FILE}\" ..."
    cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=Dell Server Fan Control Service
After=network.target

[Service]
Type=simple
ExecStart=${RUN_SCRIPT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

###############################################################################
# Enable and Start Systemd Service
###############################################################################
enable_and_start_service() {
    systemctl daemon-reload
    systemctl enable DellServerFanControl.service
    systemctl start DellServerFanControl.service
    echo "Service \"DellServerFanControl.service\" enabled and started."
}

###############################################################################
# Remove Service and Files
###############################################################################
remove_service_and_files() {
    echo "Stopping and disabling \"DellServerFanControl.service\"..."
    systemctl stop DellServerFanControl.service 2>/dev/null || true
    systemctl disable DellServerFanControl.service 2>/dev/null || true

    echo "Removing \"${SERVICE_FILE}\"..."
    rm -f "${SERVICE_FILE}"

    echo "Removing \"${CONFIG_FILE}\"..."
    rm -f "${CONFIG_FILE}"

    echo "Removing \"${RUN_SCRIPT}\"..."
    rm -f "${RUN_SCRIPT}"

    systemctl daemon-reload
    echo "DellServerFanControl removed."
}

###############################################################################
# Show Usage
###############################################################################
show_usage() {
    echo "Usage: \"${0}\" <install|remove>"
    echo "  install - Install prerequisites, prompt for config, create run script & service."
    echo "  remove  - Remove service, config, and run script."
}

###############################################################################
# Main
###############################################################################
case "$1" in
    install)
        __check_root__          # Ensure script is run as root
        __check_proxmox__       # Ensure we are on a Proxmox node
        __install_or_prompt__ "ipmitool"
        prompt_user_config
        create_run_script
        create_systemd_service
        enable_and_start_service
        __prompt_keep_installed_packages__
        ;;
    remove)
        __check_root__
        __check_proxmox__
        remove_service_and_files
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
