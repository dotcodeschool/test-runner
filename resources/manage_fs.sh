#!/bin/bash

set -ex -o pipefail

# Configuration
DATA_DIR="/var/lib/firecracker/data"
JAILER_DIR="/srv/jailer/firecracker"
LOG_FILE="/var/log/fs_manager.log"
GIT_SERVER_URL="https://git.dotcodeschool.com" # !IMPORTANT: Make sure this doesn't have a trailing '/'

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

# Create or update the root filesystem for repo ID
function create_or_update_rootfs {
    local repo_id=$1
    local rootfs_template="/var/lib/firecracker/images/ubuntu-22.04.squashfs"
    local rootfs_path="${DATA_DIR}/${repo_id}/rootfs.squashfs"
    local tmp_rootfs="tmp_rootfs"
    local repo_url="${GIT_SERVER_URL}/${repo_id}"
    local cargo_home="cargo_home"

    echo "Creating or updating root filesystem for repo ID: $repo_id"
    log_message "Creating or updating root filesystem for repo ID: $repo_id"

    # Check if rootfs already exists and use it as the template if it does
    if [ -f "$rootfs_path" ]; then
        echo "Found existing rootfs at $rootfs_path, using it as base template"
        log_message "Found existing rootfs at $rootfs_path, using it as base template"
        rootfs_template="$rootfs_path"
    fi

    # Create temporary directories for Docker to use
    mkdir -pv "$cargo_home"

    # Extract the rootfs template on the host
    echo "Extracting rootfs template"
    unsquashfs -d "$tmp_rootfs" "$rootfs_template"
    trap 'rm -rf "$tmp_rootfs" "$cargo_home"' EXIT

    # Run the Docker container to perform the git and cargo operations
    docker run --privileged --rm -i -v "$PWD:/work" -w /work -e CARGO_HOME="/work/$cargo_home" rust:latest bash -s <<EOF
cd /work
git clone $repo_url $tmp_rootfs/repo
cd $tmp_rootfs/repo
git pull
cargo update
cargo fetch
EOF

    # Copy the updated cargo directories back into the tmp_rootfs
    cp -r "$cargo_home"/. "$tmp_rootfs/root/.cargo/" || true

    # Recreate the squashfs file
    echo "Creating new squashfs image"
    mksquashfs "$tmp_rootfs" "$rootfs_path" -comp xz -b 1048576

    # Clean up the temporary directory
    rm -rf "$tmp_rootfs" "$cargo_home"
    log_message "Removed temporary directories"
    echo "$rootfs_path"
}

# Create a new filesystem for repo ID
function create_fs {
    local repo_id=$1
    local fs_path="${DATA_DIR}/${repo_id}/userfs.ext4"
    local tmp_userfs="tmp_userfs"
    local repo_url="${GIT_SERVER_URL}/${repo_id}"

    if [ -f "$fs_path" ]; then
        echo "Filesystem for repo ID $repo_id already exists. Skipping creation."
        log_message "Filesystem creation skipped for repo ID: $repo_id"
        update_rootfs "$repo_id"
        echo "$fs_path"
        return
    fi

    mkdir -pv "${DATA_DIR}/${repo_id}"
    echo "Creating new filesystem for repo ID: $repo_id"
    log_message "Creating filesystem for repo ID: $repo_id"
    truncate -s 2056M "$fs_path"  # Define the size of the filesystem
    mkfs.ext4 "$fs_path"
    log_message "Filesystem created at $fs_path"

    # Create or update rootfs
    create_or_update_rootfs "$repo_id"

    mkdir -pv "$tmp_userfs"
    mount "$fs_path" "$tmp_userfs"
    log_message "Mounted filesystem at $tmp_userfs"
    git clone "${repo_url}" "${tmp_userfs}/repo" || { echo "Failed to clone repository"; umount "$tmp_userfs"; rm -rf "$tmp_userfs"; return 1; }
    log_message "Cloned ${repo_id} repo to ${tmp_userfs}/repo"
    umount "$tmp_userfs"
    log_message "Unmounted filesystem at $tmp_userfs"
    rm -rf "$tmp_userfs"
    log_message "Removed temporary rootfs directory"
    echo "$fs_path"
}

# Update the root filesystem for repo ID
function update_rootfs {
    local repo_id=$1

    if [ ! -d "${DATA_DIR}/${repo_id}" ]; then
        echo "Repository directory ${DATA_DIR}/${repo_id} does not exist. Please create the filesystem first."
        return 1
    fi

    echo "Updating root filesystem for repo ID: $repo_id"
    log_message "Updating root filesystem for repo ID: $repo_id"

    create_or_update_rootfs "$repo_id"
}

# Move root filesystem into the jail
function move_in_rootfs {
    local repo_id=$1
    local rootfs_path="${DATA_DIR}/${repo_id}/rootfs.squashfs"
    local jail_path="${JAILER_DIR}/${repo_id}/root/rootfs.squashfs"

    if [ -f "$rootfs_path" ]; then
        echo "Moving root filesystem $rootfs_path to jail $jail_path"
        mv "$rootfs_path" "$jail_path"
        log_message "Moved root filesystem to jail: $repo_id"
    else
        echo "Root filesystem not found: $rootfs_path"
        return 1
    fi
}

# Move root filesystem out of the jail
function move_out_rootfs {
    local repo_id=$1
    local jail_path="${JAILER_DIR}/${repo_id}/root/rootfs.squashfs"
    local rootfs_path="${DATA_DIR}/${repo_id}/rootfs.squashfs"

    if [ -f "$jail_path" ]; then
        echo "Moving root filesystem $jail_path to $rootfs_path"
        mv "$jail_path" "$rootfs_path"
        log_message "Moved root filesystem out of jail: $repo_id"
        chown root:root "$rootfs_path" # Ensure the filesystem is owned by root to prevent unauthorized access
        chmod 600 "$rootfs_path" # Set the filesystem permissions to 600 to prevent unauthorized access
    else
        echo "Root filesystem not found: $jail_path"
        return 1
    fi
}

# Move filesystem into the jail
function move_in_fs {
    local repo_id=$1
    local fs_path="${DATA_DIR}/${repo_id}/userfs.ext4"
    local jail_path="${JAILER_DIR}/${repo_id}/root/userfs.ext4"

    if [ -f "$fs_path" ]; then
        echo "Moving filesystem $fs_path to jail $jail_path"
        mv "$fs_path" "$jail_path"
        log_message "Moved filesystem to jail: $repo_id"
    else
        echo "Filesystem not found: $fs_path"
        return 1
    fi

    # Move root filesystem into the jail
    move_in_rootfs "$repo_id"
}

# Move filesystem out of the jail
function move_out_fs {
    local repo_id=$1
    local jail_path="${JAILER_DIR}/${repo_id}/root/userfs.ext4"
    local fs_path="${DATA_DIR}/${repo_id}/userfs.ext4"

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

    # Move root filesystem out of the jail
    move_out_rootfs "$repo_id"
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
    --update-rootfs)
        update_rootfs "$2"
        ;;
    *)
        echo "Invalid option: $1"
        echo "Usage: $0 --check|--create <ID>|--move-in <ID>|--move-out <ID>|--cleanup|--update-rootfs <ID>"
        exit 1
        ;;
esac
