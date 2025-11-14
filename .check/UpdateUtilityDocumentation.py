#!/usr/bin/env python3
"""
UpdateUtilityDocumentation.py

Automatically generates comprehensive documentation for ProxmoxScripts utilities.
This script scans the ../Utilities directory for .sh files (ignoring those starting with underscore),
parses function header blocks and file-level documentation, and generates a complete markdown reference.

Features:
- Extracts function signatures, parameters, return values, and examples
- Parses file-level documentation including purpose, features, and dependencies
- Generates usage examples and parameter descriptions
- Creates comprehensive index and cross-references
- Consolidates all utility documentation in one location

Output: ../Utilities/_Utilities.md (complete reference documentation)

Author: Coela
"""

import os
import glob
import re
from datetime import datetime
from collections import defaultdict

# Directory paths
UTILS_DIR = os.path.join(os.path.dirname(__file__), "../Utilities")
OUTPUT_MD = os.path.join(UTILS_DIR, "_Utilities.md")

# Directories to skip during traversal
SKIP_DIRS = {".git", ".github", ".site", ".check", ".docs"}

# Regex patterns for parsing
header_start_re = re.compile(r'^# ---\s*(\S+)\s*-+')
tag_line_re = re.compile(r'^#\s*@(\w+)\s*(.*)')
comment_line_re = re.compile(r'^#\s?(.*)')
function_index_re = re.compile(r'^#\s+Function Index:\s*$')
section_header_re = re.compile(r'^#\s+([A-Z][^:]+):\s*$')
list_item_re = re.compile(r'^#\s+[-*]\s+(.+)$')

def parse_file_header(lines):
    """
    Parse file-level documentation from the header comments.
    Extracts file purpose, features, usage, dependencies, and function index.

    Returns a dictionary with:
      - name: File name from header
      - purpose: Main description/purpose
      - features: List of features
      - usage: How to source/use the file
      - dependencies: List of required files
      - function_sections: Dict of section name -> list of functions
    """
    header = {
        "name": "",
        "purpose": [],
        "features": [],
        "usage": "",
        "dependencies": [],
        "function_sections": defaultdict(list)
    }

    current_section = None
    in_function_index = False

    for i, line in enumerate(lines):
        line = line.rstrip("\n")

        # Stop at first non-comment line or function definition
        if not line.startswith("#") or line.startswith("# ---"):
            break

        # Extract content
        content_match = comment_line_re.match(line)
        if not content_match:
            continue

        content = content_match.group(1).strip()

        # Check for file name (typically line 2-3)
        if i < 5 and content and not content.startswith("=") and len(content) < 50 and content.endswith(".sh"):
            header["name"] = content
            continue

        # Check for function index
        if function_index_re.match(line):
            in_function_index = True
            continue

        # Check for section headers in function index
        if in_function_index:
            section_match = section_header_re.match(line)
            if section_match:
                current_section = section_match.group(1).strip()
                continue

            # Check for function list items
            list_match = list_item_re.match(line)
            if list_match:
                func_name = list_match.group(1).strip()
                if current_section:
                    header["function_sections"][current_section].append(func_name)
                else:
                    header["function_sections"]["General"].append(func_name)
                continue

            # End of function index
            if content and not content.startswith("-"):
                in_function_index = False

        # Parse various header sections
        if content:
            if "Usage:" in content and not header["usage"]:
                header["usage"] = content.split("Usage:", 1)[1].strip()
            elif "source " in content and not header["usage"]:
                header["usage"] = content
            elif "Features:" in content or header["features"] or (current_section is None and line.startswith("#   -")):
                if line.startswith("#   -") or line.startswith("#   *"):
                    header["features"].append(content.lstrip("-* ").strip())
            elif i < 15 and content and content not in ["", "="*10]:
                # Early lines are likely purpose/description
                if not any(x in content for x in ["Usage:", "Function Index:", "Features:"]):
                    header["purpose"].append(content)

    # Join purpose lines
    header["purpose"] = " ".join(header["purpose"]).strip()

    return header

