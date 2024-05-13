#!/bin/bash

# Configuration
DATA_DIR="/var/lib/firecracker/data"
JAILER_DIR="/srv/jailer/firecracker"
LOG_FILE="/var/log/fs_manager.log"
GIT_SERVER_URL="https://git.dotcodeschool.com/" # Change this to the URL of your Git server

# Ensure necessary directories and files exist
mkdir -p "${DATA_DIR}" "${JAILER_DIR}"
touch "${LOG_FILE}"

# Log message utility
function log_message {
    echo "$(date +"%Y-%m-%d %T") - $1" >> "${LOG_FILE}"
}

# Check for existing filesystems
function check_fs {
    echo "Checking for existing filesystems..."
    log_message "Checking filesystems"
    ls -la "${DATA_DIR}"
}

# Create a new filesystem for repo ID
function create_fs {
    local repo_id=$1
    local fs_path="${DATA_DIR}/${repo_id}.ext4"
    local rootfs="tmp_rootfs"
    local repo_url="${GIT_SERVER_URL}/${repo_id}.git" # Change this to the URL of your Git repository

    if [ -f "$fs_path" ]; then
        echo "Filesystem for repo ID $repo_id already exists. Skipping creation."
        log_message "Filesystem creation skipped for repo ID: $repo_id"
        echo "$fs_path"
        return
    fi

    echo "Creating new filesystem for repo ID: $repo_id"
    log_message "Creating filesystem for repo ID: $repo_id"
    truncate -s 500M "$fs_path"  # Define the size of the filesystem
    mkfs.ext4 "$fs_path"
    log_message "Filesystem created at $fs_path"
    mkdir -pv "$rootfs"
    mount "$fs_path" "$rootfs"
    log_message "Mounted filesystem at $rootfs"
    git clone "${repo_url}.git" "${rootfs}/repo" || { echo "Failed to clone repository"; ./cleanup --vm-id $repo_id; return 1; }
    log_message "Cloned ${repo_id} repo to ${rootfs}/repo"
    umount "$rootfs"
    log_message "Unmounted filesystem at $rootfs"
    rm -rf "$rootfs"
    log_message "Removed temporary rootfs directory"
    echo "$fs_path"
}

# Move filesystem into the jail
function move_in_fs {
    local repo_id=$1
    local fs_path="${DATA_DIR}/${repo_id}.ext4"
    local jail_path="${JAILER_DIR}/${repo_id}/root/userfs.ext4"

    if [ -f "$fs_path" ]; then
        echo "Moving filesystem $fs_path to jail $jail_path"
        mv "$fs_path" "$jail_path"
        log_message "Moved filesystem to jail: $repo_id"
    else
        echo "Filesystem not found: $fs_path"
        return 1
    fi
}

# Move filesystem out of the jail
function move_out_fs {
    local repo_id=$1
    local jail_path="${JAILER_DIR}/${repo_id}/root/userfs.ext4"
    local fs_path="${DATA_DIR}/${repo_id}.ext4"

    if [ -f "$jail_path" ]; then
        echo "Moving filesystem $jail_path to $fs_path"
        mv "$jail_path" "$fs_path"
        log_message "Moved filesystem out of jail: $repo_id"
        chown root:root "$fs_path" # Ensure the filesystem is owned by root to prevent unauthorized access
        chmod 600 "$fs_path" # Set the filesystem permissions to 600 to prevent unauthorized access
    else
        echo "Filesystem not found: $jail_path"
        return 1
    fi
}

# Cleanup stale filesystems
function cleanup_fs {
    echo "Cleaning up stale filesystems..."
    log_message "Cleaning filesystems"

    # Cleanup files older than 30 days
    find "${DATA_DIR}" -type f -name '*.ext4' -mtime +30 -exec rm {} \;
    log_message "Stale filesystems cleaned up"
}

# Handle command line options
case "$1" in
    --check)
        check_fs
        ;;
    --create)
        create_fs "$2"
        ;;
    --move-in)
        move_in_fs "$2"
        ;;
    --move-out)
        move_out_fs "$2"
        ;;
    --cleanup)
        cleanup_fs
        ;;
    *)
        echo "Invalid option: $1"
        echo "Usage: $0 --check|--create <ID>|--move-in <ID>|--move-out <ID>|--cleanup"
        exit 1
        ;;
esac
