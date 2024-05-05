#!/bin/bash

# fail if we encounter an error, uninitialized variable or a pipe breaks
set -eu -o pipefail

set -x
PS4='>\t '

# Update the package list
sudo apt update

# Install Firecracker
./install_firecracker.sh
