# Script Compliance Checklist

This checklist helps ensure your scripts follow the contributing guidelines and maximize utility reuse. Use this when creating new scripts or updating existing ones.

---

## 1. Header & Documentation

- [ ] Script starts with `#!/bin/bash`
- [ ] Header includes file name and description
- [ ] Header includes usage examples (at least one starting with `./`)
- [ ] Header includes `Function Index:` placeholder
- [ ] Script purpose and requirements are clearly documented
- [ ] Usage examples show actual invocation patterns

**Example Header:**
```bash
#!/bin/bash
#
# MyScript.sh
#
# Brief description of what the script does.
#
# Usage:
#   MyScript.sh <vmid> --option value
#   MyScript.sh 100 --storage local-lvm
#
# Requirements:
#   - Must be run as root
#   - Requires Proxmox VE environment
#
# Function Index:
#   - parse_args
#   - validate_input
#   - main
#
```

---

## 2. Script Structure & Setup

- [ ] Uses `set -u` to catch undefined variables
- [ ] Sources utilities using `${UTILITYPATH}/UtilityName.sh`
- [ ] Includes shellcheck source comments for utilities
- [ ] Error trap installed: `trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR`
- [ ] Cleanup trap installed: `trap 'cleanup' EXIT`
- [ ] Functions are properly organized with separators
- [ ] **Script supports CLI mode** - can run non-interactively with all required arguments

**Required Source Pattern:**
```bash
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
```

**Interactive vs. CLI Mode:**
- Scripts CAN be interactive but MUST support CLI mode
- All required parameters MUST be available as command-line arguments
- When all arguments provided, script MUST run without prompts
- Consider adding `--yes` or `--non-interactive` flag for automation

**Example:**
```bash
# Good: Supports both modes
VMID="${1:-}"
if [[ -z "$VMID" ]]; then
    read -p "Enter VMID: " VMID
fi
__validate_numeric__ "$VMID" "VMID"

# Can be called interactively: ./script.sh
# Can be called non-interactively: ./script.sh 100
```

---

## 3. Utility Usage Review

### 3.1 Environment & Prerequisite Checks

**Instead of writing custom checks, use:**

- [ ] `__check_root__` - Verify script is run as root
- [ ] `__check_proxmox__` - Verify running on Proxmox node
- [ ] `__require_root_and_proxmox__` - Combined check
- [ ] `__check_cluster_membership__` - Verify node is in cluster
- [ ] `__ensure_dependencies__ <commands>` - Check/install required commands
- [ ] `__install_or_prompt__ <command>` - Install missing dependencies interactively

**Source:** `Prompts.sh`

**Replace this:**
```bash
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi
```

**With this:**
```bash
__check_root__
```

---

### 3.2 Argument Parsing & Validation

**Instead of writing custom parsing, use:**

- [ ] `__validate_numeric__ <value> <field_name>` - Validate numeric input
- [ ] `__validate_ip__ <ip> <field_name>` - Validate IPv4 address
- [ ] `__validate_cidr__ <cidr> <field_name>` - Validate IP/CIDR notation
- [ ] `__validate_port__ <port> <field_name>` - Validate port (1-65535)
- [ ] `__validate_range__ <value> <min> <max> <field_name>` - Validate numeric range
- [ ] `__validate_hostname__ <hostname> <field_name>` - Validate hostname
- [ ] `__validate_mac_address__ <mac> <field_name>` - Validate MAC address
- [ ] `__validate_boolean__ <value> <field_name>` - Validate boolean value
- [ ] `__validate_vmid_range__ <start> <end>` - Validate VM ID range
- [ ] `__validate_storage__ <storage> [content_type]` - Validate storage exists
- [ ] `__parse_positional_args__ <spec> "$@"` - Parse positional arguments
- [ ] `__parse_named_args__ <spec> "$@"` - Parse named arguments (--flag value)
- [ ] `__parse_flag_options__ <spec> "$@"` - Parse flags with short/long options
- [ ] `__parse_vmid_range_args__ "$@"` - Parse VM ID range pattern
- [ ] `__generate_usage__ <script> <desc> <spec>` - Generate usage text

**Source:** `ArgumentParser.sh`

**Replace this:**
```bash
if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
    echo "Error: VMID must be numeric"
    exit 1
fi
```

**With this:**
```bash
__validate_numeric__ "$VMID" "VMID" || exit 1
```

---

### 3.3 User Communication & Messaging

**Instead of writing custom echo statements, use:**

