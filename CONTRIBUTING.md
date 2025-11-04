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
- Cluster-aware VM/CT operations (ProxmoxAPI.sh)
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
- Usage example(s) starting with `./`
- Relevant notes (root requirement, Proxmox requirement, etc.)
- A “Function Index” placeholder (see next section)

Example header:

```bash
#!/bin/bash
#
# MyScript.sh
#
# Short description of what the script does.
#
# Usage:
#   ./MyScript.sh <arg1> [--flag]
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

1. Source needed utilities (e.g., `source "${UTILITYPATH}/Prompts.sh"`). When launched via `GUI.sh`, `${UTILITYPATH}` is already exported.
2. Perform prerequisite checks (`__check_root__`, `__check_proxmox__`, dependency checks with `command -v`).
3. Parse arguments and validate input. Print usage and exit on bad input.
4. Group functions logically with clear separators such as `# --- Preliminary Checks -----------------------------------------------------`.
5. Implement main logic inside a `main()` function and call it at the end of the script.
6. Record testing notes near the bottom of the file.

**IMPORTANT**: When using utility functions in your script, you **MUST** source the corresponding utility script at the top of your file. Each utility function requires its parent script to be sourced.

Example:
```bash
# If using __validate_ip__ or __parse_positional_args__
source "${UTILITYPATH}/ArgumentParser.sh"

# If using __vm_start__ or __ct_exists__
source "${UTILITYPATH}/ProxmoxAPI.sh"

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

**NEW: Use the declarative `__parse_args__` function for simple, reliable argument parsing.**

The ArgumentParser.sh utility now provides a one-line declarative API that handles both parsing and validation automatically. **Always use this instead of manual parsing.**

**Simple Example:**
```bash
source "${UTILITYPATH}/ArgumentParser.sh"

# One line to parse and validate all arguments
__parse_args__ "start:vmid end:vmid --force:flag --node:string:?" "$@"

# After parsing, use uppercase variable names
echo "Processing VMs ${START} to ${END}"
[[ "$FORCE" == "true" ]] && echo "Force mode enabled"
[[ -n "$NODE" ]] && echo "Target node: ${NODE}"
```

**Spec Format:**
- Positional: `name:type` or `name:type:default`
- Flags: `--name:type` or `--name:flag`
- Optional: Use `:?` for optional without default, or `:value` for default value

**Common Types:**
- `vmid`, `number`, `integer`, `float`
- `ip`, `ipv4`, `ipv6`, `cidr`, `gateway`
- `port`, `hostname`, `fqdn`, `mac`
- `storage`, `bridge`, `vlan`, `node`
- `cpu`, `memory`, `disk`, `onboot`, `ostype`
- `string`, `path`, `url`, `email`
- `flag`, `boolean`

**Complete Example:**
```bash
#!/bin/bash
source "${UTILITYPATH}/ArgumentParser.sh"

# Define what arguments you need
__parse_args__ "vmid:vmid ip:ip --storage:storage:local-lvm --force:flag" "$@"

# Use the parsed variables (automatically uppercased)
echo "Creating VM ${VMID} with IP ${IP}"
echo "Storage: ${STORAGE}"
[[ "$FORCE" == "true" ]] && echo "Force mode"
```

**Benefits:**
- Automatic validation based on type
- Built-in help generation (--help)
- Consistent error messages
- Less boilerplate code
- Type-safe with clear declarations

**Legacy Validation Functions:**
All `__validate_*__` functions are still available for manual validation when needed:
- `__validate_numeric__`, `__validate_ip__`, `__validate_vmid_range__`, etc.

### 3.11 Interactive vs. CLI Mode

**IMPORTANT: All scripts MUST support a CLI mode that allows non-interactive execution.**

Scripts may be interactive (prompting users for input), but they **MUST** also support a command-line interface mode where all required information can be provided via arguments, bypassing all prompts.

**Requirements:**
- Scripts MUST accept all required parameters as command-line arguments
- When all required arguments are provided, scripts MUST run without prompting
- Interactive prompts are only acceptable when arguments are missing
- Include a `--non-interactive` or `--yes` flag to force non-interactive mode when prompts might otherwise appear

**Good Pattern:**
```bash
# Parse arguments
VMID="$1"
STORAGE="$2"
NON_INTERACTIVE="${3:-false}"

# Use arguments if provided, otherwise prompt
if [[ -z "$VMID" ]]; then
    read -p "Enter VMID: " VMID
fi

# Confirmation prompt only in interactive mode
if [[ "$NON_INTERACTIVE" != "true" ]]; then
    __prompt_user_yn "Continue with operation?" || exit 0
fi

# Rest of script proceeds automatically
```

**Benefits:**
- Scripts can be automated and scheduled
- Can be called from other scripts
- Supports CI/CD pipelines
- Allows batch operations
- Enables GUI.sh integration

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

**Don't use manual argument parsing** - 20+ lines of validation code
**Use declarative parsing** - `__parse_args__ "vmid:vmid ip:ip" "$@"`

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

   **NetworkHelper.sh** - *Network configuration and management*
   - Configure VM/CT network interfaces
   - Set IP addresses, gateways, VLANs
   - Test network connectivity
   - Use instead of: direct qm/pct network commands
   - Common functions: `__net_vm_add_interface__`, `__net_vm_set_vlan__`, `__net_ct_set_ip__`

   **Prompts.sh** - *Environment checks and user prompts*
   - Check if script is running as root
   - Verify Proxmox environment
   - Check/install dependencies
   - Use instead of: custom if statements checking $EUID
   - Common functions: `__check_root__`, `__check_proxmox__`, `__ensure_dependencies__`

   **ProxmoxAPI.sh** - *VM and Container operations* **(MOST COMMONLY USED)**
   - Start, stop, restart VMs or containers
   - Check if VM/CT exists or is running
   - Get or set VM/CT configuration
   - Execute commands on correct node (cluster-aware)
   - Use instead of: direct qm/pct commands with manual status checks
   - Common functions: `__vm_start__`, `__vm_stop__`, `__vm_exists__`, `__vm_is_running__`, `__ct_start__`, `__ct_exec__`
   - Remote execution: `__vm_node_exec__`, `__ct_node_exec__`, `__node_exec__`, `__pve_exec__`
   - **Use remote execution for commands without utility wrappers** (e.g., `qm destroy`, `qm unlock`, `pct destroy`)

   **Queries.sh** - *Cluster information and VM/CT queries*
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

- When invoked via `GUI.sh`, scripts should rely on `${UTILITYPATH}` for sourcing utilities and must be executable on their own (`./script.sh` or `bash script.sh`).
- Include at least one `./ExampleCommand.sh` usage line in the header - the GUI extracts these examples for display.
- Clean up background processes and temporary state on exit.
- **GUI.sh may invoke scripts with all arguments pre-filled**, so ensure your scripts work in non-interactive mode.

### 3.15 Quick Pre-Commit Checklist

**For a comprehensive checklist with utility usage guide, see [Utilities/_ScriptComplianceChecklist.md](Utilities/_ScriptComplianceChecklist.md)**

Basic requirements:
- [ ] Header includes description, usage, and Function Index placeholder.
- [ ] All required utilities are sourced; no duplicated helper logic.
- [ ] **All utility functions used have their corresponding utility file sourced** (check `Utilities/_Utilities.md` for reference).
- [ ] **For bulk operations: Using BulkOperations.sh framework, not manual loops.**
- [ ] **For VM/CT operations: Using ProxmoxAPI.sh functions, not direct qm/pct calls.**
- [ ] **For argument parsing: Using __parse_args__, not manual validation.**
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
