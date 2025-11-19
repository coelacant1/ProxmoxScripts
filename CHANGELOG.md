# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.3] - 2025-11-19

Script fixes, documentation updates, and function standardization

### Changed
- **Function naming standardization** - Renamed functions for consistency
  - `__get_cluster_lxc__` -> `__get_cluster_cts__` for consistent container terminology
  - `__prompt_yes_no__` -> `__prompt_user_yn__`
- **Test suite updates** - Updated test file to reflect renamed functions
  - `_TestQueries.sh`: Renamed `test_get_cluster_lxc` -> `test_get_cluster_cts`
- **BulkOperations.sh** - Removed internal wrapper functions
  - Removed `vm_wrapper` and `ct_wrapper` helper functions
- **Documentation cleanup** - Updated auto-generated utility documentation
  - Removed duplicate `__get_cluster_lxc__` documentation entries
  - Updated IP address examples for documentation
- **Testing documentation** - Enhanced test coverage documentation
  - Updated `_TestingStatus.md` with comprehensive test implementation status
  - Added test enhancement opportunities and integration test scenarios
  - Fixed issues in several scripts

### Removed
- **Deprecated function aliases** - Cleaned up backward compatibility aliases
  - Removed `__prompt_yes_no__` function (use `__prompt_user_yn__` instead)
  - Removed `__get_cluster_lxc__` function (use `__get_cluster_cts__` instead)

## [2.1.2] - 2025-11-14

Multi-remote execution improvements and debug logging support

### Added
- **Temporary Multi-Remote Mode** - Execute on IP ranges (192.168.1.100-200) or VMID ranges without saving connections
- **Dual Log Output** - Remote execution creates both output log (.log) and debug log (.debug.log) with structured logging
- **Debug Flag Support** - `./GUI.sh -d` enables DEBUG level logging on remote nodes
- **Interrupt Handling** - Ctrl+C during remote execution cleanly cancels remaining nodes

### Changed
- **Argument Parsing** - Fixed command-line flag processing to use `while` loop instead of `for` loop
- **Remote Execution Flow** - Automatically continues to next node without manual review prompts
- **Performance** - Optimized remote environment setup with parallel SSH operations (3x faster)

### Fixed
- **REMOTE_LOG_LEVEL Initialization** - ConfigManager.sh no longer overwrites command-line log level flags
- **Multi-Remote Exit Bug** - All nodes now execute successfully instead of exiting after first node

## [2.1.1] - 2025-11-14

GUI enhancements and distribution compatibility improvements

### Added
- **Polymorphic Menu System** - Centralized common menu operations (settings, help, back, exit) across all menus
- **Branch Management** - Switch branches, update scripts from GitHub, and view available branches via settings menu ('s') accessible from all menus

### Changed
- **CCPVE.sh Distribution Compatibility** - Auto-detects package manager (apt, dnf, yum, zypper, pacman) and supports non-root execution with automatic sudo usage
- **Standardized Input Prompts** - All menus now use consistent `read -rp "Choice: "` format
- **Simplified Navigation** - Pressing 'b' at root automatically returns to execution mode selection without intermediate menus

### Fixed
- **Navigation Flow** - Root directory 'b' press now returns to execution mode selection instead of exiting application

## [2.1.0] - 2025-11-13

Utility library consolidation and dependency cleanup

### Added
- **Logger integration in Utility Scripts** - Added structured logging support with safe fallback
  - New `__*_log__()` wrapper for logging events
- **Enhanced ArgumentParser.sh** - Improved argument validation, error handling, and help text generation
- **Enhanced TestFramework.sh** - Improved test assertions and result reporting

### Changed
- **Utility consolidation**
  - Renamed `ProxmoxAPI.sh` -> `Operations.sh`
  - Renamed `Queries.sh` -> `Cluster.sh`
  - Renamed `NetworkHelper.sh` -> `Network.sh`
  - Removed `BatchRunCLI.sh` - functionality integrated in GUI.sh
- **Source dependency cleanup** - Updated scripts with correct utility imports
  - Replaced `ProxmoxAPI.sh` -> `Operations.sh` across all VM/LXC bulk operations
  - Fixed `Queries.sh` -> `Cluster.sh` references in storage scripts
  - Updated `NetworkHelper.sh` -> `Network.sh` references
- **Function standardization** - Unified prompt API across all scripts
  - Updated `__prompt_yes_no__` -> `__prompt_user_yn__`
  - Consistent user interaction patterns throughout codebase
