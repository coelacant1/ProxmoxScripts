# Pending Change Tracker
## Datacenter
- [ ] Add storage: SMB, NFS, PBS (For bulk CLI calls)

## Virtual Machines
### Operations
- [ ] Bulk Hibernate
- [ ] Bulk Pause
- [ ] Bulk Resume

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
- [ ] Change hard disk options: cache, discard, io thread, read only, ssd emulation, backup, skip replication, async io
- [ ] Change vmbr model: add optional vlan, firewall, disconnect, mtu, rate limit, multiqueue, mac address (and prefix), model
- [ ] Add hard disk
- [ ] Add serial port
- [ ] Add cloudinit drive
- [ ] Disconnect all CD/DVD drives

### Options
- [x] Disable AutoStart on all VMs/LXCs
- [ ] Disable touch pointer
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



## Notes
- Change from e1000e to virtio, change nested to disable touch pointer for 110