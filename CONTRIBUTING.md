# Contributing Guide

Thank you for your interest in contributing to this repository! We appreciate your help in improving and expanding our bash scripts for Proxmox management and automation. Below are the guidelines and best practices we ask all contributors to follow.

---

## 1. Project Scope

This repository contains Bash scripts (`.sh` files) that help automate and manage Proxmox tasks. The goal is to maintain a clean, consistent, and secure set of scripts that are easy to understand and extend.

---

## 2. Getting Started

1. **Fork and Clone**
   - Fork the repository to your own GitHub account.
   - Clone your fork locally.

2. **Make Your Changes**
   - Follow the coding guidelines below.
   - **Use the [Script Compliance Checklist](Utilities/_ScriptComplianceChecklist.md)** to ensure your script follows all conventions.
   - Test your changes thoroughly in a development/test environment.

3. **Submit a Pull Request**
   - Open a pull request (PR) against the repository’s `main` branch.
   - Provide a clear title and description, referencing any related issues.

---

## 3. Shell Script Style Guide

> This section consolidates the repository’s scripting conventions (formerly in `Utilities/ScriptStyleGuide.md`) so everything you need lives in one place.

### 3.1 Core Principles

- Keep scripts simple, idempotent, and safe for Proxmox nodes.
- Prefer readable, well-documented code over clever one-liners.
- **ALWAYS use utilities from `Utilities/` - never reinvent existing functionality.**
- **Scripts CAN be interactive but MUST support a CLI mode** that bypasses all prompts and runs automatically with command-line arguments.

**Key Rule: Use Utilities First**
Before writing any logic, check `Utilities/_Utilities.md` for existing functions. The utilities provide:
- Cluster-aware VM/CT operations (Operations.sh)
- Bulk operation frameworks (BulkOperations.sh)
- Declarative argument parsing (ArgumentParser.sh)
- Progress tracking and error handling (Communication.sh)

If you find yourself writing manual loops, parsing arguments with regex, or calling `qm`/`pct` directly - you're probably reinventing a utility function.

### 3.2 Where to Place Files

- Utilities and shared helpers: `Utilities/`
- Feature scripts: domain folders (e.g., `Host/`, `Cluster/`, `Storage/`)
- Use descriptive MixedCase filenames such as `CreateCluster.sh`.

### 3.3 Shebang and Strictness

- Start every script with `#!/bin/bash`.
- Avoid enabling `set -e` globally; prefer explicit error handling, `set -e` within narrow scopes, or traps for critical sections.
- When you need strict error handling, install an `ERR` trap to provide context on failure (see section 3.9).

### 3.4 Required Header

All scripts must begin with a comment block that covers:

- File name and short description
- Usage example(s) - **Format: `#   ScriptName.sh <args>`** (no `./` prefix)
- Relevant notes (root requirement, Proxmox requirement, etc.)
- A “Function Index” placeholder (see next section)


**Important:** Usage lines should use the script name only (e.g., `ScriptName.sh`), not `./ScriptName.sh`. Scripts require `UTILITYPATH` to be set (automatically done by `GUI.sh` or must be exported manually).
Example header:

```bash
#!/bin/bash
#
# MyScript.sh
#
# Short description of what the script does.
#
# Usage:
#   MyScript.sh <arg1> [--flag]
#   MyScript.sh 100 --type host --cores 4
#
# Function Index:
#   - check_something
#   - do_work
#
```

### 3.5 Function Index

- Keep the header line exactly `# Function Index:` followed by individual `#   - function_name` lines.
- The helper at `.check/UpdateFunctionIndex.py` rewrites this section automatically by scanning for `name() {` or `function name()` definitions. Leave the list contiguous with the rest of the header comment.

### 3.6 Common Script Structure

1. Source needed utilities (e.g., `source "${UTILITYPATH}/ArgumentParser.sh"`). When launched via `GUI.sh`, `${UTILITYPATH}` is already exported.
2. Perform prerequisite checks (`__check_root__`, `__check_proxmox__`, dependency checks with `command -v`).
3. **Parse arguments using `__parse_args__`** - see section 3.10 for details. ArgumentParser handles validation and help generation automatically.
4. Group functions logically with clear separators such as `# --- Preliminary Checks -----------------------------------------------------`.
5. Implement main logic inside a `main()` function and call it at the end of the script.
6. Record testing notes near the bottom of the file.