- **Enhanced utilities** - Improvements to core libraries
  - BulkOperations.sh: Better error handling and progress reporting
  - Communication.sh: Enhanced messaging and logging
  - Prompts.sh: Improved input validation and dialogs
  - SSH.sh: Streamlined remote execution
  - GUI.sh: Better menu structure and user experience

### Fixed
- **Auto-confirm support** - Added `--yes` flag for non-interactive bulk deletion
- **Import corrections** - Fixed incorrect source dependencies and shellcheck directives
- **Storage improvements** - Enhanced validation and error handling in storage operations

### Removed
- BatchRunCLI.sh and associated test files

## [2.0.2] - 2025-11-06

ArgumentParser migration

### Changed
- **Rest of Scripts Updated with ArgumentParser** 
  - Migration of all non-interactive scripts (previously listed in TODO.md)

- **Standards Applied**
  - ArgumentParser.sh sourced with proper shellcheck directives
  - UPPERCASE variable names from ArgumentParser
  - Automatic --help support (or manual for hybrid scripts)
  - Removed manual usage() functions and validation loops
  - Proper exit codes (64 for usage errors)
  - Consistent error handling with __err__
  - Updated testing status comments

### Fixed
- **GUI.sh Critical Bug**
  - Added `bash` prefix to all script execution calls
  - Prevent immediate script closure issue

## [2.0.1] - 2025-11-04

Implementation of ArgumentParser across the codebase and improved scripting standards

### Added
- **CONTRIBUTING.md Section 3.10** - Comprehensive ArgumentParser usage guide
  - Declarative argument parsing patterns and examples
  - Custom validation patterns with `validate_custom_options()`
  - Decision guide table for when to use ArgumentParser vs manual parsing
  - Best practices for handling complex argument structures

### Changed
- **Full refactoring + implementation of ArgumentParser**
  - VirtualMachines/Hardware/BulkConfigureCPU.sh
  - VirtualMachines/Hardware/BulkConfigureNetwork.sh
  - VirtualMachines/Storage/BulkConfigureDisk.sh
  - Storage/AddStorage.sh
  - Storage/RemoveStorage.sh
  - Removed manual `usage()` and `parse_args()` functions
  - Added `validate_custom_options()` for logic validation
  - Now use `__parse_args__` declarative parsing
  - Fixed `__prompt_yes_no__` -> `__prompt_user_yn__` calls
- **ArgumentParser integration**
  - Host/Hardware/EnableCPUScalingGoverner.sh
  - RemoteManagement/ConfigureOverSSH/Proxmox/BulkDisableAutoStart.sh
  - RemoteManagement/ConfigureOverSSH/Proxmox/BulkUnmountISOs.sh
  - Storage/Ceph/SetScrubInterval.sh: (quality improvement with proper documentation/standards)
  - Removed manual `usage()` functions
  - Added ArgumentParser sourcing and `__parse_args__` calls
- **Storage/Ceph/SetScrubInterval.sh** - Updated to match current codebase
  - Added proper `@function`, `@description`, `@param` documentation tags
  - Replaced `echo` with `__info__`, `__ok__`, `__err__` communication functions
  - Added `__prompt_user_yn__` confirmations before operations
  - Added `readonly` constants for configuration values
  - User feedback with detailed status messages
- **README.md** - Corrected outdated references
  - Fixed `CCPVEOffline.sh` -> `GUI.sh` (correct script name)
  - Removed non-existent `Utilities.sh` reference
  - Enhanced Contributing section with links to CONTRIBUTING.md
  - Added ArgumentParser requirement highlights
  - Added compliance checklist references
- **CONTRIBUTING.md** - Enhanced with ArgumentParser standards
  - Updated Usage section header format to `ScriptName.sh` (no `./` prefix)
  - Clarified that GUI auto-generates usage from script comments
  - Added comprehensive Section 3.10 on argument parsing

### Fixed
- **Script header format consistency**
  - Usage section now shows `ScriptName.sh` without `./` prefix
  - All scripts properly source ArgumentParser.sh
  - Function documentation follows `@function`, `@description`, `@param` pattern
- **Prompt function calls** - Corrected `__prompt_yes_no__` -> `__prompt_user_yn__` in refactored scripts
- **Communication functions** - Ensured all user-facing messages use `__info__`, `__ok__`, `__err__` instead of plain `echo`

## [2.0.0] - 2025-11-03

### Overview
Version 2.0 introduces new utility frameworks that standardize script behavior across the codebase. Key additions include ArgumentParser for consistent argument handling, BulkOperations for unified bulk operations, ProxmoxAPI for centralized Proxmox interactions, and TestFramework for automated testing. All scripts have been refactored to use these utilities and follow consistent error handling patterns.