- [ ] `__info__ <message>` - Info message with spinner
- [ ] `__update__ <message>` - Update spinner message
- [ ] `__ok__ <message>` - Success message (stops spinner)
- [ ] `__warn__ <message>` - Warning message (stops spinner)
- [ ] `__err__ <message>` - Error message (stops spinner)
- [ ] `__prompt_user_yn__ <question>` - Yes/no prompt (returns 0/1)

**Source:** `Communication.sh`

**Replace this:**
```bash
echo "Starting operation..."
# ... work ...
echo "Operation completed successfully"
```

**With this:**
```bash
__info__ "Starting operation"
# ... work ...
__ok__ "Operation completed successfully"
```

---

### 3.4 VM Operations

**Instead of calling `qm` directly, use:**

- [ ] `__vm_exists__ <vmid>` - Check if VM exists
- [ ] `__vm_get_status__ <vmid>` - Get VM status
- [ ] `__vm_is_running__ <vmid>` - Check if VM is running
- [ ] `__vm_start__ <vmid>` - Start VM (cluster-aware)
- [ ] `__vm_stop__ <vmid> [--timeout N] [--force]` - Stop VM
- [ ] `__vm_shutdown__ <vmid> [--timeout N]` - Graceful shutdown
- [ ] `__vm_restart__ <vmid>` - Restart VM
- [ ] `__vm_suspend__ <vmid>` - Suspend VM
- [ ] `__vm_resume__ <vmid>` - Resume VM
- [ ] `__vm_set_config__ <vmid> --<param> <value>` - Set configuration
- [ ] `__vm_get_config__ <vmid> <param>` - Get configuration value
- [ ] `__vm_list_all__` - List all VMs in cluster
- [ ] `__vm_wait_for_status__ <vmid> <status> [timeout]` - Wait for status
- [ ] `__get_vm_info__ <vmid>` - Get comprehensive VM info
- [ ] `__iterate_vms__ <start> <end> <callback> [args]` - Iterate VM range

**Remote Execution (for commands without utility wrappers):**

- [ ] `__vm_node_exec__ <vmid> <command>` - Execute command on VM's node (use `{vmid}` placeholder)
- [ ] `__ct_node_exec__ <ctid> <command>` - Execute command on CT's node (use `{ctid}` placeholder)
- [ ] `__node_exec__ <node> <command>` - Execute command on specific node
- [ ] `__pve_exec__ <id> <command>` - Auto-detect VM/CT and execute on correct node

**Source:** `ProxmoxAPI.sh`

**Replace this:**
```bash
if qm status "$VMID" | grep -q "status: running"; then
    qm stop "$VMID"
fi
```

**With this:**
```bash
if __vm_is_running__ "$VMID"; then
    __vm_stop__ "$VMID"
fi
```

**For commands without utility functions (e.g., qm destroy, qm unlock):**

**Replace this:**
```bash
node=$(__get_vm_node__ "$VMID")
ssh "root@${node}" "qm destroy $VMID --purge"
```

**With this:**
```bash
__vm_node_exec__ "$VMID" "qm destroy {vmid} --purge"
```

---

### 3.5 Container (CT) Operations

**Instead of calling `pct` directly, use:**

- [ ] `__ct_exists__ <ctid>` - Check if CT exists
- [ ] `__ct_get_status__ <ctid>` - Get CT status
- [ ] `__ct_is_running__ <ctid>` - Check if CT is running
- [ ] `__ct_start__ <ctid>` - Start CT
- [ ] `__ct_stop__ <ctid> [--force]` - Stop CT
- [ ] `__ct_shutdown__ <ctid>` - Graceful shutdown
- [ ] `__ct_restart__ <ctid>` - Restart CT
- [ ] `__ct_set_config__ <ctid> -<param> <value>` - Set configuration
- [ ] `__ct_get_config__ <ctid> <param>` - Get configuration value
- [ ] `__ct_list_all__` - List all CTs in cluster
- [ ] `__ct_wait_for_status__ <ctid> <status> [timeout]` - Wait for status
- [ ] `__ct_exec__ <ctid> <command>` - Execute command in CT
- [ ] `__get_ct_info__ <ctid>` - Get comprehensive CT info
- [ ] `__iterate_cts__ <start> <end> <callback> [args]` - Iterate CT range

**Remote Execution (for commands without utility wrappers):**

- [ ] `__ct_node_exec__ <ctid> <command>` - Execute command on CT's node (use `{ctid}` placeholder)

**Source:** `ProxmoxAPI.sh`

**For commands without utility functions (e.g., pct destroy, pct unlock):**