**IMPORTANT**: When using utility functions in your script, you **MUST** source the corresponding utility script at the top of your file. Each utility function requires its parent script to be sourced.

Example:
```bash
# For argument parsing (ALWAYS needed)
source "${UTILITYPATH}/ArgumentParser.sh"

# If using __vm_start__ or __ct_exists__
source "${UTILITYPATH}/Operations.sh"

# If using __info__ or __err__
source "${UTILITYPATH}/Communication.sh"
```

See `Utilities/_Utilities.md` for a complete reference of which functions belong to which utility files.

### 3.7 Coding Conventions

- Use consistent indentation (stick to the file’s existing spacing).
- Prefer `local var` inside functions.
- Quote all variable expansions (`"${var}"`) unless you intentionally rely on word splitting.
- Use `[[ ... ]]` for conditionals and `(( ... ))` for arithmetic.
- Choose descriptive variable names; reserve UPPERCASE for environment-level knobs and use lower/mixed case for locals.
- **Never duplicate logic that exists in utilities** - always import and use utility functions.
- **Avoid `((var++))` and `((var--))` syntax** - use `var=$((var + 1))` or `var=$((var - 1))` instead for compatibility with `set -e` error handling.

### 3.8 Logging and User Feedback

- Source `Utilities/Communication.sh` to access helpers such as `__info__`, `__update__`, `__ok__`, and `__err__` for consistent messaging.
- `Utilities/Colors.sh` provides ANSI color helpers if you need custom formatting beyond the communication helpers.

### 3.9 Error Handling and Cleanup

- Install an error trap when using `Communication.sh`:
   ```bash
   trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
   ```
- Use `trap cleanup EXIT` to ensure temporary files or background processes are removed.
- Provide specific error messages before exiting so users know what to fix.
- Check for required commands with `command -v` and exit with meaningful codes.

### 3.10 Argument Parsing

**MANDATORY: Always use ArgumentParser.sh for argument parsing.**

The ArgumentParser.sh utility provides a one-line declarative API that handles both parsing and validation automatically. This is the **only approved method** for argument parsing in this repository.

**Quick Decision Guide:**

| Validation Type | Tool | Example |
|----------------|------|---------|
| Type checking (ip, vmid, port, etc.) | **ArgumentParser** | `__parse_args__ "ip:ip port:port" "$@"` |
| Range validation (1-128, etc.) | **ArgumentParser** | `__parse_args__ "cores:cpu" "$@"` |
| Format validation (standard types) | **ArgumentParser** | `__parse_args__ "mac:mac fqdn:fqdn" "$@"` |
| Relationships between arguments | **Custom function** | vCPUs can't exceed cores |
| Complex format patterns | **Custom function** | Affinity list (0,1,2 or 0-3) |
| Business logic rules | **Custom function** | At least one option required |
| Conditional warnings | **Custom function** | NUMA on small VMs |

**Pattern:** Use ArgumentParser for all parsing + type validation, then add a separate `validate_custom_options()` function for business logic.

**Why ArgumentParser is Required:**
- Automatic type validation (vmid, ip, port, etc.)
- Built-in `--help` generation - no manual `usage()` functions needed
- Consistent error messages across all scripts
- Reduces boilerplate from 100+ lines to ~1 line
- Type-safe with clear declarations
- Prevents common parsing bugs

**Basic Usage Pattern:**
```bash
#!/bin/bash
source "${UTILITYPATH}/ArgumentParser.sh"

# Define arguments in one line
__parse_args__ "start:vmid end:vmid --force:flag --node:string:?" "$@"

# Variables are automatically created in UPPERCASE
echo "Processing VMs ${START} to ${END}"
[[ "$FORCE" == "true" ]] && echo "Force mode enabled"
[[ -n "$NODE" ]] && echo "Target node: ${NODE}"
```

**Argument Spec Format:**