### Added
- **Utilities/ArgumentParser.sh** - New comprehensive argument parsing framework
  - Standardized argument handling across all scripts
  - Built-in validation for common types (vmid, string, integer, boolean, range)
  - Automatic help text generation and error messages
  - Support for optional and required parameters
- **Utilities/BulkOperations.sh** - Unified framework for bulk VM/LXC operations
  - Standardized operation patterns with consistent error handling
  - Built-in progress reporting and operation summaries
  - Automatic success/failure tracking with detailed statistics
  - Support for both range and pool-based operations
- **Utilities/Operations.sh** - Centralized Proxmox API wrapper functions
  - Consistent VM/LXC operations (start, stop, reset, migrate, etc.)
  - Standardized disk and hardware management functions
  - Pool and node management utilities
  - Improved error handling and validation
- **Utilities/Network.sh** - Network utility functions for IP and network operations
  - IP address validation and manipulation
  - Network configuration helpers
  - DNS and network interface utilities
- **Utilities/StateManager.sh** - State management system for complex operations
  - Transaction-like state tracking for multi-step operations
  - Rollback capabilities for failed operations
  - Persistent state storage and recovery
- **Utilities/TestFramework.sh** - Comprehensive testing framework for shell scripts
  - Unit testing capabilities for utility functions
  - Integration testing support
  - Test assertion functions and result reporting
  - Automated test discovery and execution
- **Utilities/_TestArgumentParser.sh** - Test suite for ArgumentParser functionality
- **Utilities/_TestBulkOperations.sh** - Test suite for BulkOperations framework
- **Utilities/_TestNetwork.sh** - Test suite for Network utilities
- **Utilities/_TestOperations.sh** - Test suite for ProxmoxAPI functions
- **Utilities/_TestRemoteExec.sh** - Test suite for remote execution utilities
- **Utilities/_TestStateManager.sh** - Test suite for StateManager functionality
- **Utilities/_TestIntegrationExample.sh** - Example integration test demonstrating framework usage
- **Utilities/RunAllTests.sh** - Automated test runner for all utility test suites
- **Utilities/_ScriptComplianceChecklist.md** - Comprehensive script compliance and quality checklist
- **VirtualMachines/Operations/BulkHibernate.sh** - New script for bulk VM hibernation
- **VirtualMachines/Operations/BulkSuspend.sh** - New script for bulk VM suspend operations
- **VirtualMachines/Operations/BulkResume.sh** - New script for bulk VM resume operations
- **VirtualMachines/Hardware/BulkToggleTabletPointer.sh** - New script for bulk tablet pointer device configuration
- **VirtualMachines/Storage/BulkConfigureDisk.sh** - New comprehensive disk configuration script

### Changed
- **Standardized script headers across entire codebase** - Fixed malformed headers
  - All scripts now follow consistent format: shebang -> documentation -> Function Index -> `set -euo pipefail` -> code
  - Removed duplicate `set -` commands that were scattered throughout script headers
  - Removed misplaced early `set -` commands that appeared before documentation blocks
  - Changed `set -u` to `set -euo pipefail` for proper error handling with pipefail and errexit
  - Fixed scripts where Function Index and documentation blocks were duplicated
  - Scripts with heredocs containing `set -euo pipefail` for remote execution are intentionally preserved
  - Affected all major script directories: Cluster/, Firewall/, HighAvailability/, Host/, LXC/, Networking/, RemoteManagement/, Security/, Storage/, VirtualMachines/
  - Improved consistency, maintainability, and error handling across all scripts
- **Refactored scripts to use new ArgumentParser and BulkOperations frameworks**
  - All bulk operation scripts now use consistent argument parsing
  - Unified error handling and reporting across all bulk operations
  - Standardized output format with operation summaries
  - Improved validation and user feedback
  - Scripts automatically generate consistent help text
