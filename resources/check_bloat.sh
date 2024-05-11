#!/bin/bash

# Usage: check_bloat.sh

function check_bloat {
    echo "Checking for potential bloat..."
    
    # Check for unnecessary TAP devices
    echo "Checking for TAP devices..."
    ip addr show | grep "tap"

    # Check for unnecessary user accounts
    echo "Checking for user accounts..."
    cat /etc/passwd | grep "vmuser"

    # Check for running VMs
    echo "Checking for running VMs..."
    pgrep -f "firecracker"

    # Check for files
    echo "Checking for files..."
    ls -1 /var/tmp/uid_tracking
    tree /var/lib/firecracker
    tree /srv/jailer/firecracker
}

check_bloat