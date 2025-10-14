#!/bin/bash
#
# This script automates the process of setting up a serial console on a Debian-based system. It creates necessary configuration files,
# updates GRUB to ensure the console output is directed to both the default terminal and the serial port, and enables a getty service 
# on the specified serial port.
#
# Usage:
# ./VMAddTerminalTTYS0.sh
#
# Example:
#   ./VMAddTerminalTTYS0.sh  # This will create /etc/init/ttyS0.conf and update GRUB to use ttyS0 at 115200 baud rate.
#
# Steps:
#   1. Create the /etc/init directory (if it does not exist) and set proper permissions.
#   2. Write the necessary configuration to /etc/init/ttyS0.conf for managing getty on ttyS0.
#   3. Update GRUB configuration to include console output on ttyS0.
#   4. Run update-grub to apply the new configuration.
#
# After running this script, the system will maintain a getty service on ttyS0, allowing console access via the specified serial port.

# Create the directory /etc/init if it doesn't exist
mkdir -p /etc/init
chmod 755 /etc/init

# Create and write the configuration to /etc/init/ttyS0.conf
cat <<EOF > /etc/init/ttyS0.conf
# ttyS0 - getty
#
# This service maintains a getty on ttyS0 from the point the system is
# started until it is shut down again.
start on stopped rc RUNLEVEL=[12345]
stop on runlevel [!12345]
respawn
exec /sbin/getty -L 115200 ttyS0 vt102
EOF

# Update GRUB_CMDLINE_LINUX in /etc/default/grub
# Replace the current GRUB_CMDLINE_LINUX line with the new one
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="quiet console=tty0 console=ttyS0,115200"/' /etc/default/grub

# Update grub with the new configuration
update-grub

echo "Script completed. ttyS0.conf has been created and GRUB has been updated."