**Replace this:**
```bash
node=$(__get_vm_node__ "$CTID")
ssh "root@${node}" "pct destroy $CTID --purge"
```

**With this:**
```bash
__ct_node_exec__ "$CTID" "pct destroy {ctid} --purge"
```

---

### 3.6 Bulk Operations

**Instead of writing loops, use:**

- [ ] `__bulk_operation__ <start> <end> <callback> [args]` - Generic bulk operation
- [ ] `__bulk_vm_operation__ [opts] <start> <end> <callback> [args]` - Bulk VM operation
- [ ] `__bulk_ct_operation__ [opts] <start> <end> <callback> [args]` - Bulk CT operation
- [ ] `__bulk_with_retry__ <retries> <start> <end> <callback> [args]` - With retry logic
- [ ] `__bulk_parallel__ <max_jobs> <start> <end> <callback> [args]` - Parallel execution
- [ ] `__bulk_summary__` - Print operation summary
- [ ] `__bulk_report__` - Print detailed report
- [ ] `__bulk_validate_range__ <start> <end>` - Validate range is reasonable
- [ ] `__bulk_save_state__ <file>` - Save state for resume
- [ ] `__bulk_load_state__ <file>` - Load saved state

**Source:** `BulkOperations.sh`

**Replace this:**
```bash
for vmid in $(seq $START_VMID $END_VMID); do
    if qm status "$vmid" &>/dev/null; then
        qm start "$vmid"
    fi
done
```

**With this:**
```bash
__bulk_vm_operation__ --name "Start VMs" --report $START_VMID $END_VMID __vm_start__
```

---

### 3.7 Network Operations

**Instead of manually configuring networks, use:**

- [ ] `__net_vm_add_interface__ <vmid> <net_id> [opts]` - Add VM interface
- [ ] `__net_vm_remove_interface__ <vmid> <net_id>` - Remove VM interface
- [ ] `__net_vm_set_bridge__ <vmid> <net_id> <bridge>` - Set bridge
- [ ] `__net_vm_set_vlan__ <vmid> <net_id> <vlan>` - Set VLAN tag
- [ ] `__net_vm_set_mac__ <vmid> <net_id> <mac>` - Set MAC address
- [ ] `__net_vm_get_interfaces__ <vmid>` - Get all interfaces
- [ ] `__net_ct_add_interface__ <ctid> <net_id> [opts]` - Add CT interface
- [ ] `__net_ct_remove_interface__ <ctid> <net_id>` - Remove CT interface
- [ ] `__net_ct_set_ip__ <ctid> <net_id> <ip>` - Set CT IP
- [ ] `__net_ct_set_gateway__ <ctid> <net_id> <gateway>` - Set CT gateway
- [ ] `__net_ct_set_nameserver__ <ctid> <nameserver>` - Set nameserver
- [ ] `__net_validate_ip__ <ip>` - Validate IP format
- [ ] `__net_validate_cidr__ <cidr>` - Validate CIDR format
- [ ] `__net_validate_mac__ <mac>` - Validate MAC format
- [ ] `__net_is_ip_in_use__ <ip>` - Check if IP is in use
- [ ] `__net_get_next_ip__ <base_ip> [start_host]` - Get next available IP
- [ ] `__net_test_connectivity__ <vmid_or_ctid> <target>` - Test connectivity
- [ ] `__net_bulk_set_bridge__ <start> <end> <net_id> <bridge>` - Bulk bridge change
- [ ] `__net_bulk_set_vlan__ <start> <end> <net_id> <vlan>` - Bulk VLAN change

**Source:** `NetworkHelper.sh`

---

### 3.8 Cluster & Node Queries

**Instead of parsing `pvecm` output, use:**

- [ ] `__get_remote_node_ips__` - Get IPs of remote cluster nodes
- [ ] `__check_cluster_membership__` - Verify node is in cluster
- [ ] `__get_number_of_cluster_nodes__` - Get node count
- [ ] `__init_node_mappings__` - Initialize node mapping arrays
- [ ] `__get_ip_from_name__ <node_name>` - Get node IP from name
- [ ] `__get_name_from_ip__ <ip>` - Get node name from IP
- [ ] `__get_cluster_lxc__` - Get all LXC VMIDs in cluster
- [ ] `__get_server_lxc__ <node>` - Get LXC VMIDs on specific node
- [ ] `__get_cluster_vms__` - Get all VM VMIDs in cluster
- [ ] `__get_server_vms__ <node>` - Get VM VMIDs on specific node
- [ ] `__get_vm_node__ <vmid>` - Get node where VM is located
- [ ] `__resolve_node_name__ <spec>` - Resolve node specification to name
- [ ] `__validate_vmid__ <vmid>` - Validate VMID exists and is VM
- [ ] `__validate_ctid__ <ctid>` - Validate CTID exists and is CT
- [ ] `get_ip_from_vmid <vmid>` - Get VM IP via ARP scan
- [ ] `__get_ip_from_guest_agent__ --vmid <vmid> [opts]` - Get IP from guest agent

