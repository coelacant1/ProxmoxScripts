#!/bin/bash
#
# BulkAddRDPConnectionGuacamole.sh
#
# Creates multiple RDP connections in Apache Guacamole for a consecutive range of
# Proxmox VMs. It uses the VMID range [START_VMID..END_VMID], retrieves each VM’s
# IP, and uses the VM’s name as the Guacamole connection name.
#
# Usage:
#   ./BulkAddRDPConnectionGuacamole.sh GUAC_SERVER_URL START_VMID END_VMID GUAC_RDP_USER GUAC_RDP_PASS
#
# Example:
#   ./BulkAddRDPConnectionGuacamole.sh "http://guac.example.com:8080/guacamole" 100 110 "myRdpUser" "myRdpPass"
#
# Notes:
#   - This script expects a valid Guacamole auth token in /tmp/cc_pve/guac_token.
#   - Run GetGuacToken.sh beforehand to store the auth token for the Guacamole server.
#   - If your Guacamole server uses a data source named something other than the first
#     returned, you may need to adapt the logic below where we pick the first data source.
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

__check_root__
__check_proxmox__
__install_or_prompt__ "jq"
__install_or_prompt__ "arp-scan"

GUAC_URL="$1"
START_VMID="$2"
END_VMID="$3"
GUAC_RDP_USER="$4"
GUAC_RDP_PASS="$5"
# If no 6th argument is given, default to "mysql"
GUAC_DATA_SOURCE="${6:-mysql}"

if [[ -z "$GUAC_URL" || -z "$START_VMID" || -z "$END_VMID" || -z "$GUAC_RDP_USER" || -z "$GUAC_RDP_PASS" ]]; then
    echo "Error: Missing required arguments."
    echo "Usage: $0 GUAC_SERVER_URL START_VMID END_VMID GUAC_RDP_USER GUAC_RDP_PASS [DATA_SOURCE]"
    exit 1
fi

if [[ ! -f "/tmp/cc_pve/guac_token" ]]; then
    echo "Error: No Guacamole auth token found in /tmp/cc_pve/guac_token."
    echo "Please run GetGuacToken.sh first."
    exit 1
fi

AUTH_TOKEN="$(cat /tmp/cc_pve/guac_token)"

echo "Using data source: '$GUAC_DATA_SOURCE'"

###############################################################################
# Main Logic
###############################################################################
for ((vmid = "$START_VMID"; vmid <= "$END_VMID"; vmid++)); do

    # Get IP from VMID (requires __get_ip_from_vmid__ in sourced Queries.sh)
    vmIp="$(__get_ip_from_vmid__ "$vmid" 2>/dev/null)"
    if [[ -z "$vmIp" ]]; then
        echo "Skipping VMID '$vmid': Could not retrieve IP."
        continue
    fi

    # Get VM name from Proxmox
    vmName="$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null |
        jq -r --arg VMID "$vmid" '.[] | select(.vmid == ($VMID|tonumber)) | .name')"

    if [[ -z "$vmName" || "$vmName" == "null" ]]; then
        vmName="VM-$vmid"
    fi

    # Build JSON payload to create an RDP connection
    createPayload="$(
        jq -n \
        --arg NAME "${vmName}" \
        --arg HOST "$vmIp" \
        --arg PORT "3389" \
        --arg USER "$GUAC_RDP_USER" \
        --arg PASS "$GUAC_RDP_PASS" \
        '{
            "parentIdentifier": "ROOT",
            "name": $NAME,
            "protocol": "rdp",
            "parameters": {
            "hostname": $HOST,
            "port": $PORT,
            "username": $USER,
            "password": $PASS,
            "security": "any",
            "ignore-cert": "true"
            },
            "attributes": {
                "max-connections": "",
                "max-connections-per-user": "",
                "weight": "",
                "failover-only": "",
                "guacd-port": "",
                "guacd-encryption": "",
                "guacd-hostname": ""
            }
        }'
    )"

    response="$(
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$createPayload" \
            "${GUAC_URL}/api/session/data/${GUAC_DATA_SOURCE}/connections?token=${AUTH_TOKEN}"
    )"

    connId="$(echo "$response" | jq -r '.identifier // empty')"
    if [[ -n "$connId" ]]; then
        echo "Created Guac connection for VMID '$vmid' (Name: '$vmName', IP: '$vmIp') with ID '$connId'."
    else
        echo "Error creating connection for VMID '$vmid'. Response: $response"
    fi

done

__prompt_keep_installed_packages__
