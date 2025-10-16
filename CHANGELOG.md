# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- **Utilities/Utilities.md** - Expanded documentation for utility functions
- **Resources/ChangeAllMACPrefix.sh** - Fixed missing source dependencies
- Updated multiple VM management scripts:
  - VirtualMachines/BulkAddIPToNote.sh - Removed unused dependencies
  - CloudInit scripts: BulkAddSSHKey.sh, BulkChangeDNS.sh, BulkChangeIP.sh, BulkChangeUserPass.sh, BulkMoveCloudInit.sh, BulkTogglePackageUpgrade.sh
  - Hardware scripts: BulkSetCPUTypeCoreCount.sh, BulkSetMemoryConfig.sh, BulkUnmountISOs.sh
  - Operations scripts: BulkDelete.sh, BulkMigrate.sh, BulkRemoteMigrate.sh, BulkReset.sh, BulkStart.sh, BulkStop.sh, BulkUnlock.sh
  - Options scripts: BulkEnableGuestAgent.sh, BulkToggleProtectionMode.sh, BulkToggleStartAtBoot.sh
  - Storage scripts: BulkChangeStorage.sh, BulkMoveDisk.sh, BulkResizeStorage.sh
  - Backup scripts: BulkBackup.sh
- **Networking/BulkPrintVMIDMacAddresses.sh** - Removed unused Prompts.sh and Queries.sh dependencies
- **Storage/Ceph/** - Cleaned up dependencies in Ceph cluster management scripts
  - RestartManagers.sh, RestartMetadata.sh, RestartMonitors.sh, RestartOSDs.sh
- **RemoteManagement/ApacheGuacamole/RDP/** - Fixed dependencies in multiple scripts
  - BulkAddSFTPServer.sh, BulkPrintRDPConfiguration.sh, BulkRemoveSFTPServer.sh
- **RemoteManagement/ConfigureOverSSH/** - Dependency cleanup in SSH configuration scripts

### Fixed
- **Storage/AddStorage.sh** - Fixed line ending formatting (CRLF → LF)
- **Storage/RemoveStorage.sh** - Fixed line ending formatting (CRLF → LF)
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
  - Utilities/Queries.sh - Enhanced query functionality
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
- **Utilities/Queries.sh** - Query utilities for system information
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
- Enhanced Queries.sh utility with improved functionality
- Updated Utilities.md documentation

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
- Significantly enhanced Queries.sh utility with additional query functions
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
- Enhanced documentation in Utilities.md with comprehensive function breakdowns

### Changed
- Refactored utility libraries for better Linux compatibility:
  - Colors.sh
  - Communication.sh
  - Conversion.sh
  - Prompts.sh
  - Queries.sh
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
- Enhanced Queries.sh with Guacamole integration functions
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
- **VerifySourceCalls.py** - Comprehensive Python script to verify source calls in shell scripts (364 lines)
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