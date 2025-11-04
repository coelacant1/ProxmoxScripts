# Pending Change Tracker
## Datacenter
- [x] Add storage: SMB, NFS, PBS (For bulk CLI calls)

## Virtual Machines
### Operations
- [x] Bulk Hibernate
- [x] Bulk Pause
- [x] Bulk Resume

### Hardware
- [x] Bulk start
- [x] Bulk shutdown
- [x] Bulk reboot
- [x] Bulk shutdown + power on (clean reboot to take VM hardware changes)
- [x] Bulk migrate
- [ ] Change CPU: core count, socket count, numa mode, type, vcpus, cpu limit, cpu affinity, cpu units, optional cpu flags
- [ ] Change BIOS type
- [ ] Change display type
- [ ] Change machine type
- [ ] Change SCSI controller type
- [x] Change hard disk options: cache, discard, io thread, read only, ssd emulation, backup, skip replication, async io
- [x] Change vmbr configuration: add optional vlan, firewall, disconnect, mtu, rate limit, multiqueue, mac address (and prefix), model
- [ ] Change memory to add balooning option as well as min/max size separately
- [ ] Add hard disk
- [ ] Add serial port
- [ ] Add cloudinit drive
- [x] Disconnect all CD/DVD drives

### Options
- [x] Disable AutoStart on all VMs/LXCs
- [x] Disable touch pointer
- [ ] Change boot order (list available on main VM, must all be same cloned instance)
- [ ] Change hot plug
- [ ] Change SMBIOS (interactive)
- [ ] Qemu guest agent: run guest trim, freeze thaw on backup, type
- [ ] Protection mode
- [ ] VM state storage
- [ ] AMD SEV configuration

### Firewall
- [ ] Insert available security group from cluster
- [ ] Remove all
- [ ] Enable firewall
- [ ] Set input/output policy

### Backup
- [ ] Bulk backup

### Snapshot
- [ ] Bulk snapshot

### Remote Management
- [ ] AddGuestAgent.sh


## Host
- [ ] Backup Host Config

## To Fix
- [ ] VM BulkCloneCloudInit using temp global functions -> migrate to conversion utility (include it)
- [ ] Utilities documentation/consistency


## Script Modification
- Use ArgumentParser.sh - create example files?
-

## Notes
- Change from e1000e to virtio, change nested to disable touch pointer for 110

---

## Not Yet Updated

### Large/Complex Scripts
- [ ] VirtualMachines/CreateFromISO.sh - Complex interactive VM creation, many configuration options
- [ ] VirtualMachines/InteractiveRestoreVM.sh - Interactive restore with user prompts

### Specialized Hardware/System Scripts
- [ ] Host/FanControl/DellIPMIFanControl.sh - IPMI-specific, hardware dependent
- [ ] Host/FanControl/EnablePWMFanControl.sh - PWM control, hardware dependent
- [ ] Host/Hardware/EnableCPUScalingGoverner.sh - Kernel parameter manipulation
- [ ] Host/Bulk/FirstTimeProxmoxSetup.sh - Complex initial setup wizard

### Interactive Menu Scripts
- [ ] BatchRunCLI.sh - Complex interactive CLI menu system
- [ ] CCPVE.sh - Complex interactive CLI menu system
- [ ] GUI.sh - Complex interactive GUI menu system

---

# Scripts Needing ArgumentParser Update

Add `source "${UTILITYPATH}/ArgumentParser.sh"` and use `__parse_args__` for argument handling.

## Cluster
- [ ] `Cluster/AddNodes.sh`
- [ ] `Cluster/CreateCluster.sh`
- [ ] `Cluster/DeleteCluster.sh`
- [ ] `Cluster/RemoveClusterNode.sh`

## Firewall (1 script)
- [ ] `Firewall/EnableFirewallSetup.sh`

## High Availability
- [ ] `HighAvailability/AddResources.sh`
- [ ] `HighAvailability/CreateHAGroup.sh`
- [ ] `HighAvailability/DisableHAClusterWide.sh`
- [ ] `HighAvailability/DisableHighAvailability.sh`

## Host/Bulk
- [ ] `Host/Bulk/FirstTimeProxmoxSetup.sh`
- [ ] `Host/Bulk/ProxmoxEnableMicrocode.sh`
- [ ] `Host/Bulk/SetTimeZone.sh`
- [ ] `Host/Bulk/UpgradeAllServers.sh`
- [ ] `Host/Bulk/UpgradeRepositories.sh`

## Host/FanControl
- [ ] `Host/FanControl/DellIPMIFanControl.sh`
- [ ] `Host/FanControl/EnablePWMFanControl.sh`

## Host/Hardware
- [ ] `Host/FixDPKGLock.sh`
- [ ] `Host/Hardware/EnableIOMMU.sh`
- [ ] `Host/Hardware/EnablePCIPassthroughLXC.sh`
- [ ] `Host/Hardware/EnableX3DOptimization.sh`
- [ ] `Host/Hardware/OnlineMemoryTest.sh`
- [ ] `Host/Hardware/OptimizeNestedVirtualization.sh`