| Format | Description | Example |
|--------|-------------|---------|
| `name:type` | Required positional | `vmid:vmid` |
| `name:type:default` | Optional with default | `port:port:22` |
| `name:type:?` | Optional without default | `node:string:?` |
| `--name:flag` | Boolean flag | `--force:flag` |
| `--name:type` | Named option | `--cores:cpu` |
| `--name:type:default` | Named with default | `--storage:storage:local-lvm` |

**Common Types:**

| Category | Types | Validation |
|----------|-------|------------|
| **IDs** | `vmid`, `number`, `integer` | Numeric validation, range checks |
| **Network** | `ip`, `ipv4`, `ipv6`, `cidr`, `gateway`, `mac`, `port` | Format validation |
| **DNS** | `hostname`, `fqdn`, `url`, `email` | RFC compliance |
| **Proxmox** | `storage`, `bridge`, `vlan`, `node`, `pool`, `ostype` | Proxmox-specific |
| **Resources** | `cpu`, `memory`, `disk` | Resource validation |
| **General** | `string`, `path`, `boolean`, `flag` | Basic types |

**Complete Real-World Example:**
```bash
#!/bin/bash
#
# BulkConfigureCPU.sh
#
# Usage:
#   BulkConfigureCPU.sh 100 110 --cores 4 --sockets 2
#   BulkConfigureCPU.sh 100 110 --type host --numa 1
#
source "${UTILITYPATH}/ArgumentParser.sh"
source "${UTILITYPATH}/Communication.sh"

# Parse all arguments in one line
__parse_args__ "start_id:vmid end_id:vmid --cores:cpu:? --sockets:number:? --numa:boolean:? --type:string:?" "$@"

# Custom validation for business logic
if [[ -n "$CORES" && -n "$SOCKETS" && -n "$NUMA" ]]; then
    total=$((CORES * SOCKETS))
    if [[ "$NUMA" == "1" && $total -le 4 ]]; then
        __warn__ "NUMA enabled for small VM (${total} cores) - may not be beneficial"
    fi
fi

# Rest of your script logic...
```

**Handling Custom Validation:**

ArgumentParser handles type validation. For business logic validation, create a separate function:

```bash
__parse_args__ "start:vmid end:vmid --cores:cpu:? --vcpus:cpu:?" "$@"

# Custom validation for relationships between arguments
validate_custom_options() {
    # Check at least one option provided
    if [[ -z "$CORES" && -z "$VCPUS" ]]; then
        __err__ "At least one option must be specified"
        exit 64
    fi
    
    # Check vCPUs doesn't exceed cores
    if [[ -n "$VCPUS" && -n "$CORES" && $VCPUS -gt $CORES ]]; then
        __err__ "vCPUs ($VCPUS) cannot exceed cores ($CORES)"
        exit 64
    fi
}

validate_custom_options
```

**When Custom Validation is Needed:**

Use a separate `validate_custom_options()` function when you need to validate:

1. **Relationships between arguments**
   ```bash
   # Example: vCPUs can't exceed total cores
   if [[ -n "$VCPUS" && -n "$CORES" && -n "$SOCKETS" ]]; then
       total=$((CORES * SOCKETS))
       if (( VCPUS > total )); then
           __err__ "vCPUs ($VCPUS) cannot exceed total cores ($total)"
           exit 64
       fi
   fi
   ```

2. **Complex format patterns ArgumentParser doesn't support**
   ```bash
   # Example: CPU affinity list format (0,1,2 or 0-3)
   if [[ -n "$AFFINITY" ]]; then
       if ! [[ "$AFFINITY" =~ ^[0-9,\-]+$ ]]; then
           __err__ "Invalid affinity format. Use: 0,1,2,3 or 0-3"
           exit 64
       fi
   fi
   ```

3. **Business logic rules**
   ```bash
   # Example: At least one option must be specified
   if [[ -z "$CORES" && -z "$SOCKETS" && -z "$NUMA" ]]; then
       __err__ "At least one CPU option must be specified"
       exit 64
   fi
   ```

4. **Conditional warnings (not errors)**
   ```bash
   # Example: Warn about potentially inefficient configuration
   if [[ "$NUMA" == "1" && $total_cores -le 4 ]]; then
       __warn__ "NUMA enabled for small VM (${total_cores} cores) - may not be beneficial"
   fi
   ```

