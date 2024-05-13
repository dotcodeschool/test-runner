#!/bin/bash

# Usage: cleanup.sh --vm-id <VM ID>

function cleanup {
    echo "Performing full cleanup for VM ID: $1"
    pgrep -f "firecracker --id $1" | xargs -r sudo kill
    ./manage_fs.sh --move-out "$1"
    ./manage_fs.sh --cleanup
    rm -r "/srv/jailer/firecracker/$1" || true
    ./manage_network.sh --cleanup "$1"
    ./manage_users.sh --delete "$1"
    # Additional cleanup as necessary
}

case "$1" in
    --vm-id)
        cleanup "$2"
       ;;
    *)
        echo "Invalid option: $1"
        echo "Usage: $0 --vm-id <VM ID>"
        exit 1
        ;;
esac