- **Major refactoring of VM/LXC bulk operation scripts** - Converted to use new frameworks
  - VirtualMachines/Operations/: BulkMigrate.sh, BulkStart.sh, BulkStop.sh, BulkReset.sh, BulkDelete.sh, BulkClone.sh, BulkUnlock.sh, BulkRemoteMigrate.sh, BulkCloneCloudInit.sh
  - VirtualMachines/CloudInit/: BulkAddSSHKey.sh, BulkChangeDNS.sh, BulkChangeIP.sh, BulkChangeUserPass.sh, BulkMoveCloudInit.sh, BulkTogglePackageUpgrade.sh
  - VirtualMachines/Hardware/: BulkConfigureCPU.sh, BulkConfigureNetwork.sh, BulkSetCPUTypeCoreCount.sh, BulkSetMemoryConfig.sh, BulkUnmountISOs.sh
  - VirtualMachines/Options/: BulkEnableGuestAgent.sh, BulkToggleProtectionMode.sh, BulkToggleStartAtBoot.sh
  - VirtualMachines/Storage/: BulkChangeStorage.sh, BulkMoveDisk.sh, BulkResizeStorage.sh
  - VirtualMachines/Backup/: BulkBackup.sh
  - LXC/Operations/: BulkClone.sh, BulkStart.sh, BulkStop.sh, BulkReset.sh, BulkDelete.sh, BulkDeleteAllLocal.sh
  - LXC/Hardware/: BulkSetCPU.sh, BulkSetMemory.sh
  - LXC/Networking/: BulkAddSSHKey.sh, BulkChangeDNS.sh, BulkChangeIP.sh, BulkChangeNetwork.sh, BulkChangeUserPass.sh
  - LXC/Options/: BulkToggleProtectionMode.sh, BulkToggleStartAtBoot.sh
- **Enhanced Utilities/Communication.sh** - Improved messaging functions and formatting
- **Enhanced Utilities/Prompts.sh** - Better user interaction and input validation
- **Enhanced Utilities/Cluster.sh** - Extended query capabilities for VM/LXC/node information
- **Enhanced Utilities/Conversion.sh** - Additional conversion and formatting utilities
- **Enhanced Utilities/Colors.sh** - Improved color output and terminal formatting
- **Enhanced Utilities/SSH.sh** - Better SSH connection handling and remote execution
- **Improved .check/_RunChecks.sh** - Enhanced validation and automated checking with better reporting
- **Updated .check/UpdateUtilityDocumentation.py** - Enhanced documentation generation for utilities
- **Updated .check/VerifySourceCalls.py** - Improved source dependency verification
- **Enhanced GUI.sh** - Better menu organization and user interface
- **Improved CONTRIBUTING.md** - Expanded contribution guidelines with framework usage documentation
- **Major expansion of Utilities/_Utilities.md** - Comprehensive documentation for all utility functions
  - Detailed function documentation with examples
  - Framework usage guides
  - Best practices and patterns

### Fixed
- **Consistent error handling** - All scripts now properly use `set -euo pipefail` for robust error detection
- **Source dependency issues** - Resolved missing or incorrect utility dependencies across all scripts
- **Function index accuracy** - All scripts now have accurate function index listings
- **Line ending consistency** - Normalized CRLF to LF across all scripts for Unix compatibility
- **Validation improvements** - Better input validation and error messages across all scripts

### Testing
- **Comprehensive test coverage** - Added test suites covering all major utility frameworks
- **Automated test execution** - RunAllTests.sh provides one-command testing for all utilities
- **Integration testing** - Example integration tests demonstrate proper framework usage
- **Test framework infrastructure** - New TestFramework.sh enables systematic testing of shell scripts

## [Unreleased] - 2025-10-16

### Added
- **RemoteManagement/ApacheGuacamole/RDP/BulkRemoveRDPConnection.sh** - New script for bulk removal of Guacamole RDP connections
  - Supports removal by substring search or VMID range
  - Includes safety confirmation prompts
  - Two operating modes: substring search and VMID range deletion
- **Storage/AddStorage.sh** - Comprehensive script for adding storage to Proxmox cluster
  - Supports NFS, SMB/CIFS, and Proxmox Backup Server (PBS) storage types
  - Configurable content types, mount options, and node targeting
  - Built-in validation and error handling
- **Storage/RemoveStorage.sh** - Safe storage removal script
  - Checks for storage usage before removal
  - Supports force removal option
  - Validates storage exists before attempting removal
- **VirtualMachines/Hardware/BulkConfigureCPU.sh** - New script for bulk CPU configuration
- **VirtualMachines/Hardware/BulkConfigureNetwork.sh** - New script for bulk network configuration
- **.check/VerifySourceCalls.py** - Enhanced with improved dependency detection and fix mode
  - Automatically adds missing source dependencies
  - Removes unused source includes
  - Adds proper shellcheck directives

### Changed
- **Major dependency cleanup** - Fixed source call dependencies across 42+ shell scripts
  - Removed unused source includes from multiple scripts
  - Added missing dependencies (Communication.sh, Prompts.sh) where needed
  - All scripts now pass VerifySourceCalls validation