**Pattern to Follow:**

```bash
#!/bin/bash
source "${UTILITYPATH}/ArgumentParser.sh"
source "${UTILITYPATH}/Communication.sh"

# 1. Parse arguments with ArgumentParser
__parse_args__ "start:vmid end:vmid --cores:cpu:? --flags:string:?" "$@"

# 2. Create separate validation function for custom logic
validate_custom_options() {
    # Check relationships
    if [[ -n "$CORES" && -n "$VCPUS" && $VCPUS -gt $CORES ]]; then
        __err__ "Invalid relationship: vCPUs > cores"
        exit 64
    fi
    
    # Check complex formats
    if [[ -n "$FLAGS" ]]; then
        if ! [[ "$FLAGS" =~ ^[+\-][a-z0-9_\-]+(,[+\-][a-z0-9_\-]+)*$ ]]; then
            __err__ "Invalid flags format: use +flag1,-flag2"
            exit 64
        fi
    fi
    
    # Business logic
    if [[ -z "$CORES" && -z "$FLAGS" ]]; then
        __err__ "At least one option required"
        exit 64
    fi
}

# 3. Call validation function
validate_custom_options

# 4. Continue with script logic
main() {
    # Your script logic here
}

main
```

**Real-World Example from BulkConfigureCPU.sh:**

See `VirtualMachines/Hardware/BulkConfigureCPU.sh` for a complete example that demonstrates:
- ArgumentParser handling basic types (vmid, cpu, number, boolean, string)
- Separate `validate_custom_options()` function for:
  - Relationship validation (vCPUs vs total cores)
  - Complex format patterns (affinity list, CPU flags)
  - Business logic (at least one option required)
  - Conditional warnings (NUMA on small VMs)

**Benefits:**
- Automatic validation based on type
- Built-in help generation (--help) - **no need for manual `usage()` functions**
- Consistent error messages
- Less boilerplate code (typically 100+ lines reduced to ~10)
- Type-safe with clear declarations

**Important Notes:**
- **DO NOT create manual `usage()` functions** - ArgumentParser automatically generates help with `--help`
- **GUI.sh extracts usage examples from header comments** (lines starting with `#   ScriptName.sh`)
- Usage format should be `ScriptName.sh <args>` without `./` prefix
- For complex validations beyond type checking, create a separate validation function
- All variables are automatically created in UPPERCASE (e.g., `start:vmid` becomes `$START`)

**What NOT to Do:**
```bash
# DON'T: Manual parsing with case/shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cores) CORES="$2"; shift 2 ;;
        --sockets) SOCKETS="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# DON'T: Manual validation
if ! [[ "$CORES" =~ ^[0-9]+$ ]]; then
    echo "Cores must be numeric"
    exit 1
fi

# DON'T: Manual usage functions
usage() {
    cat <<-USAGE
    Usage: script.sh <args>
    ...
USAGE
}

# DO: Use ArgumentParser
__parse_args__ "cores:cpu sockets:number" "$@"
```

**Legacy Validation Functions:**
All `__validate_*__` functions are still available for manual validation when needed:
- `__validate_numeric__`, `__validate_ip__`, `__validate_vmid_range__`, etc.
- Only use these if ArgumentParser doesn't support your use case

### 3.11 Non-Interactive Mode Support

**IMPORTANT: All scripts MUST support non-interactive execution through environment variable detection.**

Scripts automatically detect whether they're running in an interactive or automated context via the `NON_INTERACTIVE` environment variable. This is set automatically by:
- GUI.sh (for all remote executions)
- Remote execution frameworks
- CI/CD pipelines
- Automation tools

**The Standard:**

**DO THIS** - Use `__prompt_user_yn__` from Prompts.sh:
```bash
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

main() {
    __check_root__
    __check_proxmox__
    
    # This automatically works in both interactive and non-interactive modes
    if __prompt_user_yn__ "Proceed with operation?"; then
        perform_operation
    fi
    
    __ok__ "Operation complete"
}

main "$@"
```

