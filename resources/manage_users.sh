#!/bin/bash

# Configuration
UID_BASE=10000
UID_MAX=20000
UID_TRACKING_FILE="/var/tmp/uid_tracking"

# Ensures the UID tracking file exists
touch "$UID_TRACKING_FILE"

# Allocate UID
function allocate_uid {
    for (( uid = UID_BASE; uid <= UID_MAX; uid++ )); do
        if ! grep -q "^$uid$" "$UID_TRACKING_FILE"; then
            echo $uid >> "$UID_TRACKING_FILE"
            echo $uid
            return
        fi
    done
    echo "No UID available" >&2
    return 1
}

# Deallocate UID
function deallocate_uid {
    local uid=$1
    sed -i "/^$uid$/d" "$UID_TRACKING_FILE"
}

# Create user with dynamic UID/GID
function create_user {
    local vm_id=$1
    local user_uid=$(allocate_uid)
    if [[ $user_uid == "No UID available" ]]; then
        echo "Failed to allocate UID."
        exit 1
    fi

    local username="vmuser_$vm_id"
    
    echo "Creating user $username with UID/GID: $user_uid"
    sudo useradd -M -N -u $user_uid -g $user_uid -s /usr/sbin/nologin "$username"

    echo "User $username created successfully."
    echo $user_uid
}

# Delete user and clean up UID/GID
function delete_user {
    local vm_id=$1
    local username="vmuser_$vm_id"
    local user_uid=$(id -u $username)

    echo "Deleting user $username..."
    sudo userdel -r "$username"
    deallocate_uid $user_uid

    echo "User $username and associated resources have been cleaned up."
}

# Command-line handling logic
case "$1" in
    --create)
        create_user "$2"
        ;;
    --delete)
        delete_user "$2"
        ;;
    *)
        echo "Invalid option: $1"
        echo "Usage: $0 --create <VM ID>|--delete <VM ID>"
        exit 1
        ;;
esac
