#!/bin/bash

# Usage: cleanup.sh --vm-id <VM ID>

function cleanup_all {
    echo "Performing full cleanup for VM ID: $1"
    ./manage_fs.sh --cleanup
    ./setup_network.sh --cleanup "$1"
    ./manage_users.sh --delete "$1"
    # Additional cleanup as necessary
}

cleanup_all "$2"