**Source:** `Queries.sh`

---

### 3.9 SSH & Remote Operations

**Instead of using ssh/scp directly, use:**

- [ ] `__wait_for_ssh__ <host> <user> <pass>` - Wait for SSH to be available
- [ ] `__ssh_exec__ --host <host> --user <user> --command <cmd> [opts]` - Execute remote command
- [ ] `__scp_send__ --host <host> --user <user> --source <file> --destination <path> [opts]` - Send files
- [ ] `__scp_fetch__ --host <host> --user <user> --source <path> --destination <file> [opts]` - Fetch files
- [ ] `__ssh_exec_script__ --host <host> --user <user> --script-path <path> [opts]` - Execute script remotely
- [ ] `__ssh_exec_function__ --host <host> --user <user> --function <name> [opts]` - Execute function remotely

**Source:** `SSH.sh`

---

### 3.10 Data Conversion

**Instead of writing conversion logic, use:**

- [ ] `__ip_to_int__ <ip>` - Convert IP to 32-bit integer
- [ ] `__int_to_ip__ <int>` - Convert integer to IP
- [ ] `__cidr_to_netmask__ <cidr>` - Convert CIDR to netmask
- [ ] `__vmid_to_mac_prefix__ --vmid <vmid> [opts]` - Generate MAC prefix from VMID

**Source:** `Conversion.sh`

---

### 3.11 State Management

**Instead of manual config backups, use:**

- [ ] `__state_save_vm__ <vmid> <name>` - Save VM state
- [ ] `__state_save_ct__ <ctid> <name>` - Save CT state
- [ ] `__state_restore_vm__ <vmid> <name>` - Restore VM state
- [ ] `__state_restore_ct__ <ctid> <name>` - Restore CT state
- [ ] `__state_list__ <vmid_or_ctid>` - List saved states
- [ ] `__state_delete__ <vmid_or_ctid> <name>` - Delete saved state
- [ ] `__state_show_changes__ <vmid_or_ctid> <name>` - Show config changes
- [ ] `__state_export__ <vmid_or_ctid> <name> <format>` - Export state
- [ ] `__state_validate__ <file>` - Validate state file

**Source:** `StateManager.sh`

---

### 3.12 Terminal Colors & Formatting

**Only use if custom formatting is needed beyond Communication.sh:**

- [ ] `__line_rgb__ <text> <r> <g> <b>` - Print colored line
- [ ] `__line_gradient__ <text> <r1> <g1> <b1> <r2> <g2> <b2>` - Print gradient line
- [ ] `__gradient_print__ <text> <r1> <g1> <b1> <r2> <g2> <b2>` - Print multi-line gradient

**Source:** `Colors.sh`

**Note:** For most cases, use Communication.sh functions instead.

---

## 4. Code Quality Checks

- [ ] All variables are quoted: `"${var}"` not `$var`
- [ ] Local variables use `local` keyword in functions
- [ ] Using `[[ ... ]]` for conditionals (not `[ ... ]`)
- [ ] Using `(( ... ))` for arithmetic
- [ ] No code duplication - reused logic moved to functions
- [ ] Clear function names describing what they do
- [ ] Functions have single responsibility
- [ ] Error messages are descriptive and actionable
- [ ] All error paths properly handled

---

## 5. Testing & Validation

- [ ] Script tested in development environment
- [ ] **Tested in both interactive mode and CLI mode**
- [ ] CLI mode works with all arguments provided (no prompts)
- [ ] Interactive mode works when arguments are missing
- [ ] Edge cases tested (missing arguments, invalid input, etc.)
- [ ] Testing notes added to script footer
- [ ] ShellCheck run and warnings addressed
- [ ] Script works when launched via GUI.sh
- [ ] Script works when run directly

**Testing Notes Template:**
```bash
# Testing status:
#   - Date: YYYY-MM-DD
#   - Environment: PVE version, cluster/standalone
#   - Test scenarios:
#     * Interactive mode - PASS/FAIL
#     * CLI mode (all args) - PASS/FAIL
#     * Edge case 1 - PASS/FAIL
#     * Edge case 2 - PASS/FAIL
#   - Known limitations: List any known issues
```