**DON'T DO THIS** - Don't parse `--non-interactive` flags:
```bash
# WRONG! Don't add this
while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive)
            export NON_INTERACTIVE=1
            shift
            ;;
    esac
done
```

**For Destructive Operations:**

Destructive operations MUST require explicit confirmation to prevent accidental data loss. There are two approaches:

**Option 1: Use `--force` flag (Recommended for single operations)**
```bash
# Parse --force flag
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

main() {
    __check_root__
    
    __warn__ "DESTRUCTIVE: This will delete all data"
    
    # Safety check: Require --force in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ $FORCE -eq 0 ]]; then
        __err__ "Destructive operation requires --force flag in non-interactive mode"
        __err__ "Usage: $0 --force"
        __err__ "Or add '--force' to parameters in GUI"
        exit 1
    fi
    
    # Prompt for confirmation (unless force is set)
    if [[ $FORCE -eq 1 ]]; then
        __info__ "Force mode enabled - proceeding without confirmation"
    elif ! __prompt_user_yn__ "Really delete?"; then
        __info__ "Operation cancelled"
        exit 0
    fi
    
    perform_deletion
}
```

**Option 2: Use `--yes` flag (For bulk operations with ArgumentParser)**
```bash
# Use ArgumentParser with --yes flag
__parse_args__ "vmid:vmid --yes:flag" "$@"

main() {
    __check_root__
    
    __warn__ "DESTRUCTIVE: This will delete VM $VMID"
    
    # Safety check: Require --yes in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ "$YES" != "true" ]]; then
        __err__ "Destructive operation requires --yes flag in non-interactive mode"
        __err__ "Usage: $0 $VMID --yes"
        __err__ "Or add '--yes' to parameters in GUI"
        exit 1
    fi
    
    # Prompt for confirmation (unless --yes provided)
    if [[ "$YES" == "true" ]]; then
        __info__ "Auto-confirm enabled (--yes flag) - proceeding without prompt"
    elif ! __prompt_user_yn__ "Really delete VM $VMID?"; then
        __info__ "Operation cancelled"
        exit 0
    fi
    
    perform_deletion
}
```

**When to Use Each:**

| Flag | Use Case | Example Scripts |
|------|----------|-----------------|
| `--force` | Single destructive operations | WipeDisk.sh, RemoveLocalLVMAndExpand.sh, DeleteCluster.sh |
| `--yes` | Bulk operations with ArgumentParser | BulkDelete.sh, BulkDeleteRange.sh |

**Both patterns provide:**
- Protection in non-interactive mode (requires explicit flag)
- User confirmation in interactive mode (unless flag provided)
- Clear error messages for GUI users
- Consistent behavior across repository

**Benefits:**
- Consistent behavior across all scripts
- Automatic detection by GUI and automation tools
- No manual flags needed for non-interactive execution
- Destructive operations protected by explicit --force
- Simpler code (no flag parsing needed)

**See Also:**
- `NON_INTERACTIVE_STANDARD.md` - Complete specification
- `Utilities/Prompts.sh` - Functions that auto-detect mode

### 3.12 Testing Notes

