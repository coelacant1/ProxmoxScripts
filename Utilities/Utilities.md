# Utility Functions Quick Description and Usage

__check_root__
- Checks if the script is run as root, otherwise exits.
- Example usage: __check_root__
- Example output: Error: This script must be run as root (sudo).

__check_proxmox__
- Checks if the environment is a Proxmox node, otherwise exits.
- Example usage: __check_proxmox__
- Example output: Error: 'pveversion' command not found. Are you sure this is a Proxmox node?

__install_or_prompt__
- Checks if a command is available; if missing, prompts to install or exits if declined.
- Example usage: __install_or_prompt__ "curl"
- Example output: The 'curl' utility is required but is not installed. Would you like to install 'curl' now? [y/N]:

__prompt_keep_installed_packages__
- Prompts whether to keep or remove packages installed during this session.
- Example usage: __prompt_keep_installed_packages__
- Example output: The following packages were installed during this session: ... Do you want to KEEP these packages? [Y/n]:

__get_remote_node_ips__
- Lists IP addresses for remote nodes in the Proxmox cluster.
- Example usage: readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )
- Example output: 172.20.83.22 (newline) 172.20.83.23 ...

__check_cluster_membership__
- Verifies if the node is part of a Proxmox cluster, otherwise exits.
- Example usage: __check_cluster_membership__
- Example output: Node is in a cluster named: MyClusterName

__get_number_of_cluster_nodes__
- Returns the total number of nodes in the Proxmox cluster.
- Example usage: __get_number_of_cluster_nodes__
- Example output: 3

__ip_to_int__
- Converts a dotted IPv4 address to its 32-bit integer representation.
- Example usage: __ip_to_int__ "192.168.0.1"
- Example output: 3232235521

__int_to_ip__
- Converts a 32-bit integer back into a dotted IPv4 address.
- Example usage: __int_to_ip__ 3232235521
- Example output: 192.168.0.1

__init_node_mappings__
- Builds internal mappings (node ID ↔ IP ↔ name) from cluster status.
- Example usage: __init_node_mappings__
- Example output: (No direct output; arrays are populated internally.)

__get_ip_from_name__
- Given a node name, prints its IP or exits if not found.
- Example usage: __get_ip_from_name__ "IHK03"
- Example output: 172.20.83.23

__get_name_from_ip__
- Given a node IP, prints its node name or exits if not found.
- Example usage: __get_name_from_ip__ "172.20.83.23"
- Example output: IHK03

__get_cluster_lxc__
- Lists VMIDs of all LXC containers in the entire cluster.
- Example usage: readarray -t ALL_CLUSTER_LXC < <( __get_cluster_lxc__ )
- Example output: 101 (newline) 102 ...

__get_server_lxc__
- Lists VMIDs of LXC containers on a specific Proxmox server.
- Example usage: readarray -t NODE_LXC < <( __get_server_lxc__ "local" )
- Example output: 201 (newline) 202 ...

__get_cluster_vms__
- Lists VMIDs of all QEMU VMs in the entire cluster.
- Example usage: readarray -t ALL_CLUSTER_VMS < <( __get_cluster_vms__ )
- Example output: 300 (newline) 301 ...

__get_server_vms__
- Lists VMIDs of QEMU VMs on a specific Proxmox server.
- Example usage: readarray -t NODE_VMS < <( __get_server_vms__ "local" )
- Example output: 401 (newline) 402 ...