# Proxmox VE Management Scripts

[![Version](https://img.shields.io/badge/version-2.1.6-blue.svg)](https://github.com/coelacant1/ProxmoxScripts/releases)
[![Repository Checks](https://github.com/coelacant1/ProxmoxScripts/actions/workflows/checks.yml/badge.svg)](https://github.com/coelacant1/ProxmoxScripts/actions/workflows/checks.yml)
[![Deploy static content to Pages](https://github.com/coelacant1/ProxmoxScripts/actions/workflows/static.yml/badge.svg?branch=main)](https://github.com/coelacant1/ProxmoxScripts/actions/workflows/static.yml)
[![Release on .sh changes](https://github.com/coelacant1/ProxmoxScripts/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/coelacant1/ProxmoxScripts/actions/workflows/release.yml)

This repository provides automation scripts for managing Proxmox VE (Virtual Environment) systems efficiently. The scripts are designed for system administrators and DevOps professionals who need to streamline their Proxmox operations.

### **Key Features:**
- **Cross-Platform GUI**: Run on any Linux distribution (Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE, etc.) to manage Proxmox clusters
- **Remote Execution**: Control single or multiple Proxmox nodes from a central workstation
- **Branch Management**: Switch between stable (main) and testing branches with built-in updates
- **Interactive Interface**: Text-based GUI with comprehensive help system and settings

Explore the scripts for Proxmox VE management on the website:
[Visit the Proxmox VE One-Click Scripts Website](https://coelacant1.github.io/ProxmoxScripts/)

> [!WARNING]
> ### **Read and Understand Before Executing:**
> These scripts perform administrative operations on Proxmox infrastructure. Before running ANY script:
> - **Read and understand** what the script does
> - **Maintain a local copy** of the repository for review and version control
> - **Manually validate** each script before execution on production systems
> - **Test in a non-production environment** first whenever possible
> - **You are responsible for any changes made to your infrastructure**

## Version 2.0 Update

Version 2.0 represents a major refactor focused on extending backend utilities, improving remote cluster management, and establishing comprehensive testing and quality assurance frameworks.

**Major Changes:**
- **Remote Cluster Management** - Execute scripts on single or multiple Proxmox nodes without re-downloading the repository, with support for temporary multi-remote mode using IP/VMID ranges
- **Unified Utility Framework** - New ArgumentParser, BulkOperations, and Operations utilities standardize script behavior and error handling across the entire codebase
- **Structured Logging System** - Dual log output with separate .log and .debug.log files, debug flag support (-d), and configurable log levels (INFO, DEBUG, ERROR) for both local and remote execution
- **Comprehensive Testing System** - TestFramework with automated test suites for all utility libraries, plus RunAllTests.sh for continuous integration
- **Enhanced Bulk Operations** - Improved VM/LXC bulk operations with progress tracking, detailed statistics, and automatic success/failure reporting
- **Script Compliance Standards** - All scripts now follow consistent patterns with standardized headers, argument parsing, logging, and error handling
- **Quality Assurance Tools** - Repository checks including line ending conversion, function indexing, source verification, code formatting, security analysis, and dead code detection
- **Cross-Platform GUI Improvements** - Auto-detects package managers across all major Linux distributions with branch management and settings accessible from any menu
- **Script Validation** - Scripts validated against Proxmox VE 9.1.1 documentation with standardized notes tracking validation status, changes, and known issues

## Getting Started

These instructions will guide you on how to start using the scripts for managing your Proxmox infrastructure.

### Prerequisites

**For Local Execution on Proxmox:**
- Proxmox VE 8.x or newer installed and running
- SSH access with appropriate privileges
- Basic knowledge of Proxmox operations and Linux

**For Remote Execution from Any Linux System:**
- Any major Linux distribution (Debian, Ubuntu, Fedora, RHEL, CentOS, Arch, openSUSE, etc.)
- `wget` and `unzip` (for updating scripts from GitHub)
- `jq` (for parsing node configuration files)
- `sshpass` (for password-based SSH authentication, not needed if using SSH keys)
- Network access to target Proxmox nodes

### Single Line Usage

> [!NOTE]
> **Works on any Linux distribution** - automatically detects and uses the appropriate package manager (apt, dnf, yum, zypper, or pacman).

To execute the single line call to navigate all scripts use:
```bash
bash -c "$(wget -qLO - https://github.com/coelacant1/ProxmoxScripts/raw/main/CCPVE.sh)"
```

Or an even shorter single line call:
```bash
bash <(curl -L pve.coela.sh)
```

Short single line call with the full header:
```bash
bash <(curl -L pve.coela.sh) -h
```

Use the testing branch (downloads from the 'testing' branch instead of 'main'):
```bash
bash <(curl -L pve.coela.sh) --testing
```

Or specify an explicit branch:
```bash
bash <(curl -L pve.coela.sh) --branch experimental-feature
```

### Direct Non-Interactive Script Execution

You can now execute a specific script from the repository directly (without launching the interactive text UI) using new flags exposed by `CCPVE.sh`.

List all runnable scripts (relative paths):
```bash
bash <(curl -L pve.coela.sh) --list
```

Run a specific script by relative path (as shown in the list):
```bash
bash <(curl -L pve.coela.sh) --run Host/QuickDiagnostic.sh
```

Pass arguments to that script:
```bash
bash <(curl -L pve.coela.sh) --run Storage/Benchmark.sh --args "--device /dev/nvme0n1 --mode quick"
```

Combined wget form examples:
```bash
bash -c "$(wget -qLO - https://github.com/coelacant1/ProxmoxScripts/raw/main/CCPVE.sh)" --list
bash -c "$(wget -qLO - https://github.com/coelacant1/ProxmoxScripts/raw/main/CCPVE.sh)" --run VirtualMachines/CreateFromISO.sh --args "--iso debian-12.iso --vmid 900 --storage local-lvm"
```

> [!TIP]
> **Best Practices:**
> - Use `--list` first if unsure of the correct relative path
> - The repository is downloaded fresh each invocation (ephemeral mode)
> - For repeated usage, clone the repo and call `GUI.sh` directly
> - `UTILITYPATH` is exported automatically so scripts can source shared helpers

![Single Line Online Command](.site/MultiView.png)

### Installation

> [!IMPORTANT]
> **For Production Use:** Clone and maintain a local copy of the repository. Review and validate all scripts before execution on production infrastructure.

Requires git if you plan to download through cloning:
```bash
apt update
apt install git wget unzip jq sshpass
```

**Note:** `sshpass` is only needed if you plan to use password-based SSH authentication for remote execution. If you configure SSH keys, it's not required.

To execute these scripts offline on your system, follow these steps:

1. Clone the repository to your Proxmox server or your local machine and move the folder to your server:
    ```bash
    git clone https://github.com/coelacant1/ProxmoxScripts.git
    ```

2. Navigate into the cloned repository directory:
    ```bash
    cd ProxmoxScripts
    ```

3. Execute the GUI (scripts are made executable automatically):
    ```bash
    ./GUI.sh
    ```

4. To update scripts, use the GUI settings menu (press 's' from any menu, then select option 1)


## Usage

### GUI Interactive Mode

The recommended way to use ProxmoxScripts is through the interactive GUI, which can run on **any Linux system** to manage local or remote Proxmox nodes:

```bash
./GUI.sh
```

**GUI Features:**
- **Cross-Platform**: Works on any major Linux distribution (auto-detects package manager)
- **Execution Modes**:
  - Local execution (run directly on Proxmox node)
  - Single remote node (manage one Proxmox server from your workstation)
  - Multiple remote nodes (execute across entire cluster simultaneously)
- **Built-in Branch Management**: Switch between branches and update scripts via settings menu (press `s`)
- **Interactive Help**: Press `h` or `?` anywhere to access comprehensive documentation
- **Node Management**: Configure and manage Proxmox nodes via `nodes.json`
- **Parameter History**: Edit command parameters with readline shortcuts (Ctrl+A/E, Ctrl+K/U, etc.)
- **Real-time Output**: View script execution with colored output and progress indicators

**Quick Tips:**
- Press `s` to access settings (branch selection, updates)
- Press `h` or `?` to access the manual system
- Press `l` to change log level (debug/info/quiet) for remote execution
- Press `b` to go back, `e` to exit
- Use `./GUI.sh -c` to clear logs before starting
- Configure remote nodes by pressing `m` in the execution mode menu

> [!TIP]
> **New to the GUI?** Press `h` or `?` from anywhere to access the interactive help system with comprehensive documentation.

### Remote Execution from Any Linux System

You can run the GUI on **any Linux distribution** (Ubuntu, Fedora, Arch, etc.) to remotely manage Proxmox clusters. This allows you to:
- Control production Proxmox nodes from a development workstation
- Manage multiple datacenters from a central location
- Execute scripts across entire clusters simultaneously
- Maintain consistent configurations across all nodes

Configure remote nodes in `nodes.json` (auto-created from template):

```json
{
  "nodes": [
    {"name": "pve01", "ip": "192.168.1.101"},
    {"name": "pve02", "ip": "192.168.1.102"}
  ]
}
```

Then select remote execution mode in GUI.sh to run scripts across your cluster.

### Script Usage

Each script includes detailed usage information in its header comments. Scripts automatically source required utility functions from the `Utilities/` directory.

Example for description and example commands in each script in this repository:

- **Remote Migrate VMs** (`RemoteMigrateVMs.sh`):
  This script migrates virtual machines (VMs) from a local Proxmox node to a target Proxmox node.
  It utilizes the Proxmox API for migration and requires proper authentication using an API token.
  The script removes any existing Cloud-Init drives before initiating the migration and adjusts VM IDs based on a provided offset.

  Usage:
    ```bash
    ./RemoteMigrateVMs.sh <target_host> <api_token> <fingerprint> <target_storage> <vm_offset> <target_network>
    ```

  Where:
    target_host - The hostname or IP address of the target Proxmox server.
    api_token - The API token used for authentication.
    fingerprint - The SSL fingerprint of the target Proxmox server.
    target_storage - The storage identifier on the target node where VMs will be stored.
    vm_offset - An integer value to offset the VM IDs to avoid conflicts.
    target_network - The network bridge on the target server to connect the VMs.

## Contributing

Please read the [CONTRIBUTING.md](CONTRIBUTING.md) guide for:

- **Style guide** - Function documentation, error handling, and naming conventions
- **Utility functions** - Required usage of shared utilities from `Utilities/` directory
- **Testing requirements** - How to test your changes
- **Compliance checklist** - Use `Utilities/_ScriptComplianceChecklist.md` before submitting

Quick steps:
- Fork the repository on GitHub
- Create a feature branch
- Follow the scripting standards in CONTRIBUTING.md
- Test thoroughly in a development environment
- Submit a pull request with clear description

For questions, open an issue in the GitHub repository.

## Support

For support:
- **In-GUI Help**: Press `h` or `?` in GUI.sh to access built-in manuals
- **Troubleshooting**: See `Manuals/troubleshooting.txt` for common issues
- **GitHub Issues**: Open an issue with logs and reproduction steps
- **Documentation**: Check CONTRIBUTING.md and Utilities/_Utilities.md

See [CHANGELOG.md](CHANGELOG.md) for version history.
