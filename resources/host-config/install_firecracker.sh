#!/bin/bash

# fail if we encounter an error, uninitialized variable or a pipe breaks
set -eu -o pipefail

set -x
PS4='>\t '

ARCH=${1:-$(uname -m)}
release_url="https://github.com/firecracker-microvm/firecracker/releases"

# Use curl to fetch the latest release tag securely
latest=$(curl -fsSLI -o /dev/null -w %{url_effective} "${release_url}/latest" | xargs basename)

# Check if the necessary curl command succeeded
if [ -z "$latest" ]; then
    echo "Failed to fetch the latest version of Firecracker." >&2
    exit 1
fi

# Download and extract the Firecracker tarball
curl -fSL "${release_url}/download/${latest}/firecracker-${latest}-${ARCH}.tgz" | tar -xz

# Check if the tar command succeeded
if [ $? -ne 0 ]; then
    echo "Failed to extract Firecracker." >&2
    exit 1
fi

# Ensure the directory exists before moving
if [ ! -d "release-${latest}-${ARCH}" ]; then
    echo "The expected release directory does not exist." >&2
    exit 1
fi

# Move and rename binaries to /usr/local/bin instead of /usr/bin to avoid conflicts with system binaries
sudo mv "release-${latest}-${ARCH}/firecracker-${latest}-${ARCH}" /usr/bin/firecracker
sudo mv "release-${latest}-${ARCH}/jailer-${latest}-${ARCH}" /usr/bin/jailer

# Check if binaries exist and set executable permissions
if [ -f "/usr/bin/firecracker" ] && [ -f "/usr/bin/jailer" ]; then
    sudo chmod +x /usr/bin/firecracker /usr/bin/jailer
else
    echo "Firecracker binaries are missing after moving." >&2
    exit 1
fi

echo "Firecracker installed successfully."
