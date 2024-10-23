#!/bin/bash

# Function to check and install packages
check_and_install() {
    package=$1
    if ! command -v $package &> /dev/null; then
        echo "$package is not installed. Installing..."
	sudo apt-get install -y $package
  ##      sudo apt-get update && sudo apt-get install -y $package
    else
        echo "$package is already installed."
    fi
}

# Check and install minicom and python3-pip (for pyserial)
check_and_install minicom
check_and_install python3-pip

# Install pyserial using pip
if ! python3 -c "import serial" &> /dev/null; then
    echo "pyserial is not installed. Installing..."
    pip3 install pyserial
else
    echo "pyserial is already installed."
fi

devices=$(ls /dev/cdc-wdm* 2>/dev/null)

if [ -z "$devices" ]; then
    echo "No device found"
    exit 1
fi

device=$(echo "$devices" | head -n 1)
wwan_interface="wwan0"

# Function to send AT command
send_at_command() {
    echo "Sending AT command: $1"
    echo -e "$1\r" | minicom -D /dev/ttyUSB4 -b 115200
##    echo -e "$1\r" | minicom -D /dev/ttyUSB4 -b 115200 -8 -C /tmp/minicom.cap
    sleep 2
}

# Function to restart module
restart_module() {
    echo "Restarting module..."
    send_at_command "AT+CFUN=6"
    sleep 15  # Wait for module to restart
}

# Function to execute QMI command with error handling
execute_qmi_command() {
    if ! $1; then
        echo "Error executing QMI command. Restarting module..."
        restart_module
        if ! $1; then
            echo "Command failed after module restart. Exiting."
            exit 1
        fi
    fi
}

execute_qmi_command "sudo qmicli -d $device --dms-set-operating-mode='low-power'"
sleep 1
execute_qmi_command "sudo qmicli -d $device --dms-set-operating-mode='online'"
sleep 1
sudo ip link set $wwan_interface down
sleep 1
echo 'Y' | sudo tee /sys/class/net/$wwan_interface/qmi/raw_ip
sleep 2
sudo ip link set $wwan_interface up
sleep 1
execute_qmi_command "sudo qmicli -p -d $device --device-open-net='net-raw-ip|net-no-qos-header' --wds-start-network=\"apn='internet',ip-type=4\" --client-no-release-cid"
sleep 2
execute_qmi_command "sudo qmicli -p -d $device --wds-get-packet-service-status"
execute_qmi_command "sudo qmicli -p -d $device --wds-get-current-settings"
sleep 2
sudo udhcpc -q -f -i $wwan_interface