def parse_function_block(lines, start_index):
    """
    Parse a function header block starting at start_index in lines.
    Handles multi-line tags and extracts comprehensive function metadata.

    Returns a tuple (func_info, new_index) where func_info is a dictionary with:
      - function: Function name
      - description: Full description
      - usage: Usage pattern
      - params: List of parameter descriptions
      - return: Return value description
      - example_output: Example of what function outputs
      - notes: Additional notes or warnings
    """
    info = {
        "function": "",
        "description": "",
        "usage": "",
        "params": [],
        "return": "",
        "example_output": "",
        "notes": []
    }

    current_tag = None
    i = start_index + 1  # skip the "# ---" header line

    while i < len(lines):
        line = lines[i].rstrip("\n")
        if not line.startswith("#"):
            break

        tag_match = tag_line_re.match(line)
        if tag_match:
            tag, content = tag_match.groups()
            tag = tag.lower()
            content = content.strip()

            if tag == "function":
                info["function"] = content
                current_tag = "function"
            elif tag == "description":
                info["description"] = content
                current_tag = "description"
            elif tag == "usage":
                info["usage"] = content
                current_tag = "usage"
            elif tag == "param":
                info["params"].append(content)
                current_tag = "params"
            elif tag == "return":
                info["return"] = content
                current_tag = "return"
            elif tag == "example_output" or tag == "example":
                info["example_output"] = content
                current_tag = "example_output"
            elif tag == "note" or tag == "warning":
                info["notes"].append(content)
                current_tag = "notes"
            else:
                current_tag = None
        else:
            # Continuation line: append to current tag
            cont_match = comment_line_re.match(line)
            if cont_match and current_tag:
                cont_text = cont_match.group(1).strip()
                if cont_text:
                    if current_tag in ["params", "notes"]:
                        if info[current_tag]:
                            info[current_tag][-1] += " " + cont_text
                    else:
                        info[current_tag] += " " + cont_text
        i += 1

    return info, i

def parse_file(file_path):
    """
    Parse a shell script file for both file-level documentation and function definitions.
    Returns a tuple of (file_header, functions_list).
    """
    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Parse file header
    file_header = parse_file_header(lines)

    # Parse function blocks
    functions = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if header_start_re.match(line):
            func_info, i = parse_function_block(lines, i)
            if func_info.get("function"):
                functions.append(func_info)
        else:
            i += 1

    return file_header, functions

def format_function_docs(fname, func, detail_level="full"):
    """
    Format function documentation with varying levels of detail.

    Args:
        fname: Filename containing the function
        func: Function info dictionary
        detail_level: "brief", "standard", or "full"

    Returns:
        List of markdown lines
    """
    lines = []
    func_name = func.get("function", "unknown")

    if detail_level == "brief":
        # Brief format: one-line summary
        desc = func.get("description", "").split(".")[0]
        lines.append(f"- **`{func_name}`**: {desc}")
        return lines

    # Standard and full format
    lines.append(f"### `{func_name}`")

    # Description
    desc = func.get("description", "No description available.")
    lines.append(f"**Description**: {desc}")

    # Usage
    usage = func.get("usage", "")
    if usage:
        lines.append(f"**Usage**:")
        lines.append(f"```bash")
        lines.append(usage)
        lines.append(f"```")

    # Parameters
    params = func.get("params", [])
    if params:
        lines.append(f"**Parameters**:")
        for param in params:
            lines.append(f"- {param}")

    # Return value
    ret = func.get("return", "")
    if ret:
        lines.append(f"**Returns**: {ret}")

    # Example output (full detail only)
    if detail_level == "full":
        example = func.get("example_output", "")
        if example:
            lines.append(f"**Example Output**:")
            lines.append(f"```")
            lines.append(example)
            lines.append(f"```")

    # Notes
    notes = func.get("notes", [])
    if notes:
        lines.append(f"**Notes**:")
        for note in notes:
            lines.append(f"- {note}")

    lines.append("---")

    return lines

def generate_table_of_contents(file_data):
    """Generate comprehensive table of contents."""
    lines = []
    lines.append("# Table of Contents")
    lines.append("- [Overview](#overview)")
    lines.append("- [Quick Start](#quick-start)")
    lines.append("- [Design Principles](#design-principles)")
    lines.append("- [Utility Files](#utility-files)")

    for fname in sorted(file_data.keys()):
        anchor = fname.replace(".sh", "").lower()
        lines.append(f"  - [{fname}](#{anchor})")

    lines.append("- [Testing](#testing)")
    lines.append("- [Common Patterns](#common-patterns)")
    lines.append("")

    return lines

