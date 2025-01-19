#!/bin/bash
#
# HostIPerfTest.sh
#
# Automates an Iperf throughput test between two specified hosts, allowing you
# to define which is the server and which is the client by hostname.
#
# Usage:
#   ./HostIPerfTest.sh <server_host> <client_host> <port>
#
# Example:
#   ./HostIPerfTest.sh 192.168.1.10 192.168.1.11 5001
#
# This script will:
#   1. Ensure iperf3 is installed locally on Proxmox.
#   2. Start an iperf3 server on the specified server host using SSH.
#   3. Run the iperf3 client on the specified client host to display throughput results.
#   4. Kill the iperf3 server process automatically upon completion.
#   5. Prompt whether to keep or remove any newly installed packages.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Preliminary Checks
###############################################################################
__check_root__
__check_proxmox__

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <server_host> <client_host> <port>"
  exit 1
fi

###############################################################################
# Argument Parsing
###############################################################################
serverHost="$1"
clientHost="$2"
port="$3"

###############################################################################
# Iperf Installation Check
###############################################################################
__install_or_prompt__ "iperf3"

###############################################################################
# Start Iperf Server on Server Host
###############################################################################
echo "Starting iperf3 server on '${serverHost}'..."
ssh "root@${serverHost}" "pkill -f 'iperf3 -s' || true"
ssh "root@${serverHost}" "iperf3 -s -p '${port}' &"

echo "Waiting 5 seconds for the iperf3 server to be ready..."
sleep 5

###############################################################################
# Run Iperf Client on Client Host
###############################################################################
echo "Running iperf3 client on '${clientHost}' connecting to '${serverHost}'..."
ssh "root@${clientHost}" "iperf3 -c '${serverHost}' -p '${port}' -t 10"

###############################################################################
# Kill Iperf Server
###############################################################################
echo "Stopping iperf3 server on '${serverHost}'..."
ssh "root@${serverHost}" "pkill -f 'iperf3 -s'"

echo "Iperf test completed successfully."

###############################################################################
# Prompt to Keep or Remove Packages
###############################################################################
__prompt_keep_installed_packages__
