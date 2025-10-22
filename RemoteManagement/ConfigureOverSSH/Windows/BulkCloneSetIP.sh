#!/bin/bash
#
# BulkCloneSetIPWindows.sh
#
# Clones a Windows VM multiple times on a Proxmox server, updates each clone's
# IPv4 address (including CIDR notation), sets a new default gateway, and
# configures DNS. The script accomplishes this by uploading a ChangeIP.bat file
# to the Windows VM, then starting it in the background via "start /b".
#
# Usage:
#   ./BulkCloneSetIPWindows.sh <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId> <sshUsername> <sshPassword> <vmNamePrefix> <interfaceName> <dns1> <dns2>
#
# Example:
#   ./BulkCloneSetIPWindows.sh 192.168.1.50 192.168.1.10/24 192.168.1.1 5 9000 9010 Administrator Passw0rd WinClone- "Ethernet" 8.8.8.8 8.8.4.4
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/SSH.sh"
source "${UTILITYPATH}/Conversion.sh"

###############################################################################
# Check prerequisites and parse arguments
###############################################################################

__check_root__
__check_proxmox__
__ensure_dependencies__ sshpass

###############################################################################
# Argument Parsing
###############################################################################
if [ "$#" -lt 12 ]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId> <sshUsername> <sshPassword> <vmNamePrefix> <interfaceName> <dns1> <dns2>"
  exit 1
fi

templateIpAddr="$1"
startIpCidr="$2"
newGateway="$3"
instanceCount="$4"
templateId="$5"
baseVmId="$6"
sshUsername="$7"
sshPassword="$8"
vmNamePrefix="$9"
interfaceName="${10}"
# Strip quotes from interfaceName if present
interfaceName="${interfaceName//\"/}"
dns1="${11}"
dns2="${12}"

IFS='/' read -r startIpAddrOnly startMask <<<"$startIpCidr"
ipInt="$(__ip_to_int__ "$startIpAddrOnly")"
netmask="$(__cidr_to_netmask__ "$startMask")"

###############################################################################
# Create a temporary .bat file with netsh commands for Windows IP reconfiguration
###############################################################################
tempBat="/tmp/ChangeIP.bat.$$"
cat <<'EOF' > "$tempBat"
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

ssh-keygen -f "/root/.ssh/known_hosts" -R "${templateIpAddr}"

remoteBatPath="C:/Users/${sshUsername}/ChangeIP.bat"
remoteBatPathCmd="C:\\Users\\${sshUsername}\\ChangeIP.bat"

###############################################################################
# Main logic: Clone and configure Windows VMs
###############################################################################
for (( i=0; i<instanceCount; i++ )); do
  currentVmId=$((baseVmId + i))
  currentIp="$(__int_to_ip__ "$ipInt")"

  ssh-keygen -f "/root/.ssh/known_hosts" -R "${currentIp}"

  echo "Cloning VM ID \"$templateId\" to new VM ID \"$currentVmId\" with IP \"$currentIp/$startMask\"..."
  qm clone "$templateId" "$currentVmId" --name "${vmNamePrefix}${currentVmId}"
  qm start "$currentVmId"

  echo "Waiting for SSH on template IP: \"$templateIpAddr\"..."
  __wait_for_ssh__ "$templateIpAddr" "$sshUsername" "$sshPassword"

  echo "Uploading 'ChangeIP.bat' to Windows VM..."
  __scp_send__ \
    --host "$templateIpAddr" \
    --user "$sshUsername" \
    --password "$sshPassword" \
    --source "$tempBat" \
    --destination "$remoteBatPath"

  echo "Starting IP change script in the background via 'start /b'..."
  echo "DEBUG: interfaceName='${interfaceName}' currentIp='${currentIp}' netmask='${netmask}' newGateway='${newGateway}' dns1='${dns1}' dns2='${dns2}'"
<<<<<<< HEAD
  remoteCmd="cmd /c \"${remoteBatPathCmd} \\\"${interfaceName}\\\" ${currentIp} ${netmask} ${newGateway} ${dns1} ${dns2}\""
=======
  remoteCmd="cmd /c \"${remoteBatPathCmd} ${interfaceName} ${currentIp} ${netmask} ${newGateway} ${dns1} ${dns2}\""
>>>>>>> 16697ce890883a184393ebd5f5c010e656434138
  echo "DEBUG: remoteCmd='${remoteCmd}'"

  __ssh_exec__ \
    --host "$templateIpAddr" \
    --user "$sshUsername" \
    --password "$sshPassword" \
    --extra-ssh-arg "-o ServerAliveInterval=3" \
    --extra-ssh-arg "-o ServerAliveCountMax=1" \
    --command "$remoteCmd" || true

  echo "Waiting for new IP \"$currentIp\" to become reachable via SSH..."
  __wait_for_ssh__ "$currentIp" "$sshUsername" "$sshPassword"

  ipInt=$(( ipInt + 1 ))
done

rm -f "$tempBat"
__prompt_keep_installed_packages__