def generate_quick_reference(file_data):
    """Generate quick reference table for all functions."""
    lines = []
    lines.append("# Quick Reference")
    lines.append("")
    lines.append("| Function | File | Purpose |")
    lines.append("|----------|------|---------|")

    all_functions = []
    for fname, (header, functions) in file_data.items():
        for func in functions:
            func_name = func.get("function", "")
            desc = func.get("description", "").split(".")[0]
            all_functions.append((func_name, fname, desc))

    # Sort by function name
    for func_name, fname, desc in sorted(all_functions):
        fname_short = fname.replace(".sh", "")
        lines.append(f"| `{func_name}` | {fname_short} | {desc} |")

    lines.append("")
    return lines

def generate_markdown():
    """Main function to generate comprehensive documentation."""

    # Get list of .sh files (ignoring files starting with underscore and TestFramework.sh)
    sh_files = sorted([
        os.path.basename(f) for f in glob.glob(os.path.join(UTILS_DIR, "*.sh"))
        if not os.path.basename(f).startswith("_") and os.path.basename(f) != "TestFramework.sh"
    ])

    # Parse all files
    file_data = {}
    for fname in sh_files:
        file_path = os.path.join(UTILS_DIR, fname)
        header, functions = parse_file(file_path)
        file_data[fname] = (header, functions)

    # Build markdown document
    md_lines = []

    # Header
    md_lines.append("# ProxmoxScripts Utility Functions Reference")
    md_lines.append("")
    md_lines.append(f"**Auto-generated documentation** - Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    md_lines.append("")
    md_lines.append("---")
    md_lines.append("")

    # Overview
    md_lines.append("## Overview")
    md_lines.append("")
    md_lines.append("This reference provides comprehensive documentation for all utility functions in the ProxmoxScripts repository. ")
    md_lines.append("These utilities provide reusable functions for building automation scripts, ")
    md_lines.append("management tools, and integration solutions for Proxmox VE environments.")
    md_lines.append("")

    # Utility Files Overview
    md_lines.append("## Utility Files Overview")
    md_lines.append("")
    md_lines.append("### ArgumentParser.sh")
    md_lines.append("**Argument parsing and input validation**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Parse command-line arguments (positional, named, or flags)")
    md_lines.append("- Validate user input (IP addresses, numbers, hostnames, ports, etc.)")
    md_lines.append("- Generate usage/help messages")
    md_lines.append("")
    md_lines.append("**Common functions:** `__validate_ip__`, `__validate_numeric__`, `__parse_flag_options__`, `__validate_vmid_range__`")
    md_lines.append("")

    md_lines.append("### BulkOperations.sh")
    md_lines.append("**Bulk operations on VM/CT ranges**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Perform operations on a range of VMs or containers")
    md_lines.append("- Track progress and handle failures")
    md_lines.append("- Generate operation reports and summaries")
    md_lines.append("- Save/resume operation state")
    md_lines.append("")
    md_lines.append("**Common functions:** `__bulk_vm_operation__`, `__bulk_ct_operation__`, `__bulk_summary__`, `__bulk_report__`")
    md_lines.append("")

    md_lines.append("### Colors.sh")
    md_lines.append("**Terminal color and gradient output**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Add colored output to scripts")
    md_lines.append("- Create gradient text effects")
    md_lines.append("- Customize terminal formatting")
    md_lines.append("")
    md_lines.append("**Note:** For most cases, use `Communication.sh` functions instead.")
    md_lines.append("")
    md_lines.append("**Common functions:** `__line_rgb__`, `__line_gradient__`")
    md_lines.append("")

    md_lines.append("### Communication.sh")
    md_lines.append("**User feedback and messaging**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Display progress messages with spinners")
    md_lines.append("- Show success, error, warning, or info messages")
    md_lines.append("- Provide consistent user feedback")
    md_lines.append("- Handle errors with context")
    md_lines.append("")
    md_lines.append("**Common functions:** `__info__`, `__ok__`, `__err__`, `__warn__`, `__update__`, `__prompt_user_yn__`")
    md_lines.append("")

    md_lines.append("### Conversion.sh")
    md_lines.append("**Data format conversions**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Convert IP addresses to integers and vice versa")
    md_lines.append("- Convert CIDR notation to netmask")
    md_lines.append("- Generate MAC address prefixes from VMIDs")
    md_lines.append("")
    md_lines.append("**Common functions:** `__ip_to_int__`, `__int_to_ip__`, `__cidr_to_netmask__`, `__vmid_to_mac_prefix__`")
    md_lines.append("")

    md_lines.append("### Network.sh")
    md_lines.append("**Network configuration and management**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Configure VM/CT network interfaces")
    md_lines.append("- Set IP addresses, gateways, VLANs")
    md_lines.append("- Test network connectivity")
    md_lines.append("- Bulk network operations across VMs/CTs")
    md_lines.append("")
    md_lines.append("**Common functions:** `__net_vm_add_interface__`, `__net_vm_set_vlan__`, `__net_ct_set_ip__`, `__net_test_connectivity__`")
    md_lines.append("")

    md_lines.append("### Prompts.sh")
    md_lines.append("**Environment checks and user prompts**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Check if script is running as root")
    md_lines.append("- Verify Proxmox environment")
    md_lines.append("- Check/install dependencies")
    md_lines.append("- Prompt users for confirmation")
    md_lines.append("")
    md_lines.append("**Common functions:** `__check_root__`, `__check_proxmox__`, `__ensure_dependencies__`, `__prompt_user_yn__`")
    md_lines.append("")

    md_lines.append("### Operations.sh")
    md_lines.append("**VM and Container operations**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Start, stop, restart VMs or containers")
    md_lines.append("- Check if VM/CT exists or is running")
    md_lines.append("- Get or set VM/CT configuration")
    md_lines.append("- Execute commands in containers")
    md_lines.append("- Wait for VM/CT status changes")
    md_lines.append("")
    md_lines.append("**Common functions:** `__vm_start__`, `__vm_stop__`, `__vm_exists__`, `__vm_is_running__`, `__ct_start__`, `__ct_exec__`")
    md_lines.append("")

    md_lines.append("### Cluster.sh")
    md_lines.append("**Cluster information and VM/CT queries**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Find which node a VM/CT is on")
    md_lines.append("- Get cluster node information")
    md_lines.append("- List VMs/CTs on specific nodes")
    md_lines.append("- Get VM IP addresses")
    md_lines.append("- Query cluster status")
    md_lines.append("")
    md_lines.append("**Common functions:** `__get_vm_node__`, `__get_cluster_vms__`, `get_ip_from_vmid`, `__check_cluster_membership__`")
    md_lines.append("")

    md_lines.append("### SSH.sh")
    md_lines.append("**Remote SSH operations**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Execute commands on remote hosts via SSH")
    md_lines.append("- Transfer files using SCP")
    md_lines.append("- Wait for SSH to become available")
    md_lines.append("- Run scripts or functions remotely")
    md_lines.append("")
    md_lines.append("**Common functions:** `__ssh_exec__`, `__scp_send__`, `__wait_for_ssh__`, `__ssh_exec_script__`")
    md_lines.append("")

    md_lines.append("### StateManager.sh")
    md_lines.append("**Configuration backup and restore**")
    md_lines.append("")
    md_lines.append("Use this when you need to:")
    md_lines.append("- Save VM/CT configuration snapshots")
    md_lines.append("- Restore previous configurations")
    md_lines.append("- Compare configuration changes")
    md_lines.append("- Export/import state data")
    md_lines.append("")
    md_lines.append("**Common functions:** `__state_save_vm__`, `__state_restore_vm__`, `__state_list__`, `__state_show_changes__`")
    md_lines.append("")

    md_lines.append("---")
    md_lines.append("")

    # Quick Start
    md_lines.append("## Quick Start")
    md_lines.append("")
    md_lines.append("```bash")
    md_lines.append("# Source utilities in your script")
    md_lines.append('UTILITYPATH="path/to/Utilities"')
    md_lines.append('source "${UTILITYPATH}/Operations.sh"')
    md_lines.append('source "${UTILITYPATH}/ArgumentParser.sh"')
    md_lines.append("")
    md_lines.append("# Use functions directly")
    md_lines.append("__vm_start__ 100")
    md_lines.append('__validate_ip__ "192.168.1.1" "IP Address"')
    md_lines.append("```")
    md_lines.append("")

    # Design Principles
    md_lines.append("## Design Principles")
    md_lines.append("")
    md_lines.append("1. **Non-Interactive**: All functions designed for automation (no user prompts during execution)")
    md_lines.append("2. **Consistent Return Codes**: 0 for success, 1 for errors, consistent across all functions")
    md_lines.append("3. **Error Messages to stderr**: All errors written to stderr, data to stdout for easy parsing")
    md_lines.append("4. **Input Validation**: Comprehensive validation with clear error messages")
    md_lines.append("5. **Testability**: Functions can be mocked and tested without Proxmox environment")
    md_lines.append("")

    # Table of Contents
    md_lines.extend(generate_table_of_contents(file_data))

    # Quick Reference
    md_lines.extend(generate_quick_reference(file_data))

    # Utility Files Section
    md_lines.append("# Utility Files")
    md_lines.append("")

    # Generate detailed documentation for each file
    for fname in sh_files:
        header, functions = file_data[fname]

        # File header
        anchor = fname.replace(".sh", "").lower()
        md_lines.append(f"# {fname}")
        md_lines.append("")

        # File purpose
        if header["purpose"]:
            md_lines.append(f"**Purpose**: {header['purpose']}")
            md_lines.append("")

        # Features
        if header["features"]:
            md_lines.append("**Features**:")
            for feature in header["features"]:
                md_lines.append(f"- {feature}")
            md_lines.append("")

        # Usage
        if header["usage"]:
            md_lines.append("**Usage**:")
            md_lines.append("```bash")
            md_lines.append(header["usage"])
            md_lines.append("```")
            md_lines.append("")

        # Function sections if available
        if header["function_sections"]:
            md_lines.append("**Functions**:")
            for section, funcs in header["function_sections"].items():
                if section != "General":
                    md_lines.append(f"- *{section}*: {', '.join([f'`{f}`' for f in funcs])}")
                else:
                    for f in funcs:
                        md_lines.append(f"- `{f}`")
            md_lines.append("")

        md_lines.append("---")
        md_lines.append("")

        # Individual function documentation
        if functions:
            md_lines.append(f"#### Functions in {fname}")
            md_lines.append("")

            for func in functions:
                md_lines.extend(format_function_docs(fname, func, detail_level="full"))

    # Testing Section
    md_lines.append("## Testing")
    md_lines.append("")
    md_lines.append("All utilities include test coverage using the TestFramework.sh testing infrastructure.")
    md_lines.append("")
    md_lines.append("```bash")
    md_lines.append("# Run all utility tests")
    md_lines.append("bash Utilities/RunAllTests.sh")
    md_lines.append("")
    md_lines.append("# Run specific test file")
    md_lines.append("bash Utilities/_TestOperations.sh")
    md_lines.append("")
    md_lines.append("# Run with verbose output")
    md_lines.append("bash Utilities/RunAllTests.sh -v")
    md_lines.append("```")
    md_lines.append("")
    md_lines.append("See `TestFramework.sh` and individual `_Test*.sh` files for testing documentation.")
    md_lines.append("")

    # Common Patterns
    md_lines.append("## Common Patterns")
    md_lines.append("")
    md_lines.append("### Bulk VM Operations")
    md_lines.append("```bash")
    md_lines.append("# Start range of VMs with progress tracking")
    md_lines.append("__bulk_vm_operation__ --name \"Start VMs\" --report 100 110 __vm_start__")
    md_lines.append("```")
    md_lines.append("")
    md_lines.append("### Argument Parsing")
    md_lines.append("```bash")
    md_lines.append("# Parse and validate arguments")
    md_lines.append('__parse_positional_args__ "VMID:numeric:required IP:ip:required" "$@"')
    md_lines.append("```")
    md_lines.append("")
    md_lines.append("### Network Configuration")
    md_lines.append("```bash")
    md_lines.append("# Add network interface with VLAN")
    md_lines.append("__net_vm_add_interface__ 100 net1 --bridge vmbr0 --vlan 10")
    md_lines.append("```")
    md_lines.append("")
    md_lines.append("### Error Handling")
    md_lines.append("```bash")
    md_lines.append("# All functions use consistent error handling")
    md_lines.append("if ! __vm_start__ 100; then")
    md_lines.append('    echo "Failed to start VM" >&2')
    md_lines.append("    exit 1")
    md_lines.append("fi")
    md_lines.append("```")
    md_lines.append("")

    # Footer
    md_lines.append("---")
    md_lines.append("")
    md_lines.append("**Note**: This documentation is automatically generated from source code comments. ")
    md_lines.append("To update, run: `python3 .check/UpdateUtilityDocumentation.py`")
    md_lines.append("")

    # Write to file
    with open(OUTPUT_MD, "w", encoding="utf-8") as out_file:
        out_file.write("\n".join(md_lines))

    print(f"Documentation generated successfully at: {OUTPUT_MD}")
    print(f"Total utility files: {len(sh_files)}")
    total_functions = sum(len(functions) for _, functions in file_data.values())
    print(f"Total functions documented: {total_functions}")

if __name__ == "__main__":
    generate_markdown()
