#!/bin/bash

# Usage: check_bloat.sh

function check_bloat {
    echo -e "\033[1;34mChecking for potential bloat...\033[0m"
    
    # Initialize counters
    local tap_count=0
    local user_count=0
    local vm_count=0
    local uid_file_exists=0
    local data_dir_exists=0
    local jailer_dir_exists=0

    # Check for unnecessary TAP devices
    echo -e "\033[1;34mChecking for TAP devices...\033[0m"
    local tap_devices=$(ip tap show)
    if [ -n "$tap_devices" ]; then
        echo "$(ip addr show | grep "tap")"
        tap_count=$(echo "$tap_devices" | wc -l)
    else
        echo "No TAP devices found."
    fi

    # Check for unnecessary user accounts
    echo -e "\033[1;34mChecking for user accounts...\033[0m"
    local user_accounts=$(cat /etc/passwd | grep "vmuser")
    if [ -n "$user_accounts" ]; then
        echo "$user_accounts"
        user_count=$(echo "$user_accounts" | wc -l)
    else
        echo "No user accounts found."
    fi

    # Check for running VMs
    echo -e "\033[1;34mChecking for running VMs...\033[0m"
    local vms=$(pgrep -f "firecracker")
    if [ -n "$vms" ]; then
        echo "$vms"
        vm_count=$(echo "$vms" | wc -l)
    else
        echo "No VMs are running."
    fi

    # Check for files
    echo -e "\033[1;34mChecking for files...\033[0m"
    if [ -f "/var/tmp/uid_tracking" ]; then
        local uid_list=$(cat /var/tmp/uid_tracking)
        if [ -z "$uid_list" ]; then
            echo "UID tracking file is empty."
        else
            echo -e "\033[1;33mUID tracking file contents:\033[0m"
        fi
        echo "$uid_list"
        uid_file_exists=1
    else
        echo "UID tracking file is missing."
    fi
    if [ -d "/var/lib/firecracker/data" ]; then
        if [ -z "$(ls -A /var/lib/firecracker/data)" ]; then
            echo "Data directory is empty."
        else
            echo -e "\033[1;33mFiles in data directory:\033[0m"
        fi
        echo "$(ls -lh /var/lib/firecracker/data)"
        data_dir_exists=1
    else
        echo "No data directory found."
    fi
    if [ -d "/srv/jailer/firecracker" ]; then
        if [ -z "$(ls -A /srv/jailer/firecracker)" ]; then
            echo "Jailer directory is empty."
        else
            echo -e "\033[1;33mFiles in jailer directory:\033[0m"
        fi
        echo "$(ls -lh /srv/jailer/firecracker)"
        jailer_dir_exists=1
    else
        echo "No jailer directory found."
    fi

    # Summary output in color
    echo -e "\033[1;32mSummary:\033[0m Found $tap_count TAP devices, $user_count user accounts, $vm_count running VMs."
    echo -e "UID tracking file exists: $uid_file_exists, Data directory exists: $data_dir_exists, Jailer directory exists: $jailer_dir_exists."
}

check_bloat
