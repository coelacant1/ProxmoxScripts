#!/bin/bash
#
# BulkAddRDPConnectionGuacamole.sh
#
# Creates multiple RDP connections in Apache Guacamole for a consecutive range of
# Proxmox VMs. It uses the VMID range [START_VMID..END_VMID], retrieves each VM’s
# IP, and uses the VM’s name as the Guacamole connection name.
#
# Usage:
#   BulkAddRDPConnectionGuacamole.sh GUAC_SERVER_URL START_VMID END_VMID GUAC_RDP_USER GUAC_RDP_PASS
#
# Example:
#   BulkAddRDPConnectionGuacamole.sh "http://guac.example.com:8080/guacamole" 100 110 "myRdpUser" "myRdpPass"
#
# Notes:
#   - This script expects a valid Guacamole auth token in /tmp/cc_pve/guac_token.
#   - Run GetGuacToken.sh beforehand to store the auth token for the Guacamole server.
#   - If your Guacamole server uses a data source named something other than the first
#     returned, you may need to adapt the logic below where we pick the first data source.
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Discovery.sh
source "${UTILITYPATH}/Discovery.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "guac_url:url start_vmid:vmid end_vmid:vmid guac_rdp_user:string guac_rdp_pass:string guac_data_source:string:mysql" "$@"

__check_root__
__check_proxmox__
__install_or_prompt__ "jq"
__install_or_prompt__ "arp-scan"

if [[ ! -f "/tmp/cc_pve/guac_token" ]]; then
    echo "Error: No Guacamole auth token found in /tmp/cc_pve/guac_token."
    echo "Please run GetGuacToken.sh first."
    exit 1
fi

AUTH_TOKEN="$(cat /tmp/cc_pve/guac_token)"

# --- main --------------------------------------------------------------------
main() {
    __info__ "Using data source: '$GUAC_DATA_SOURCE'"
    __info__ "Creating RDP connections for VMs $START_VMID to $END_VMID"

    local created=0
    local failed=0

    for ((vmid = START_VMID; vmid <= END_VMID; vmid++)); do
        __update__ "Processing VM $vmid..."

        local vm_ip
        vm_ip="$(__get_ip_from_vmid__ "$vmid" 2>/dev/null)"

        if [[ -z "$vm_ip" ]]; then
            __warn__ "Could not retrieve IP for VM $vmid. Skipping."
            ((failed++))
            continue
        fi

        local vm_name
        vm_name="$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
            | jq -r --arg VMID "$vmid" '.[] | select(.vmid == ($VMID|tonumber)) | .name')"

        if [[ -z "$vm_name" || "$vm_name" == "null" ]]; then
            vm_name="VM-$vmid"
        fi

        local create_payload
        create_payload="$(
            jq -n \
                --arg NAME "${vm_name}" \
                --arg HOST "$vm_ip" \
                --arg PORT "3389" \
                --arg USER "$RDP_USER" \
                --arg PASS "$RDP_PASS" \
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

        local response
        response="$(
            curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "$create_payload" \
                "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connections?token=${auth_token}"
        )"

        local conn_id
        conn_id="$(echo "$response" | jq -r '.identifier // empty')"

        if [[ -n "$conn_id" ]]; then
            __ok__ "Created connection for VM $vmid (Name: $vm_name, IP: $vm_ip, ID: $conn_id)"
            ((created++))
        else
            __warn__ "Failed to create connection for VM $vmid. Response: $response"
            ((failed++))
        fi
    done

    __info__ "Created: $created, Failed: $failed"
    __prompt_keep_installed_packages__

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "All RDP connections created successfully"
}

main

# Testing status:
#   - Pending validation

# Testing status:
#   - ArgumentParser.sh sourced
#   - Updated to use ArgumentParser.sh
#   - Pending validation
