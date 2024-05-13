#!/bin/bash

# Usage: check_bloat.sh

function check_bloat {
    echo -e "\f\033[1;34mChecking for potential bloat...\033[0m"
    
    # Initialize counters
    local tap_count=0
    local user_count=0
    local vm_count=0
    local uid_entry_count=0
    local uid_file_exists="NO"
    local data_dir_exists="NO"
    local jailer_dir_exists="NO"

    # Check for unnecessary TAP devices
    echo -e "\f\033[1;34mChecking for TAP devices...\033[0m"
    local tap_devices=$(ip tap show)
    if [ -n "$tap_devices" ]; then
        echo -e "\f$(ip addr show | grep "tap")"
        tap_count=$(echo "$tap_devices" | wc -l)
    else
        echo "No TAP devices found."
    fi

    # Check for unnecessary user accounts
    echo -e "\f\033[1;34mChecking for user accounts...\033[0m"
    local user_accounts=$(cat /etc/passwd | grep "vmuser")
    if [ -n "$user_accounts" ]; then
        echo -e "\f$user_accounts"
        user_count=$(echo "$user_accounts" | wc -l)
    else
        echo "No user accounts found."
    fi

    # Check for running VMs
    echo -e "\f\033[1;34mChecking for running VMs...\033[0m"
    local vms=$(pgrep -f "firecracker")
    if [ -n "$vms" ]; then
        ps -p "$(echo "$vms" | tr '\n' ' '  | sed 's/ $//')" -o pid,user,uid,stat,cmd # Display process information
        vm_count=$(echo "$vms" | wc -l)
    else
        echo "No VMs are running."
    fi

    # Check for files
    echo -e "\f\033[1;34mChecking for files...\033[0m"
    if [ -f "/var/tmp/uid_tracking" ]; then
        local uid_list=$(cat /var/tmp/uid_tracking)
        if [ -z "$uid_list" ]; then
            echo -e "\033[1mUID tracking file is empty.\033[0m"
        else
            echo -e "\f\033[1;33mUID tracking file contents:\033[0m"
            echo -e "\f$uid_list"
            uid_entry_count=$(echo "$uid_list" | wc -l)
        fi
        uid_file_exists="YES"
    else
        echo "UID tracking file is missing."
    fi
    
    if [ -d "/srv/jailer/firecracker" ]; then
        if [ -z "$(ls -A /srv/jailer/firecracker)" ]; then
            echo -e "\033[1mJailer directory is empty.\033[0m"
        else
            echo -e "\f\033[1;33mFiles in jailer directory:\033[0m"
            echo -e "\f$(ls -lh /srv/jailer/firecracker)\n"
            tree /srv/jailer/firecracker
            echo -e "\n"
        fi
        jailer_dir_exists="YES"
    else
        echo "No jailer directory found."
    fi

    if [ -d "/var/lib/firecracker/data" ]; then
        if [ -z "$(ls -A /var/lib/firecracker/data)" ]; then
            echo -e "\033[1mData directory is empty.\033[0m"
        else
            echo -e "\f\033[1;33mFiles in data directory:\033[0m"
            echo -e "\f$(ls -lh /var/lib/firecracker/data)"
            tree /var/lib/firecracker/data
        fi
        data_dir_exists="YES"
    else
        echo "No data directory found."
    fi

    # Summary output in color
    echo -e "\f\033[1;32mSummary:\033[0m 

Found $tap_count TAP devices, $user_count user accounts, $vm_count running VMs, $uid_entry_count entries in UID tracking file."
    echo -e "
    - UID tracking file exists: \033[1m$uid_file_exists\033[0m
    - Data directory exists: \033[1m$data_dir_exists\033[0m
    - Jailer directory exists: \033[1m$jailer_dir_exists\033[0m
    "
}

check_bloat
