# ProxmoxScripts Utility Functions Reference

**Auto-generated documentation** - Last updated: 2025-10-28 12:20:49

---

## Overview

This reference provides comprehensive documentation for all utility functions in the ProxmoxScripts repository. 
These utilities provide reusable functions for building automation scripts, 
management tools, and integration solutions for Proxmox VE environments.

## Utility Files Overview

### ArgumentParser.sh
**Argument parsing and input validation**

Use this when you need to:
- Parse command-line arguments (positional, named, or flags)
- Validate user input (IP addresses, numbers, hostnames, ports, etc.)
- Generate usage/help messages

**Common functions:** `__validate_ip__`, `__validate_numeric__`, `__parse_flag_options__`, `__validate_vmid_range__`

### BulkOperations.sh
**Bulk operations on VM/CT ranges**

Use this when you need to:
- Perform operations on a range of VMs or containers
- Track progress and handle failures
- Generate operation reports and summaries
- Save/resume operation state

**Common functions:** `__bulk_vm_operation__`, `__bulk_ct_operation__`, `__bulk_summary__`, `__bulk_report__`

### Colors.sh
**Terminal color and gradient output**

Use this when you need to:
- Add colored output to scripts
- Create gradient text effects
- Customize terminal formatting

**Note:** For most cases, use `Communication.sh` functions instead.

**Common functions:** `__line_rgb__`, `__line_gradient__`

### Communication.sh
**User feedback and messaging**

Use this when you need to:
- Display progress messages with spinners
- Show success, error, warning, or info messages
- Provide consistent user feedback
- Handle errors with context

**Common functions:** `__info__`, `__ok__`, `__err__`, `__warn__`, `__update__`, `__prompt_user_yn__`

### Conversion.sh
**Data format conversions**

Use this when you need to:
- Convert IP addresses to integers and vice versa
- Convert CIDR notation to netmask
- Generate MAC address prefixes from VMIDs

**Common functions:** `__ip_to_int__`, `__int_to_ip__`, `__cidr_to_netmask__`, `__vmid_to_mac_prefix__`

### Network.sh
**Network configuration and management**

Use this when you need to:
- Configure VM/CT network interfaces
- Set IP addresses, gateways, VLANs
- Test network connectivity
- Bulk network operations across VMs/CTs

**Common functions:** `__net_vm_add_interface__`, `__net_vm_set_vlan__`, `__net_ct_set_ip__`, `__net_test_connectivity__`

### Prompts.sh
**Environment checks and user prompts**

Use this when you need to:
- Check if script is running as root
- Verify Proxmox environment
- Check/install dependencies
- Prompt users for confirmation

**Common functions:** `__check_root__`, `__check_proxmox__`, `__ensure_dependencies__`, `__prompt_user_yn__`

### Operations.sh
**VM and Container operations (MOST COMMONLY USED)**

Use this when you need to:
- Start, stop, restart VMs or containers
- Check if VM/CT exists or is running
- Get or set VM/CT configuration
- Execute commands in containers
- Wait for VM/CT status changes
- Execute cluster-aware commands on correct node

**Common functions:** `__vm_start__`, `__vm_stop__`, `__vm_exists__`, `__vm_is_running__`, `__ct_start__`, `__ct_exec__`

**Remote execution functions:** `__vm_node_exec__`, `__ct_node_exec__`, `__node_exec__`, `__pve_exec__`

**Note:** Use remote execution functions for commands that don't have utility wrappers (e.g., `qm destroy`, `qm unlock`, `pct destroy`).

### Cluster.sh
**Cluster information and VM/CT queries**

Use this when you need to:
- Find which node a VM/CT is on
- Get cluster node information
- List VMs/CTs on specific nodes
- Get VM IP addresses
- Query cluster status

**Common functions:** `__get_vm_node__`, `__get_cluster_vms__`, `get_ip_from_vmid`, `__check_cluster_membership__`

### SSH.sh
**Remote SSH operations**

Use this when you need to:
- Execute commands on remote hosts via SSH
- Transfer files using SCP
- Wait for SSH to become available
- Run scripts or functions remotely

**Common functions:** `__ssh_exec__`, `__scp_send__`, `__wait_for_ssh__`, `__ssh_exec_script__`

### StateManager.sh
**Configuration backup and restore**

Use this when you need to:
- Save VM/CT configuration snapshots
- Restore previous configurations
- Compare configuration changes
- Export/import state data

**Common functions:** `__state_save_vm__`, `__state_restore_vm__`, `__state_list__`, `__state_show_changes__`

---

## Quick Start

```bash
# Source utilities in your script
UTILITYPATH="path/to/Utilities"
source "${UTILITYPATH}/Operations.sh"
source "${UTILITYPATH}/ArgumentParser.sh"

# Use functions directly
__vm_start__ 100
__validate_ip__ "192.168.1.1" "IP Address"
```

## Design Principles

1. **Non-Interactive**: All functions designed for automation (no user prompts during execution)
2. **Consistent Return Codes**: 0 for success, 1 for errors, consistent across all functions
3. **Error Messages to stderr**: All errors written to stderr, data to stdout for easy parsing
4. **Input Validation**: Comprehensive validation with clear error messages
5. **Testability**: Functions can be mocked and tested without Proxmox environment

