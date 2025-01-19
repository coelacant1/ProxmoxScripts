#!/bin/bash
#
# This script automates the process of cloning virtual machines (VMs) within a Proxmox VE environment. It clones a source VM into
# a specified number of new VMs, assigning them unique IDs, names based on a user-provided base name, and assigns cloud-init IP addresses. 
# Adding cloned VMs to a designated pool is optional. This script is particularly useful for quickly deploying multiple VMs based on a 
# standardized configuration.
#
# Usage:
# ./BulkCloneCloudInit.sh <source_vm_id> <base_vm_name> <start_vm_id> <num_vms> <start_ip/cidr> <bridge> [gateway] [pool_name]
#
# Arguments:
#   source_vm_id - The ID of the VM that will be cloned.
#   base_vm_name - The base name for the new VMs, which will be appended with a numerical index.
#   start_vm_id - The starting VM ID for the first clone.
#   num_vms - The number of VMs to clone.
#   start_ip/cidr - The new IP address and subnet mask of the VM
#   bridge - The network bridge to be used for the cloned VMs.
#   gateway - Optional. The gateway for the IP configuration
#   pool_name - Optional. The name of the pool to which the new VMs will be added. If not provided, VMs are not added to any pool.
#
# Example:
#   ./BulkCloneCloudInit.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0 192.168.1.1 PoolName
#   ./BulkCloneCloudInit.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0 # Without specifying a gateway or pool
#
# Function Index:
#   - __ip_to_int__
#   - __int_to_ip__
#

# Check if the minimum required parameters are provided
if [ "$#" -lt 6 ]; then
    echo "Usage: $0 <source_vm_id> <base_vm_name> <start_vm_id> <num_vms> <start_ip/cidr> <bridge> [gateway] [pool_name]"
    exit 1
fi

# Assigning input arguments
SOURCE_VM_ID=$1
BASE_VM_NAME=$2
START_VM_ID=$3
NUM_VMS=$4
START_IP_CIDR=$5
BRIDGE=$6  # Network bridge, required
GATEWAY=${7:-}  # Optional gateway, default to an empty string if not provided
POOL_NAME=${8:-}  # Optional pool name, default to an empty string if not provided

# Extract the IP address and CIDR from the start_ip/cidr
IFS='/' read -r START_IP SUBNET_MASK <<< "$START_IP_CIDR"

# Convert IP address to an integer
__ip_to_int__() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    echo "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
}

# Convert integer to IP address
__int_to_ip__() {
    local ip
    ip=$(printf "%d.%d.%d.%d" "$((($1 >> 24) & 255))" "$((($1 >> 16) & 255))" "$((($1 >> 8) & 255))" "$((($1 & 255))")
    echo "$ip"
}

# Get the starting IP as an integer
START_IP_INT=$(__ip_to_int__ "$START_IP")

# Loop to create clones
for (( i=0; i<$NUM_VMS; i++ )); do
    TARGET_VM_ID=$((START_VM_ID + i))
    NAME_INDEX=$((i + 1))
    VM_NAME="${BASE_VM_NAME}${NAME_INDEX}"

    # Increment the IP address
    CURRENT_IP_INT=$((START_IP_INT + i))
    NEW_IP=$(__int_to_ip__ "$CURRENT_IP_INT")

    # Clone the VM and set the constructed name
    qm clone $SOURCE_VM_ID $TARGET_VM_ID --name $VM_NAME

    # Set the static IP, subnet mask, and gateway using Cloud-Init
    qm set $TARGET_VM_ID --ipconfig0 ip=${NEW_IP}/${SUBNET_MASK},gw=${GATEWAY}

    # Set the network bridge
    qm set $TARGET_VM_ID --net0 virtio,bridge=$BRIDGE

    # Check if a pool name was provided and add VM to the pool if it was
    if [ -n "$POOL_NAME" ]; then
        qm set $TARGET_VM_ID --pool $POOL_NAME
    fi

done

echo "Cloning completed!"