## Host/Other
- [ ] `Host/QuickDiagnostic.sh`
- [ ] `Host/RemoveLocalLVMAndExpand.sh`
- [ ] `Host/SeparateNode.sh`
- [ ] `Host/Storage/ExpandEXT4Partition.sh`

## LXC
- [ ] `LXC/InteractiveRestoreCT.sh`
- [ ] `LXC/UpdateAll.sh`

## Networking
- [ ] `Networking/AddNetworkBond.sh`
- [ ] `Networking/BulkPrintVMIDMacAddresses.sh`
- [ ] `Networking/BulkSetDNS.sh`
- [ ] `Networking/FindVMFromMacAddress.sh`
- [ ] `Networking/HostIPerfTest.sh`
- [ ] `Networking/UpdateNetworkInterfaceNames.sh`
- [ ] `Networking/UplinkSpeedTest.sh`

## RemoteManagement/ApacheGuacamole
- [ ] `RemoteManagement/ApacheGuacamole/BulkDeleteConnectionGuacamole.sh`
- [ ] `RemoteManagement/ApacheGuacamole/GetGuacamoleAuthenticationToken.sh`
- [ ] `RemoteManagement/ApacheGuacamole/RDP/BulkAddRDPConnectionGuacamole.sh`
- [ ] `RemoteManagement/ApacheGuacamole/RDP/BulkAddSFTPServer.sh`
- [ ] `RemoteManagement/ApacheGuacamole/RDP/BulkRemoveDriveRedirection.sh`
- [ ] `RemoteManagement/ApacheGuacamole/RDP/BulkRemoveRDPConnection.sh`
- [ ] `RemoteManagement/ApacheGuacamole/RDP/BulkRemoveSFTPServer.sh`
- [ ] `RemoteManagement/ApacheGuacamole/RDP/BulkUpdateDriveRedirection.sh`
- [ ] `RemoteManagement/ApacheGuacamole/RemoveGuacamoleAuthenticationToken.sh`

## RemoteManagement/ConfigureOverSSH
- [ ] `RemoteManagement/ConfigureOverSSH/Proxmox/BulkCloneSetIP.sh`
- [ ] `RemoteManagement/ConfigureOverSSH/Proxmox/BulkReconfigureMacAddresses.sh`
- [ ] `RemoteManagement/ConfigureOverSSH/Ubuntu/BulkCloneSetIP.sh`
- [ ] `RemoteManagement/ConfigureOverSSH/Windows/BulkCloneSetIP.sh`

## Resources
- [ ] `Resources/ChangeAllMACPrefix.sh`
- [ ] `Resources/ExportProxmoxResources.sh`
- [ ] `Resources/FindLinkedClone.sh`

## Security
- [ ] `Security/PenetrationTest.sh`
- [ ] `Security/PortScan.sh`

## Storage
- [ ] `Storage/Benchmark.sh`
- [ ] `Storage/DiskDeleteBulk.sh`

## Storage/Ceph/Cluster
- [ ] `Storage/Ceph/Cluster/CreateOSDs.sh`
- [ ] `Storage/Ceph/Cluster/RestartManagers.sh`
- [ ] `Storage/Ceph/Cluster/RestartMetadata.sh`
- [ ] `Storage/Ceph/Cluster/RestartMonitors.sh`
- [ ] `Storage/Ceph/Cluster/RestartOSDs.sh`
- [ ] `Storage/Ceph/Cluster/StartStoppedOSDs.sh`

## Storage/Ceph/Host
- [ ] `Storage/Ceph/Host/EditCrushmap.sh`
- [ ] `Storage/Ceph/Host/RestartAllDaemons.sh`
- [ ] `Storage/Ceph/Host/RestartManager.sh`
- [ ] `Storage/Ceph/Host/RestartMetadata.sh`
- [ ] `Storage/Ceph/Host/RestartMonitor.sh`
- [ ] `Storage/Ceph/Host/RestartOSDs.sh`
- [ ] `Storage/Ceph/Host/SingleDrive.sh`

## Storage/Other
- [ ] `Storage/Ceph/Host/WipeDisk.sh`
- [ ] `Storage/DiskDeleteWithSnapshot.sh`
- [ ] `Storage/FilesystemTrimAll.sh`
- [ ] `Storage/OptimizeSpindown.sh`
- [ ] `Storage/PassthroughStorageToLXC.sh`
- [ ] `Storage/UpdateStaleMount.sh`

## VirtualMachines
- [ ] `VirtualMachines/Configuration/VMAddTerminalTTYS0.sh`
- [ ] `VirtualMachines/ConvertVMToTemplate.sh`
- [ ] `VirtualMachines/CreateFromISO.sh`
- [ ] `VirtualMachines/InteractiveRestoreVM.sh`

