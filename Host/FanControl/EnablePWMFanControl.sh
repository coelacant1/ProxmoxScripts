#!/bin/bash
#
# EnablePWMFanControl.sh
#
# A script to manage system fans using fancontrol for efficient cooling management.
# This script allows you to install or uninstall a PWM-based fan control service
# with minimum and maximum temperature thresholds, as well as minimum and maximum
# fan speeds for interpolation.
#
# Usage:
#   ./EnablePWMFanControl.sh install [<min-temp> <max-temp> <min-pwm> <max-pwm>]
#   ./EnablePWMFanControl.sh uninstall
#
# Examples:
#   ./EnablePWMFanControl.sh install      # Installs fancontrol with default thresholds
#   ./EnablePWMFanControl.sh install 35 80 50 255
#   ./EnablePWMFanControl.sh uninstall    # Uninstalls fancontrol and reverts to default
#
# This script:
#   1) Installs the 'fancontrol' package if needed (prompts before installing).
#   2) Creates or updates /etc/fancontrol with min/max temp and min/max PWM settings.
#   3) Enables and starts the fancontrol systemd service.
#   4) Allows uninstalling fancontrol and reverting system fans to defaults.
#
# Make sure to run this script on a Proxmox node that has direct access to PWM
# fan control (e.g., /sys/class/hwmon/).
#
# Function Index:
#   - show_usage
#   - install_fancontrol
#   - uninstall_fancontrol
#

source "$UTILITIES"

###############################################################################
# Preliminary Checks
###############################################################################
check_root
check_proxmox

###############################################################################
# Helper Functions
###############################################################################
show_usage() {
  echo "Usage:"
  echo "  \"$0\" install [<min-temp> <max-temp> <min-pwm> <max-pwm>]"
  echo "  \"$0\" uninstall"
  echo
  echo "Examples:"
  echo "  \"$0\" install"
  echo "  \"$0\" install 35 80 50 255"
  echo "  \"$0\" uninstall"
}

install_fancontrol() {
  local minTemp="$1"
  local maxTemp="$2"
  local minPwm="$3"
  local maxPwm="$4"

  install_or_prompt "fancontrol"

  local hwmonDevice
  hwmonDevice="$(ls /sys/class/hwmon/ | head -n1)"
  if [[ -z "$hwmonDevice" ]]; then
    echo "Error: No hwmon device found. Ensure your system supports PWM fan control."
    exit 3
  fi

  local FANCONTROL_CONF="/etc/fancontrol"

  echo "Generating \"$FANCONTROL_CONF\" with:"
  echo "  Min Temp : \"$minTemp\""
  echo "  Max Temp : \"$maxTemp\""
  echo "  Min PWM  : \"$minPwm\""
  echo "  Max PWM  : \"$maxPwm\""
  echo "  HwmonDev : \"$hwmonDevice\""

  cat <<EOF > "$FANCONTROL_CONF"
#------------------------------------------------------------------------------
# /etc/fancontrol
# Created by EnablePWMFanControl.sh
#------------------------------------------------------------------------------

INTERVAL=10
DEVPATH=hwmon0=/sys/class/hwmon/$hwmonDevice
DEVNAME=hwmon0=$(cat /sys/class/hwmon/"$hwmonDevice"/name 2>/dev/null || echo "unknown")
FCTEMPS=hwmon0/pwm1=hwmon0/temp1_input
FCFANS=hwmon0/pwm1=hwmon0/fan1_input
MINTEMP=hwmon0/pwm1=$minTemp
MAXTEMP=hwmon0/pwm1=$maxTemp
MINPWM=hwmon0/pwm1=$minPwm
MAXPWM=hwmon0/pwm1=$maxPwm
MINSTOP=hwmon0/pwm1=$minPwm
MINSTART=hwmon0/pwm1=$(($minPwm + 10))
EOF

  systemctl enable fancontrol
  systemctl restart fancontrol

  echo "fancontrol installation and configuration complete."
  prompt_keep_installed_packages
}

uninstall_fancontrol() {
  echo "Stopping and disabling fancontrol..."
  systemctl stop fancontrol || true
  systemctl disable fancontrol || true

  echo "Removing fancontrol package..."
  apt-get remove -y --purge fancontrol
  apt-get autoremove -y

  local FANCONTROL_CONF="/etc/fancontrol"
  if [[ -f "$FANCONTROL_CONF" ]]; then
    echo "Removing \"$FANCONTROL_CONF\"..."
    rm -f "$FANCONTROL_CONF"
  fi

  echo "fancontrol uninstalled. System fans reverted to default."
}

###############################################################################
# Main
###############################################################################
action="$1"
case "$action" in
  install)
    minTemp="${2:-30}"
    maxTemp="${3:-70}"
    minPwm="${4:-60}"
    maxPwm="${5:-255}"
    install_fancontrol "$minTemp" "$maxTemp" "$minPwm" "$maxPwm"
    ;;
  uninstall)
    uninstall_fancontrol
    ;;
  *)
    show_usage
    exit 1
    ;;
esac