- **Line ending normalization** - Converted CRLF to LF across all modified scripts for Unix compatibility
- **Utilities/Communication.sh** - Added new utility functions for better script communication
- **Utilities/Prompts.sh** - Enhanced prompt utilities with additional functionality
- **Utilities/_Utilities.md** - Expanded documentation for utility functions
- **Resources/ChangeAllMACPrefix.sh** - Fixed missing source dependencies
- Updated multiple VM management scripts:
  - VirtualMachines/BulkAddIPToNote.sh - Removed unused dependencies
  - CloudInit scripts: BulkAddSSHKey.sh, BulkChangeDNS.sh, BulkChangeIP.sh, BulkChangeUserPass.sh, BulkMoveCloudInit.sh, BulkTogglePackageUpgrade.sh
  - Hardware scripts: BulkSetCPUTypeCoreCount.sh, BulkSetMemoryConfig.sh, BulkUnmountISOs.sh
  - Operations scripts: BulkDelete.sh, BulkMigrate.sh, BulkRemoteMigrate.sh, BulkReset.sh, BulkStart.sh, BulkStop.sh, BulkUnlock.sh
  - Options scripts: BulkEnableGuestAgent.sh, BulkToggleProtectionMode.sh, BulkToggleStartAtBoot.sh
  - Storage scripts: BulkChangeStorage.sh, BulkMoveDisk.sh, BulkResizeStorage.sh
  - Backup scripts: BulkBackup.sh