---

## 6. Final Review

- [ ] Run `.check/UpdateFunctionIndex.py` to update Function Index
- [ ] All utility functions have proper source statements
- [ ] Header documentation is complete and accurate
- [ ] Usage examples are tested and correct
- [ ] Script follows consistent naming conventions
- [ ] Cleanup on exit is properly handled
- [ ] No sensitive data (passwords, tokens) in code or logs
- [ ] Script follows security best practices
- [ ] Code is readable and well-commented where needed

---

## Quick Utility Reference

### Most Commonly Used Utilities

| When you need to... | Use this utility | Source this file |
|---------------------|------------------|------------------|
| Check if root | `__check_root__` | `Prompts.sh` |
| Check if Proxmox | `__check_proxmox__` | `Prompts.sh` |
| Validate IP address | `__validate_ip__` | `ArgumentParser.sh` |
| Validate numeric input | `__validate_numeric__` | `ArgumentParser.sh` |
| Show info message | `__info__` | `Communication.sh` |
| Show success message | `__ok__` | `Communication.sh` |
| Show error message | `__err__` | `Communication.sh` |
| Start a VM | `__vm_start__` | `ProxmoxAPI.sh` |
| Stop a VM | `__vm_stop__` | `ProxmoxAPI.sh` |
| Check if VM exists | `__vm_exists__` | `ProxmoxAPI.sh` |
| Check if VM running | `__vm_is_running__` | `ProxmoxAPI.sh` |
| Execute command on VM's node | `__vm_node_exec__` | `ProxmoxAPI.sh` |
| Execute command on CT's node | `__ct_node_exec__` | `ProxmoxAPI.sh` |
| Execute command on any node | `__node_exec__` | `ProxmoxAPI.sh` |
| Start a CT | `__ct_start__` | `ProxmoxAPI.sh` |
| Stop a CT | `__ct_stop__` | `ProxmoxAPI.sh` |
| Bulk VM operations | `__bulk_vm_operation__` | `BulkOperations.sh` |
| Get VM IP | `get_ip_from_vmid` | `Queries.sh` |
| Parse arguments | `__parse_positional_args__` | `ArgumentParser.sh` |

### Complete Function Reference

See `Utilities/_Utilities.md` for comprehensive documentation of all 172+ utility functions.

---

## Script Conversion Workflow

1. **Identify current functionality** - What does the script do?
2. **Find utility equivalents** - Check `Utilities/_Utilities.md` for existing functions
3. **Source required utilities** - Add source statements for needed utilities
4. **Replace custom code** - Replace custom implementations with utility calls
5. **Test thoroughly** - Ensure behavior is unchanged
6. **Document changes** - Update testing notes

---

## Example: Before and After

### Before (Custom Code)
```bash
#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Must run as root"
    exit 1
fi

VMID=$1
if [ -z "$VMID" ]; then
    echo "Usage: $0 <vmid>"
    exit 1
fi

if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
    echo "VMID must be numeric"
    exit 1
fi

if qm status "$VMID" 2>/dev/null | grep -q "running"; then
    echo "VM $VMID is already running"
    exit 0
fi

echo "Starting VM $VMID..."
qm start "$VMID"
echo "VM started successfully"
```

### After (Using Utilities)
```bash
#!/bin/bash
#
# StartVM.sh
#
# Starts a Proxmox VM with validation and error handling.
#
# Usage:
#   StartVM.sh <vmid>
#
# Function Index:
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ProxmoxAPI.sh
source "${UTILITYPATH}/ProxmoxAPI.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

main() {
    __check_root__
    
    # Parse and validate arguments
    __parse_positional_args__ "VMID:numeric:required" "$@" || exit 1
    
    # Check if VM exists
    if ! __vm_exists__ "$VMID"; then
        __err__ "VM $VMID does not exist"
        exit 1
    fi
    
    # Check if already running
    if __vm_is_running__ "$VMID"; then
        __warn__ "VM $VMID is already running"
        exit 0
    fi
    
    # Start the VM
    __info__ "Starting VM $VMID"
    if __vm_start__ "$VMID"; then
        __ok__ "VM $VMID started successfully"
    else
        __err__ "Failed to start VM $VMID"
        exit 1
    fi
}

main "$@"

# Testing status:
#   - 2025-10-27: Tested on PVE 8.2, single node
```

**Benefits of utility version:**
- Consistent error handling
- Better user feedback with spinner
- Proper input validation
- Cluster-aware VM operations
- Follows all coding standards
- More maintainable and readable
