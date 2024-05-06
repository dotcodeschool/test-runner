#!/bin/bash

# Usage: setup_network.sh --setup <vm_id> | --cleanup <vm_id> | --get-ip <vm_id>
# Example: setup_network.sh --setup vm123

VM_ID=$2
TAP_DEV="tap_${VM_ID}"  # Unique TAP device name based on VM ID
LEASE_FILE="/var/lib/dhcp/dhclient.leases"  # Path might vary depending on the system

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Function to setup a TAP device and start DHCP
function setup_network {
    local tap_dev="tap_${VM_ID}"

    # Create and configure the TAP device
    sudo ip tuntap add dev "$tap_dev" mode tap user `whoami`
    sudo ip link set "$tap_dev" up

    # Start DHCP client to get an IP from the DHCP server
    sudo dhclient "$tap_dev"

    echo "Network setup with DHCP completed for TAP device $tap_dev"
}

# Function to clean up TAP device and release DHCP IP
function cleanup_network {
    local tap_dev="tap_${VM_ID}"

    # Release the DHCP IP and remove the TAP device
    sudo dhclient -r "$tap_dev"
    sudo ip link del "$tap_dev"

    echo "Network cleanup completed for TAP device $tap_dev"
}

# Function to retrieve the IP address for a given VM
function get_ip {
    local tap_dev="tap_${VM_ID}"
    # Extract the IP address from the lease file
    local ip_addr=$(grep -A 8 "interface \"$tap_dev\"" $LEASE_FILE | grep 'fixed-address' | tail -1 | awk '{ print $2 }' | sed 's/;//')
    
    if [ -n "$ip_addr" ]; then
        echo "IP address for $tap_dev is $ip_addr"
    else
        echo "No IP address found for $tap_dev"
    fi
}

# Handle command line options
case "$1" in
    --setup)
        setup_network "$2"
        ;;
    --cleanup)
        cleanup_network "$2"
        ;;
    --get-ip)
        get_ip "$2"
        ;;
    *)
        echo "Invalid option: $1"
        echo "Usage: $0 --setup <vm_id> | --cleanup <vm_id> | --get-ip <vm_id>"
        exit 1
        ;;
esac
