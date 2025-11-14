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


- **LXC/InteractiveRestoreCT.sh**
   - Intentionally interactive (indicated by name)
   - Currently uses manual `read -p`
   - Would hang if run remotely through Remote GUI
   - **Recommendation:** Implement Pattern 3
   - **Priority:** Medium (create RestoreCT.sh core script)

- **VirtualMachines/InteractiveRestoreVM.sh**
   - Intentionally interactive (indicated by name)
   - Currently uses manual `read -p`
   - Would hang if run remotely through Remote GUI
   - **Recommendation:** Implement Pattern 3
   - **Priority:** Medium (create RestoreVM.sh core script)

---

# Scripts Needing ArgumentParser Update

Add `source "${UTILITYPATH}/ArgumentParser.sh"` and use `__parse_args__` for argument handling.

## TBD
- [ ] `LXC/InteractiveRestoreCT.sh`
- [ ] `VirtualMachines/CreateFromISO.sh`
- [ ] `VirtualMachines/InteractiveRestoreVM.sh`

