#!/bin/bash

# Usage: manage_network.sh --setup <VM ID>|--cleanup <VM ID>|--get-tap-ip <VM ID>|--get-fc-ip <VM ID>|--get-fc-mac <VM ID>
# Example: manage_network.sh --setup 1

set -e -o pipefail

VM_ID=$2
VM_ID=${VM_ID:0:11}     # Truncate the ID to ensure it's no longer than 11 characters
TAP_DEV="tap_${VM_ID}"  # Unique TAP device name based on VM ID
HOST_IFACE="enp1s0"     # Host interface for internet access

IP_RANGES=("172.16.0.0:172.31.255.255")
SUBNET_MASK="/30"
STEP_SIZE=4

# Enable IP forwarding
sudo sysctl -wq net.ipv4.ip_forward=1

# Function to convert IP address to decimal
ip_to_decimal() {
    local ip=$1
    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    echo $((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))
}

# Function to convert decimal back to IP address
decimal_to_ip() {
    local num=$1
    echo "$((num >> 24 & 255)).$((num >> 16 & 255)).$((num >> 8 & 255)).$((num & 255))"
}

# TODO: Improve the algorithm to find available IP ranges, this is a naive implementation that scales poorly
# Populate active IPs into a hash set
declare -A active_ips

populate_active_ips() {
    for ip in $(ip addr show | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+'); do
        active_ips["$ip"]=1
    done
}

# Check if any IP in a given range is in use
is_range_in_use() {
    local start_dec=$1
    local end_dec=$2
    for ((ip_dec=start_dec; ip_dec<=end_dec; ip_dec++)); do
        ip=$(decimal_to_ip "$ip_dec")
        if [[ -n "${active_ips[$ip]}" ]]; then
            return 0
        fi
    done
    return 1
}

# Find the first available /30 IP range in the given subrange
find_available_ip_in_subrange() {
    local start_ip=$1
    local end_ip=$2
    local start_dec=$(ip_to_decimal "$start_ip")
    local end_dec=$(ip_to_decimal "$end_ip")
    local step=$STEP_SIZE

    for ((ip_dec=start_dec; ip_dec<end_dec; ip_dec+=step)); do
        ip_range_start=$(decimal_to_ip "$ip_dec")
        ip_range_end=$(decimal_to_ip "$((ip_dec + step - 1))")

        if ! is_range_in_use "$ip_dec" "$((ip_dec + step - 1))"; then
            echo $ip_range_start
            return 0
        else
            ip_dec=$(ip_to_decimal "$ip_range_start")
        fi

    done

    return 1
}

# Find the first available /30 IP range across all defined private IP ranges
find_available_ip_range() {
    populate_active_ips
    for range in "${IP_RANGES[@]}"; do
        IFS=":" read -r start_ip end_ip <<< "$range"
        available_ip=$(find_available_ip_in_subrange "$start_ip" "$end_ip")
        if [[ -n "$available_ip" ]]; then
            echo "$available_ip"
            return 0
        fi
    done

    echo "No available /30 ranges found in the specified range."
    return 1
}

# Function to setup a TAP device and start DHCP
function setup_network {
    # Get the start of an available /30 IP range and increment by 1
    local new_tap_ip=$(decimal_to_ip "$(( $(ip_to_decimal "$(find_available_ip_range)") + 1 ))")
    local tap_ip="${new_tap_ip}"
    
    # Remove the TAP device if it already exists
    sudo ip link del "$TAP_DEV" 2> /dev/null || true

    # Create and configure the TAP device
    sudo ip tuntap add dev "$TAP_DEV" mode tap user "$(ps -p $(pgrep -f "firecracker --id $VM_ID") -o user=)"
    sudo ip addr add "${tap_ip}${SUBNET_MASK}" dev "$TAP_DEV"
    sudo ip link set dev "$TAP_DEV" up

    # Setup iptables for NAT and packet forwarding
    sudo iptables -t nat -A POSTROUTING -o "$HOST_IFACE" -j MASQUERADE
    sudo iptables -I FORWARD 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -I FORWARD 1 -i "$TAP_DEV" -o "$HOST_IFACE" -j ACCEPT

    echo "Network setup completed for TAP device ${TAP_DEV} with IP ${tap_ip}"
}

# Function to clean up TAP device and release DHCP IP
function cleanup_network {
    # Remove the specified TAP device
    if [[ -n "$1" ]]; then
        ssh-keygen -f "/root/.ssh/known_hosts" -R "$TAP_DEV" 2> /dev/null || true
        sudo ip link del "$TAP_DEV" 2> /dev/null || true
        sudo iptables -D FORWARD -i "$TAP_DEV" -o "$HOST_IFACE" -j ACCEPT || true
        echo "Network cleanup completed for TAP device $TAP_DEV"
        return 0
        
    else
        # Remove all TAP devices and corresponding iptables rules
        for tap_dev in $(ip link show | grep 'tap' | awk '{print $2}' | sed 's/.$//'); do
            sudo ip link del "${tap_dev}" 2> /dev/null || true
            sudo iptables -D FORWARD -i "${tap_dev}" -o "$HOST_IFACE" -j ACCEPT || true
        done

        sudo iptables -t nat -D POSTROUTING -o "$HOST_IFACE" -j MASQUERADE || true
        sudo iptables -D FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true
        echo "Network cleanup completed for all TAP devices"
    fi
}

# Function to retrieve the IP address for a given VM
function get_tap_ip {
    # Extract the IP address using ip command
    local ip_addr=$(ip addr show $TAP_DEV | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

    if [ -n "$ip_addr" ]; then
        echo "$ip_addr"
    else
        echo "No IP address found for $TAP_DEV"
    fi
}

# Calculate IP address for the VM based on IP address of the TAP device
function get_fc_ip {
    local ip_addr=$(get_tap_ip "$1")
    local fc_ip=$(decimal_to_ip "$(( $(ip_to_decimal $ip_addr) + 1 ))")
    echo $fc_ip
}

# Function to convert IP address to MAC address
function get_fc_mac {
    local ip_addr=$(get_fc_ip "$1")
    local mac_addr=$(printf "06:00:%02X:%02X:%02X:%02X" $(echo $ip_addr | tr '.' ' '))
    echo $mac_addr
}

# Handle command line options
case "$1" in
    --setup)
        setup_network "$2"
        ;;
    --cleanup)
        cleanup_network "$2"
        ;;
    --get-tap-ip)
        get_tap_ip "$2"
        ;;
    --get-fc-ip)
        get_fc_ip "$2"
        ;;
    --get-fc-mac)
        get_fc_mac "$2"
        ;;
    *)
        echo "Invalid option: $1"
        echo "Usage: $0 --setup <vm_id> | --cleanup <vm_id> | --get-ip <vm_id> | --get-mac <vm_id>"
        exit 1
        ;;
esac