- Add a `# Testing status` comment near the end of the script describing how you validated it (environments, scenarios, known limitations).
- Run [ShellCheck](https://www.shellcheck.net/) or equivalent linters and address warnings where practical.
- **Test both interactive and CLI modes** to ensure full functionality in both scenarios.
- **When creating tests for utility functions**, use the TestFramework.sh located in `Utilities/`:
  - Source `TestFramework.sh` and use `run_test_suite` to execute tests
  - Use assertion functions like `assert_exit_code`, `assert_equals`, etc.
  - Follow the naming convention `_Test<UtilityName>.sh` (e.g., `_TestArgumentParser.sh`)
  - See existing test files in `Utilities/` for examples of proper formatting

### 3.13 Common Anti-Patterns to Avoid

**Don't use manual loops for bulk operations on existing VMs/CTs**
```bash
for (( vmid=100; vmid<=110; vmid++ )); do
    qm start "$vmid"  # Fails on multi-node clusters
done
```
**Use BulkOperations framework** - handles cluster-awareness, progress tracking, error handling
```bash
__bulk_vm_operation__ --name "Start VMs" --report 100 110 __vm_start__
```

**Exception: Simple loops ARE appropriate when:**
- Creating new VMs/CTs that don't exist yet (e.g., cloning, provisioning)
- All operations happen on a single node (not cluster-wide)
- Operations are inherently sequential and can't be parallelized

Example - BulkClone using simple loop (appropriate):
```bash
for (( i=0; i<COUNT; i++ )); do
    target_vmid=$((START_VMID + i))
    __node_exec__ "$source_node" "qm clone ${SOURCE_VMID} ${target_vmid} --name ${vm_name}"
done
```
This is correct because: clones don't exist yet, all execute on source VM's node, and cloning is sequential.

**Don't use direct qm/pct calls** - `qm stop 100` fails if VM is on different node
**Use ProxmoxAPI functions** - `__vm_stop__ 100` works cluster-wide

**Don't manually handle node detection and SSH**
```bash
node=$(__get_vm_node__ "$vmid")
ssh "root@${node}" "qm destroy $vmid --purge"
```
**Use remote execution utilities** - `__vm_node_exec__ "$vmid" "qm destroy {vmid} --purge"`

**Don't use manual argument parsing**
```bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cores) CORES="$2"; shift 2 ;;
        --sockets) SOCKETS="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done
if ! [[ "$CORES" =~ ^[0-9]+$ ]]; then
    echo "Invalid cores"
    exit 1
fi
```
**Use ArgumentParser** - `__parse_args__ "cores:cpu sockets:number" "$@"` (handles parsing, validation, and help automatically)

**Don't create manual usage() functions**
```bash
# NEVER DO THIS - ArgumentParser handles help automatically
usage() {
    cat <<-USAGE
    Usage: script.sh <args>
    Options: --cores, --sockets
USAGE
    exit 1
}
```
**Use ArgumentParser** - Automatic `--help` generation from argument spec

**Don't use top-level callback functions in bulk scripts** - implies reusability when it's not
**Use local callbacks in main()** - keeps bulk-specific logic contained

### 3.14 Reusable Templates and Utilities

**MANDATORY: Always check utilities before writing new code.** The repository provides tested, cluster-aware utilities that handle common tasks. Using them ensures consistency, reduces bugs, and improves maintainability.

- Review `Utilities/_ExampleScript.sh` for a fully fleshed-out reference implementation that demonstrates every convention in practice.
- Consult `Utilities/_Utilities.md` for the complete function reference.
- **Key helper libraries under `Utilities/`:**

   **ArgumentParser.sh** - *Declarative argument parsing and validation*
   - One-line declarative parsing with `__parse_args__` function
   - Automatic type validation and help generation
   - Supports positional args, flags, and optional parameters
   - Main function: `__parse_args__ "spec" "$@"`
   - Legacy validation functions still available: `__validate_ip__`, `__validate_numeric__`, `__validate_vmid_range__`, etc.

   **BulkOperations.sh** - *Bulk operations on VM/CT ranges*
   - **WHEN TO USE**: Scripts that operate on a range of **existing** VMs/CTs across the cluster
     - Examples: BulkStart, BulkStop, BulkDelete, BulkSnapshot, BulkMigrate
     - Key indicator: Operating on VMs/CTs that already exist and may be on different nodes
   - **WHEN NOT TO USE**:
     - Creating new VMs/CTs that don't exist yet (e.g., BulkClone, BulkProvision)
     - Operations that inherently happen on a single node
     - Sequential operations that can't benefit from cluster-wide execution
   - **WHY**: Provides automatic cluster-awareness, progress tracking, error handling, and reporting
   - **HOW**: Define a local callback function inside `main()` that does the work for a single VM/CT
   - Pattern: `__bulk_vm_operation__ --name "Operation" --report START END callback_function`
   - Common functions: `__bulk_vm_operation__`, `__bulk_ct_operation__`, `__bulk_summary__`
   - See: `VirtualMachines/Operations/BulkDelete.sh` for existing VMs, `VirtualMachines/Operations/BulkClone.sh` for simple loop alternative

   **Colors.sh** - *Terminal color and gradient output*
   - Add colored output to scripts
   - Create gradient text effects
   - **Note:** For most cases, use `Communication.sh` functions instead
   - Common functions: `__line_rgb__`, `__line_gradient__`

   **Communication.sh** - *User feedback and messaging*
   - Display progress messages with spinners
   - Show success, error, warning, or info messages
   - Provide consistent user feedback
   - Use instead of: echo statements, manual spinner logic
   - Common functions: `__info__`, `__ok__`, `__err__`, `__warn__`, `__update__`, `__prompt_user_yn__`

   **Conversion.sh** - *Data format conversions*
   - Convert IP addresses to integers and vice versa
   - Convert CIDR notation to netmask
   - Generate MAC address prefixes from VMIDs
   - Use instead of: manual conversion calculations
   - Common functions: `__ip_to_int__`, `__int_to_ip__`, `__cidr_to_netmask__`, `__vmid_to_mac_prefix__`

   **Network.sh** - *Network configuration and management*
   - Configure VM/CT network interfaces
   - Set IP addresses, gateways, VLANs
   - Test network connectivity
   - Use instead of: direct qm/pct network commands
   - Common functions: `__net_vm_add_interface__`, `__net_vm_set_vlan__`, `__net_ct_set_ip__`

   **Prompts.sh** - *Environment checks and user prompts*
   - Check if script is running as root
   - Verify Proxmox environment
   - Check/install dependencies
   - **Prompt user with automatic non-interactive support**
   - Use instead of: custom if statements checking $EUID, manual `read -p` prompts
   - Common functions: `__check_root__`, `__check_proxmox__`, `__ensure_dependencies__`, `__prompt_user_yn__`
   - **Important:** `__prompt_user_yn__` automatically detects NON_INTERACTIVE mode and returns "yes"

   **Operations.sh** - *VM and Container operations* **(MOST COMMONLY USED)**
   - Start, stop, restart VMs or containers
   - Check if VM/CT exists or is running
   - Get or set VM/CT configuration
   - Execute commands on correct node (cluster-aware)
   - Use instead of: direct qm/pct commands with manual status checks
   - Common functions: `__vm_start__`, `__vm_stop__`, `__vm_exists__`, `__vm_is_running__`, `__ct_start__`, `__ct_exec__`
   - Remote execution: `__vm_node_exec__`, `__ct_node_exec__`, `__node_exec__`, `__pve_exec__`
   - **Use remote execution for commands without utility wrappers** (e.g., `qm destroy`, `qm unlock`, `pct destroy`)

   **Cluster.sh** - *Cluster information and VM/CT queries*
   - Find which node a VM/CT is on
   - Get cluster node information
   - List VMs/CTs on specific nodes
   - Use instead of: parsing pvecm/pvesh output manually
   - Common functions: `__get_vm_node__`, `__get_cluster_vms__`, `get_ip_from_vmid`, `__check_cluster_membership__`

   **SSH.sh** - *Remote SSH operations*
   - Execute commands on remote hosts via SSH
   - Transfer files using SCP
   - Wait for SSH to become available
   - Use instead of: raw ssh/scp commands with manual error handling
   - Common functions: `__ssh_exec__`, `__scp_send__`, `__wait_for_ssh__`, `__ssh_exec_script__`

   **StateManager.sh** - *Configuration backup and restore*
   - Save VM/CT configuration snapshots
   - Restore previous configurations
   - Compare configuration changes
   - Use instead of: manual config file backups
   - Common functions: `__state_save_vm__`, `__state_restore_vm__`, `__state_list__`, `__state_show_changes__`

- **`Utilities/_Utilities.md`** provides comprehensive documentation for all utility functions, including which functions are available in each file. **Always consult this reference** when writing scripts to ensure you source the correct utility files for the functions you need.

### 3.14 GUI Invocation Expectations

- When invoked via `GUI.sh`, scripts should rely on `${UTILITYPATH}` for sourcing utilities and must be executable on their own (`bash ScriptName.sh`).
- Include usage examples in the header with format `#   ScriptName.sh <args>` (no `./` prefix) - the GUI extracts these for display.
- Scripts require `UTILITYPATH` to be set, which is automatically done by `GUI.sh` or must be exported manually before direct execution.
- Clean up background processes and temporary state on exit.
- **GUI.sh may invoke scripts with all arguments pre-filled**, so ensure your scripts work in non-interactive mode.

### 3.15 Quick Pre-Commit Checklist

**For a comprehensive checklist with utility usage guide, see [Utilities/_ScriptComplianceChecklist.md](Utilities/_ScriptComplianceChecklist.md)**

Basic requirements:
- [ ] Header includes description, usage examples (`ScriptName.sh <args>` format), and Function Index placeholder.
- [ ] **ArgumentParser.sh is sourced** - MANDATORY for all scripts with arguments.
- [ ] **Using `__parse_args__` for argument parsing** - NO manual parsing or validation loops allowed.
- [ ] **NO manual `usage()` functions** - ArgumentParser handles `--help` automatically.
- [ ] All required utilities are sourced; no duplicated helper logic.
- [ ] **All utility functions used have their corresponding utility file sourced** (check `Utilities/_Utilities.md` for reference).
- [ ] **For bulk operations: Using BulkOperations.sh framework, not manual loops.**
- [ ] **For VM/CT operations: Using Operations.sh functions, not direct qm/pct calls.**
- [ ] **Script supports CLI mode** - can run non-interactively with all arguments provided.
- [ ] Variables are quoted and scoped appropriately.
- [ ] Error handling and cleanup paths are present.
- [ ] Testing notes updated and (where possible) ShellCheck run.

### 3.16 Minimal End-to-End Example

For a quick reference, here’s a compact script skeleton that follows every requirement. Use this as a mental checklist or see `_ExampleScript.sh`:

```bash
#!/bin/bash
#
# SampleMinimal.sh
#
# Demonstrates the minimal structure for ProxmoxScripts contributions.
#
# Usage:
#   ./SampleMinimal.sh <vmid> --node <node>
#   ./SampleMinimal.sh 100 --node pve1 --force
#
# Function Index:
#   - main
#

set -u

# Source required utilities - ALWAYS source the utility files for functions you use
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR
trap 'rm -f "${TMP_FILE:-}"' EXIT

# Parse arguments with one declarative line
__parse_args__ "vmid:vmid --node:string --force:flag" "$@"

main() {
   __check_root__
   __info__ "Running on VM ${VMID} (node: ${NODE})"
   [[ "$FORCE" == "true" ]] && __info__ "Force mode enabled"
   # ... perform work here ...
   __ok__ "Done"
}

main

# Testing status:
#   - 2025-10-27: Ran locally on PVE 8.2 test node (root shell)
```

For a complete walk-through with richer prompts, colors, and validation patterns, study `Utilities/_ExampleScript.sh` alongside this minimal skeleton.

---

## 4. Submitting Changes

1. **Commit Messages**
   - Use clear, concise commit messages.
   - Reference any related issues (e.g., `Fixes #123`) in your commit or PR description.

2. **Pull Request Description**
   - Use the [Pull Request Template](.github/PULL_REQUEST_TEMPLATE.md)
   - Provide a summary of what the PR does and why.
   - Include screenshots, logs, or references if it helps the reviewer.

3. **Code Review**
   - All pull requests undergo review from maintainers or other contributors.
   - Address feedback promptly and be open to revising your approach.

4. **Testing**
   - Test your script in a test or sandbox environment (especially for Proxmox clusters).
   - Document any steps to reproduce your tests.
   - **Verify compliance**: Review your script against the [Script Compliance Checklist](Utilities/_ScriptComplianceChecklist.md) before submitting.

---

## 5. Good Practices

- **Small, Focused Changes**: Submit small, atomic pull requests to keep reviews manageable.
- **Security Considerations**: Avoid storing or echoing sensitive data (tokens, passwords) in logs, follow the [Security Policy](SECURITY.md)
- **Documentation**: Update or create documentation relevant to your changes (e.g., script headers and comments).
- **Respect the Code of Conduct**: Please be courteous and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

---

## 6. Thank You

By following these guidelines, you help us maintain a clean, consistent codebase and an effective workflow. If you have any questions or suggestions for improving these guidelines, feel free to open an issue or drop a comment in a pull request.
