#!/bin/bash
#
# BulkCloneSetIP_Windows.sh
#
# Clones a Windows VM multiple times on a Proxmox server, updates each clone's
# IPv4 address (including CIDR notation), sets a new default gateway, and
# configures DNS. The script accomplishes this by uploading a ChangeIP.bat file
# to the Windows VM, then starting it in the background via "start /b".
#
# Usage:
#   BulkCloneSetIPWindows.sh <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId> <sshUsername> <sshPassword> <vmNamePrefix> <interfaceName> <dns1> <dns2>
#
# Example:
#   BulkCloneSetIPWindows.sh 192.168.1.50 192.168.1.10/24 192.168.1.1 5 9000 9010 Administrator Passw0rd WinClone- "Ethernet" 8.8.8.8 8.8.4.4
#
# Function Index:
#   - main
#

# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/SSH.sh
source "${UTILITYPATH}/SSH.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Conversion.sh
source "${UTILITYPATH}/Conversion.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "template_ip:ip start_ip_cidr:string new_gateway:ip count:number template_id:vmid base_vm_id:vmid ssh_username:string ssh_password:string vm_name_prefix:string interface_name:string dns1:ip dns2:ip" "$@"

###############################################################################
# Check prerequisites
###############################################################################
__check_root__
__check_proxmox__
__ensure_dependencies__ sshpass

# Strip quotes from interface name if present
INTERFACE_NAME="${INTERFACE_NAME//\"/}"

IFS='/' read -r startIpAddrOnly startMask <<<"$START_IP_CIDR"
ipInt="$(__ip_to_int__ "$startIpAddrOnly")"
netmask="$(__cidr_to_netmask__ "$startMask")"

###############################################################################
# Create a temporary .bat file with netsh commands for Windows IP reconfiguration
###############################################################################
tempBat="/tmp/ChangeIP.bat.$$"
cat <<'EOF' >"$tempBat"
@echo off
:: ChangeIP.bat
:: Usage: ChangeIP.bat <InterfaceName> <NewIP> <Netmask> <Gateway> <DNS1> <DNS2>

::if "%~6"=="" (
::  echo Usage: %~nx0 InterfaceName NewIP Netmask Gateway DNS1 DNS2
::   exit /b 1
::)

set IFACE=%1
set NEWIP=%2
set NETMASK=%3
set GATEWAY=%4
set DNS1=%5
set DNS2=%6

echo Changing IP of interface [%IFACE%] to %NEWIP%/%NETMASK% gateway=%GATEWAY%
ping 127.0.0.1 -n 4 >nul
netsh interface ip set address name="%IFACE%" static %NEWIP% %NETMASK% %GATEWAY% 1

echo Setting DNS to %DNS1% (primary) and %DNS2% (secondary)
netsh interface ip set dns name="%IFACE%" static %DNS1% primary
netsh interface ip add dns name="%IFACE%" %DNS2% index=2
EOF

ssh-keygen -f "/root/.ssh/known_hosts" -R "${TEMPLATE_IP}"

remoteBatPath="C:/Users/${SSH_USERNAME}/ChangeIP.bat"
remoteBatPathCmd="C:\\Users\\${SSH_USERNAME}\\ChangeIP.bat"

###############################################################################
# Main logic: Clone and configure Windows VMs
###############################################################################
main() {
    for ((i = 0; i < COUNT; i++)); do
        currentVmId=$((BASE_VM_ID + i))
        currentIp="$(__int_to_ip__ "$ipInt")"

    ssh-keygen -f "/root/.ssh/known_hosts" -R "${currentIp}"

    echo "Cloning VM ID \"$TEMPLATE_ID\" to new VM ID \"$currentVmId\" with IP \"$currentIp/$startMask\"..."
    qm clone "$TEMPLATE_ID" "$currentVmId" --name "${VM_NAME_PREFIX}${currentVmId}"
    qm start "$currentVmId"

    echo "Waiting for SSH on template IP: \"$TEMPLATE_IP\"..."
    __wait_for_ssh__ "$TEMPLATE_IP" "$SSH_USERNAME" "$SSH_PASSWORD"

    echo "Uploading 'ChangeIP.bat' to Windows VM..."
    __scp_send__ \
        --host "$TEMPLATE_IP" \
        --user "$SSH_USERNAME" \
        --password "$SSH_PASSWORD" \
        --source "$tempBat" \
        --destination "$remoteBatPath"

    echo "Starting IP change script in the background via 'start /b'..."
    echo "DEBUG: interfaceName='${INTERFACE_NAME}' currentIp='${currentIp}' netmask='${netmask}' newGateway='${NEW_GATEWAY}' dns1='${DNS1}' dns2='${DNS2}'"
    remoteCmd="cmd /c \"${remoteBatPathCmd} ${INTERFACE_NAME} ${currentIp} ${netmask} ${NEW_GATEWAY} ${DNS1} ${DNS2}\""
    echo "DEBUG: remoteCmd='${remoteCmd}'"

    __ssh_exec__ \
        --host "$TEMPLATE_IP" \
        --user "$SSH_USERNAME" \
        --password "$SSH_PASSWORD" \
        --extra-ssh-arg "-o ServerAliveInterval=3" \
        --extra-ssh-arg "-o ServerAliveCountMax=1" \
        --command "$remoteCmd" || true

    echo "Waiting for new IP \"$currentIp\" to become reachable via SSH..."
    __wait_for_ssh__ "$currentIp" "$SSH_USERNAME" "$SSH_PASSWORD"

        ipInt=$((ipInt + 1))
    done

    rm -f "$tempBat"
    __prompt_keep_installed_packages__
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Fixed script name in header to match filename
# - 2025-11-24: Refactored main logic into main() function
# - 2025-11-24: Fixed variable name mismatches (COUNT, BASE_VM_ID)
# - 2025-11-20: ArgumentParser.sh sourced
# - 2025-11-20: Pending validation
# - 2025-11-20: Updated to use ArgumentParser.sh
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