# Table of Contents
- [Overview](#overview)
- [Quick Start](#quick-start)
- [Design Principles](#design-principles)
- [Utility Files](#utility-files)
  - [ArgumentParser.sh](#argumentparser)
  - [BulkOperations.sh](#bulkoperations)
  - [Colors.sh](#colors)
  - [Communication.sh](#communication)
  - [Conversion.sh](#conversion)
  - [Network.sh](#Network)
  - [Prompts.sh](#prompts)
  - [Operations.sh](#proxmoxapi)
  - [Cluster.sh](#queries)
  - [RunAllTests.sh](#runalltests)
  - [SSH.sh](#ssh)
  - [StateManager.sh](#statemanager)
- [Testing](#testing)
- [Common Patterns](#common-patterns)

# Quick Reference

| Function | File | Purpose |
|----------|------|---------|
| `__bulk_ct_operation__` | BulkOperations | Bulk operation on CTs with existence checking |
| `__bulk_filter__` | BulkOperations | Filter IDs based on a condition function |
| `__bulk_load_state__` | BulkOperations | Load bulk operation state from file |
| `__bulk_operation__` | BulkOperations | Generic bulk operation handler with progress tracking |
| `__bulk_parallel__` | BulkOperations | Execute operations in parallel (experimental) |
| `__bulk_print_results__` | BulkOperations | Print results in machine-readable format |
| `__bulk_report__` | BulkOperations | Print detailed report including failed/skipped IDs |
| `__bulk_save_state__` | BulkOperations | Save bulk operation state to file for resume |
| `__bulk_summary__` | BulkOperations | Print summary of bulk operation results |
| `__bulk_validate_range__` | BulkOperations | Validate that a range is reasonable for bulk operations |
| `__bulk_vm_operation__` | BulkOperations | Bulk operation on VMs with existence checking |
| `__bulk_with_retry__` | BulkOperations | Retry failed operations with configurable attempts |
| `__check_cluster_membership__` | Queries | Checks if the node is recognized as part of a cluster by examining 'pvecm status' |
| `__check_ct_status__` | Queries | Checks if a container is running and optionally stops it with user confirmation |
| `__check_proxmox__` | Prompts | Checks if this is a Proxmox node |
| `__check_root__` | Prompts | Checks if the current user is root |
| `__check_vm_status__` | Queries | Checks if a VM is running and optionally stops it with user confirmation |
| `__cidr_to_netmask__` | Conversion | Converts a CIDR prefix to a dotted-decimal netmask |
| `__ct_exec__` | ProxmoxAPI | Execute command inside a CT |
| `__ct_exists__` | ProxmoxAPI | Check if a CT exists |
| `__ct_get_config__` | ProxmoxAPI | Get CT configuration parameter value |
| `__ct_get_status__` | ProxmoxAPI | Get CT status |
| `__ct_is_running__` | ProxmoxAPI | Check if CT is running |
| `__ct_list_all__` | ProxmoxAPI | List all CTs |
| `__ct_node_exec__` | ProxmoxAPI | Execute a command on the node where a CT is located |
| `__ct_restart__` | ProxmoxAPI | Restart a CT |
| `__ct_set_config__` | ProxmoxAPI | Set CT configuration parameter |
| `__ct_shutdown__` | ProxmoxAPI | Gracefully shutdown a CT |
| `__ct_start__` | ProxmoxAPI | Start a CT |
| `__ct_stop__` | ProxmoxAPI | Stop a CT |
| `__ct_wait_for_status__` | ProxmoxAPI | Wait for CT to reach a specific status |
| `__display_script_info__` | Communication | Displays complete script information with headers and examples in a consistent format |
| `__ensure_dependencies__` | Prompts | Verifies that the specified commands are available; installs them if missing |
| `__err__` | Communication | Stops the spinner and prints an error message in red |
| `__get_cluster_lxc__` | Queries | Retrieves the VMIDs for all LXC containers across the entire cluster |
| `__get_cluster_vms__` | Queries | Retrieves the VMIDs for all VMs (QEMU) across the entire cluster |
| `__get_ct_info__` | ProxmoxAPI | Get comprehensive CT information |
| `__get_ip_from_guest_agent__` | Queries | Attempts to retrieve the first non-loopback IP address reported by the QEMU guest agent for a VM |
| `__get_ip_from_name__` | Queries | Given a node’s name (e |
| `__get_name_from_ip__` | Queries | Given a node’s link0 IP (e |
| `__get_number_of_cluster_nodes__` | Queries | Returns the total number of nodes in the cluster by counting lines matching a numeric ID from `pvecm nodes` |
| `__get_remote_node_ips__` | Queries | Gathers IPs for all cluster nodes (excluding local) from 'pvecm status' |
| `__get_server_lxc__` | Queries | Retrieves the VMIDs for all LXC containers on a specific server |
| `__get_server_vms__` | Queries | Retrieves the VMIDs for all VMs (QEMU) on a specific server |
| `__get_vm_info__` | ProxmoxAPI | Get comprehensive VM information |
| `__get_vm_node__` | Queries | Gets the node name where a specific VM is located in the cluster |
| `__gradient_print__` | Colors | Prints multi-line text with a vertical color gradient |
| `__handle_err__` | Communication | Handles errors by stopping the spinner and printing error details including the line number, exit code, and failing command |
| `__info__` | Communication | Prints an informational message in bold yellow and starts the rainbow spinner |
| `__init_node_mappings__` | Queries | Parses `pvecm status` and `pvecm nodes` to build internal maps: NODEID_TO_IP[nodeid]   -> IP, NODEID_TO_NAME[nodeid] -> Name, then creates: NAME_TO_IP[name] -> IP and IP_TO_NAME[ip] -> name |
| `__install_or_prompt__` | Prompts | Checks if a specified command is available |
| `__int_lerp__` | Colors | Performs integer linear interpolation between START and END using FRACTION (0 to 100) |
| `__int_to_ip__` | Conversion | Converts a 32-bit integer to its dotted IPv4 address equivalent |
| `__ip_to_int__` | Conversion | Converts a dotted IPv4 address string to its 32-bit integer equivalent |
| `__iterate_cts__` | ProxmoxAPI | Iterate through CT range and call callback for each |
| `__iterate_vms__` | ProxmoxAPI | Iterate through VM range and call callback for each |
| `__line_gradient__` | Colors | Applies a left-to-right color gradient to a single line of text |
| `__line_rgb__` | Colors | Prints a line of text in a single, solid RGB color |
| `__net_bulk_set_bridge__` | Network | Change bridge for multiple VMs |
| `__net_bulk_set_vlan__` | Network | Set VLAN tag for multiple VMs |
| `__net_ct_add_interface__` | Network | Add network interface to CT |
| `__net_ct_get_interfaces__` | Network | Get list of network interfaces for CT |
| `__net_ct_remove_interface__` | Network | Remove network interface from CT |
| `__net_ct_set_gateway__` | Network | Set gateway for CT interface |
| `__net_ct_set_ip__` | Network | Set IP address for CT interface |
| `__net_ct_set_nameserver__` | Network | Set nameserver for CT |
| `__net_get_next_ip__` | Network | Get next available IP in subnet |
| `__net_is_ip_in_use__` | Network | Check if IP address is in use by any VM/CT |
| `__net_migrate_network__` | Network | Migrate VMs from one bridge/VLAN to another |
| `__net_ping__` | Network | Ping host from node |
| `__net_test_connectivity__` | Network | Test network connectivity from VM/CT |
| `__net_test_dns__` | Network | Test DNS resolution from CT |
| `__net_test_gateway__` | Network | Test gateway reachability from CT |
| `__net_validate_cidr__` | Network | Validate IP address in CIDR notation |
| `__net_validate_ip__` | Network | Validate IPv4 address format |
| `__net_validate_mac__` | Network | Validate MAC address format |
| `__net_vm_add_interface__` | Network | Add network interface to VM |
| `__net_vm_get_interfaces__` | Network | Get list of network interfaces for VM |
| `__net_vm_remove_interface__` | Network | Remove network interface from VM |
| `__net_vm_set_bridge__` | Network | Change bridge for VM network interface |
| `__net_vm_set_mac__` | Network | Set MAC address for VM network interface |
| `__net_vm_set_vlan__` | Network | Set or change VLAN tag for VM network interface |
| `__node_exec__` | ProxmoxAPI | Execute a command on a specific node (local or remote via SSH) |
| `__ok__` | Communication | Stops the spinner and prints a success message in green |
| `__parse_args__` | ArgumentParser | One-line declarative argument parser with automatic validation |
| `__prompt_keep_installed_packages__` | Prompts | Prompts the user whether to keep or remove all packages that were installed in this session via __install_or_prompt__() |
| `__prompt_user_yn__` | Prompts | Prompts the user with a yes/no question and returns 0 for yes, 1 for no |
| `__pve_exec__` | ProxmoxAPI | Generic Proxmox command executor on correct node |
| `__require_root_and_proxmox__` | Prompts | Convenience helper that ensures the script is run as root on a Proxmox node |
| `__resolve_node_name__` | Queries | Resolves a node specification (local/hostname/IP) to a node name |
| `__scp_fetch__` | SSH | Copies files/directories from the remote host to the local machine via SCP |
| `__scp_fetch__` | SSH | Copies files/directories from the remote host to the local machine via SCP |
| `__scp_send__` | SSH | Copies one or more local files/directories to a remote destination via SCP |
| `__scp_send__` | SSH | Copies one or more local files/directories to a remote destination via SCP |
| `__show_script_examples__` | Communication | Extracts and displays example invocation lines (lines starting with '#  |
| `__show_script_header__` | Communication | Displays the top commented section of a script file in green |
| `__simulate_blink_async__` | Colors | Simulates a blinking effect by toggling between bright and dim text asynchronously |
| `__spin__` | Communication | Runs an infinite spinner with rainbow color cycling in the background |
| `__ssh_exec__` | SSH | Executes a command on a remote host via SSH, supporting password or key-based authentication and optional sudo or shell invocation |
| `__ssh_exec__` | SSH | Executes a command on a remote host via SSH, supporting password or key-based authentication and optional sudo or shell invocation |
| `__ssh_exec_function__` | SSH | Ships one or more local Bash function definitions to the remote host and invokes a selected function with optional arguments |
| `__ssh_exec_function__` | SSH | Ships one or more local Bash function definitions to the remote host and invokes a selected function with optional arguments |
| `__ssh_exec_script__` | SSH | Transfers a local script (or inline content) to the remote host, sets executable permissions, runs it, and optionally removes it afterward |
| `__ssh_exec_script__` | SSH | Transfers a local script (or inline content) to the remote host, sets executable permissions, runs it, and optionally removes it afterward |
| `__state_cleanup__` | StateManager | Clean up old state files |
| `__state_compare_ct__` | StateManager | Compare current CT state with saved state |
| `__state_compare_vm__` | StateManager | Compare current VM state with saved state |
| `__state_delete__` | StateManager | Delete a state file |
| `__state_diff__` | StateManager | Show differences between two states |
| `__state_export_ct__` | StateManager | Export CT state to portable format |
| `__state_export_vm__` | StateManager | Export VM state to portable format |
| `__state_info__` | StateManager | Show detailed information about a state file |
| `__state_list__` | StateManager | List all saved states |
| `__state_restore_bulk__` | StateManager | Restore state for multiple VMs/CTs |
| `__state_restore_ct__` | StateManager | Restore CT configuration from state file |
| `__state_restore_vm__` | StateManager | Restore VM configuration from state file |
| `__state_save_bulk__` | StateManager | Save state for multiple VMs/CTs |
| `__state_save_ct__` | StateManager | Save CT configuration to state file |
| `__state_save_vm__` | StateManager | Save VM configuration to state file |
| `__state_show_changes__` | StateManager | Show changes that will be applied during restore |
| `__state_snapshot_cluster__` | StateManager | Save state of all VMs and CTs in cluster |
| `__state_validate__` | StateManager | Validate a state file |
| `__stop_spin__` | Communication | Stops the running spinner process (if any) and restores the cursor |
| `__update__` | Communication | Updates the text displayed next to the spinner without stopping it |
| `__validate_ctid__` | Queries | Validates that a CTID exists and is a container (lxc), not a VM |
| `__validate_vm_id_range__` | Queries | Validates that VM IDs are numeric and in correct order |
| `__validate_vmid__` | Queries | Validates that a VMID exists and is a VM (qemu), not a container |
| `__vm_exists__` | ProxmoxAPI | Check if a VM exists (cluster-wide) |
| `__vm_get_config__` | ProxmoxAPI | Get VM configuration parameter value |
| `__vm_get_status__` | ProxmoxAPI | Get VM status (running, stopped, paused, etc) |
| `__vm_is_running__` | ProxmoxAPI | Check if VM is running |
| `__vm_list_all__` | ProxmoxAPI | List all VMs in the cluster |
| `__vm_node_exec__` | ProxmoxAPI | Execute a command on the node where a VM is located |
| `__vm_restart__` | ProxmoxAPI | Restart a VM |
| `__vm_resume__` | ProxmoxAPI | Resume a suspended VM |
| `__vm_set_config__` | ProxmoxAPI | Set VM configuration parameter |
| `__vm_shutdown__` | ProxmoxAPI | Gracefully shutdown a VM (sends ACPI shutdown signal) |
| `__vm_start__` | ProxmoxAPI | Start a VM (cluster-aware) |
| `__vm_stop__` | ProxmoxAPI | Stop a VM (cluster-aware) |
| `__vm_suspend__` | ProxmoxAPI | Suspend a VM (save state to disk) |
| `__vm_wait_for_status__` | ProxmoxAPI | Wait for VM to reach a specific status |
| `__vmid_to_mac_prefix__` | Conversion | Converts a numeric VMID into a deterministic MAC prefix string (e |
| `__wait_for_ssh__` | SSH | Repeatedly attempts to connect via SSH to a specified host using a given username and password until SSH is reachable or until the maximum number of attempts is exhausted |
| `__warn__` | Communication | Stops the spinner and prints a warning message in yellow |
| `get_ip_from_vmid` | Queries | Retrieves the IP address of a VM by using its net0 MAC address for an ARP scan on the default interface (vmbr0) |

# Utility Files

# ArgumentParser.sh

**Purpose**: !/bin/bash ArgumentParser.sh (v2) Simple, declarative argument parsing for ProxmoxScripts. One-line usage with automatic validation and help generation. __parse_args__ "start:number end:number --force:flag --node:string" "$@" After parsing, arguments are available as variables: $START, $END, $FORCE, $NODE

**Usage**:
```bash
source "${UTILITYPATH}/ArgumentParser.sh"
```

**Functions**:
- `__parse_args__`
- `__validate_numeric__`
- `__validate_integer__`
- `__validate_vmid__`
- `__validate_float__`
- `__validate_ip__`
- `__validate_ipv6__`
- `__validate_cidr__`
- `__validate_port__`
- `__validate_range__`
- `__validate_hostname__`
- `__validate_fqdn__`
- `__validate_mac_address__`
- `__validate_boolean__`
- `__validate_storage__`
- `__validate_bridge__`
- `__validate_vlan__`
- `__validate_node_name__`
- `__validate_cpu_cores__`
- `__validate_memory__`
- `__validate_disk_size__`
- `__validate_onboot__`
- `__validate_ostype__`
- `__validate_path__`
- `__validate_url__`
- `__validate_email__`
- `__validate_string__`
- `__validate_vmid_range__`

---

#### Functions in ArgumentParser.sh

### `__parse_args__`
**Description**: One-line declarative argument parser with automatic validation
**Usage**:
```bash
__parse_args__ "spec" "$@" Spec Format: "name:type name:type --flag:type --opt:type:default" Types: number, num, numeric   - Numeric value (0-9+) int, integer          - Integer (can be negative) vmid                  - VM/CT ID (100-999999999) float, decimal        - Decimal number (e.g., 1.5) ip, ipv4              - IPv4 address (192.168.1.100) ipv6                  - IPv6 address cidr, network         - CIDR notation (192.168.1.0/24) gateway               - Gateway IP address port                  - Port number (1-65535) hostname, host        - Hostname (RFC 1123) fqdn                  - Fully qualified domain name mac                   - MAC address (XX:XX:XX:XX:XX:XX) string, str           - Any string path, file            - File/directory path url                   - URL (http/https) email                 - Email address bool, boolean         - Boolean value (true/false, yes/no, 1/0) flag                  - Boolean flag (--flag sets to true) storage               - Proxmox storage name bridge                - Network bridge (vmbr0, vmbr1, etc.) vlan                  - VLAN ID (1-4094) node, nodename        - Proxmox node name pool                  - Resource pool name cpu, cores            - CPU cores (1-max) memory, ram           - Memory in MB (min 16) disk, disksize        - Disk size (with units: 10G, 500M) onboot                - OnBoot setting (0 or 1) ostype                - OS type (l26, l24, win10, etc.) range                 - Number range (start-end) Optional/Default: name:type:default     - Optional with default value name:type:?           - Optional, empty if not provided Examples: __parse_args__ "vmid:number --force:flag" "$@" __parse_args__ "start:number end:number --node:string:?" "$@" __parse_args__ "ip:ip port:port:22" "$@"
```
**Returns**: Sets global variables with uppercase names, returns 1 on error
---
# BulkOperations.sh

**Purpose**: !/bin/bash Standardized framework for bulk VM/CT operations with progress tracking, error handling, and reporting. Reduces code duplication in bulk scripts.

**Features**:
- Progress tracking with counters
- Detailed error reporting
- Operation summaries
- Retry logic for failed operations
- Parallel execution support
- Filtering capabilities

**Usage**:
```bash
source "${UTILITYPATH}/BulkOperations.sh"
```

**Functions**:
- *Core Operations*: `__bulk_operation__`, `__bulk_vm_operation__`, `__bulk_ct_operation__`
- *Reporting*: `__bulk_report__`, `__bulk_summary__`, `__bulk_print_results__`
- *Advanced*: `__bulk_with_retry__`, `__bulk_filter__`, `__bulk_parallel__`
- *Utilities*: `__bulk_save_state__`, `__bulk_load_state__`, `__bulk_validate_range__`

---

#### Functions in BulkOperations.sh

### `__bulk_operation__`
**Description**: Generic bulk operation handler with progress tracking.
**Usage**:
```bash
__bulk_operation__ <start_id> <end_id> <callback> [args...]
```
**Parameters**:
- 1 Start ID
- 2 End ID
- 3 Callback function name
- @ Additional arguments to pass to callback
**Returns**: 0 on success, 1 if any operations failed The callback function receives: id [args...] Callback should return 0 on success, non-zero on failure
---
### `__bulk_vm_operation__`
**Description**: Bulk operation on VMs with existence checking.
**Usage**:
```bash
__bulk_vm_operation__ [options] <start_id> <end_id> <callback> [args...]
```
**Parameters**:
- --name Operation name for reporting
- --skip-stopped Skip VMs that are stopped
- --skip-running Skip VMs that are running
- --report Show detailed report
- 1 Start VMID
- 2 End VMID
- 3 Callback function
- @ Additional callback arguments
**Returns**: 0 on success, 1 if any operations failed
---
### `__bulk_ct_operation__`
**Description**: Bulk operation on CTs with existence checking.
**Usage**:
```bash
__bulk_ct_operation__ [options] <start_id> <end_id> <callback> [args...]
```
**Parameters**:
- --name Operation name for reporting
- --skip-stopped Skip CTs that are stopped
- --skip-running Skip CTs that are running
- --report Show detailed report
- 1 Start CTID
- 2 End CTID
- 3 Callback function
- @ Additional callback arguments
**Returns**: 0 on success, 1 if any operations failed
---
### `__bulk_summary__`
**Description**: Print summary of bulk operation results.
**Usage**:
```bash
__bulk_summary__
```
**Returns**: 0 always
---
### `__bulk_report__`
**Description**: Print detailed report including failed/skipped IDs.
**Usage**:
```bash
__bulk_report__
```
**Returns**: 0 always
---
### `__bulk_print_results__`
**Description**: Print results in machine-readable format.
**Usage**:
```bash
__bulk_print_results__ [--format json|csv]
```
**Parameters**:
- --format Output format (default: text)
**Returns**: 0 always
---
### `__bulk_with_retry__`
**Description**: Retry failed operations with configurable attempts.
**Usage**:
```bash
__bulk_with_retry__ <retries> <start_id> <end_id> <callback> [args...]
```
**Parameters**:
- 1 Number of retry attempts
- 2 Start ID
- 3 End ID
- 4 Callback function
- @ Additional callback arguments
**Returns**: 0 if all eventually succeed, 1 otherwise
---
### `__bulk_filter__`
**Description**: Filter IDs based on a condition function.
**Usage**:
```bash
__bulk_filter__ <start_id> <end_id> <filter_fn>
```
**Parameters**:
- 1 Start ID
- 2 End ID
- 3 Filter function (returns 0 to include, 1 to exclude)
**Returns**: Prints filtered IDs to stdout, one per line
---
### `__bulk_parallel__`
**Description**: Execute operations in parallel (experimental).
**Usage**:
```bash
__bulk_parallel__ <max_jobs> <start_id> <end_id> <callback> [args...]
```
**Parameters**:
- 1 Maximum parallel jobs
- 2 Start ID
- 3 End ID
- 4 Callback function
- @ Additional callback arguments
**Returns**: 0 on success, 1 if any failed NOTE: This is experimental and may have issues with spinners/output
---
### `__bulk_save_state__`
**Description**: Save bulk operation state to file for resume.
**Usage**:
```bash
__bulk_save_state__ <filename>
```
**Parameters**:
- 1 Filename to save state
**Returns**: 0 on success, 1 on error
---
### `__bulk_load_state__`
**Description**: Load bulk operation state from file.
**Usage**:
```bash
__bulk_load_state__ <filename>
```
**Parameters**:
- 1 Filename to load state from
**Returns**: 0 on success, 1 on error
---
### `__bulk_validate_range__`
**Description**: Validate that a range is reasonable for bulk operations.
**Usage**:
```bash
__bulk_validate_range__ <start> <end> [--max-range <n>]
```
**Parameters**:
- 1 Start ID
- 2 End ID
- --max-range Maximum allowed range (default: 1000)
**Returns**: 0 if valid, 1 if invalid
---
# Colors.sh

**Purpose**: !/bin/bash Provides 24-bit gradient printing and asynchronous "blink" simulation.

**Functions**:
- `__int_lerp__`
- `__gradient_print__`
- `__line_gradient__`
- `__line_rgb__`
- `__simulate_blink_async__`

---

#### Functions in Colors.sh

### `__int_lerp__`
**Description**: Performs integer linear interpolation between START and END using FRACTION (0 to 100). Calculates: start + ((end - start) * fraction) / 100.
**Usage**:
```bash
 __int_lerp__ <start> <end> <fraction>
```
**Parameters**:
- start The starting integer value.
- end The ending integer value.
- fraction The interpolation fraction (0 to 100).
**Returns**:  Prints the interpolated integer value.
**Example Output**:
```
 For __int_lerp__ 10 20 50, the output is: 15
```
---
### `__gradient_print__`
**Description**: Prints multi-line text with a vertical color gradient. Interpolates colors from (R1,G1,B1) to (R2,G2,B2) line-by-line. For a single line, prints in the end color.
**Usage**:
```bash
 __gradient_print__ "multi-line text" R1 G1 B1 R2 G2 B2 [excluded_chars]
```
**Parameters**:
- text The multi-line text to print.
- R1 G1 B1 The starting RGB color.
- R2 G2 B2 The ending RGB color.
- excluded_chars (Optional) String of characters to exclude from coloring.
**Returns**:  Prints the text with a gradient applied.
**Example Output**:
```
 When given ASCII art and colors from (128,0,128) to (0,255,255), the output is the ASCII art printed with a vertical gradient.
```
---
### `__line_gradient__`
**Description**: Applies a left-to-right color gradient to a single line of text. Interpolates each character from (R1,G1,B1) to (R2,G2,B2).
**Usage**:
```bash
 __line_gradient__ "text" R1 G1 B1 R2 G2 B2
```
**Parameters**:
- text The text to print.
- R1 G1 B1 The starting RGB color.
- R2 G2 B2 The ending RGB color.
**Returns**:  Prints the text with a horizontal gradient applied.
**Example Output**:
```
 For __line_gradient__ "Hello" 255 0 0 0 0 255, the output is "Hello" printed with a gradient transitioning from red to blue.
```
---
### `__line_rgb__`
**Description**: Prints a line of text in a single, solid RGB color.
**Usage**:
```bash
 __line_rgb__ "text" R G B
```
**Parameters**:
- text The text to print.
- R G B The RGB color values.
**Returns**:  Prints the text in the specified color.
**Example Output**:
```
 For __line_rgb__ "Static Text" 0 255 0, the output is "Static Text" printed in bright green.
```
---
### `__simulate_blink_async__`
**Description**: Simulates a blinking effect by toggling between bright and dim text asynchronously. Runs in a background subshell, allowing the main script to continue.
**Usage**:
```bash
 __simulate_blink_async__ "text to blink" [times] [delay]
```
**Parameters**:
- text The text to blink.
- times (Optional) Number of blink cycles (default: 5).
- delay (Optional) Delay between toggles in seconds (default: 0.3).
**Returns**:  Prints the blinking text effect asynchronously.
**Example Output**:
```
 For __simulate_blink_async__ "Blinking" 5 0.3, the output is "Blinking" toggling between bright and dim (observed asynchronously).
```
---
# Communication.sh

**Purpose**: !/bin/bash Provides spinner animation, color-coded printing, and error handling utilities for other Bash scripts. Example: #!/bin/bash source "./Communication.sh" info "Performing tasks..." # ... do work ...

**Usage**:
```bash
source "Communication.sh"
```

**Functions**:
- `__spin__`
- `__stop_spin__`
- `__info__`
- `__update__`
- `__ok__`
- `__warn__`
- `__err__`
- `__handle_err__`
- `__show_script_header__`
- `__show_script_examples__`
- `__display_script_info__`

---

#### Functions in Communication.sh

### `__spin__`
**Description**: Runs an infinite spinner with rainbow color cycling in the background.
**Usage**:
```bash
__spin__ &
```
**Returns**: Runs indefinitely until terminated.
**Example Output**:
```
When executed in the background, the spinner animates through rainbow colors.
```
---
### `__stop_spin__`
**Description**: Stops the running spinner process (if any) and restores the cursor.
**Usage**:
```bash
__stop_spin__
```
**Returns**: Terminates the spinner and resets SPINNER_PID.
**Example Output**:
```
The spinner process is terminated and the cursor is made visible.
```
---
### `__info__`
**Description**: Prints an informational message in bold yellow and starts the rainbow spinner. If a spinner is already running, it stops the old one first.
**Usage**:
```bash
__info__ "message"
```
**Parameters**:
- msg The message to display.
**Returns**: Displays the message and starts the spinner.
**Example Output**:
```
"Processing..." is displayed in bold yellow with an active spinner.
```
---
### `__update__`
**Description**: Updates the text displayed next to the spinner without stopping it.
**Usage**:
```bash
__update__ "new message"
```
**Parameters**:
- new message The updated text to display.
**Returns**: Updates the spinner line text.
**Example Output**:
```
The text next to the spinner is replaced with "new message".
```
---
### `__ok__`
**Description**: Stops the spinner and prints a success message in green.
**Usage**:
```bash
__ok__ "success message"
```
**Parameters**:
- msg The success message to display.
**Returns**: Terminates the spinner and displays the success message.
**Example Output**:
```
The spinner stops and "Completed successfully!" is printed in green bold.
```
---
### `__warn__`
**Description**: Stops the spinner and prints a warning message in yellow.
**Usage**:
```bash
__warn__ "warning message"
```
**Parameters**:
- msg The warning message to display.
**Returns**: Terminates the spinner and displays the warning message.
**Example Output**:
```
The spinner stops and "Warning: check configuration!" is printed in yellow bold.
```
---
### `__err__`
**Description**: Stops the spinner and prints an error message in red.
**Usage**:
```bash
__err__ "error message"
```
**Parameters**:
- msg The error message to display.
**Returns**: Terminates the spinner and displays the error message.
**Example Output**:
```
The spinner stops and "Operation failed!" is printed in red bold.
```
---
### `__handle_err__`
**Description**: Handles errors by stopping the spinner and printing error details including the line number, exit code, and failing command.
**Usage**:
```bash
trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
```
**Parameters**:
- line_number The line number where the error occurred.
- command The command that caused the error.
**Returns**: Displays error details and stops the spinner.
**Example Output**:
```
Error details with line number, exit code, and failing command are printed.
```
---
### `__show_script_header__`
**Description**: Displays the top commented section of a script file in green.
**Usage**:
```bash
__show_script_header__ <script_path>
```
**Parameters**:
- script_path The path to the script file.
**Returns**: Displays the header comments in green (0, 255, 0).
**Example Output**:
```
Shows script description, usage, arguments, etc. in green.
```
---
### `__show_script_examples__`
**Description**: Extracts and displays example invocation lines (lines starting with '# ./') in green.
**Usage**:
```bash
__show_script_examples__ <script_path>
```
**Parameters**:
- script_path The path to the script file.
**Returns**: Displays example invocation lines in green (0, 255, 0).
**Example Output**:
```
Shows lines like "./script.sh arg1 arg2" in green.
```
---
### `__display_script_info__`
**Description**: Displays complete script information with headers and examples in a consistent format.
**Usage**:
```bash
__display_script_info__ <script_path> [script_display_name]
```
**Parameters**:
- script_path The path to the script file.
- script_display_name Optional display name (defaults to script_path).
**Returns**: Displays formatted script information with colored headers and content.
**Example Output**:
```
Shows "Selected script", top comments, and example invocations sections.
```
---
# Conversion.sh

**Purpose**: !/bin/bash Provides utility functions for converting data structures, such as converting a dotted IPv4 address to its 32-bit integer representation (and vice versa). Example: source "./Conversion.sh" This script is mainly intended as a library of functions to be sourced

**Usage**:
```bash
source "Conversion.sh"
```

**Functions**:
- `__ip_to_int__`
- `__int_to_ip__`
- `__cidr_to_netmask__`
- `__vmid_to_mac_prefix__`

---

#### Functions in Conversion.sh

### `__ip_to_int__`
**Description**: Converts a dotted IPv4 address string to its 32-bit integer equivalent.
**Usage**:
```bash
__ip_to_int__ "127.0.0.1"
```
**Parameters**:
- 1 Dotted IPv4 address string (e.g., "192.168.1.10")
**Returns**: Prints the 32-bit integer representation of the IP to stdout.
**Example Output**:
```
For __ip_to_int__ "127.0.0.1", the output is: 2130706433
```
---
### `__int_to_ip__`
**Description**: Converts a 32-bit integer to its dotted IPv4 address equivalent.
**Usage**:
```bash
__int_to_ip__ 2130706433
```
**Parameters**:
- 1 32-bit integer
**Returns**: Prints the dotted IPv4 address string to stdout.
**Example Output**:
```
For __int_to_ip__ 2130706433, the output is: 127.0.0.1
```
---
### `__cidr_to_netmask__`
**Description**: Converts a CIDR prefix to a dotted-decimal netmask.
**Usage**:
```bash
__cidr_to_netmask__ 18
```
**Parameters**:
- 1 CIDR prefix (e.g., 18)
**Returns**: Prints the full subnet netmask.
**Example Output**:
```
For __cidr_to_netmask__ 18, the output is: 255.255.192.0
```
---
### `__vmid_to_mac_prefix__`
**Description**: Converts a numeric VMID into a deterministic MAC prefix string (e.g., BC:12:34).
**Usage**:
```bash
__vmid_to_mac_prefix__ --vmid 1234 [--prefix BC] [--pad-length 4]
```
**Returns**: Prints the computed MAC prefix (uppercase) to stdout.
**Example Output**:
```
__vmid_to_mac_prefix__ --vmid 512 --prefix aa --pad-length 6
```
---
# Network.sh

**Purpose**: !/bin/bash Network management framework for VM/CT network configuration, IP management, and network validation.

**Features**:
- Configure network interfaces
- Manage IP addresses (DHCP/Static)
- VLAN and bridge management
- Network validation and testing
- Bulk network operations
- Network migration support

**Usage**:
```bash
source "${UTILITYPATH}/Network.sh"
```

**Functions**:
- *VM Network Configuration*: `__net_vm_add_interface__`, `__net_vm_remove_interface__`, `__net_vm_set_bridge__`, `__net_vm_set_vlan__`, `__net_vm_set_mac__`, `__net_vm_get_interfaces__`
- *CT Network Configuration*: `__net_ct_add_interface__`, `__net_ct_remove_interface__`, `__net_ct_set_ip__`, `__net_ct_set_gateway__`, `__net_ct_set_nameserver__`, `__net_ct_get_interfaces__`
- *IP Management*: `__net_validate_ip__`, `__net_validate_cidr__`, `__net_validate_mac__`, `__net_is_ip_in_use__`, `__net_get_next_ip__`
- *Network Testing*: `__net_test_connectivity__`, `__net_test_dns__`, `__net_test_gateway__`, `__net_ping__`
- *Bulk Operations*: `__net_bulk_set_bridge__`, `__net_bulk_set_vlan__`, `__net_migrate_network__`

---

#### Functions in Network.sh

### `__net_vm_add_interface__`
**Description**: Add network interface to VM.
**Usage**:
```bash
__net_vm_add_interface__ <vmid> <net_id> [options]
```
**Parameters**:
- 1 VMID
- 2 Network ID (net0, net1, etc.)
- --bridge Bridge name (e.g., vmbr0)
- --vlan VLAN tag
- --mac MAC address
- --model Network model (virtio, e1000, etc.)
**Returns**: 0 on success, 1 on error
---
### `__net_vm_remove_interface__`
**Description**: Remove network interface from VM.
**Usage**:
```bash
__net_vm_remove_interface__ <vmid> <net_id>
```
**Parameters**:
- 1 VMID
- 2 Network ID (net0, net1, etc.)
**Returns**: 0 on success, 1 on error
---
### `__net_vm_set_bridge__`
**Description**: Change bridge for VM network interface.
**Usage**:
```bash
__net_vm_set_bridge__ <vmid> <net_id> <bridge>
```
**Parameters**:
- 1 VMID
- 2 Network ID (net0, net1, etc.)
- 3 Bridge name (e.g., vmbr0)
**Returns**: 0 on success, 1 on error
---
### `__net_vm_set_vlan__`
**Description**: Set or change VLAN tag for VM network interface.
**Usage**:
```bash
__net_vm_set_vlan__ <vmid> <net_id> <vlan>
```
**Parameters**:
- 1 VMID
- 2 Network ID (net0, net1, etc.)
- 3 VLAN tag (or "none" to remove)
**Returns**: 0 on success, 1 on error
---
### `__net_vm_set_mac__`
**Description**: Set MAC address for VM network interface.
**Usage**:
```bash
__net_vm_set_mac__ <vmid> <net_id> <mac>
```
**Parameters**:
- 1 VMID
- 2 Network ID (net0, net1, etc.)
- 3 MAC address
**Returns**: 0 on success, 1 on error
---
### `__net_vm_get_interfaces__`
**Description**: Get list of network interfaces for VM.
**Usage**:
```bash
__net_vm_get_interfaces__ <vmid>
```
**Parameters**:
- 1 VMID
**Returns**: 0 on success, prints interface list
---
### `__net_ct_add_interface__`
**Description**: Add network interface to CT.
**Usage**:
```bash
__net_ct_add_interface__ <ctid> <net_id> [options]
```
**Parameters**:
- 1 CTID
- 2 Network ID (net0, net1, etc.)
- --bridge Bridge name
- --ip IP address (CIDR notation or dhcp)
- --gateway Gateway address
- --vlan VLAN tag
**Returns**: 0 on success, 1 on error
---
### `__net_ct_remove_interface__`
**Description**: Remove network interface from CT.
**Usage**:
```bash
__net_ct_remove_interface__ <ctid> <net_id>
```
**Parameters**:
- 1 CTID
- 2 Network ID (net0, net1, etc.)
**Returns**: 0 on success, 1 on error
---
### `__net_ct_set_ip__`
**Description**: Set IP address for CT interface.
**Usage**:
```bash
__net_ct_set_ip__ <ctid> <net_id> <ip>
```
**Parameters**:
- 1 CTID
- 2 Network ID (net0, net1, etc.)
- 3 IP address in CIDR notation or "dhcp"
**Returns**: 0 on success, 1 on error
---
### `__net_ct_set_gateway__`
**Description**: Set gateway for CT interface.
**Usage**:
```bash
__net_ct_set_gateway__ <ctid> <net_id> <gateway>
```
**Parameters**:
- 1 CTID
- 2 Network ID (net0, net1, etc.)
- 3 Gateway IP address
**Returns**: 0 on success, 1 on error
---
### `__net_ct_set_nameserver__`
**Description**: Set nameserver for CT.
**Usage**:
```bash
__net_ct_set_nameserver__ <ctid> <nameserver>
```
**Parameters**:
- 1 CTID
- 2 Nameserver IP address
**Returns**: 0 on success, 1 on error
---
### `__net_ct_get_interfaces__`
**Description**: Get list of network interfaces for CT.
**Usage**:
```bash
__net_ct_get_interfaces__ <ctid>
```
**Parameters**:
- 1 CTID
**Returns**: 0 on success, prints interface list
---
### `__net_validate_ip__`
**Description**: Validate IPv4 address format.
**Usage**:
```bash
__net_validate_ip__ <ip>
```
**Parameters**:
- 1 IP address
**Returns**: 0 if valid, 1 if invalid
---
### `__net_validate_cidr__`
**Description**: Validate IP address in CIDR notation.
**Usage**:
```bash
__net_validate_cidr__ <cidr>
```
**Parameters**:
- 1 IP in CIDR notation (e.g., 192.168.1.10/24)
**Returns**: 0 if valid, 1 if invalid
---
### `__net_validate_mac__`
**Description**: Validate MAC address format.
**Usage**:
```bash
__net_validate_mac__ <mac>
```
**Parameters**:
- 1 MAC address
**Returns**: 0 if valid, 1 if invalid
---
### `__net_is_ip_in_use__`
**Description**: Check if IP address is in use by any VM/CT.
**Usage**:
```bash
__net_is_ip_in_use__ <ip>
```
**Parameters**:
- 1 IP address
**Returns**: 0 if in use, 1 if not in use
---
### `__net_get_next_ip__`
**Description**: Get next available IP in subnet.
**Usage**:
```bash
__net_get_next_ip__ <base_ip> [start_host]
```
**Parameters**:
- 1 Base IP (e.g., 192.168.1.0)
- 2 Starting host number (default: 1)
**Returns**: 0 on success, prints next available IP
---
### `__net_test_connectivity__`
**Description**: Test network connectivity from VM/CT.
**Usage**:
```bash
__net_test_connectivity__ <vmid_or_ctid> <target>
```
**Parameters**:
- 1 VM or CT ID
- 2 Target IP or hostname
**Returns**: 0 if reachable, 1 if not reachable
---
### `__net_test_dns__`
**Description**: Test DNS resolution from CT.
**Usage**:
```bash
__net_test_dns__ <ctid> <hostname>
```
**Parameters**:
- 1 CTID
- 2 Hostname to resolve
**Returns**: 0 if resolvable, 1 if not
---
### `__net_test_gateway__`
**Description**: Test gateway reachability from CT.
**Usage**:
```bash
__net_test_gateway__ <ctid>
```
**Parameters**:
- 1 CTID
**Returns**: 0 if gateway reachable, 1 if not
---
### `__net_ping__`
**Description**: Ping host from node.
**Usage**:
```bash
__net_ping__ <host> [count]
```
**Parameters**:
- 1 Host IP or hostname
- 2 Ping count (default: 4)
**Returns**: 0 if reachable, 1 if not
---
### `__net_bulk_set_bridge__`
**Description**: Change bridge for multiple VMs.
**Usage**:
```bash
__net_bulk_set_bridge__ <start_vmid> <end_vmid> <net_id> <bridge>
```
**Parameters**:
- 1 Start VMID
- 2 End VMID
- 3 Network ID (net0, net1, etc.)
- 4 New bridge name
**Returns**: 0 on success, 1 if any failed
---
### `__net_bulk_set_vlan__`
**Description**: Set VLAN tag for multiple VMs.
**Usage**:
```bash
__net_bulk_set_vlan__ <start_vmid> <end_vmid> <net_id> <vlan>
```
**Parameters**:
- 1 Start VMID
- 2 End VMID
- 3 Network ID (net0, net1, etc.)
- 4 VLAN tag
**Returns**: 0 on success, 1 if any failed
---
### `__net_migrate_network__`
**Description**: Migrate VMs from one bridge/VLAN to another.
**Usage**:
```bash
__net_migrate_network__ <start_vmid> <end_vmid> <net_id> [options]
```
**Parameters**:
- 1 Start VMID
- 2 End VMID
- 3 Network ID
- --from-bridge Source bridge
- --to-bridge Destination bridge
- --from-vlan Source VLAN
- --to-vlan Destination VLAN
**Returns**: 0 on success, 1 if any failed
---
# Prompts.sh

**Purpose**: !/bin/bash Provides functions for user interaction and prompts (e.g., checking root permissions, verifying Proxmox environment, installing packages on demand). # Then call its functions, for example: __check_root__ __check_proxmox__ __prompt_user_yn__ "Continue with operation?" __install_or_prompt__ "curl" __prompt_keep_installed_packages__

**Usage**:
```bash
source ./Prompts.sh
```

**Functions**:
- `__check_root__`
- `__check_proxmox__`
- `__prompt_user_yn__`
- `__install_or_prompt__`
- `__prompt_keep_installed_packages__`
- `__ensure_dependencies__`
- `__require_root_and_proxmox__`

---

#### Functions in Prompts.sh

### `__check_root__`
**Description**: Checks if the current user is root. Exits if not.
**Usage**:
```bash
__check_root__
```
**Returns**: Exits 1 if not root.
**Example Output**:
```
If not run as root, the output is: "Error: This script must be run as root (sudo)."
```
---
### `__check_proxmox__`
**Description**: Checks if this is a Proxmox node. Exits if not.
**Usage**:
```bash
__check_proxmox__
```
**Returns**: Exits 2 if not Proxmox.
**Example Output**:
```
If 'pveversion' is not found, the output is: "Error: 'pveversion' command not found. Are you sure this is a Proxmox node?"
```
---
### `__prompt_user_yn__`
**Description**: Prompts the user with a yes/no question and returns 0 for yes, 1 for no.
**Usage**:
```bash
__prompt_user_yn__ "Question text?"
```
**Parameters**:
- question The question to ask the user
**Returns**: Returns 0 if user answers yes (Y/y), 1 if user answers no (N/n) or presses Enter (default: no)
**Example Output**:
```
 __prompt_user_yn__ "Continue with operation?" && echo "Proceeding..." || echo "Cancelled"
```
---
### `__install_or_prompt__`
**Description**: Checks if a specified command is available. If not, prompts the user to install it via apt-get. Exits if the user declines. Also keeps track of installed packages in SESSION_INSTALLED_PACKAGES.
**Usage**:
```bash
__install_or_prompt__ <command_name>
```
**Parameters**:
- command_name The name of the command to check and install if missing.
**Returns**: Exits 1 if user declines the installation.
**Example Output**:
```
If "curl" is missing and the user declines installation, the output is: "Aborting script because 'curl' is not installed."
```
---
### `__prompt_keep_installed_packages__`
**Description**: Prompts the user whether to keep or remove all packages that were installed in this session via __install_or_prompt__(). If the user chooses "No", each package in SESSION_INSTALLED_PACKAGES is removed.
**Usage**:
```bash
__prompt_keep_installed_packages__
```
**Returns**: Removes packages if user says "No", otherwise does nothing.
**Example Output**:
```
If the user chooses "No", the output is: "Removing the packages installed in this session..." followed by "Packages removed."
```
---
### `__ensure_dependencies__`
**Description**: Verifies that the specified commands are available; installs them if missing. Supports automatic installation or interactive prompting.
**Usage**:
```bash
__ensure_dependencies__ [--auto-install] [--quiet] <command> [<command> ...]
```
**Example Output**:
```
__ensure_dependencies__ --auto-install curl rsync
```
---
### `__require_root_and_proxmox__`
**Description**: Convenience helper that ensures the script is run as root on a Proxmox node.
**Usage**:
```bash
__require_root_and_proxmox__
```
---
# Operations.sh

**Purpose**: !/bin/bash Wrapper functions for common Proxmox operations with built-in error handling, validation, and cluster-awareness. Reduces code duplication and provides consistent patterns for VM/CT operations.

**Features**:
- Cluster-aware operations (automatic node detection)
- Built-in error handling and validation
- Consistent return codes and error messages
- Testable and mockable functions
- State management helpers

**Usage**:
```bash
source "${UTILITYPATH}/Operations.sh"
```

**Functions**:
- *VM Operations*: `__vm_exists__`, `__vm_get_status__`, `__vm_is_running__`, `__vm_start__`, `__vm_stop__`, `__vm_set_config__`, `__vm_get_config__`
- *CT Operations*: `__ct_exists__`, `__ct_get_status__`, `__ct_is_running__`, `__ct_start__`, `__ct_stop__`, `__ct_set_config__`, `__ct_get_config__`
- *Iteration Helpers*: `__iterate_vms__`, `__iterate_cts__`
- *Additional VM Operations*: `__vm_shutdown__`, `__vm_restart__`, `__vm_suspend__`, `__vm_resume__`, `__vm_list_all__`, `__vm_wait_for_status__`
- *Additional CT Operations*: `__ct_shutdown__`, `__ct_restart__`, `__ct_list_all__`, `__ct_wait_for_status__`, `__ct_exec__`
- *Configuration Helpers*: `__get_vm_info__`, `__get_ct_info__`, `__validate_vm_config__`, `__validate_ct_config__`
- *Remote Execution Helpers*: `__node_exec__`, `__vm_node_exec__`, `__ct_node_exec__`, `__pve_exec__`

---

#### Functions in Operations.sh

### `__vm_exists__`
**Description**: Check if a VM exists (cluster-wide).
**Usage**:
```bash
__vm_exists__ <vmid>
```
**Parameters**:
- 1 VM ID
**Returns**: 0 if exists, 1 if not
---
### `__vm_get_status__`
**Description**: Get VM status (running, stopped, paused, etc).
**Usage**:
```bash
__vm_get_status__ <vmid>
```
**Parameters**:
- 1 VM ID
**Returns**: Prints status to stdout, returns 1 on error
---
### `__vm_is_running__`
**Description**: Check if VM is running.
**Usage**:
```bash
__vm_is_running__ <vmid>
```
**Parameters**:
- 1 VM ID
**Returns**: 0 if running, 1 if not
---
### `__vm_start__`
**Description**: Start a VM (cluster-aware).
**Usage**:
```bash
__vm_start__ <vmid> [options]
```
**Parameters**:
- 1 VM ID
- @ Additional qm start options
**Returns**: 0 on success, 1 on error
---
### `__vm_stop__`
**Description**: Stop a VM (cluster-aware).
**Usage**:
```bash
__vm_stop__ <vmid> [--timeout <seconds>] [--force]
```
**Parameters**:
- 1 VM ID
- --timeout Timeout in seconds before force stop
- --force Force stop immediately
**Returns**: 0 on success, 1 on error
---
### `__vm_set_config__`
**Description**: Set VM configuration parameter.
**Usage**:
```bash
__vm_set_config__ <vmid> --<param> <value> [--<param> <value> ...]
```
**Parameters**:
- 1 VM ID
- @ Configuration parameters (e.g., --memory 2048 --cores 4)
**Returns**: 0 on success, 1 on error
---
### `__vm_get_config__`
**Description**: Get VM configuration parameter value.
**Usage**:
```bash
__vm_get_config__ <vmid> <param>
```
**Parameters**:
- 1 VM ID
- 2 Parameter name (e.g., memory, cores)
**Returns**: Prints value to stdout, returns 1 on error
---
### `__ct_exists__`
**Description**: Check if a CT exists.
**Usage**:
```bash
__ct_exists__ <ctid>
```
**Parameters**:
- 1 CT ID
**Returns**: 0 if exists, 1 if not
---
### `__ct_get_status__`
**Description**: Get CT status.
**Usage**:
```bash
__ct_get_status__ <ctid>
```
**Parameters**:
- 1 CT ID
**Returns**: Prints status to stdout, returns 1 on error
---
### `__ct_is_running__`
**Description**: Check if CT is running.
**Usage**:
```bash
__ct_is_running__ <ctid>
```
**Parameters**:
- 1 CT ID
**Returns**: 0 if running, 1 if not
---
### `__ct_start__`
**Description**: Start a CT.
**Usage**:
```bash
__ct_start__ <ctid>
```
**Parameters**:
- 1 CT ID
**Returns**: 0 on success, 1 on error
---
### `__ct_stop__`
**Description**: Stop a CT.
**Usage**:
```bash
__ct_stop__ <ctid> [--force]
```
**Parameters**:
- 1 CT ID
- --force Force stop
**Returns**: 0 on success, 1 on error
---
### `__ct_set_config__`
**Description**: Set CT configuration parameter.
**Usage**:
```bash
__ct_set_config__ <ctid> -<param> <value> [-<param> <value> ...]
```
**Parameters**:
- 1 CT ID
- @ Configuration parameters (e.g., -memory 2048 -cores 4)
**Returns**: 0 on success, 1 on error
---
### `__ct_get_config__`
**Description**: Get CT configuration parameter value.
**Usage**:
```bash
__ct_get_config__ <ctid> <param>
```
**Parameters**:
- 1 CT ID
- 2 Parameter name (e.g., memory, cores)
**Returns**: Prints value to stdout, returns 1 on error
---
### `__iterate_vms__`
**Description**: Iterate through VM range and call callback for each.
**Usage**:
```bash
__iterate_vms__ <start_id> <end_id> <callback> [callback_args...]
```
**Parameters**:
- 1 Start VM ID
- 2 End VM ID
- 3 Callback function name
- @ Additional arguments to pass to callback
**Returns**: 0 on success, 1 if any callback fails Callback function receives: vmid [args...]
---
### `__iterate_cts__`
**Description**: Iterate through CT range and call callback for each.
**Usage**:
```bash
__iterate_cts__ <start_id> <end_id> <callback> [callback_args...]
```
**Parameters**:
- 1 Start CT ID
- 2 End CT ID
- 3 Callback function name
- @ Additional arguments to pass to callback
**Returns**: 0 on success, 1 if any callback fails Callback function receives: ctid [args...]
---
### `__vm_shutdown__`
**Description**: Gracefully shutdown a VM (sends ACPI shutdown signal).
**Usage**:
```bash
__vm_shutdown__ <vmid> [--timeout <seconds>]
```
**Parameters**:
- 1 VM ID
- --timeout Timeout in seconds (default: 60)
**Returns**: 0 on success, 1 on error
---
### `__vm_restart__`
**Description**: Restart a VM.
**Usage**:
```bash
__vm_restart__ <vmid> [--timeout <seconds>]
```
**Parameters**:
- 1 VM ID
- --timeout Shutdown timeout before restart
**Returns**: 0 on success, 1 on error
---
### `__vm_suspend__`
**Description**: Suspend a VM (save state to disk).
**Usage**:
```bash
__vm_suspend__ <vmid>
```
**Parameters**:
- 1 VM ID
**Returns**: 0 on success, 1 on error
---
### `__vm_resume__`
**Description**: Resume a suspended VM.
**Usage**:
```bash
__vm_resume__ <vmid>
```
**Parameters**:
- 1 VM ID
**Returns**: 0 on success, 1 on error
---
### `__vm_list_all__`
**Description**: List all VMs in the cluster.
**Usage**:
```bash
__vm_list_all__ [--running] [--stopped]
```
**Parameters**:
- --running Only list running VMs
- --stopped Only list stopped VMs
**Returns**: Prints VM IDs to stdout, one per line
---
### `__vm_wait_for_status__`
**Description**: Wait for VM to reach a specific status.
**Usage**:
```bash
__vm_wait_for_status__ <vmid> <status> [--timeout <seconds>]
```
**Parameters**:
- 1 VM ID
- 2 Desired status (running, stopped, paused)
- --timeout Max seconds to wait (default: 60)
**Returns**: 0 if status reached, 1 on timeout or error
---
### `__ct_shutdown__`
**Description**: Gracefully shutdown a CT.
**Usage**:
```bash
__ct_shutdown__ <ctid> [--timeout <seconds>]
```
**Parameters**:
- 1 CT ID
- --timeout Timeout in seconds (default: 60)
**Returns**: 0 on success, 1 on error
---
### `__ct_restart__`
**Description**: Restart a CT.
**Usage**:
```bash
__ct_restart__ <ctid>
```
**Parameters**:
- 1 CT ID
**Returns**: 0 on success, 1 on error
---
### `__ct_list_all__`
**Description**: List all CTs.
**Usage**:
```bash
__ct_list_all__ [--running] [--stopped]
```
**Parameters**:
- --running Only list running CTs
- --stopped Only list stopped CTs
**Returns**: Prints CT IDs to stdout, one per line
---
### `__ct_wait_for_status__`
**Description**: Wait for CT to reach a specific status.
**Usage**:
```bash
__ct_wait_for_status__ <ctid> <status> [--timeout <seconds>]
```
**Parameters**:
- 1 CT ID
- 2 Desired status (running, stopped)
- --timeout Max seconds to wait (default: 60)
**Returns**: 0 if status reached, 1 on timeout or error
---
### `__ct_exec__`
**Description**: Execute command inside a CT.
**Usage**:
```bash
__ct_exec__ <ctid> <command>
```
**Parameters**:
- 1 CT ID
- 2 Command to execute
**Returns**: Command exit code
---
### `__get_vm_info__`
**Description**: Get comprehensive VM information.
**Usage**:
```bash
__get_vm_info__ <vmid>
```
**Parameters**:
- 1 VM ID
**Returns**: Prints VM info in key=value format
---
### `__get_ct_info__`
**Description**: Get comprehensive CT information.
**Usage**:
```bash
__get_ct_info__ <ctid>
```
**Parameters**:
- 1 CT ID
**Returns**: Prints CT info in key=value format
---
### `__node_exec__`
**Description**: Execute a command on a specific node (local or remote via SSH). Automatically handles local vs remote execution and cluster context.
**Usage**:
```bash
__node_exec__ <node> <command>
```
**Parameters**:
- 1 Node name (from __get_vm_node__ or __resolve_node_name__)
- 2 Command to execute
**Returns**: Command exit code, stdout/stderr passed through
**Example Output**:
```
__node_exec__ "$(__get_vm_node__ 100)" "qm stop 100"
```
---
### `__vm_node_exec__`
**Description**: Execute a command on the node where a VM is located. Wrapper around __node_exec__ that automatically finds the VM's node.
**Usage**:
```bash
__vm_node_exec__ <vmid> <command>
```
**Parameters**:
- 1 VM ID
- 2 Command to execute (can use {vmid} placeholder)
**Returns**: Command exit code
**Example Output**:
```
__vm_node_exec__ 100 "qm set {vmid} --protection 0"
```
---
### `__ct_node_exec__`
**Description**: Execute a command on the node where a CT is located. Wrapper around __node_exec__ that automatically finds the CT's node.
**Usage**:
```bash
__ct_node_exec__ <ctid> <command>
```
**Parameters**:
- 1 CT ID
- 2 Command to execute (can use {ctid} placeholder)
**Returns**: Command exit code
**Example Output**:
```
__ct_node_exec__ 100 "pct set {ctid} --protection 0"
```
---
### `__pve_exec__`
**Description**: Generic Proxmox command executor on correct node. Detects command type (qm/pct/pvesh) and routes to appropriate node.
**Usage**:
```bash
__pve_exec__ <vmid_or_ctid> <command>
```
**Parameters**:
- 1 VM/CT ID
- 2 Full command (qm/pct/pvesh command)
**Returns**: Command exit code
**Example Output**:
```
__pve_exec__ 200 "pct clone 200 201"
```
---
# Cluster.sh

**Purpose**: !/bin/bash This script provides functions for prompting users, querying node/cluster information, and other utility tasks on Proxmox or Debian systems. Generally, this script is meant to be sourced by other scripts rather than run directly. For example: source ./Cluster.sh readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )

**Usage**:
```bash
source "./Cluster.sh"
```

**Functions**:
- `__get_remote_node_ips__`
- `__check_cluster_membership__`
- `__get_number_of_cluster_nodes__`
- `__init_node_mappings__`
- `__get_ip_from_name__`
- `__get_name_from_ip__`
- `__get_cluster_lxc__`
- `__get_server_lxc__`
- `__get_cluster_vms__`
- `__get_server_vms__`
- `__get_vm_node__`
- `__resolve_node_name__`
- `__validate_vm_id_range__`
- `__get_ip_from_vmid__`
- `__get_ip_from_guest_agent__`
- `__validate_vmid__`
- `__check_vm_status__`
- `__validate_ctid__`
- `__check_ct_status__`

---

#### Functions in Cluster.sh

### `__get_remote_node_ips__`
**Description**: Gathers IPs for all cluster nodes (excluding local) from 'pvecm status'. Outputs each IP on a new line, which can be captured into an array with readarray.
**Usage**:
```bash
readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )
```
**Returns**: Prints each remote node IP on a separate line to stdout.
**Example Output**:
```
Given pvecm status output with remote IPs, the function might output: 192.168.1.2 192.168.1.3
```
---
### `__check_cluster_membership__`
**Description**: Checks if the node is recognized as part of a cluster by examining 'pvecm status'. If no cluster name is found, it exits with an error.
**Usage**:
```bash
__check_cluster_membership__
```
**Returns**: Exits 3 if the node is not in a cluster (according to pvecm).
**Example Output**:
```
If the node is in a cluster, the output is: Node is in a cluster named: MyClusterName
```
---
### `__get_number_of_cluster_nodes__`
**Description**: Returns the total number of nodes in the cluster by counting lines matching a numeric ID from `pvecm nodes`.
**Usage**:
```bash
local num_nodes=$(__get_number_of_cluster_nodes__)
```
**Returns**: Prints the count of cluster nodes to stdout.
**Example Output**:
```
If there are 3 nodes in the cluster, the output is: 3
```
---
### `__init_node_mappings__`
**Description**: Parses `pvecm status` and `pvecm nodes` to build internal maps: NODEID_TO_IP[nodeid]   -> IP, NODEID_TO_NAME[nodeid] -> Name, then creates: NAME_TO_IP[name] -> IP and IP_TO_NAME[ip] -> name.
**Usage**:
```bash
__init_node_mappings__
```
**Returns**: Populates the associative arrays with node information.
**Example Output**:
```
No direct output; internal mappings are initialized for later queries.
```
---
### `__get_ip_from_name__`
**Description**: Given a node’s name (e.g., "pve01"), prints its link0 IP address. Exits if not found.
**Usage**:
```bash
__get_ip_from_name__ "pve03"
```
**Parameters**:
- 1 The node name.
**Returns**: Prints the IP to stdout or exits 1 if not found.
**Example Output**:
```
For __get_ip_from_name__ "pve03", the output is: 192.168.83.23
```
---
### `__get_name_from_ip__`
**Description**: Given a node’s link0 IP (e.g., "172.20.83.23"), prints its name. Exits if not found.
**Usage**:
```bash
__get_name_from_ip__ "172.20.83.23"
```
**Parameters**:
- 1 The node IP.
**Returns**: Prints the node name to stdout or exits 1 if not found.
**Example Output**:
```
For __get_name_from_ip__ "172.20.83.23", the output is: pve03
```
---
### `__get_cluster_lxc__`
**Description**: Retrieves the VMIDs for all LXC containers across the entire cluster.
**Usage**:
```bash
readarray -t ALL_CLUSTER_LXC < <( __get_cluster_lxc__ )
```
**Returns**: Prints each LXC VMID on a separate line.
**Example Output**:
```
The function may output: 101 102
```
---
### `__get_server_lxc__`
**Description**: Retrieves the VMIDs for all LXC containers on a specific server. The server can be specified by hostname, IP address, or "local".
**Usage**:
```bash
readarray -t NODE_LXC < <( __get_server_lxc__ "local" )
```
**Parameters**:
- 1 Hostname/IP/"local" specifying the server.
**Returns**: Prints each LXC VMID on its own line.
**Example Output**:
```
For __get_server_lxc__ "local", the output might be: 201 202
```
---
### `__get_cluster_vms__`
**Description**: Retrieves the VMIDs for all VMs (QEMU) across the entire cluster.
**Usage**:
```bash
readarray -t ALL_CLUSTER_VMS < <( __get_cluster_vms__ )
```
**Returns**: Prints each QEMU VMID on a separate line.
**Example Output**:
```
The function may output: 301 302
```
---
### `__get_server_vms__`
**Description**: Retrieves the VMIDs for all VMs (QEMU) on a specific server. The server can be specified by hostname, IP address, or "local".
**Usage**:
```bash
readarray -t NODE_VMS < <( __get_server_vms__ "local" )
```
**Parameters**:
- 1 Hostname/IP/"local" specifying the server.
**Returns**: Prints each QEMU VMID on its own line.
**Example Output**:
```
For __get_server_vms__ "local", the output might be: 401 402
```
---
### `__get_vm_node__`
**Description**: Gets the node name where a specific VM is located in the cluster. Returns empty string if VM is not found.
**Usage**:
```bash
local node=$(__get_vm_node__ 400)
```
**Parameters**:
- 1 The VMID to locate.
**Returns**: Prints the node name to stdout, or empty string if not found.
**Example Output**:
```
For __get_vm_node__ 400, the output might be: pve01
```
---
### `__resolve_node_name__`
**Description**: Resolves a node specification (local/hostname/IP) to a node name. Converts "local" to the current hostname, resolves IPs to node names.
**Usage**:
```bash
local node=$(__resolve_node_name__ "local")
```
**Parameters**:
- 1 Node specification: "local", hostname, or IP address.
**Returns**: Prints the resolved node name to stdout, or exits 1 if resolution fails.
**Example Output**:
```
For __resolve_node_name__ "192.168.1.20", the output might be: pve02
```
---
### `__validate_vm_id_range__`
**Description**: Validates that VM IDs are numeric and in correct order.
**Usage**:
```bash
__validate_vm_id_range__ "$START_ID" "$END_ID"
```
**Parameters**:
- 1 Start VM ID.
- 2 End VM ID.
**Returns**: Returns 0 if valid, 1 if invalid (with error message to stderr).
**Example Output**:
```
__validate_vm_id_range__ 400 430
```
---
### `get_ip_from_vmid`
**Description**: Retrieves the IP address of a VM by using its net0 MAC address for an ARP scan on the default interface (vmbr0). Prints the IP if found.
**Usage**:
```bash
get_ip_from_vmid 100
```
**Parameters**:
- 1 The VMID.
**Returns**: Prints the discovered IP or exits 1 if not found.
**Example Output**:
```
For get_ip_from_vmid 100, the output might be: 192.168.1.100
```
---
### `__get_ip_from_guest_agent__`
**Description**: Attempts to retrieve the first non-loopback IP address reported by the QEMU guest agent for a VM.
**Usage**:
```bash
__get_ip_from_guest_agent__ --vmid <vmid> [--retries <count>] [--delay <seconds>] [--ip-family <ipv4|ipv6>] [--include-loopback] [--allow-link-local]
```
**Returns**: Prints the discovered IP on success; exits with status 1 otherwise.
**Example Output**:
```
__get_ip_from_guest_agent__ --vmid 105 --retries 60 --delay 5
```
---
### `__validate_vmid__`
**Description**: Validates that a VMID exists and is a VM (qemu), not a container. Exits with error if VMID doesn't exist or is not a VM.
**Usage**:
```bash
__validate_vmid__ <vmid>
```
**Parameters**:
- vmid The VM ID to validate
**Returns**: 0 if valid VM, exits with error otherwise
**Example Output**:
```
For __validate_vmid__ 100: VMID 100 is a valid VM
```
---
### `__check_vm_status__`
**Description**: Checks if a VM is running and optionally stops it with user confirmation. Can be used in force mode to skip confirmation.
**Usage**:
```bash
__check_vm_status__ <vmid> [--stop] [--force]
```
**Parameters**:
- vmid The VM ID to check
- --stop Optional: Offer to stop the VM if running
- --force Optional: Stop without confirmation (requires --stop)
**Returns**: 0 if VM is stopped, 1 if running and not stopped
**Example Output**:
```
__check_vm_status__ 100 --stop --force
```
---
### `__validate_ctid__`
**Description**: Validates that a CTID exists and is a container (lxc), not a VM. Exits with error if CTID doesn't exist or is not a container.
**Usage**:
```bash
__validate_ctid__ <ctid>
```
**Parameters**:
- ctid The container ID to validate
**Returns**: 0 if valid container, exits with error otherwise
**Example Output**:
```
For __validate_ctid__ 100: CTID 100 is a valid container
```
---
### `__check_ct_status__`
**Description**: Checks if a container is running and optionally stops it with user confirmation. Can be used in force mode to skip confirmation.
**Usage**:
```bash
__check_ct_status__ <ctid> [--stop] [--force]
```
**Parameters**:
- ctid The container ID to check
- --stop Optional: Offer to stop the container if running
- --force Optional: Stop without confirmation (requires --stop)
**Returns**: 0 if container is stopped, 1 if running and not stopped
**Example Output**:
```
__check_ct_status__ 100 --stop --force
```
---
# RunAllTests.sh

**Purpose**: !/usr/bin/env bash

---

# SSH.sh

**Purpose**: !/bin/bash This script provides repeated-use SSH functions that can be sourced by other scripts.

**Usage**:
```bash
source SSH.sh
```

**Functions**:
- `__wait_for_ssh__`
- `__ssh_exec__`
- `__scp_send__`
- `__scp_fetch__`
- `__ssh_exec_script__`
- `__ssh_exec_function__`
- `__ssh_exec__`
- `__scp_send__`
- `__scp_fetch__`
- `__ssh_exec_script__`
- `__ssh_exec_function__`

---

#### Functions in SSH.sh

### `__wait_for_ssh__`
**Description**: Repeatedly attempts to connect via SSH to a specified host using a given username and password until SSH is reachable or until the maximum number of attempts is exhausted.
**Usage**:
```bash
__wait_for_ssh__ <host> <sshUsername> <sshPassword>
```
**Parameters**:
- 1 The SSH host (IP or domain).
- 2 The SSH username.
- 3 The SSH password.
**Returns**: Returns 0 if a connection is established within the max attempts, otherwise exits with code 1.
**Example Output**:
```
For __wait_for_ssh__ "192.168.1.100" "user" "pass", the output might be: SSH is up on "192.168.1.100"
```
---
### `__ssh_exec__`
**Description**: Executes a command on a remote host via SSH, supporting password or key-based authentication and optional sudo or shell invocation.
**Usage**:
```bash
__ssh_exec__ --host <host> --user <user> [--password <pass> | --identity <key>] [--port <port>] [--sudo] [--shell <shell>] [--connect-timeout <seconds>] [--extra-ssh-arg <arg>] [--strict-host-key-checking] [--known-hosts-file <path>] --command "<command>"
```
**Example Output**:
```
__ssh_exec__ --host server --user admin --identity ~/.ssh/id_ed25519 --sudo --shell bash --command "apt update"
```
---
### `__scp_send__`
**Description**: Copies one or more local files/directories to a remote destination via SCP.
**Usage**:
```bash
__scp_send__ --host <host> --user <user> [--password <pass> | --identity <key>] [--port <port>] [--recursive] [--connect-timeout <seconds>] [--extra-scp-arg <arg>] --source <path> [--source <path> ...] --destination <remotePath>
```
---
### `__scp_fetch__`
**Description**: Copies files/directories from the remote host to the local machine via SCP.
**Usage**:
```bash
__scp_fetch__ --host <host> --user <user> [--password <pass> | --identity <key>] [--port <port>] [--recursive] [--connect-timeout <seconds>] --source <remotePath> [--source <remotePath> ...] --destination <localPath>
```
---
### `__ssh_exec_script__`
**Description**: Transfers a local script (or inline content) to the remote host, sets executable permissions, runs it, and optionally removes it afterward.
**Usage**:
```bash
__ssh_exec_script__ --host <host> --user <user> [--password <pass> | --identity <key>] --script-path <path> [--remote-path <path>] [--arg <value> ...] [--sudo] [--keep-remote]
```
---
### `__ssh_exec_function__`
**Description**: Ships one or more local Bash function definitions to the remote host and invokes a selected function with optional arguments.
**Usage**:
```bash
__ssh_exec_function__ --host <host> --user <user> [--password <pass> | --identity <key>] --function <name> [--function <name> ...] [--call <name>] [--arg <value> ...] [--sudo]
```
**Example Output**:
```
__ssh_exec_function__ --host node --user root --password secret --function configure_node --call configure_node --arg 10.0.0.5
```
---
### `__ssh_exec__`
**Description**: Executes a command on a remote host via SSH, supporting password or key-based authentication and optional sudo or shell invocation.
**Usage**:
```bash
__ssh_exec__ --host <host> --user <user> [--password <pass> | --identity <key>] [--port <port>] [--sudo] [--shell <shell>] [--connect-timeout <seconds>] [--extra-ssh-arg <arg>] [--strict-host-key-checking] [--known-hosts-file <path>] --command "<command>"
```
**Example Output**:
```
__ssh_exec__ --host server --user admin --identity ~/.ssh/id_ed25519 --sudo --shell bash --command "apt update"
```
---
### `__scp_send__`
**Description**: Copies one or more local files/directories to a remote destination via SCP.
**Usage**:
```bash
__scp_send__ --host <host> --user <user> [--password <pass> | --identity <key>] [--port <port>] [--recursive] [--connect-timeout <seconds>] [--extra-scp-arg <arg>] --source <path> [--source <path> ...] --destination <remotePath>
```
---
### `__scp_fetch__`
**Description**: Copies files/directories from the remote host to the local machine via SCP.
**Usage**:
```bash
__scp_fetch__ --host <host> --user <user> [--password <pass> | --identity <key>] [--port <port>] [--recursive] [--connect-timeout <seconds>] --source <remotePath> [--source <remotePath> ...] --destination <localPath>
```
---
### `__ssh_exec_script__`
**Description**: Transfers a local script (or inline content) to the remote host, sets executable permissions, runs it, and optionally removes it afterward.
**Usage**:
```bash
__ssh_exec_script__ --host <host> --user <user> [--password <pass> | --identity <key>] --script-path <path> [--remote-path <path>] [--arg <value> ...] [--sudo] [--keep-remote]
```
---
### `__ssh_exec_function__`
**Description**: Ships one or more local Bash function definitions to the remote host and invokes a selected function with optional arguments.
**Usage**:
```bash
__ssh_exec_function__ --host <host> --user <user> [--password <pass> | --identity <key>] --function <name> [--function <name> ...] [--call <name>] [--arg <value> ...] [--sudo]
```
**Example Output**:
```
__ssh_exec_function__ --host node --user root --password secret --function configure_node --call configure_node --arg 10.0.0.5
```
---
# StateManager.sh

**Purpose**: !/bin/bash State management framework for saving, restoring, and comparing VM/CT states. Enables configuration snapshots, state tracking, and rollback capabilities.

**Features**:
- Save VM/CT configurations to JSON
- Restore configurations from snapshots
- Compare states and detect changes
- Track configuration history
- Support rollback operations
- Bulk state operations

**Usage**:
```bash
source "${UTILITYPATH}/StateManager.sh"
```

**Functions**:
- *VM State Management*: `__state_save_vm__`, `__state_restore_vm__`, `__state_compare_vm__`, `__state_export_vm__`
- *CT State Management*: `__state_save_ct__`, `__state_restore_ct__`, `__state_compare_ct__`, `__state_export_ct__`
- *Bulk Operations*: `__state_save_bulk__`, `__state_restore_bulk__`, `__state_snapshot_cluster__`
- *State Files*: `__state_list__`, `__state_info__`, `__state_delete__`, `__state_cleanup__`
- *Comparison*: `__state_diff__`, `__state_show_changes__`, `__state_validate__`

---

#### Functions in StateManager.sh

### `__state_save_vm__`
**Description**: Save VM configuration to state file.
**Usage**:
```bash
__state_save_vm__ <vmid> [state_name]
```
**Parameters**:
- 1 VMID
- 2 State name (default: timestamp)
**Returns**: 0 on success, 1 on error State file format: JSON with metadata and configuration
---
### `__state_restore_vm__`
**Description**: Restore VM configuration from state file.
**Usage**:
```bash
__state_restore_vm__ <vmid> <state_name> [--force]
```
**Parameters**:
- 1 VMID
- 2 State name
- --force Apply changes without confirmation
**Returns**: 0 on success, 1 on error
---
### `__state_compare_vm__`
**Description**: Compare current VM state with saved state.
**Usage**:
```bash
__state_compare_vm__ <vmid> <state_name>
```
**Parameters**:
- 1 VMID
- 2 State name
**Returns**: 0 if identical, 1 if different
---
### `__state_export_vm__`
**Description**: Export VM state to portable format.
**Usage**:
```bash
__state_export_vm__ <vmid> <output_file>
```
**Parameters**:
- 1 VMID
- 2 Output file path
**Returns**: 0 on success, 1 on error
---
### `__state_save_ct__`
**Description**: Save CT configuration to state file.
**Usage**:
```bash
__state_save_ct__ <ctid> [state_name]
```
**Parameters**:
- 1 CTID
- 2 State name (default: timestamp)
**Returns**: 0 on success, 1 on error
---
### `__state_restore_ct__`
**Description**: Restore CT configuration from state file.
**Usage**:
```bash
__state_restore_ct__ <ctid> <state_name> [--force]
```
**Parameters**:
- 1 CTID
- 2 State name
- --force Apply without confirmation
**Returns**: 0 on success, 1 on error
---
### `__state_compare_ct__`
**Description**: Compare current CT state with saved state.
**Usage**:
```bash
__state_compare_ct__ <ctid> <state_name>
```
**Parameters**:
- 1 CTID
- 2 State name
**Returns**: 0 if identical, 1 if different
---
### `__state_export_ct__`
**Description**: Export CT state to portable format.
**Usage**:
```bash
__state_export_ct__ <ctid> <output_file>
```
**Parameters**:
- 1 CTID
- 2 Output file path
**Returns**: 0 on success, 1 on error
---
### `__state_save_bulk__`
**Description**: Save state for multiple VMs/CTs.
**Usage**:
```bash
__state_save_bulk__ <type> <start_id> <end_id> [state_name]
```
**Parameters**:
- 1 Type (vm or ct)
- 2 Start ID
- 3 End ID
- 4 State name (default: timestamp)
**Returns**: 0 on success, 1 if any failed
---
### `__state_restore_bulk__`
**Description**: Restore state for multiple VMs/CTs.
**Usage**:
```bash
__state_restore_bulk__ <type> <start_id> <end_id> <state_name> [--force]
```
**Parameters**:
- 1 Type (vm or ct)
- 2 Start ID
- 3 End ID
- 4 State name
- --force Apply without confirmation
**Returns**: 0 on success, 1 if any failed
---
### `__state_snapshot_cluster__`
**Description**: Save state of all VMs and CTs in cluster.
**Usage**:
```bash
__state_snapshot_cluster__ [state_name]
```
**Parameters**:
- 1 State name (default: timestamp)
**Returns**: 0 on success, 1 if any failed
---
### `__state_list__`
**Description**: List all saved states.
**Usage**:
```bash
__state_list__ [type] [id]
```
**Parameters**:
- 1 Type filter (vm or ct, optional)
- 2 ID filter (optional)
**Returns**: 0 always
---
### `__state_info__`
**Description**: Show detailed information about a state file.
**Usage**:
```bash
__state_info__ <type> <id> <state_name>
```
**Parameters**:
- 1 Type (vm or ct)
- 2 ID
- 3 State name
**Returns**: 0 on success, 1 if not found
---
### `__state_delete__`
**Description**: Delete a state file.
**Usage**:
```bash
__state_delete__ <type> <id> <state_name>
```
**Parameters**:
- 1 Type (vm or ct)
- 2 ID
- 3 State name
**Returns**: 0 on success, 1 if not found
---
### `__state_cleanup__`
**Description**: Clean up old state files.
**Usage**:
```bash
__state_cleanup__ [--days <n>]
```
**Parameters**:
- --days Number of days to keep (default: 30)
**Returns**: 0 always
---
### `__state_diff__`
**Description**: Show differences between two states.
**Usage**:
```bash
__state_diff__ <type> <id> <state1> <state2>
```
**Parameters**:
- 1 Type (vm or ct)
- 2 ID
- 3 First state name
- 4 Second state name
**Returns**: 0 if identical, 1 if different
---
### `__state_show_changes__`
**Description**: Show changes that will be applied during restore.
**Usage**:
```bash
__state_show_changes__ <vmid_or_ctid> <state_name>
```
**Parameters**:
- 1 VM or CT ID
- 2 State name
**Returns**: 0 always
---
### `__state_validate__`
**Description**: Validate a state file.
**Usage**:
```bash
__state_validate__ <state_file>
```
**Parameters**:
- 1 State file path
**Returns**: 0 if valid, 1 if invalid
---
## Testing

All utilities include test coverage using the TestFramework.sh testing infrastructure.

```bash
# Run all utility tests
bash Utilities/RunAllTests.sh

# Run specific test file
bash Utilities/_TestOperations.sh

# Run with verbose output
bash Utilities/RunAllTests.sh -v
```

See `TestFramework.sh` and individual `_Test*.sh` files for testing documentation.

## Common Patterns

### Bulk VM Operations
```bash
# Start range of VMs with progress tracking
__bulk_vm_operation__ --name "Start VMs" --report 100 110 __vm_start__
```

### Argument Parsing
```bash
# Parse and validate arguments
__parse_positional_args__ "VMID:numeric:required IP:ip:required" "$@"
```

### Network Configuration
```bash
# Add network interface with VLAN
__net_vm_add_interface__ 100 net1 --bridge vmbr0 --vlan 10
```

### Error Handling
```bash
# All functions use consistent error handling
if ! __vm_start__ 100; then
    echo "Failed to start VM" >&2
    exit 1
fi
```

### Remote Execution (Cluster-Aware Commands)
```bash
# Execute qm/pct commands on the correct node automatically
__vm_node_exec__ 100 "qm destroy {vmid} --purge"
__ct_node_exec__ 200 "pct destroy {ctid} --purge"

# Execute command on specific node
__node_exec__ "pve02" "qm unlock 100"

# Auto-detect VM/CT and execute
__pve_exec__ 100 "qm template 100"
```

---

**Note**: This documentation is automatically generated from source code comments. 
To update, run: `python3 .check/UpdateUtilityDocumentation.py`