- **Networking/BulkPrintVMIDMacAddresses.sh** - Removed unused Prompts.sh and Cluster.sh dependencies
- **Storage/Ceph/** - Cleaned up dependencies in Ceph cluster management scripts
  - RestartManagers.sh, RestartMetadata.sh, RestartMonitors.sh, RestartOSDs.sh
- **RemoteManagement/ApacheGuacamole/RDP/** - Fixed dependencies in multiple scripts
  - BulkAddSFTPServer.sh, BulkPrintRDPConfiguration.sh, BulkRemoveSFTPServer.sh
- **RemoteManagement/ConfigureOverSSH/** - Dependency cleanup in SSH configuration scripts

### Fixed
- **Storage/AddStorage.sh** - Fixed line ending formatting (CRLF -> LF)
- **Storage/RemoveStorage.sh** - Fixed line ending formatting (CRLF -> LF)
- **Storage/Ceph/SetScrubInterval.sh** - Added missing source dependencies and fixed formatting
- All scripts now have proper shellcheck source directives for IDE integration

### Removed
- **VirtualMachines/Hardware/BulkChangeNetwork.sh** - Deprecated (replaced by BulkConfigureNetwork.sh)
- **VirtualMachines/Operations/-BulkHibernate.sh** - Removed incomplete development script

## [Unreleased] - 2025-10-14

### Added
- **VirtualMachines/Backup/** - New directory structure for VM backup operations
  - BulkBackup.sh - Relocated and enhanced bulk VM backup functionality
- **VirtualMachines/Configuration/** - New directory for VM configuration scripts
  - VMAddTerminalTTYS0.sh - Relocated terminal configuration script
- **VirtualMachines/Operations/BulkMigrate.sh** - New script for VM migration operations
- **.docs/** - New documentation directory structure
- **.gitignore** - Added Git ignore file for repository hygiene
- **CHANGELOG.md** - Comprehensive changelog with detailed version history and verbose commit descriptions

### Changed
- Major refactoring of VirtualMachines directory structure with improved organization
- Updated multiple VM management scripts:
  - Utilities/Cluster.sh - Enhanced query functionality
  - VirtualMachines/BulkAddIPToNote.sh - Improved IP note management
  - CloudInit scripts: BulkAddSSHKey.sh, BulkChangeDNS.sh, BulkChangeIP.sh, BulkChangeUserPass.sh, BulkMoveCloudInit.sh, BulkTogglePackageUpgrade.sh
  - Hardware scripts: BulkChangeNetwork.sh, BulkSetCPUTypeCoreCount.sh, BulkSetMemoryConfig.sh, BulkUnmountISOs.sh
  - Operations scripts: BulkDelete.sh, BulkRemoteMigrate.sh, BulkReset.sh, BulkStart.sh, BulkStop.sh, BulkUnlock.sh
  - Options scripts: BulkEnableGuestAgent.sh, BulkToggleProtectionMode.sh, BulkToggleStartAtBoot.sh
  - Storage scripts: BulkChangeStorage.sh, BulkMoveDisk.sh, BulkResizeStorage.sh

### Removed
- VirtualMachines/Hardware/VMAddTerminalTTYS0.sh - Relocated to Configuration directory
- VirtualMachines/Operations/BulkBackup.sh - Relocated to Backup directory

## [v1.52] - 2025-10-06

### Added
- Implemented BatchRunCLI for nested calls to virtualized Proxmox hosts, enabling interactive and non-interactive bulk CLI execution
- Enhanced SSH utilities with functionality for remote host management

### Changed
- Refactored BatchRunCLI.sh with improved architecture
- Enhanced Communication.sh utilities with better error handling and logging
- Updated GUI.sh with improved user interface elements

## [v1.51] - 2025-10-03

### Added
- **BatchRunCLI.sh** - New interactive/non-interactive bulk CLI execution script
- **Utilities/SSH.sh** - Comprehensive SSH utilities library for remote operation
- **Utilities/Conversion.sh** - Data conversion utilities
- **Utilities/Prompts.sh** - User prompt utilities
- **Utilities/Cluster.sh** - Query utilities for system information
- Test scripts for new utilities (_TestConversion.sh, _TestPrompts.sh, _TestSSH.sh)

### Changed
- Refactored multiple bulk remote scripts to use new utility functions:
  - BulkCloneSetIP.sh
  - BulkDisableAutoStart.sh
  - BulkReconfigureMacAddresses.sh
  - BulkUnmountISOs.sh
- Updated CCPVE.sh to set up CLI calls
- Consolidated and improved CONTRIBUTING.md with script style guide
- Enhanced SetScrubInterval.sh for Ceph storage
- Updated README.md

### Removed
- Deprecated ScriptStyleGuide.md (moved content to CONTRIBUTING.md)

## [v1.50] - 2025-10-01

### Added
- **BulkDisableAutoStart.sh** - Bulk disable autostart on all nested VMs
- **BulkUnmountISOs.sh** - Bulk unmount ISOs on all nested VMs
- **ChangeAllMACPrefix.sh** - Script for editing MAC address prefixes of a single host instance
- **ScriptStyleGuide.md** - Comprehensive style guide for consistent script development
- Enhanced example script (_ExampleScript.sh) with more useful examples

### Changed
- Updated CCPVE.sh with better nested call handling for non-root users
- Improved GUI.sh with additional menu options
- Enhanced Colors.sh with better color handling
- Updated README.md with new script documentation

### Fixed
- Fixed nested call functionality for non-root users in CCPVE.sh

## [v1.47] - 2025-09-09

### Added
- **BulkReconfigureMacAddresses.sh** - Bulk reconfigure MAC addresses for multiple VMs
- **BulkCloneSetIP.sh** (Proxmox) - Enhanced bulk clone script with MAC address randomization
- Automatic MAC address randomization during bulk clone operations
- MAC prefix configuration set to BC:XX:XX where XXXX is the VM ID

### Changed
- Reorganized ConfigureOverSSH scripts into platform-specific subdirectories (Proxmox, Debian, Ubuntu, Windows)
- Moved guest agent installation script to dedicated location

### Removed
- Deprecated BulkCloneSetIPDebian.sh in favor of platform-organized structure

## [v1.44] - 2025-08-20

### Fixed
- Added missing Conversion.sh helper include in BulkCloneSetIPDebian.sh
- Resolved script dependency issue preventing proper execution

## [v1.43] - 2025-08-20

### Fixed
- Corrected elif/else mistype in BulkClone.sh that was causing conditional logic errors
- Improved code readability with better formatting

## [v1.42] - 2025-07-14

### Changed
- Refactored BulkToggleProtectionMode.sh to directly edit unprivileged flag in LXC configuration files
- Replaced protected flag with more reliable unprivileged flag manipulation

### Fixed
- Protection toggle now correctly sets unprivileged flag on LXC containers
- Resolved issues with LXC container protection not being applied correctly

## [v1.41] - 2025-07-08

### Added
- **RestartAllDaemons.sh** - Comprehensive script to restart or check status of all local Ceph services
  - Supports Ceph Monitor (mon) services
  - Supports Ceph Metadata Server (mds) services
  - Supports Ceph Manager (mgr) services
  - Supports Ceph OSD (osd) services
  - Interactive status checking and restart options

## [v1.40] - 2025-07-08

### Added
- **Host/RestartManager.sh** - Restart Ceph Manager daemon on local host
- **Host/RestartMetadata.sh** - Restart Ceph Metadata Server daemon on local host
- **Host/RestartMonitor.sh** - Restart Ceph Monitor daemon on local host
- **Host/RestartOSDs.sh** - Restart all Ceph OSD daemons on local host

### Changed
- Reorganized Ceph management scripts into logical subdirectories:
  - **Cluster/** - Cluster-wide operations (CreateOSDs, RestartManagers, RestartMetadata, RestartMonitors, RestartOSDs, StartStoppedOSDs)
  - **Host/** - Host-specific operations (EditCrushmap, SingleDrive, WipeDisk, and new restart scripts)
  - **Pools/** - Pool management (SetPoolMinSize1, SetPoolSize1)
- Updated RestartMetadata.sh in Cluster

## [v1.39] - 2025-04-09

### Added
- **RestartManagers.sh** - Restart all Ceph Manager daemons across cluster
- **RestartMetadata.sh** - Restart all Ceph Metadata Server daemons across cluster
- **RestartMonitors.sh** - Restart all Ceph Monitor daemons across cluster
- **RestartOSDs.sh** - Restart all Ceph OSD daemons across cluster
- Auto-restart functionality for cluster Ceph services

### Changed
- Renamed Ceph scripts for consistency and clarity:
  - CephCreateOSDs.sh -> CreateOSDs.sh
  - CephEditCrushmap.sh -> EditCrushmap.sh
  - CephSetPoolMinSize1.sh -> SetPoolMinSize1.sh
  - CephSetPoolSize1.sh -> SetPoolSize1.sh
  - CephSetScrubInterval.sh -> SetScrubInterval.sh
  - CephSingleDrive.sh -> SingleDrive.sh
  - CephSparsifyDisk.sh -> SparsifyDisk.sh
  - CephStartStoppedOSDs.sh -> StartStoppedOSDs.sh
  - CephWipeDisk.sh -> WipeDisk.sh
- Enhanced Cluster.sh utility with improved functionality
- Updated _Utilities.md documentation

### Fixed
- Fixed pool setting issues with bulk VM clone operations
- Corrected MAC address printing in BulkPrintVMIDMacAddresses.sh

## [v1.38] - 2025-02-20

### Added
- **BulkPrintVMIDMacAddresses.sh** - Print VM IDs and their associated MAC addresses
- **BulkAddSFTPServer.sh** - Bulk add SFTP server configurations to Guacamole
- **BulkPrintRDPConfiguration.sh** - Print RDP configuration details for multiple connections
- **BulkRemoveDriveRedirection.sh** - Bulk remove drive redirection from RDP connections
- **BulkRemoveSFTPServer.sh** - Bulk remove SFTP server configurations from Guacamole
- **RestoreVM.sh** - Restore virtual machines from backups

### Changed
- Renamed BulkAddRDPConnectionGuacamole.sh for consistency
- Significantly enhanced Cluster.sh utility with additional query functions
- Improved Apache Guacamole automation capabilities

## [v1.37] - 2025-02-16

### Added
- **BulkUpdateDriveRedirection.sh** - Configure Apache Guacamole drive redirection for multiple RDP connections
- Drive redirection configuration for improved file sharing in remote desktop sessions

### Changed
- Reorganized remote management scripts into better directory structure:
  - Created ApacheGuacamole subdirectory with RDP and DriveRedirection subfolders
  - Moved Guacamole authentication token scripts to dedicated locations
- Updated BulkCloneSetIPWindows.sh with improved functionality
- Standardized ConfigureOverSSH script organization

## [v1.36] - 2025-02-02

### Added
- **UpdateUtilityDocumentation.py** - Python script for automatic utility function documentation generation
- Automated documentation system for utility functions
- Enhanced documentation in _Utilities.md with comprehensive function breakdowns

### Changed
- Refactored utility libraries for better Linux compatibility:
  - Colors.sh
  - Communication.sh
  - Conversion.sh
  - Prompts.sh
  - Cluster.sh
  - SSH.sh
- Updated VerifySourceCalls.py for better cross-platform support
- Enhanced GUI.sh
- Improved UplinkSpeedTest.sh networking script

### Fixed
- Fixed Python code compatibility issues for use on Linux systems
- Resolved path handling in Python verification scripts
- Corrected documentation generation errors

## [v1.35] - 2025-02-02

### Changed
- Renamed LXC/Storage/BulkMoveDisk.sh to BulkMoveVolume.sh for accuracy

### Fixed
- Fixed storage move operations for LXC containers
- Corrected volume path handling in LXC storage operations

## [v1.34] - 2025-01-29

### Added
- **BulkAddFirewallLXCVM.sh** - Bulk configure firewall rules for LXC containers and VMs
- Comprehensive firewall configuration automation
- Support for both LXC and VM firewall management

## [v1.33] - 2025-01-23

### Added
- **BulkAddConnectionGuacamole.sh** (RDP) - Automatically create RDP connections for Apache Guacamole by specifying VMID range
- **BulkDeleteConnectionGuacamole.sh** - Bulk delete Guacamole connections by keyword search
- **GetGuacamoleAuthenticationToken.sh** - Create local Guacamole authentication tokens for management
- **RemoveGuacamoleAuthenticationToken.sh** - Remove Guacamole authentication tokens
- Query function to retrieve IP addresses from virtual machine IDs
- Automatic RDP connection creation for specified VMID ranges

### Changed
- Enhanced Cluster.sh with Guacamole integration functions
- Moved installation of required tools to top of file for better user experience


## [v1.31] - 2025-01-22

### Fixed
- Fixed BulkCloneWindows functionality with improved conversion utilities
- Corrected BulkCloneSetIPWindows.sh script operations
- Added serve.bat for documentation site

## [v1.30] - 2025-01-22

### Added
- Test scripts for utilities: _TestCommunication.sh and _TestConversion.sh

### Changed
- Enhanced Conversion.sh with additional conversion functions

### Fixed
- Fixed BulkCloneSetIPWindows functionality with major refactoring
- Improved Windows IP configuration during bulk clone operations

## [v1.29] - 2025-01-19

### Added
- **VerifySourceCalls.py** - Comprehensive Python script to verify source calls in shell scripts
- Automated verification system for script dependencies and source calls
- Integration with .check directory for continuous validation
- Shell script execution for validation (_RunChecks.bat, _RunChecks.sh)
- .gitattributes configuration for consistent line endings

### Changed
- Updated ShellCheck.py with improved validation
- Comprehensive refactoring of all scripts to ensure proper source call verification:
  - Updated 80+ scripts across Cluster, Firewall, GUI, HighAvailability, Host, LXC, Networking, Resources, Security, Storage, and VirtualMachines directories
  - Standardized source call patterns throughout the codebase
  - Improved script reliability and maintainability

## [v1.28] - 2025-01-15

### Added
- **FindLinkedClone.sh** - Method to find linked clones from the base VM ID
- Ability to trace VM clone relationships
- Enhanced clone tracking capabilities

## [v1.27] - 2025-01-14

### Added
- **CreateVirtualMachine.sh** - Virtual Machine creation from local and remote ISOs
- **BulkConfigureOverSSH.sh** - Non-cloud init VM configuration over SSH
- Method to hide ASCII art in terminal output
- Color support in GUI for better user experience

### Changed
- Enhanced GUI appearance with color coding
- Improved UI layout for small terminal windows
- Better visual feedback for user actions

### Fixed
- Bulk clone Debian functionality corrected
- Protection option toggle fixed (contributed by RaymondH)

## [v1.26] - 2025-01-11

### Fixed
- Major fixes for unified script architecture
- Cluster modification improvements for better stability
- Script cleanup and error handling improvements

## [v1.25] - 2025-01-10

### Fixed
- Removed carriage return characters causing script execution issues on Linux
- Simplified include statements for utilities script
- Cross-platform compatibility improvements

## [v1.24] - 2025-01-07

### Added
- **Utilities function library** for code reusability across all scripts
- Centralized common functions to reduce code duplication
- Foundation for modular script architecture

## [v1.23] - 2025-01-06

### Added
- Multiple new operational scripts for various Proxmox tasks
- Repository templates (CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md)
- GitHub policies and contribution guidelines

### Changed
- Split Online/Offline script functionality for better compatibility
- Improved script organization and structure

## [v1.22] - 2025-01-05

### Changed
- Split Configuration scripts into Cluster and Host directories
- Better organization of configuration-related scripts
- Clearer separation of cluster-wide vs. host-specific operations

## [v1.21] - 2025-01-04

### Added
- **Offline script** functionality for systems without internet access
- Automated release workflow for .sh file changes
- Cluster management scripts for node operations

## [v1.20] - 2025-01-01

### Added
- **Method to remove and re-add stale mounts** in storage operations
- Automated stale mount detection and remediation

## [v1.19] - 2024-12-29

### Added
- **Single line command** to navigate all scripts (b4b6109.sh)
- Simplified script access and execution

### Fixed
- Various bug fixes and improvements
- Enhanced stability and reliability

## [v1.18] - 2024-12-21

### Added
- SEO information for better project discoverability
- Enhanced documentation for search engine optimization

### Fixed
- Case sensitivity issues in script names and paths
- Cross-platform compatibility improvements

---

## Template for Future Releases

## [X.X.X] - YYYY-MM-DD

### Added
- New features or scripts

### Changed
- Modifications to existing features

### Fixed
- Bug fixes and corrections

### Removed
- Deprecated or removed features

### Testing
- Testing improvements

### Next Tasks
- Planned future work